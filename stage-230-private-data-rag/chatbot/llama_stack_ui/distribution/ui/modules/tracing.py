"""
MLflow tracing for the RAG chatbot (Stage 230 → Stage 250 product MLflow).

Every chat turn becomes one MLflow trace: a root span per mode with child
spans for input guardrails, retrieval, generation, and output guardrails.
Guardrail-blocked turns are tagged so they can be filtered in the MLflow UI.

Tracing must never break or slow the chat:
- disabled entirely unless MLFLOW_TRACKING_URI is set;
- initialization happens lazily on the first turn and a failure disables
  tracing for the rest of the process;
- every helper swallows its own exceptions;
- span export is asynchronous (MLflow 3 default), so the streamed UI path
  never waits on the tracking server.
"""

import logging
import os
from contextlib import contextmanager

logger = logging.getLogger(__name__)

DEFAULT_EXPERIMENT = "private-rag-chatbot"
APP_NAME = "private-rag-chatbot"

# GUARDRAIL is not a built-in mlflow SpanType; span_type accepts custom
# strings and the UI renders them verbatim.
SPAN_TYPE_GUARDRAIL = "GUARDRAIL"

_state = {"initialized": False, "enabled": False}


def _resolve_version():
    """Chatbot build version for agent versioning.

    Binary OpenShift builds do not support --build-arg, so deploy.sh writes
    the git SHA to a VERSION file in the build context; the env var remains
    as an override for other build paths.
    """
    version = os.environ.get("CHATBOT_VERSION", "").strip()
    if version and version != "dev":
        return version
    try:
        from pathlib import Path

        file_version = Path("/app/VERSION").read_text().strip()
        if file_version:
            return file_version
    except Exception:  # pylint: disable=broad-exception-caught
        pass
    return version or "dev"


def _init():
    """Lazily configure MLflow once per process; returns whether enabled."""
    if _state["initialized"]:
        return _state["enabled"]
    _state["initialized"] = True

    uri = os.environ.get("MLFLOW_TRACKING_URI", "").strip()
    if not uri:
        logger.info("MLflow tracing disabled: MLFLOW_TRACKING_URI not set")
        return False

    try:
        import mlflow

        mlflow.set_tracking_uri(uri)
        mlflow.set_experiment(
            os.environ.get("MLFLOW_EXPERIMENT_NAME", DEFAULT_EXPERIMENT)
        )
        _state["enabled"] = True
        logger.info("MLflow tracing enabled (tracking URI %s)", uri)

        # Agent versioning: one LoggedModel per chatbot build; traces link
        # to the app version that produced them (Agent versions UI).
        version = _resolve_version()
        if version:
            try:
                mlflow.set_active_model(name=f"{APP_NAME}-{version}")
                logger.info("MLflow active model: %s-%s", APP_NAME, version)
            except Exception as e:  # pylint: disable=broad-exception-caught
                logger.warning("MLflow active model not set: %s", e)
    except Exception as e:  # pylint: disable=broad-exception-caught
        logger.warning(
            "MLflow tracing disabled after initialization error: %s", e
        )
    return _state["enabled"]


def enabled():
    return _init()


@contextmanager
def span(name, span_type="CHAIN", inputs=None, attributes=None):
    """No-op-safe span context manager. Yields the live span or None."""
    if not _init():
        yield None
        return

    try:
        import mlflow

        cm = mlflow.start_span(
            name=name, span_type=span_type, attributes=attributes or {}
        )
        live_span = cm.__enter__()
    except Exception as e:  # pylint: disable=broad-exception-caught
        logger.debug("MLflow span %s failed to start: %s", name, e)
        yield None
        return

    try:
        if inputs is not None:
            set_inputs(live_span, inputs)
        yield live_span
    finally:
        try:
            cm.__exit__(None, None, None)
        except Exception as e:  # pylint: disable=broad-exception-caught
            logger.debug("MLflow span %s failed to close: %s", name, e)


def set_inputs(live_span, inputs):
    if live_span is None:
        return
    try:
        live_span.set_inputs(inputs)
    except Exception as e:  # pylint: disable=broad-exception-caught
        logger.debug("MLflow set_inputs failed: %s", e)


def set_outputs(live_span, outputs):
    if live_span is None:
        return
    try:
        live_span.set_outputs(outputs)
    except Exception as e:  # pylint: disable=broad-exception-caught
        logger.debug("MLflow set_outputs failed: %s", e)


