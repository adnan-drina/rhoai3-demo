"""
Run and Score Tests Component -- the main evaluation harness.

For each discovered *_tests.yaml config:
  1. Loads the YAML and resolves .txt file references in scoring templates
  2. Calls the RAG agent through Llama Stack Agent API (full chain)
  3. Scores outputs via Llama Stack scoring.score() API
  4. Runs custom tool_choice scorer for agent tool invocation checks
  5. Generates per-scenario HTML reports
  6. Uploads reports to S3

Adapted from rhoai-genaiops run_all_llamastack_tests with RAG agent
execution replacing the generic backend HTTP POST.
"""

from typing import List
from kfp.dsl import component


@component(
    base_image="python:3.12",
    packages_to_install=[
        "llama_stack_client==0.3.1",
        "boto3",
        "pyyaml",
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
    from types import SimpleNamespace
    from llama_stack_client import LlamaStackClient

    EVAL_CONFIGS_DIR = "/eval-configs"

    # -- helpers ---------------------------------------------------------------

    def replace_txt_files(obj, base_path="."):
        """Replace any string ending in .txt with the contents of that file."""
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

    def call_rag_agent(client, model_id, vector_db_id, prompt):
        """
        Call the RAG agent through Llama Stack Agent API.
        Returns dict with answer text and tool_calls list.
        """
        import uuid

        try:
            from llama_stack_client import Agent, AgentEventLogger

            agent = Agent(
                client,
                model=model_id,
                instructions="You are a helpful assistant. Answer questions based on the provided documents.",
                tools=[{
                    "name": "builtin::rag/knowledge_search",
                    "args": {"vector_store_ids": [vector_db_id]},
                }],
            )

            session_id = agent.create_session(session_name=f"eval-{uuid.uuid4().hex[:8]}")
            response = agent.create_turn(
                messages=[{"role": "user", "content": prompt}],
                session_id=session_id,
                stream=False,
            )

            answer = ""
            tool_calls = []

            if hasattr(response, "output_message"):
                answer = response.output_message.content or ""
            elif hasattr(response, "content"):
                answer = response.content or ""

            if hasattr(response, "steps"):
                for step in response.steps or []:
                    if hasattr(step, "tool_calls"):
                        for tc in step.tool_calls or []:
                            tool_name = getattr(tc, "tool_name", None) or getattr(tc, "name", "unknown")
                            tool_calls.append(str(tool_name))

            return {"answer": answer if isinstance(answer, str) else str(answer), "tool_calls": tool_calls}

        except Exception as e:
            print(f"    Agent call failed: {e}")
            # Fallback: direct inference without RAG
            try:
                resp = client.inference.chat_completion(
                    model_id=model_id,
                    messages=[{"role": "user", "content": prompt}],
                    sampling_params={"strategy": {"type": "greedy"}, "max_tokens": 1024},
                )
                content = resp.completion_message.content or ""
                return {"answer": content if isinstance(content, str) else str(content), "tool_calls": []}
            except Exception as e2:
                print(f"    Fallback inference also failed: {e2}")
                return {"answer": f"ERROR: {e2}", "tool_calls": []}

    def score_tool_choice(eval_row):
        """
        Custom scorer: verify expected RAG tools were invoked.
        1.0 = perfect match, 0.8 = all expected + extras,
        0.5 = partial, 0.0 = missed all.
        """
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

        return {
            "score": score,
            "tools_called": sorted(actual),
            "tools_expected": sorted(expected),
            "missing_tools": sorted(missing),
            "extra_tools": sorted(extra),
        }

    def generate_html_report(scenario_results, scenario_name):
        """Generate a self-contained HTML report for one scenario."""
        rows_html = ""
        for i, result in enumerate(scenario_results, 1):
            scores_parts = []
            for scorer_name, score_data in result.get("scores", {}).items():
                s = score_data.get("score", "N/A") if isinstance(score_data, dict) else "N/A"
                scores_parts.append(f"<strong>{scorer_name}:</strong> {s}")
            scores_cell = "<br>".join(scores_parts) if scores_parts else "N/A"

            tools_called = ", ".join(result.get("tool_calls", [])) or "none"

            rows_html += f"""
            <tr>
              <td style="text-align:center">{i}</td>
              <td>{result.get('prompt', '')}</td>
              <td>{result.get('answer', '')[:500]}</td>
              <td>{result.get('expected', '')[:500]}</td>
              <td>{scores_cell}</td>
              <td>{tools_called}</td>
            </tr>"""

        return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>RAG Eval - {scenario_name}</title>
<style>
body {{ font-family: -apple-system, sans-serif; margin: 20px; background: #f8f9fa; }}
.container {{ max-width: 1400px; margin: 0 auto; background: #fff; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,.1); overflow: hidden; }}
.header {{ background: linear-gradient(135deg, #667eea, #764ba2); color: #fff; padding: 30px; text-align: center; }}
.content {{ padding: 30px; }}
table {{ width: 100%; border-collapse: collapse; margin-top: 15px; }}
th {{ background: #667eea; color: #fff; padding: 12px 8px; text-align: left; font-size: .9em; }}
td {{ padding: 10px 8px; border-bottom: 1px solid #eee; vertical-align: top; max-width: 300px; word-wrap: break-word; font-size: .85em; }}
tr:nth-child(even) {{ background: #f8f9fa; }}
.meta {{ color: #6c757d; margin: 10px 0; }}
</style></head><body>
<div class="container">
  <div class="header"><h1>RAG Evaluation Report</h1><p>{scenario_name}</p></div>
  <div class="content">
    <p class="meta">Run ID: {run_id} | Generated: {time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime())} | Tests: {len(scenario_results)}</p>
    <table>
      <thead><tr><th>#</th><th>Prompt</th><th>Generated Answer</th><th>Expected Answer</th><th>Scores</th><th>Tools Called</th></tr></thead>
      <tbody>{rows_html}</tbody>
    </table>
  </div>
</div></body></html>"""

    def upload_to_s3(html_content, s3_key):
        """Upload HTML string to S3 via boto3."""
        import boto3

        endpoint = os.environ.get("AWS_S3_ENDPOINT")
        bucket = os.environ.get("AWS_S3_BUCKET", "pipelines")
        access_key = os.environ.get("AWS_ACCESS_KEY_ID")
        secret_key = os.environ.get("AWS_SECRET_ACCESS_KEY")
        region = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")

        if not all([endpoint, access_key, secret_key]):
            print("    S3 credentials incomplete -- skipping upload")
            return

        s3 = boto3.client(
            "s3",
            endpoint_url=endpoint if endpoint.startswith("http") else f"http://{endpoint}",
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            region_name=region,
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

    # -- main logic ------------------------------------------------------------

    print("=" * 60)
    print("RAG Evaluation Harness")
    print(f"  Configs to process: {len(test_configs)}")
    print(f"  Run ID: {run_id}")
    print("=" * 60)

    client = LlamaStackClient(
        base_url=default_llamastack_url,
        timeout=600.0,
    )

    for config_dict in test_configs:
        config_path = config_dict["config_path"]
        full_path = os.path.join(EVAL_CONFIGS_DIR, config_path)

        print(f"\n--- Processing: {config_path} ---")

        with open(full_path, "r") as f:
            config = yaml.safe_load(f)

        scenario_name = config.get("name", config_path)
        vector_db_id = config["vector_db_id"]
        model_id = config.get("model_id", "granite-8b-agent")
        llamastack_url = config.get("llamastack_url", default_llamastack_url)

        if llamastack_url != default_llamastack_url:
            test_client = LlamaStackClient(base_url=llamastack_url, timeout=600.0)
        else:
            test_client = client

        scoring_params = config.get("scoring_params", {})
        scoring_params = replace_txt_files(scoring_params, os.path.join(EVAL_CONFIGS_DIR, os.path.dirname(config_path)))

        tests = config.get("tests", [])
        print(f"  Scenario: {scenario_name}")
        print(f"  Collection: {vector_db_id}")
        print(f"  Tests: {len(tests)}")

        eval_rows = []
        scenario_results = []

        for idx, test in enumerate(tests, 1):
            prompt = test["prompt"]
            expected = test["expected_result"]
            expected_tools = test.get("expected_tools", [])

            print(f"  [{idx}/{len(tests)}] {prompt[:60]}...")

            result = call_rag_agent(test_client, model_id, vector_db_id, prompt)

            eval_row = {
                "input_query": prompt,
                "generated_answer": result["answer"],
                "expected_answer": expected,
                "tool_calls": result["tool_calls"],
                "expected_tools": expected_tools,
            }
            eval_rows.append(eval_row)

            scenario_result = {
                "prompt": prompt,
                "answer": result["answer"],
                "expected": expected,
                "tool_calls": result["tool_calls"],
                "scores": {},
            }
            scenario_results.append(scenario_result)

        # -- Llama Stack scoring ---
        llama_stack_scorers = {}
        custom_results = {}

        for scorer_name, scorer_config in scoring_params.items():
            if scorer_name == "basic::tool_choice":
                print(f"  Scoring: {scorer_name} (custom)")
                tool_scores = [score_tool_choice(row) for row in eval_rows]
                custom_results[scorer_name] = tool_scores
            else:
                llama_stack_scorers[scorer_name] = scorer_config

        if llama_stack_scorers:
            print(f"  Scoring via Llama Stack: {list(llama_stack_scorers.keys())}")
            try:
                scoring_response = test_client.scoring.score(
                    input_rows=eval_rows,
                    scoring_functions=llama_stack_scorers,
                )

                for scorer_name, result in scoring_response.results.items():
                    if hasattr(result, "score_rows") and result.score_rows:
                        for i, score_row in enumerate(result.score_rows):
                            if i < len(scenario_results):
                                scenario_results[i]["scores"][scorer_name] = score_row

                    if hasattr(result, "aggregated_results") and result.aggregated_results:
                        print(f"    {scorer_name} aggregate: {result.aggregated_results}")

            except Exception as e:
                print(f"  Llama Stack scoring failed: {e}")
                for i in range(len(scenario_results)):
                    for scorer_name in llama_stack_scorers:
                        scenario_results[i]["scores"][scorer_name] = {"score": "ERROR", "error": str(e)}

        # Merge custom tool_choice scores
        for scorer_name, scores in custom_results.items():
            for i, score_data in enumerate(scores):
                if i < len(scenario_results):
                    scenario_results[i]["scores"][scorer_name] = score_data

        # Print summary
        print(f"\n  Results for {scenario_name}:")
        for i, sr in enumerate(scenario_results, 1):
            score_parts = [f"{k}={v.get('score', '?')}" for k, v in sr["scores"].items() if isinstance(v, dict)]
            print(f"    [{i}] {', '.join(score_parts)} | tools: {sr['tool_calls']}")

        # -- Generate and upload HTML ---
        html = generate_html_report(scenario_results, scenario_name)
        safe_name = vector_db_id.replace("/", "_")
        s3_key = f"eval-results/{run_id}/{safe_name}_results.html"
        upload_to_s3(html, s3_key)

    print("\n" + "=" * 60)
    print(f"Evaluation complete. Processed {len(test_configs)} config(s).")
    print("=" * 60)
