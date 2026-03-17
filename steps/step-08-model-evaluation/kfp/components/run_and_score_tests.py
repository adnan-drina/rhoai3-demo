"""
Run and Score Tests Component — evaluation harness for pre-RAG and post-RAG tests.

For each *_tests.yaml:
  1. Load config and resolve .txt template references
  2. For pre-RAG (mode=pre-rag): call model via LlamaStack /v1/chat/completions
  3. For post-RAG (mode=post-rag): retrieve context, then call model with context
  4. Score via mistral-3-bf16 as LLM-as-judge (direct vLLM endpoint)
  5. Generate per-scenario HTML reports
  6. Upload reports to S3
"""

from typing import List
from kfp.dsl import component


@component(
    base_image="python:3.12",
    packages_to_install=[
        "boto3",
        "pyyaml",
        "requests",
    ],
)
def run_and_score_tests_component(
    test_configs: List[dict],
    default_llamastack_url: str,
    run_id: str = "eval",
):
    import os
    import re
    import yaml
    import time
    import tempfile
    import requests as http

    EVAL_CONFIGS_DIR = "/shared-data/eval-configs"
    OAI_MODEL_PREFIX = "vllm-inference"
    JUDGE_URL = "http://mistral-3-bf16-predictor.private-ai.svc.cluster.local:8080/v1/chat/completions"
    JUDGE_MODEL = "mistral-3-bf16"

    def replace_txt_files(obj, base_path="."):
        if isinstance(obj, dict):
            return {k: replace_txt_files(v, base_path) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [replace_txt_files(item, base_path) for item in obj]
        elif isinstance(obj, str) and obj.endswith(".txt"):
            file_path = os.path.join(base_path, obj)
            if os.path.exists(file_path):
                with open(file_path, "r", encoding="utf-8") as f:
                    return f.read()
        return obj

    def resolve_vector_store_id(base_url, name):
        if not name:
            return None
        try:
            resp = http.get(f"{base_url}/v1/vector_stores", timeout=10)
            resp.raise_for_status()
            for vs in resp.json().get("data", []):
                if vs.get("name") == name:
                    return vs["id"]
        except Exception:
            pass
        return name

    def call_llm(base_url, model_id, prompt, system_prompt=None):
        oai_model = f"{OAI_MODEL_PREFIX}/{model_id}"
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        resp = http.post(
            f"{base_url}/v1/chat/completions",
            json={
                "model": oai_model,
                "messages": messages,
                "max_tokens": 2048,
                "temperature": 0,
                "stream": False,
            },
            timeout=120,
        )
        resp.raise_for_status()
        data = resp.json()
        choices = data.get("choices") or []
        if not choices:
            return {"answer": "", "tool_calls": []}

        msg = choices[0].get("message", {})
        content = msg.get("content") or ""
        return {"answer": content, "tool_calls": []}

    def call_rag_agent(base_url, model_id, vector_db_id, prompt):
        store_id = resolve_vector_store_id(base_url, vector_db_id)
        oai_model = f"{OAI_MODEL_PREFIX}/{model_id}"

        context_text = ""
        tool_calls = []
        try:
            search_resp = http.post(
                f"{base_url}/v1/vector_stores/{store_id}/search",
                json={"query": prompt, "max_num_results": 5},
                timeout=30,
            )
            search_resp.raise_for_status()
            results = search_resp.json().get("data", [])
            if results:
                tool_calls.append("builtin::rag/knowledge_search")
                chunks = []
                for r in results:
                    for c in r.get("content", []):
                        chunks.append(c.get("text", ""))
                context_text = "\n---\n".join(chunks)
        except Exception as e:
            print(f"    Retrieval warning: {e}")

        system = "You are a helpful assistant. Answer based on the provided document context."
        if context_text:
            system += f"\n\nDocument context:\n{context_text[:4000]}"

        resp = http.post(
            f"{base_url}/v1/chat/completions",
            json={
                "model": oai_model,
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": prompt},
                ],
                "max_tokens": 2048,
                "temperature": 0,
                "stream": False,
            },
            timeout=120,
        )
        resp.raise_for_status()
        data = resp.json()
        choices = data.get("choices") or []
        if not choices:
            return {"answer": "", "tool_calls": tool_calls}

        content = choices[0].get("message", {}).get("content") or ""
        return {"answer": content, "tool_calls": tool_calls}

    def call_judge(question, expected, generated, judge_template):
        prompt = (
            judge_template
            .replace("{input_query}", question)
            .replace("{expected_answer}", expected)
            .replace("{generated_answer}", generated)
        )
        try:
            r = http.post(
                JUDGE_URL,
                json={
                    "model": JUDGE_MODEL,
                    "messages": [{"role": "user", "content": prompt}],
                    "max_tokens": 300,
                    "temperature": 0,
                    "stream": False,
                },
                timeout=60,
            )
            r.raise_for_status()
            feedback = r.json()["choices"][0]["message"]["content"]
            match = re.search(r"\(([A-E])\)", feedback)
            letter = match.group(1) if match else feedback[:3]
            return letter, feedback
        except Exception as e:
            return "?", f"Judge error: {e}"

    def score_tool_choice(eval_row):
        actual = set(eval_row.get("tool_calls", []))
        expected = set(eval_row.get("expected_tools", []))
        if not expected:
            return {"score": 1.0, "note": "No tool expectations"}
        missing = expected - actual
        extra = actual - expected
        if not missing and not extra:
            score = 1.0
        elif not missing:
            score = 0.8
        elif len(missing) < len(expected):
            score = 0.5
        else:
            score = 0.0
        return {"score": score, "tools_called": sorted(actual), "tools_expected": sorted(expected)}

    def generate_html_report(scenario_results, scenario_name, mode):
        color = "#28a745" if mode == "post-rag" else "#6c757d"
        alt_color = "#20c997" if mode == "post-rag" else "#495057"
        rows_html = ""
        for i, r in enumerate(scenario_results, 1):
            letter = r.get("judge_letter", "?")
            lcolor = {
                "A": "#28a745", "B": "#28a745",
                "C": "#ffc107", "D": "#6c757d", "E": "#dc3545",
            }.get(letter, "#6c757d")
            tools = ", ".join(r.get("tool_calls", [])) or "none"

            rows_html += f"""
            <tr>
              <td style="text-align:center">{i}</td>
              <td>{r['prompt'][:250]}</td>
              <td>{r['answer'][:500]}</td>
              <td>{r['expected'][:500]}</td>
              <td><span style="display:inline-block;padding:2px 10px;border-radius:4px;background:{lcolor};color:#fff;font-weight:bold;font-size:1.1em">({letter})</span><br><small>{r.get('judge_feedback', '')[:300]}</small></td>
              <td>{tools}</td>
            </tr>"""

        return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>RAG Eval - {scenario_name} ({mode})</title>
