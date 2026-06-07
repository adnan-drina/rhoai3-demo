"""EvalHub adapter for the ACME and whoami RAG scenario evaluations."""

from __future__ import annotations

import json
import os
import re
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import requests
import yaml
from evalhub.adapter import (
    EvaluationResult,
    FrameworkAdapter,
    JobCallbacks,
    JobPhase,
    JobResults,
    JobSpec,
    JobStatus,
    JobStatusUpdate,
    MessageInfo,
)


BENCHMARK_CONFIGS = {
    "acme_corporate_pre_rag": "acme_corporate_pre_rag_tests.yaml",
    "acme_corporate_post_rag": "acme_corporate_post_rag_tests.yaml",
    "whoami_pre_rag": "whoami_pre_rag_tests.yaml",
    "whoami_post_rag": "whoami_post_rag_tests.yaml",
}

LETTER_SCORES = {
    "A": 1.0,
    "B": 0.9,
    "C": 0.5,
    "D": 0.25,
    "E": 0.0,
}

DEFAULT_JUDGE_PROMPT = """You are an evaluation judge comparing a GENERATED RESPONSE against an EXPECTED RESPONSE.

Question: {input_query}
Expected Response: {expected_answer}
Generated Response: {generated_answer}

Select the BEST match:
(A) The Generated Response contains the SAME key facts as the Expected Response.
(B) The Generated Response is a SUPERSET with all expected points plus correct detail.
(C) The Generated Response is a SUBSET with some but not all expected points.
(D) The responses differ but do NOT affect factual accuracy.
(E) The Generated Response DISAGREES with or CONTRADICTS the Expected Response.

You MUST respond with exactly one letter in parentheses followed by a brief explanation.

Answer:
"""


