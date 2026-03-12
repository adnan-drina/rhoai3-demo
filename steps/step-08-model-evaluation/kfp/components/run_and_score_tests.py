"""
Run and Score Tests Component — evaluation harness for pre-RAG and post-RAG tests.

Inspired by: https://github.com/rhoai-genaiops/evals/blob/main/evals-pipeline/kfp_pipeline.py

For each *_tests.yaml:
  1. Load config and resolve .txt template references
  2. For pre-RAG (mode=pre-rag): call /v1/chat/completions without tools
  3. For post-RAG (mode=post-rag): call /v1/chat/completions, then score tool_choice
  4. Score via LlamaStack scoring.score() (basic + llm-as-judge)
  5. Generate per-scenario HTML reports
  6. Upload reports to S3
"""

from typing import List
from kfp.dsl import component


@component(
    base_image="python:3.12",
    packages_to_install=[
        "llama_stack_client==0.4.2",
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
    import yaml
    import json
    import time
    import tempfile
    import requests as http

    EVAL_CONFIGS_DIR = "/shared-data/eval-configs"
    OAI_MODEL_PREFIX = "vllm-granite-agent"

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
        """Direct LLM call via OpenAI-compatible endpoint (pre-RAG mode)."""
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
        """RAG: retrieve context via vector_stores/search, then call chat/completions."""
        store_id = resolve_vector_store_id(base_url, vector_db_id)
        oai_model = f"{OAI_MODEL_PREFIX}/{model_id}"

        # Step 1: Retrieve context from vector store
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

        # Step 2: Call LLM with retrieved context
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
        rows_html = ""
        for i, result in enumerate(scenario_results, 1):
            scores_parts = []
            for scorer_name, score_data in result.get("scores", {}).items():
                s = score_data.get("score", "N/A") if isinstance(score_data, dict) else "N/A"
                scores_parts.append(f"<strong>{scorer_name}:</strong> {s}")
            scores_cell = "<br>".join(scores_parts) if scores_parts else "N/A"
            tools = ", ".join(result.get("tool_calls", [])) or "none"
            mode_badge = f'<span style="background:{("#28a745" if mode=="post-rag" else "#6c757d")};color:#fff;padding:2px 8px;border-radius:4px;font-size:.75em">{mode}</span>'

            rows_html += f"""
            <tr>
              <td style="text-align:center">{i}</td>
              <td>{result.get('prompt', '')}</td>
              <td>{result.get('answer', '')[:500]}</td>
              <td>{result.get('expected', '')[:500]}</td>
              <td>{scores_cell}</td>
              <td>{tools}</td>
            </tr>"""

        return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>RAG Eval - {scenario_name}</title>
<style>
body {{ font-family: -apple-system, sans-serif; margin: 20px; background: #f8f9fa; }}
.container {{ max-width: 1400px; margin: 0 auto; background: #fff; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,.1); overflow: hidden; }}
.header {{ background: linear-gradient(135deg, {"#28a745, #20c997" if mode=="post-rag" else "#6c757d, #495057"}); color: #fff; padding: 30px; text-align: center; }}
.content {{ padding: 30px; }}
table {{ width: 100%; border-collapse: collapse; margin-top: 15px; }}
th {{ background: {"#28a745" if mode=="post-rag" else "#6c757d"}; color: #fff; padding: 12px 8px; text-align: left; font-size: .9em; }}
td {{ padding: 10px 8px; border-bottom: 1px solid #eee; vertical-align: top; max-width: 300px; word-wrap: break-word; font-size: .85em; }}
tr:nth-child(even) {{ background: #f8f9fa; }}
.meta {{ color: #6c757d; margin: 10px 0; }}
</style></head><body>
<div class="container">
  <div class="header"><h1>RAG Evaluation — {mode.upper()}</h1><p>{scenario_name}</p></div>
  <div class="content">
    <p class="meta">Run ID: {run_id} | Mode: {mode} | Generated: {time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime())} | Tests: {len(scenario_results)}</p>
    <table>
      <thead><tr><th>#</th><th>Prompt</th><th>Generated Answer</th><th>Expected</th><th>Scores</th><th>Tools</th></tr></thead>
      <tbody>{rows_html}</tbody>
    </table>
  </div>
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

        tests = config.get("tests", [])
        print(f"  Scenario: {scenario_name}")
        print(f"  Mode: {mode}")
        print(f"  Collection: {vector_db_id or 'none (pre-rag)'}")
        print(f"  Tests: {len(tests)}")

        eval_rows = []
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

            eval_row = {
                "input_query": prompt,
                "generated_answer": result["answer"],
                "expected_answer": expected,
                "tool_calls": result["tool_calls"],
                "expected_tools": expected_tools,
            }
            eval_rows.append(eval_row)
            scenario_results.append({
                "prompt": prompt,
                "answer": result["answer"],
                "expected": expected,
                "tool_calls": result["tool_calls"],
                "scores": {},
            })

        # -- Scoring --
        llama_stack_scorers = {}
        custom_results = {}

        for scorer_name, scorer_config in scoring_params.items():
            if scorer_name == "basic::tool_choice":
                print(f"  Scoring: {scorer_name} (custom)")
                custom_results[scorer_name] = [score_tool_choice(r) for r in eval_rows]
            else:
                llama_stack_scorers[scorer_name] = scorer_config

        if llama_stack_scorers:
            print(f"  Scoring via LlamaStack: {list(llama_stack_scorers.keys())}")
            try:
                score_resp = http.post(
                    f"{llamastack_url}/v1/scoring/score",
                    json={
                        "input_rows": [
                            {k: v for k, v in r.items() if k in ("input_query", "generated_answer", "expected_answer")}
                            for r in eval_rows
                        ],
                        "scoring_functions": llama_stack_scorers,
                    },
                    timeout=300,
                )
                score_resp.raise_for_status()
                scoring_data = score_resp.json()

                for scorer_name, result_data in scoring_data.get("results", {}).items():
                    rows = result_data.get("score_rows", [])
                    for i, sr in enumerate(rows):
                        if i < len(scenario_results):
                            scenario_results[i]["scores"][scorer_name] = sr
                    agg = result_data.get("aggregated_results")
                    if agg:
                        print(f"    {scorer_name} aggregate: {agg}")

            except Exception as e:
                print(f"  Scoring error: {e}")
                for i in range(len(scenario_results)):
                    for sn in llama_stack_scorers:
                        scenario_results[i]["scores"][sn] = {"score": "ERROR", "error": str(e)[:100]}

        for scorer_name, scores in custom_results.items():
            for i, sd in enumerate(scores):
                if i < len(scenario_results):
                    scenario_results[i]["scores"][scorer_name] = sd

        # Print summary
        print(f"\n  Results for {scenario_name} ({mode}):")
        for i, sr in enumerate(scenario_results, 1):
            sp = [f"{k}={v.get('score','?')}" for k, v in sr["scores"].items() if isinstance(v, dict)]
            print(f"    [{i}] {', '.join(sp)} | tools: {sr['tool_calls']}")

        # Generate and upload HTML
        html = generate_html_report(scenario_results, scenario_name, mode)
        safe_name = (vector_db_id or "baseline").replace("/", "_")
        s3_key = f"eval-results/{run_id}/{safe_name}_{mode}_results.html"
        upload_to_s3(html, s3_key)

    print("\n" + "=" * 60)
    print(f"Evaluation complete. Processed {len(test_configs)} config(s).")
    print("=" * 60)