def set_attributes(live_span, attributes):
    if live_span is None:
        return
    try:
        live_span.set_attributes(attributes)
    except Exception as e:  # pylint: disable=broad-exception-caught
        logger.debug("MLflow set_attributes failed: %s", e)


_prompt_cache = {}


def ensure_prompt_version(name, template):
    """Register the template in the MLflow prompt registry if it changed.

    Record-only integration: the code remains the source of truth; the
    registry gives versioned history (visible in the MLflow Prompts page
    and the Gen AI studio Prompts view) and traces are tagged with the
    version they ran with. Cached per (name, template) so a version is
    registered at most once per process. Returns the version or None.
    """
    if not _init() or not template:
        return None
    cache_key = (name, hash(template))
    if cache_key in _prompt_cache:
        return _prompt_cache[cache_key]
    version = None
    try:
        from mlflow.genai import load_prompt, register_prompt

        try:
            latest = load_prompt(name, allow_missing=True)
        except TypeError:
            try:
                latest = load_prompt(name)
            except Exception:  # pylint: disable=broad-exception-caught
                latest = None
        except Exception:  # pylint: disable=broad-exception-caught
            latest = None
        if latest is not None and latest.template == template:
            version = latest.version
        else:
            registered = register_prompt(
                name=name, template=template,
                commit_message="registered by chatbot tracing",
            )
            version = registered.version
            logger.info("Registered prompt %s version %s", name, version)
    except Exception as e:  # pylint: disable=broad-exception-caught
        logger.debug("MLflow prompt registration failed for %s: %s", name, e)
    _prompt_cache[cache_key] = version
    return version


def tag_prompts(prompt_versions):
    """Tag the active trace with the prompt versions used this turn."""
    tags = {
        f"prompt.{name}": str(version)
        for name, version in (prompt_versions or {}).items()
        if version is not None
    }
    if tags:
        tag_trace(tags)


def set_session(session_id, user=None):
    """Attach the conversation id to the active trace (Sessions grouping).

    Prefers the dedicated update_current_trace kwargs where the SDK has
    them; falls back to the documented metadata keys otherwise.
    """
    if not _state["enabled"] or not session_id:
        return
    try:
        import mlflow

        try:
            kwargs = {"session_id": str(session_id)}
            if user:
                kwargs["user_id"] = str(user)
            mlflow.update_current_trace(**kwargs)
        except TypeError:
            metadata = {"mlflow.trace.session": str(session_id)}
            if user:
                metadata["mlflow.trace.user"] = str(user)
            mlflow.update_current_trace(metadata=metadata)
    except Exception as e:  # pylint: disable=broad-exception-caught
        logger.debug("MLflow set_session failed: %s", e)


def tag_trace(tags):
    """Tag the active trace (values stringified). Safe no-op when disabled."""
    if not _state["enabled"]:
        return
    try:
        import mlflow

        mlflow.update_current_trace(
            tags={str(k): str(v) for k, v in tags.items()}
        )
    except Exception as e:  # pylint: disable=broad-exception-caught
        logger.debug("MLflow tag_trace failed: %s", e)


def record_guardrail(live_span, stage, is_blocked, shield_id=None,
                     violation_message=None, shields=None):
    """Record a guardrail verdict on its span and tag the trace on block."""
    set_outputs(live_span, {
        "blocked": bool(is_blocked),
        "shield_id": shield_id,
        "violation_message": violation_message,
        "shields_checked": list(shields or []),
    })
    if is_blocked:
        tag_trace({
            "guardrail.blocked": "true",
            "guardrail.stage": stage,
            "guardrail.shield_id": shield_id or "",
        })


def record_turn_result(turn_span, response=None, blocked_message=None,
                       reasoning=None, tool_results=None):
    """Record the final outcome of a chat turn on the root span.

    tool_results must be captured here, at end of turn: the agent-mode
    fallback vector search (and any late-streamed tool items) populate the
    sources AFTER the generation span's outputs are snapshotted.
    """
    outputs = {"blocked": blocked_message is not None}
    if blocked_message is not None:
        outputs["blocked_message"] = blocked_message
    else:
        outputs["response"] = response
        if reasoning:
            outputs["reasoning"] = reasoning
    if tool_results is not None:
        outputs["tool_results"] = tool_results
    set_outputs(turn_span, outputs)
    if blocked_message is None:
        tag_trace({"guardrail.blocked": "false"})