class RAGScenarioAdapter(FrameworkAdapter):
    """Run one YAML-backed RAG scenario benchmark inside an EvalHub job pod."""

    def run_benchmark_job(self, config: JobSpec, callbacks: JobCallbacks) -> JobResults:
        started = time.monotonic()
        params = config.parameters or {}
        callbacks.report_status(
            JobStatusUpdate(
                status=JobStatus.RUNNING,
                phase=JobPhase.INITIALIZING,
                progress=0.0,
                message=MessageInfo(
                    message=f"Loading {config.benchmark_id}",
                    message_code="rag_scenario_loading",
                ),
            )
        )

        scenario_config = self._load_scenario_config(config.benchmark_id, params)
        judge_prompt = self._load_judge_prompt(params)
        tests = scenario_config.get("tests") or []
        if not tests:
            raise ValueError(f"Scenario {config.benchmark_id} has no tests")

        mode = scenario_config.get("mode") or ("post-rag" if scenario_config.get("vector_db_id") else "pre-rag")
        vector_db_id = scenario_config.get("vector_db_id")
        model_id = params.get("model_id") or scenario_config.get("model_id") or config.model.name
        llamastack_url = (
            params.get("llamastack_url")
            or scenario_config.get("llamastack_url")
            or config.model.url
        )
        judge_url = params.get(
            "judge_url",
            os.environ.get(
                "RAG_EVAL_JUDGE_URL",
                "http://mistral-3-bf16-predictor.maas.svc.cluster.local:8080/v1",
            ),
        )
        judge_model = params.get("judge_model", os.environ.get("RAG_EVAL_JUDGE_MODEL", "mistral-3-bf16"))
        pass_letters = set(params.get("pass_letters") or ["A", "B"])

        scenario_results: list[dict[str, Any]] = []
        total = len(tests)

        for index, test in enumerate(tests, 1):
            callbacks.report_status(
                JobStatusUpdate(
                    status=JobStatus.RUNNING,
                    phase=JobPhase.RUNNING_EVALUATION,
                    progress=(index - 1) / total,
                    message=MessageInfo(
                        message=f"Evaluating test {index}/{total}",
                        message_code="rag_scenario_running",
                    ),
                    current_step=test.get("prompt", "")[:120],
                    total_steps=total,
                    completed_steps=index - 1,
                )
            )

            prompt = test["prompt"]
            expected = test["expected_result"]
            expected_tools = test.get("expected_tools") or []

            if mode == "pre-rag" or not vector_db_id:
                answer_payload = self._call_llm(llamastack_url, model_id, prompt, params)
            else:
                answer_payload = self._call_rag(llamastack_url, model_id, vector_db_id, prompt, params)

            letter, feedback = self._call_judge(
                judge_url=judge_url,
                judge_model=judge_model,
                question=prompt,
                expected=expected,
                generated=answer_payload["answer"],
                judge_template=judge_prompt,
                timeout=int(params.get("judge_timeout_seconds", 60)),
            )
            tool_score = self._score_tool_choice(answer_payload["tool_calls"], expected_tools)

            scenario_results.append(
                {
                    "index": index,
                    "prompt": prompt,
                    "expected": expected,
                    "answer": answer_payload["answer"],
                    "tool_calls": answer_payload["tool_calls"],
                    "expected_tools": expected_tools,
                    "judge_letter": letter,
                    "judge_score": LETTER_SCORES.get(letter, 0.0),
                    "judge_feedback": feedback,
                    "tool_score": tool_score,
                    "passed": letter in pass_letters,
                }
            )

        duration = time.monotonic() - started
        metrics, summary = self._summarize(scenario_config, mode, scenario_results, pass_letters)

        callbacks.report_status(
            JobStatusUpdate(
                status=JobStatus.RUNNING,
                phase=JobPhase.POST_PROCESSING,
                progress=1.0,
                message=MessageInfo(
                    message="Packaging RAG scenario results",
                    message_code="rag_scenario_post_processing",
                ),
                total_steps=total,
                completed_steps=total,
            )
        )

        return JobResults(
            id=config.id,
            benchmark_id=config.benchmark_id,
            benchmark_index=config.benchmark_index,
            model_name=config.model.name,
            results=metrics,
            overall_score=float(summary["pass_rate"]),
            num_examples_evaluated=total,
            duration_seconds=duration,
            completed_at=datetime.now(UTC),
            evaluation_metadata={
                "artifacts": {
                    "rag_scenario_summary": summary,
                    "rag_scenario_results": scenario_results,
                }
            },
        )

    def _load_scenario_config(self, benchmark_id: str, params: dict[str, Any]) -> dict[str, Any]:
        config_name = params.get("config_name") or BENCHMARK_CONFIGS.get(benchmark_id)
        if not config_name:
            raise ValueError(f"Unknown RAG scenario benchmark: {benchmark_id}")

        raw_yaml = params.get("config_yaml")
        if not raw_yaml:
            raw_yaml = self._load_text_config("eval-test-cases", config_name, params)

        parsed = yaml.safe_load(raw_yaml) or {}
        if not isinstance(parsed, dict):
            raise ValueError(f"Scenario config {config_name} is not a YAML mapping")
        return parsed

    def _load_judge_prompt(self, params: dict[str, Any]) -> str:
        if params.get("judge_prompt"):
            return str(params["judge_prompt"])

        try:
            return self._load_text_config(
                "eval-configs",
                "judge_prompt.txt",
                params,
                env_path="RAG_EVAL_JUDGE_PROMPT_PATH",
            )
        except Exception:
            return DEFAULT_JUDGE_PROMPT

    def _load_text_config(
        self,
        configmap_name: str,
        key: str,
        params: dict[str, Any],
        env_path: str | None = None,
    ) -> str:
        if env_path and os.environ.get(env_path):
            return Path(os.environ[env_path]).read_text(encoding="utf-8")

        local_dir = params.get("config_dir") or os.environ.get("RAG_EVAL_CONFIG_DIR")
        if local_dir:
            candidate = Path(local_dir) / key
            if candidate.exists():
                return candidate.read_text(encoding="utf-8")
            candidate = Path(local_dir) / "scoring-templates" / key
            if candidate.exists():
                return candidate.read_text(encoding="utf-8")

        namespace = (
            params.get("config_namespace")
            or os.environ.get("RAG_EVAL_CONFIG_NAMESPACE")
            or self._service_account_namespace()
            or "enterprise-rag"
        )
        data = self._read_configmap(namespace, configmap_name)
        if key not in data:
            raise KeyError(f"ConfigMap {namespace}/{configmap_name} does not contain key {key}")
        return data[key]

    def _read_configmap(self, namespace: str, name: str) -> dict[str, str]:
        token_path = Path("/var/run/secrets/kubernetes.io/serviceaccount/token")
        if not token_path.exists():
            raise RuntimeError("Kubernetes service account token is not available")

        ca_path = Path("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")
        verify: str | bool = str(ca_path) if ca_path.exists() else True
        token = token_path.read_text(encoding="utf-8").strip()
        url = f"https://kubernetes.default.svc/api/v1/namespaces/{namespace}/configmaps/{name}"
        response = requests.get(
            url,
            headers={"Authorization": f"Bearer {token}"},
            verify=verify,
            timeout=10,
        )
        if response.status_code != 200:
            raise RuntimeError(
                f"Failed to read ConfigMap {namespace}/{name}: "
                f"HTTP {response.status_code} {response.text[:500]}"
            )
        return response.json().get("data") or {}

    def _service_account_namespace(self) -> str | None:
        namespace_path = Path("/var/run/secrets/kubernetes.io/serviceaccount/namespace")
        if namespace_path.exists():
            return namespace_path.read_text(encoding="utf-8").strip()
        return None

    def _call_llm(
        self,
        base_url: str,
        model_id: str,
        prompt: str,
        params: dict[str, Any],
        system_prompt: str | None = None,
    ) -> dict[str, Any]:
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        response = self._post_json(
            f"{self._api_base(base_url)}/chat/completions",
            {
                "model": self._oai_model(model_id),
                "messages": messages,
                "max_tokens": int(params.get("max_tokens", 2048)),
                "temperature": float(params.get("temperature", 0)),
                "stream": False,
            },
            timeout=int(params.get("llm_timeout_seconds", 120)),
            description="candidate model",
        )
        choices = response.get("choices") or []
        if not choices:
            return {"answer": "", "tool_calls": []}
        return {
            "answer": choices[0].get("message", {}).get("content") or "",
            "tool_calls": [],
        }

    def _call_rag(
        self,
        base_url: str,
        model_id: str,
        vector_db_id: str,
        prompt: str,
        params: dict[str, Any],
    ) -> dict[str, Any]:
        store_id = self._resolve_vector_store_id(base_url, vector_db_id)
        context_text = ""
        tool_calls: list[str] = []

        try:
            search = self._post_json(
                f"{self._api_base(base_url)}/vector_stores/{store_id}/search",
                {"query": prompt, "max_num_results": int(params.get("max_num_results", 5))},
                timeout=int(params.get("retrieval_timeout_seconds", 30)),
                description=f"vector store search {vector_db_id}",
            )
            results = search.get("data") or []
            chunks: list[str] = []
            for result in results:
                for content in result.get("content", []):
                    if isinstance(content, dict):
                        text = content.get("text", "")
                    else:
                        text = str(content)
                    if text:
                        chunks.append(text)
            if chunks:
                tool_calls.append("builtin::rag/knowledge_search")
                context_text = "\n---\n".join(chunks)
        except Exception:
            context_text = ""

        max_context_chars = int(params.get("max_context_chars", 4000))
        system_prompt = "You are a helpful assistant. Answer based on the provided document context."
        if context_text:
            system_prompt += f"\n\nDocument context:\n{context_text[:max_context_chars]}"
        answer = self._call_llm(base_url, model_id, prompt, params, system_prompt=system_prompt)
        answer["tool_calls"] = tool_calls
        return answer

    def _resolve_vector_store_id(self, base_url: str, name: str) -> str:
        try:
            response = requests.get(f"{self._api_base(base_url)}/vector_stores", timeout=10)
            response.raise_for_status()
            for store in response.json().get("data", []):
                if store.get("name") == name:
                    return store.get("id") or name
        except Exception:
            pass
        return name

    def _call_judge(
        self,
        judge_url: str,
        judge_model: str,
        question: str,
        expected: str,
        generated: str,
        judge_template: str,
        timeout: int,
    ) -> tuple[str, str]:
        prompt = (
            judge_template.replace("{input_query}", question)
            .replace("{expected_answer}", expected)
            .replace("{generated_answer}", generated)
        )
        try:
            response = self._post_json(
                self._chat_completions_url(judge_url),
                {
                    "model": judge_model,
                    "messages": [{"role": "user", "content": prompt}],
                    "max_tokens": 300,
                    "temperature": 0,
                    "stream": False,
                },
                timeout=timeout,
                description="judge model",
            )
            feedback = response["choices"][0]["message"]["content"]
            match = re.search(r"\(([A-E])\)", feedback)
            return (match.group(1) if match else "?", feedback)
        except Exception as exc:
            return "?", f"Judge error: {exc}"

    def _score_tool_choice(self, actual_tools: list[str], expected_tools: list[str]) -> dict[str, Any]:
        actual = set(actual_tools)
        expected = set(expected_tools)
        if not expected:
            return {
                "score": 1.0,
                "tools_called": sorted(actual),
                "tools_expected": [],
            }
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

    def _summarize(
        self,
        scenario_config: dict[str, Any],
        mode: str,
        scenario_results: list[dict[str, Any]],
        pass_letters: set[str],
    ) -> tuple[list[EvaluationResult], dict[str, Any]]:
        total = len(scenario_results)
        passed = sum(1 for result in scenario_results if result["judge_letter"] in pass_letters)
        pass_rate = passed / total if total else 0.0
        mean_judge_score = (
            sum(float(result["judge_score"]) for result in scenario_results) / total if total else 0.0
        )
        tool_pass_rate = (
            sum(float(result["tool_score"]["score"]) for result in scenario_results) / total if total else 0.0
        )
        letter_counts = {
            letter: sum(1 for result in scenario_results if result["judge_letter"] == letter)
            for letter in ["A", "B", "C", "D", "E", "?"]
        }
        rag_hits = sum(
            1
            for result in scenario_results
            if "builtin::rag/knowledge_search" in result.get("tool_calls", [])
        )

        summary = {
            "scenario": scenario_config.get("name", "RAG Scenario"),
            "mode": mode,
            "tests_total": total,
            "tests_passed": passed,
            "pass_rate": pass_rate,
            "mean_judge_score": mean_judge_score,
            "tool_pass_rate": tool_pass_rate,
            "letter_counts": letter_counts,
            "rag_tool_calls": rag_hits,
            "pass_letters": sorted(pass_letters),
            "completed_at": datetime.now(UTC).isoformat(),
        }

        metrics = [
            EvaluationResult(metric_name="pass_rate", metric_value=pass_rate, metric_type="float", num_samples=total),
            EvaluationResult(metric_name="mean_judge_score", metric_value=mean_judge_score, metric_type="float", num_samples=total),
            EvaluationResult(metric_name="tool_pass_rate", metric_value=tool_pass_rate, metric_type="float", num_samples=total),
            EvaluationResult(metric_name="tests_total", metric_value=total, metric_type="int", num_samples=total),
            EvaluationResult(metric_name="tests_passed", metric_value=passed, metric_type="int", num_samples=total),
            EvaluationResult(metric_name="rag_tool_calls", metric_value=rag_hits, metric_type="int", num_samples=total),
        ]
        for letter, count in letter_counts.items():
            metric_letter = "unknown" if letter == "?" else letter
            metrics.append(
                EvaluationResult(
                    metric_name=f"judge_count_{metric_letter}",
                    metric_value=count,
                    metric_type="int",
                    num_samples=total,
                )
            )
        return metrics, summary

    def _api_base(self, base_url: str) -> str:
        base = base_url.rstrip("/")
        if base.endswith("/v1"):
            return base
        return f"{base}/v1"

    def _chat_completions_url(self, base_url: str) -> str:
        base = base_url.rstrip("/")
        if base.endswith("/chat/completions"):
            return base
        if base.endswith("/v1"):
            return f"{base}/chat/completions"
        return f"{base}/v1/chat/completions"

    def _oai_model(self, model_id: str) -> str:
        if model_id.startswith("vllm-inference/"):
            return model_id
        return f"vllm-inference/{model_id}"

    def _post_json(
        self,
        url: str,
        payload: dict[str, Any],
        timeout: int,
        description: str,
    ) -> dict[str, Any]:
        response = requests.post(url, json=payload, timeout=timeout)
        if response.status_code >= 400:
            raise RuntimeError(
                f"{description} returned HTTP {response.status_code}: {response.text[:500]}"
            )
        try:
            return response.json()
        except json.JSONDecodeError as exc:
            raise RuntimeError(f"{description} returned invalid JSON: {response.text[:500]}") from exc
