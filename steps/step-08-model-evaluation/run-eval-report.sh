#!/bin/bash
# Step 08: Generate pre/post RAG evaluation reports from GitOps-managed test configs
# Reads *_tests.yaml from the PVC (synced by ArgoCD), runs the Llama Stack eval API,
# and uploads HTML reports to MinIO.
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

log_step "Running evaluation on $LSD_POD..."
echo ""

oc exec "$LSD_POD" -n "$NAMESPACE" -- python3 -c "
import warnings; warnings.filterwarnings('ignore')
import logging; logging.getLogger('httpx').setLevel(logging.WARNING)
import json, time, os, tempfile, glob, yaml
import requests as http
from llama_stack_client import LlamaStackClient, BadRequestError

BASE = 'http://localhost:8321'
MODEL = 'vllm-granite-agent/granite-8b-agent'
RUN_ID = '$RUN_ID'
S3_ENDPOINT = '$MINIO_ENDPOINT'
S3_KEY = '$MINIO_KEY'
S3_SECRET = '$MINIO_SECRET'
S3_BUCKET = '$MINIO_BUCKET'
EVAL_DIR = '/tmp/eval-configs'

client = LlamaStackClient(base_url=BASE)

stores = {vs.name: vs.id for vs in client.vector_stores.list().data}
print(f'Vector stores: {list(stores.keys())}')

# --- Load test configs from PVC ---
configs = sorted(glob.glob(os.path.join(EVAL_DIR, '*_tests.yaml')))
print(f'Test configs found: {len(configs)}')
for c in configs:
    print(f'  {os.path.basename(c)}')

# --- Register judge scoring function ---
judge_path = os.path.join(EVAL_DIR, 'scoring-templates', 'judge_prompt.txt')
if os.path.exists(judge_path):
    with open(judge_path) as f:
        JUDGE_PROMPT = f.read()
else:
    JUDGE_PROMPT = 'Question: {input_query}\nExpected: {expected_answer}\nGenerated: {generated_answer}\nAnswer: '

try:
    client.scoring_functions.register(
        scoring_fn_id='rag-eval-judge', description='RAG quality judge',
        return_type={'type': 'string'}, provider_id='llm-as-judge',
        provider_scoring_fn_id='llm-as-judge-base',
        params={'type': 'llm_as_judge', 'judge_model': MODEL, 'prompt_template': JUDGE_PROMPT})
except BadRequestError:
    pass

# --- Helpers ---
def retrieve_context(q, store_id):
    try:
        r = http.post(f'{BASE}/v1/vector_stores/{store_id}/search',
            json={'query': q, 'max_num_results': 3}, timeout=30).json()
        chunks = []
        for item in r.get('data', []):
            for c in item.get('content', []):
                chunks.append(c.get('text', ''))
        return chr(10).join(chunks[:3])
    except Exception as e:
        print(f'    Retrieval error: {e}')
        return ''

def call_llm(q, context=None):
    msgs = []
    if context:
        msgs.append({'role': 'system', 'content': f'Answer based on this context:{chr(10)}{context[:3000]}'})
    msgs.append({'role': 'user', 'content': q})
    r = http.post(f'{BASE}/v1/chat/completions', json={
        'model': MODEL, 'messages': msgs, 'max_tokens': 400, 'temperature': 0, 'stream': False
    }, timeout=120).json()
    return r['choices'][0]['message']['content']