<style>
body {{ font-family: -apple-system, sans-serif; margin: 20px; background: #f8f9fa; }}
.container {{ max-width: 1400px; margin: 0 auto; background: #fff; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,.1); overflow: hidden; }}
.header {{ background: linear-gradient(135deg, {color}, {alt_color}); color: #fff; padding: 30px; text-align: center; }}
table {{ width: 100%; border-collapse: collapse; margin: 15px 0; }}
th {{ background: {color}; color: #fff; padding: 12px 8px; text-align: left; font-size: .9em; }}
td {{ padding: 10px 8px; border-bottom: 1px solid #eee; vertical-align: top; max-width: 350px; word-wrap: break-word; font-size: .85em; }}
tr:nth-child(even) {{ background: #f8f9fa; }}
.meta {{ color: #6c757d; margin: 10px 30px; font-size: .9em; }}
.badge {{ display: inline-block; padding: 4px 12px; border-radius: 4px; color: #fff; background: {color}; font-weight: bold; }}
</style></head><body>
<div class="container">
  <div class="header"><h1>RAG Evaluation Report</h1><p>{scenario_name}</p><span class="badge">{mode.upper()}</span></div>
  <p class="meta">Run ID: {run_id} | Candidate: granite-8b-agent | Judge: {JUDGE_MODEL} | {time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime())} | Tests: {len(scenario_results)}</p>
  <div style="padding: 0 30px 30px;"><table><thead><tr><th>#</th><th>Question</th><th>Generated Answer</th><th>Expected</th><th>Judge Score</th><th>Tools</th></tr></thead>
  <tbody>{rows_html}</tbody></table></div>
</div></body></html>"""

    def upload_to_s3(html_content, s3_key):
        import boto3
        endpoint = os.environ.get("AWS_S3_ENDPOINT")
        bucket = os.environ.get("AWS_S3_BUCKET", "pipelines")
        access_key = os.environ.get("AWS_ACCESS_KEY_ID")
        secret_key = os.environ.get("AWS_SECRET_ACCESS_KEY")
        if not all([endpoint, access_key, secret_key]):
            print("    S3 credentials incomplete — skipping upload")
            return
        s3 = boto3.client(
            "s3",
            endpoint_url=endpoint if endpoint.startswith("http") else f"http://{endpoint}",
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            verify=False,
        )
        with tempfile.NamedTemporaryFile(mode="w", suffix=".html", delete=False) as f:
            f.write(html_content)
            tmp_path = f.name
        try:
            s3.upload_file(tmp_path, bucket, s3_key, ExtraArgs={"ContentType": "text/html"})
            print(f"    Uploaded to s3://{bucket}/{s3_key}")
        finally:
            os.unlink(tmp_path)

    # -- main logic --
    print("=" * 60)
    print("RAG Evaluation Harness (Pre-RAG + Post-RAG)")
    print(f"  Configs: {len(test_configs)}")
    print(f"  Run ID: {run_id}")
    print(f"  Judge: {JUDGE_MODEL} (direct vLLM endpoint)")
    print("=" * 60)

    for config_dict in test_configs:
        config_path = config_dict["config_path"]
        full_path = os.path.join(EVAL_CONFIGS_DIR, config_path)

        print(f"\n--- {config_path} ---")

        with open(full_path, "r") as f:
            config = yaml.safe_load(f)

        scenario_name = config.get("name", config_path)
        vector_db_id = config.get("vector_db_id")
        model_id = config.get("model_id", "granite-8b-agent")
        mode = config.get("mode", "post-rag" if vector_db_id else "pre-rag")
        llamastack_url = config.get("llamastack_url", default_llamastack_url)

        scoring_params = config.get("scoring_params", {})
        scoring_params = replace_txt_files(
            scoring_params,
            os.path.join(EVAL_CONFIGS_DIR, os.path.dirname(config_path)),
        )

        judge_template = ""
        for scorer_name, scorer_config in scoring_params.items():
            if isinstance(scorer_config, dict):
                pt = scorer_config.get("prompt_template", "")
                if pt and isinstance(pt, str) and len(pt) > 50:
                    judge_template = pt
                    break
        if not judge_template:
            judge_template_path = os.path.join(EVAL_CONFIGS_DIR, "scoring-templates", "judge_prompt.txt")
            if os.path.exists(judge_template_path):
                with open(judge_template_path, "r") as f:
                    judge_template = f.read()

        tests = config.get("tests", [])
        print(f"  Scenario: {scenario_name}")
        print(f"  Mode: {mode}")
        print(f"  Collection: {vector_db_id or 'none (pre-rag)'}")
        print(f"  Tests: {len(tests)}")

        scenario_results = []

        for idx, test in enumerate(tests, 1):
            prompt = test["prompt"]
            expected = test["expected_result"]
            expected_tools = test.get("expected_tools", [])

            print(f"  [{idx}/{len(tests)}] {prompt[:60]}...")

            try:
                if mode == "pre-rag" or not vector_db_id:
                    result = call_llm(llamastack_url, model_id, prompt)
                else:
                    result = call_rag_agent(llamastack_url, model_id, vector_db_id, prompt)
                print(f"    Answer: {result['answer'][:80]}...")
            except Exception as e:
                print(f"    ERROR: {e}")
                result = {"answer": f"ERROR: {e}", "tool_calls": []}

            letter, feedback = call_judge(prompt, expected, result["answer"], judge_template)
            print(f"    Judge: ({letter})")

            tool_score = score_tool_choice({
                "tool_calls": result["tool_calls"],
                "expected_tools": expected_tools,
            })

            scenario_results.append({
                "prompt": prompt,
                "answer": result["answer"],
                "expected": expected,
                "tool_calls": result["tool_calls"],
                "judge_letter": letter,
                "judge_feedback": feedback,
                "tool_score": tool_score,
            })

        # Print summary
        print(f"\n  Results for {scenario_name} ({mode}):")
        for i, sr in enumerate(scenario_results, 1):
            print(f"    [{i}] Judge: ({sr['judge_letter']}) | Tools: {sr['tool_calls']}")

        # Generate and upload HTML — correct naming: {scenario}_{mode}_report.html
        html = generate_html_report(scenario_results, scenario_name, mode)
        safe_name = os.path.basename(config_path).replace(".yaml", "").replace("_tests", "")
        s3_key = f"eval-results/{run_id}/{safe_name}_report.html"
        upload_to_s3(html, s3_key)

    print("\n" + "=" * 60)
    print(f"Evaluation complete. Processed {len(test_configs)} config(s).")
    print("=" * 60)
