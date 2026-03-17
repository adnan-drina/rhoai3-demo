#!/bin/bash
# Step 08: Generate pre/post RAG evaluation reports
# - Reads *_tests.yaml from eval-configs/ (GitOps-managed)
# - Candidate model: granite-8b-agent via lsd-rag
# - Judge model: mistral-3-bf16 via direct vLLM (larger model = better judge)
# - Reports uploaded to MinIO
#
# Usage: ./run-eval-report.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="private-ai"
RUN_ID="eval-$(date +%Y%m%d-%H%M%S)"

source "$REPO_ROOT/scripts/lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 08: Pre/Post RAG Evaluation Report                       ║"
echo "║  Run ID: $RUN_ID                                           ║"
echo "║  Candidate: granite-8b-agent | Judge: mistral-3-bf16           ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

check_oc_logged_in

LSD_POD=$(oc get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep "lsd-rag.*Running" | awk '{print $1}' | head -1)
if [ -z "$LSD_POD" ]; then
    log_error "lsd-rag pod not found"
    exit 1
fi
log_success "Using pod: $LSD_POD"

MINIO_ENDPOINT=$(oc get secret minio-connection -n "$NAMESPACE" -o jsonpath='{.data.AWS_S3_ENDPOINT}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
MINIO_KEY=$(oc get secret minio-connection -n "$NAMESPACE" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
MINIO_SECRET=$(oc get secret minio-connection -n "$NAMESPACE" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
MINIO_BUCKET=$(oc get secret minio-connection -n "$NAMESPACE" -o jsonpath='{.data.AWS_S3_BUCKET}' 2>/dev/null | base64 -d 2>/dev/null || echo "rhoai-storage")

log_step "Copying eval configs to lsd-rag pod..."
oc exec "$LSD_POD" -n "$NAMESPACE" -- mkdir -p /tmp/eval-configs/scoring-templates 2>/dev/null
for f in "$SCRIPT_DIR"/eval-configs/*_tests.yaml; do
    [ -f "$f" ] && oc cp "$f" "$NAMESPACE/$LSD_POD:/tmp/eval-configs/$(basename $f)" 2>/dev/null
done
for f in "$SCRIPT_DIR"/eval-configs/scoring-templates/*.txt; do
    [ -f "$f" ] && oc cp "$f" "$NAMESPACE/$LSD_POD:/tmp/eval-configs/scoring-templates/$(basename $f)" 2>/dev/null
done
log_success "Configs copied"
echo ""

log_step "Running evaluation..."
echo ""

oc exec "$LSD_POD" -n "$NAMESPACE" -- python3 -c "
import warnings; warnings.filterwarnings('ignore')
import logging; logging.getLogger('httpx').setLevel(logging.WARNING)
import json, time, os, tempfile, glob, yaml, re
import requests as http

# --- Config ---
LLAMASTACK_URL = 'http://localhost:8321'
CANDIDATE_MODEL = 'vllm-inference/granite-8b-agent'
JUDGE_URL = 'http://mistral-3-bf16-predictor.private-ai.svc.cluster.local:8080/v1/chat/completions'
JUDGE_MODEL = 'mistral-3-bf16'
RUN_ID = '$RUN_ID'
S3_ENDPOINT = '$MINIO_ENDPOINT'
S3_KEY = '$MINIO_KEY'
S3_SECRET = '$MINIO_SECRET'
S3_BUCKET = '$MINIO_BUCKET'
EVAL_DIR = '/tmp/eval-configs'

from llama_stack_client import LlamaStackClient
client = LlamaStackClient(base_url=LLAMASTACK_URL)

stores = {vs.name: vs.id for vs in client.vector_stores.list().data}
print(f'Vector stores: {list(stores.keys())}')
print(f'Candidate: {CANDIDATE_MODEL}')
print(f'Judge: {JUDGE_MODEL} (separate, larger model)')

configs = sorted(glob.glob(os.path.join(EVAL_DIR, '*_tests.yaml')))
print(f'Test configs: {len(configs)}')

# --- Load judge prompt ---
judge_path = os.path.join(EVAL_DIR, 'scoring-templates', 'judge_prompt.txt')
with open(judge_path) as f:
    JUDGE_TEMPLATE = f.read()

# --- Helpers ---
def retrieve_context(q, store_id):
    try:
        r = http.post(f'{LLAMASTACK_URL}/v1/vector_stores/{store_id}/search',
            json={'query': q, 'max_num_results': 3}, timeout=30).json()
        chunks = []
        for item in r.get('data', []):
            for c in item.get('content', []):
                chunks.append(c.get('text', ''))
        return chr(10).join(chunks[:3])
    except Exception as e:
        return ''

def call_candidate(q, context=None):
    msgs = []
    if context:
        msgs.append({'role': 'system', 'content': f'Answer based on this context:{chr(10)}{context[:3000]}'})
    msgs.append({'role': 'user', 'content': q})
    r = http.post(f'{LLAMASTACK_URL}/v1/chat/completions', json={
        'model': CANDIDATE_MODEL, 'messages': msgs, 'max_tokens': 400, 'temperature': 0, 'stream': False
    }, timeout=120).json()
    return r['choices'][0]['message']['content']

def call_judge(question, expected, generated):
    prompt = JUDGE_TEMPLATE.replace('{input_query}', question).replace('{expected_answer}', expected).replace('{generated_answer}', generated)
    try:
        r = http.post(JUDGE_URL, json={
            'model': JUDGE_MODEL,
            'messages': [{'role': 'user', 'content': prompt}],
            'max_tokens': 300, 'temperature': 0, 'stream': False,
        }, timeout=60).json()
        feedback = r['choices'][0]['message']['content']
        match = re.search(r'\(([A-E])\)', feedback)
        letter = match.group(1) if match else feedback[:3]
        return letter, feedback
    except Exception as e:
        return '?', f'Judge error: {e}'

def generate_html(name, mode, results, run_id):
    color = '#28a745' if mode == 'post-rag' else '#6c757d'
    rows = ''
    for i, r in enumerate(results, 1):
        letter = r.get('judge_letter', '?')
        lcolor = {'A':'#28a745','B':'#28a745','C':'#ffc107','D':'#6c757d','E':'#dc3545'}.get(letter,'#6c757d')
        rows += f'''<tr>
          <td>{i}</td><td>{r['q'][:250]}</td>
          <td>{r['answer'][:500]}</td><td>{r['expected'][:500]}</td>
          <td><span style=\"display:inline-block;padding:2px 10px;border-radius:4px;background:{lcolor};color:#fff;font-weight:bold;font-size:1.1em\">({letter})</span><br><small>{r.get('judge_feedback','')[:300]}</small></td>
        </tr>'''
    return f'''<!DOCTYPE html>
<html><head><meta charset=\"utf-8\"><title>RAG Eval - {name} ({mode})</title>
<style>
body {{ font-family: -apple-system, sans-serif; margin: 20px; background: #f8f9fa; }}
.container {{ max-width: 1400px; margin: 0 auto; background: #fff; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,.1); overflow: hidden; }}
.header {{ background: linear-gradient(135deg, {color}, {'#20c997' if mode=='post-rag' else '#495057'}); color: #fff; padding: 30px; text-align: center; }}
table {{ width: 100%; border-collapse: collapse; margin: 15px 0; padding: 0 30px; }}
th {{ background: {color}; color: #fff; padding: 12px 8px; text-align: left; font-size: .9em; }}
td {{ padding: 10px 8px; border-bottom: 1px solid #eee; vertical-align: top; max-width: 350px; word-wrap: break-word; font-size: .85em; }}
tr:nth-child(even) {{ background: #f8f9fa; }}
.meta {{ color: #6c757d; margin: 10px 30px; font-size: .9em; }}
.badge {{ display: inline-block; padding: 4px 12px; border-radius: 4px; color: #fff; background: {color}; font-weight: bold; }}
</style></head><body>
<div class=\"container\">
  <div class=\"header\"><h1>RAG Evaluation Report</h1><p>{name}</p><span class=\"badge\">{mode.upper()}</span></div>
  <p class=\"meta\">Run ID: {run_id} | Candidate: granite-8b-agent | Judge: mistral-3-bf16 | {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())} | Tests: {len(results)}</p>
  <div style=\"padding: 0 30px 30px;\"><table><thead><tr><th>#</th><th>Question</th><th>Generated Answer</th><th>Expected</th><th>Judge Score</th></tr></thead>
  <tbody>{rows}</tbody></table></div>
</div></body></html>'''

def upload_to_s3(html, s3_key):
    if not all([S3_ENDPOINT, S3_KEY, S3_SECRET]):
        return
    try:
        import boto3
        endpoint = S3_ENDPOINT if S3_ENDPOINT.startswith('http') else f'http://{S3_ENDPOINT}'
        s3 = boto3.client('s3', endpoint_url=endpoint, aws_access_key_id=S3_KEY,
            aws_secret_access_key=S3_SECRET, verify=False)
        with tempfile.NamedTemporaryFile(mode='w', suffix='.html', delete=False) as f:
            f.write(html)
            tmp = f.name
        s3.upload_file(tmp, S3_BUCKET, s3_key, ExtraArgs={'ContentType': 'text/html'})
        os.unlink(tmp)
        print(f'    Uploaded: s3://{S3_BUCKET}/{s3_key}')
    except Exception as e:
        print(f'    Upload error: {e}')

# --- Process each config ---
for cfg_path in configs:
    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)

    scenario = cfg.get('name', os.path.basename(cfg_path))
    mode = cfg.get('mode', 'post-rag')
    db_id = cfg.get('vector_db_id')
    tests = cfg.get('tests', [])
    store_id = stores.get(db_id, '') if db_id else ''

    print(f'\\n{\"=\"*70}')
    print(f'{scenario} [{mode}] ({len(tests)} tests)')
    print(f'{\"=\"*70}')

    results = []
    for t in tests:
        q = t['prompt']
        expected = t['expected_result']

        # Generate answer
        if mode == 'post-rag' and store_id:
            ctx = retrieve_context(q, store_id)
            answer = call_candidate(q, context=ctx)
        else:
            answer = call_candidate(q)

        # Judge (using mistral-3-bf16)
        letter, feedback = call_judge(q, expected, answer)

        results.append({'q': q, 'expected': expected, 'answer': answer,
                        'judge_letter': letter, 'judge_feedback': feedback})
        print(f'  Q: {q[:55]}')
        print(f'  A: {answer[:75]}...')
        print(f'  Judge: ({letter})')

    # Generate and upload HTML
    html = generate_html(scenario, mode, results, RUN_ID)
    safe = os.path.basename(cfg_path).replace('.yaml','').replace('_tests','')
    s3_key = f'eval-results/{RUN_ID}/{safe}_report.html'
    upload_to_s3(html, s3_key)

print(f'\\n{\"=\"*70}')
print(f'EVALUATION COMPLETE — Run ID: {RUN_ID}')
print(f'Reports: s3://{S3_BUCKET}/eval-results/{RUN_ID}/')
print(f'{\"=\"*70}')
"

if [ $? -eq 0 ]; then
    echo ""
    log_success "Evaluation reports generated"
    echo ""
    echo "View reports:"
    echo "  MinIO UI: https://$(oc get route minio-console -n minio-storage -o jsonpath='{.spec.host}' 2>/dev/null)/browser/${MINIO_BUCKET}/eval-results/${RUN_ID}/"
else
    log_error "Evaluation failed"
    exit 1
fi