def generate_html(name, mode, results, run_id):
    color = '#28a745' if mode == 'post-rag' else '#6c757d'
    rows = ''
    for i, r in enumerate(results, 1):
        rows += f'''<tr>
          <td>{i}</td><td>{r['q'][:200]}</td>
          <td>{r['answer'][:500]}</td><td>{r['expected'][:500]}</td>
          <td><strong>{r.get('judge_letter','')}</strong><br><small>{r.get('judge_feedback','')[:250]}</small></td>
        </tr>'''
    return f'''<!DOCTYPE html>
<html><head><meta charset=\"utf-8\"><title>RAG Eval - {name} ({mode})</title>
<style>
body {{ font-family: -apple-system, sans-serif; margin: 20px; background: #f8f9fa; }}
.container {{ max-width: 1400px; margin: 0 auto; background: #fff; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,.1); overflow: hidden; }}
.header {{ background: linear-gradient(135deg, {color}, {'#20c997' if mode=='post-rag' else '#495057'}); color: #fff; padding: 30px; text-align: center; }}
table {{ width: 100%; border-collapse: collapse; margin: 15px 30px; }}
th {{ background: {color}; color: #fff; padding: 12px 8px; text-align: left; font-size: .9em; }}
td {{ padding: 10px 8px; border-bottom: 1px solid #eee; vertical-align: top; max-width: 350px; word-wrap: break-word; font-size: .85em; }}
tr:nth-child(even) {{ background: #f8f9fa; }}
.meta {{ color: #6c757d; margin: 10px 30px; }}
.badge {{ display: inline-block; padding: 4px 12px; border-radius: 4px; color: #fff; background: {color}; font-weight: bold; }}
</style></head><body>
<div class=\"container\">
  <div class=\"header\"><h1>RAG Evaluation Report</h1><p>{name}</p><span class=\"badge\">{mode.upper()}</span></div>
  <p class=\"meta\">Run ID: {run_id} | Mode: {mode} | {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())} | Tests: {len(results)}</p>
  <table><thead><tr><th>#</th><th>Question</th><th>Generated Answer</th><th>Expected</th><th>Judge Score</th></tr></thead>
  <tbody>{rows}</tbody></table>
</div></body></html>'''

def upload_to_s3(html, s3_key):
    if not all([S3_ENDPOINT, S3_KEY, S3_SECRET]):
        print(f'    S3 creds missing')
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
    eval_rows = []

    for t in tests:
        q = t['prompt']
        expected = t['expected_result']

        if mode == 'post-rag' and store_id:
            ctx = retrieve_context(q, store_id)
            answer = call_llm(q, context=ctx)
        else:
            answer = call_llm(q)

        results.append({'q': q, 'expected': expected, 'answer': answer, 'judge_letter': '', 'judge_feedback': ''})
        eval_rows.append({'input_query': q, 'expected_answer': expected,
            'chat_completion_input': json.dumps([{'role':'user','content':q}])})
        print(f'  Q: {q[:55]}...')
        print(f'  A: {answer[:75]}...')

    # Score via Llama Stack eval API
    safe = os.path.basename(cfg_path).replace('.yaml','').replace('_tests','')
    ds_id = f'{safe}-{RUN_ID}'
    bm_id = f'{safe}-bm-{RUN_ID}'

    try:
        client.beta.datasets.register(purpose='eval/question-answer',
            source={'type':'rows','rows':eval_rows},
            dataset_id=ds_id, metadata={}, extra_body={'provider_id':'localfs'})

        client.alpha.benchmarks.register(benchmark_id=bm_id, dataset_id=ds_id,
            scoring_functions=['basic::subset_of', 'rag-eval-judge'],
            extra_body={'provider_id':'meta-reference'})

        job = client.alpha.eval.run_eval(bm_id, benchmark_config={
            'eval_candidate':{'type':'model','model':MODEL,'sampling_params':{'max_tokens':400}},
            'scoring_params':{'basic::subset_of':{'type':'basic','aggregation_functions':['accuracy']}},
        })
        result = client.alpha.eval.jobs.retrieve(job_id=job.job_id, benchmark_id=bm_id)

        for fn_id, sr in (result.scores or {}).items():
            if sr.aggregated_results:
                print(f'  {fn_id}: {sr.aggregated_results}')
            for i, row in enumerate(sr.score_rows or []):
                if i < len(results):
                    fb = row.get('judge_feedback', '')
                    if fb:
                        letter = fb.strip()[0:3] if fb.strip() else ''
                        results[i]['judge_letter'] = letter
                        results[i]['judge_feedback'] = fb
                    score = row.get('score')
                    if score is not None:
                        existing = results[i].get('judge_letter', '')
                        results[i]['judge_letter'] = f'{existing} subset_of={score}'.strip()

    except Exception as e:
        print(f'  Scoring error: {e}')

    html = generate_html(scenario, mode, results, RUN_ID)
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
    echo "  CLI:      oc exec -n minio-storage deploy/minio -- mc ls local/${MINIO_BUCKET}/eval-results/${RUN_ID}/"
else
    log_error "Evaluation failed"
    exit 1
fi
