"""Entrypoint for the RHOAI RAG scenario EvalHub adapter."""

import logging

from evalhub.adapter import (
    DefaultCallbacks,
    ErrorInfo,
    JobPhase,
    JobStatus,
    JobStatusUpdate,
    MessageInfo,
)

from rag_scenario_adapter import RAGScenarioAdapter


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)


def main() -> None:
    adapter = RAGScenarioAdapter()
    callbacks = DefaultCallbacks.from_adapter(adapter)

    try:
        results = adapter.run_benchmark_job(adapter.job_spec, callbacks)
        callbacks.report_results(results)
        logging.info("EvalHub RAG scenario job completed: %s", results.id)
    except Exception as exc:
        logging.exception("EvalHub RAG scenario job failed")
        callbacks.report_status(
            JobStatusUpdate(
                status=JobStatus.FAILED,
                phase=JobPhase.COMPLETED,
                progress=1.0,
                message=MessageInfo(
                    message="RAG scenario evaluation failed",
                    message_code="rag_scenario_failed",
                ),
                error=ErrorInfo(
                    message=str(exc),
                    message_code="rag_scenario_exception",
                ),
            )
        )
        raise


if __name__ == "__main__":
    main()
