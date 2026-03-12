#!/bin/bash
# Step 08: Generate and store pre/post RAG evaluation reports
# Runs the Llama Stack eval API from the lsd-rag pod (localhost, no DNS issues)
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

# Get MinIO credentials for report upload
MINIO_ENDPOINT=$(oc get secret minio-connection -n "$NAMESPACE" -o jsonpath='{.data.AWS_S3_ENDPOINT}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
MINIO_KEY=$(oc get secret minio-connection -n "$NAMESPACE" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
MINIO_SECRET=$(oc get secret minio-connection -n "$NAMESPACE" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
MINIO_BUCKET=$(oc get secret minio-connection -n "$NAMESPACE" -o jsonpath='{.data.AWS_S3_BUCKET}' 2>/dev/null | base64 -d 2>/dev/null || echo "rhoai-storage")

log_step "Running evaluation on $LSD_POD..."
echo ""

oc exec "$LSD_POD" -n "$NAMESPACE" -- python3 -c "
import warnings; warnings.filterwarnings('ignore')
import logging; logging.getLogger('httpx').setLevel(logging.WARNING)
import json, time, os, tempfile
import requests as http
from llama_stack_client import LlamaStackClient, BadRequestError

BASE = 'http://localhost:8321'
MODEL = 'vllm-granite-agent/granite-8b-agent'
RUN_ID = '$RUN_ID'
S3_ENDPOINT = '$MINIO_ENDPOINT'
S3_KEY = '$MINIO_KEY'
S3_SECRET = '$MINIO_SECRET'
S3_BUCKET = '$MINIO_BUCKET'

client = LlamaStackClient(base_url=BASE)

# --- Discover vector stores ---
stores = {vs.name: vs.id for vs in client.vector_stores.list().data}
print(f'Vector stores: {list(stores.keys())}')

# --- Test cases ---
scenarios = {
    'acme_corporate': [
        {'q': 'What are the key calibration procedures for DFO lithography?',
         'a': 'DFO calibration involves alignment verification, dose calibration, focus optimization, and overlay measurement.'},
        {'q': 'What products and standards does ACME cover?',
         'a': 'ACME covers EUV and DUV lithography products aligned with SEMI and ISO standards.'},
        {'q': 'Describe the Tier-1 and Tier-2 trouble response procedures.',
         'a': 'Tier-1 covers initial triage and standard fixes. Tier-2 involves engineering analysis and root cause investigation.'},
    ],
    'eu_ai_act': [
        {'q': 'What are the main risk categories in the EU AI Act?',
         'a': 'Unacceptable risk (banned), high risk (strict requirements), limited risk (transparency), minimal risk (voluntary).'},
        {'q': 'What obligations do providers of high-risk AI systems have?',
         'a': 'Risk management, data governance, technical documentation, human oversight, and accuracy.'},
    ],
    'whoami': [
        {'q': 'What is this persons professional background?',
         'a': 'Technology professional with experience in cloud computing, Kubernetes, and AI/ML platforms.'},
    ],
}

# --- Register LLM-as-judge scoring function ---
JUDGE_PROMPT = '''Evaluate the response quality.
Question: {input_query}
Expected: {expected_answer}
Generated: {generated_answer}
Select: (A) subset (B) superset (C) same (D) disagrees (E) insignificant diff.
Answer: '''

try:
    client.scoring_functions.register(
        scoring_fn_id='rag-eval-judge', description='RAG quality judge',
        return_type={'type': 'string'}, provider_id='llm-as-judge',
        provider_scoring_fn_id='llm-as-judge-base',
        params={'type': 'llm_as_judge', 'judge_model': MODEL, 'prompt_template': JUDGE_PROMPT})
except BadRequestError:
    pass

# --- Helper functions ---
def retrieve_context(q, store_id):
    try:
        r = http.post(f'{BASE}/v1/vector_stores/{store_id}/search',
            json={'query': q, 'max_num_results': 3}, timeout=30).json()
        chunks = []
        for item in r.get('data', []):
            for c in item.get('content', []):
                chunks.append(c.get('text', ''))
        return chr(10).join(chunks[:3])
    except:
        return ''

def call_llm(q, context=None):
    msgs = []
    if context:
        msgs.append({'role': 'system', 'content': f'Answer based on this context:{chr(10)}{context[:3000]}'})
    msgs.append({'role': 'user', 'content': q})
    r = http.post(f'{BASE}/v1/chat/completions', json={
        'model': MODEL, 'messages': msgs, 'max_tokens': 300, 'temperature': 0, 'stream': False
    }, timeout=60).json()
    return r['choices'][0]['message']['content']

def generate_html(scenario_name, mode, results, run_id):
    color = '#28a745' if mode == 'post-rag' else '#6c757d'
    rows = ''
    for i, r in enumerate(results, 1):
        score = r.get('judge_score', '')
        feedback = r.get('judge_feedback', '')[:200]
        rows += f'''<tr>
          <td>{i}</td><td>{r['q']}</td>
          <td>{r['answer'][:400]}</td><td>{r['expected'][:400]}</td>
          <td><strong>{score}</strong><br><small>{feedback}</small></td>
        </tr>'''

    return f'''<!DOCTYPE html>
<html><head><meta charset=\"utf-8\"><title>RAG Eval - {scenario_name} ({mode})</title>
<style>
body {{ font-family: -apple-system, sans-serif; margin: 20px; background: #f8f9fa; }}
.container {{ max-width: 1400px; margin: 0 auto; background: #fff; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,.1); overflow: hidden; }}
.header {{ background: linear-gradient(135deg, {color}, {'#20c997' if mode=='post-rag' else '#495057'}); color: #fff; padding: 30px; text-align: center; }}
.content {{ padding: 30px; }}
table {{ width: 100%; border-collapse: collapse; margin-top: 15px; }}
th {{ background: {color}; color: #fff; padding: 12px 8px; text-align: left; font-size: .9em; }}
td {{ padding: 10px 8px; border-bottom: 1px solid #eee; vertical-align: top; max-width: 350px; word-wrap: break-word; font-size: .85em; }}
tr:nth-child(even) {{ background: #f8f9fa; }}
.meta {{ color: #6c757d; margin: 10px 0; }}
.badge {{ display: inline-block; padding: 4px 12px; border-radius: 4px; color: #fff; background: {color}; font-weight: bold; }}
</style></head><body>
<div class=\"container\">
  <div class=\"header\">
    <h1>RAG Evaluation Report</h1>
    <p>{scenario_name}</p>
    <span class=\"badge\">{mode.upper()}</span>
  </div>
  <div class=\"content\">
    <p class=\"meta\">Run ID: {run_id} | Mode: {mode} | Generated: {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())} | Tests: {len(results)}</p>
    <table>
      <thead><tr><th>#</th><th>Question</th><th>Generated Answer</th><th>Expected</th><th>Judge Score</th></tr></thead>
      <tbody>{rows}</tbody>
    </table>
  </div>
</div></body></html>'''

def upload_to_s3(html, s3_key):
    if not all([S3_ENDPOINT, S3_KEY, S3_SECRET]):
        print(f'    S3 credentials missing - cannot upload')
        return False
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
        return True
    except Exception as e:
        print(f'    Upload failed: {e}')
        return False

# --- Run evaluations ---
all_results = {}

for scenario, tests in scenarios.items():
    store_id = stores.get(scenario, '')
    print(f'\\n{\"=\"*70}')
    print(f'Scenario: {scenario}')
    print(f'{\"=\"*70}')

    for mode in ['pre-rag', 'post-rag']:
        print(f'\\n  --- {mode.upper()} ---')
        results = []
        rows_for_eval = []

        for t in tests:
            q, expected = t['q'], t['a']
            if mode == 'post-rag' and store_id:
                ctx = retrieve_context(q, store_id)
                answer = call_llm(q, context=ctx)
            else:
                answer = call_llm(q)

            results.append({'q': q, 'expected': expected, 'answer': answer,
                           'judge_score': '', 'judge_feedback': ''})
            rows_for_eval.append({
                'input_query': q, 'expected_answer': expected,
                'chat_completion_input': json.dumps([{'role':'user','content':q}]),
            })
            print(f'    Q: {q[:50]}...')
            print(f'    A: {answer[:80]}...')

        # Score via Llama Stack eval API
        ds_id = f'{scenario}-{mode}-{RUN_ID}'
        bm_id = f'{scenario}-{mode}-bm-{RUN_ID}'

        try:
            client.beta.datasets.register(purpose='eval/question-answer',
                source={'type':'rows','rows':rows_for_eval},
                dataset_id=ds_id, metadata={}, extra_body={'provider_id':'localfs'})

            client.alpha.benchmarks.register(benchmark_id=bm_id, dataset_id=ds_id,
                scoring_functions=['basic::subset_of', 'rag-eval-judge'],
                extra_body={'provider_id':'meta-reference'})

            job = client.alpha.eval.run_eval(bm_id, benchmark_config={
                'eval_candidate':{'type':'model','model':MODEL,'sampling_params':{'max_tokens':300}},
                'scoring_params':{'basic::subset_of':{'type':'basic','aggregation_functions':['accuracy']}},
            })
            result = client.alpha.eval.jobs.retrieve(job_id=job.job_id, benchmark_id=bm_id)

            # Extract scores
            for fn_id, sr in (result.scores or {}).items():
                for i, row in enumerate(sr.score_rows or []):
                    if i < len(results):
                        if 'judge' in fn_id:
                            results[i]['judge_score'] = row.get('judge_feedback','')[:50]
                            results[i]['judge_feedback'] = row.get('judge_feedback','')
                        else:
                            existing = results[i].get('judge_score','')
                            results[i]['judge_score'] = f'{existing} subset_of={row.get(\"score\",\"?\")}'.strip()

                if sr.aggregated_results:
                    print(f'    {fn_id}: {sr.aggregated_results}')

        except Exception as e:
            print(f'    Scoring error: {e}')

        # Generate and upload HTML report
        html = generate_html(scenario, mode, results, RUN_ID)
        s3_key = f'eval-results/{RUN_ID}/{scenario}_{mode}_report.html'
        upload_to_s3(html, s3_key)

        all_results[f'{scenario}_{mode}'] = results

# --- Summary ---
print(f'\\n{\"=\"*70}')
print(f'EVALUATION COMPLETE')
print(f'Run ID: {RUN_ID}')
print(f'Reports: s3://{S3_BUCKET}/eval-results/{RUN_ID}/')
print(f'{\"=\"*70}')
"

if [ $? -eq 0 ]; then
    echo ""
    log_success "Evaluation reports generated"
    echo ""
    echo "View reports:"
    echo "  MinIO UI: https://$(oc get route minio-console -n minio-storage -o jsonpath='{.spec.host}' 2>/dev/null || echo 'minio-console')/browser/${MINIO_BUCKET}/eval-results/${RUN_ID}/"
    echo "  CLI:      oc exec -n minio-storage deploy/minio -- mc ls local/${MINIO_BUCKET}/eval-results/${RUN_ID}/"
else
    log_error "Evaluation failed"
    exit 1
fi
