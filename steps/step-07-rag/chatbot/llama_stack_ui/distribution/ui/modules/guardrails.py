"""
Guardrails module — calls the NeMo Guardrails OpenAI-compatible API.

Step 09 deploys NeMo Guardrails through the TrustyAI operator. The chatbot keeps
its shield toggle by using NeMo as a policy decision point before input reaches
the agent and after output is generated.
"""

import os
import logging
import requests
import urllib3

logger = logging.getLogger(__name__)

NEMO_GUARDRAILS_URL = os.getenv(
    "NEMO_GUARDRAILS_URL",
    "http://nemo-guardrails.enterprise-rag.svc.cluster.local:8000"
)
NEMO_MODEL = os.getenv("NEMO_GUARDRAILS_MODEL", "granite-8b-agent")
VERIFY_SSL = False
if not VERIFY_SSL:
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

BLOCK_PHRASES = (
    "i can't help with that type of request",
    "please keep your message under 100 words",
)


def _nemo_chat(text: str) -> str:
    resp = requests.post(
        f"{NEMO_GUARDRAILS_URL.rstrip('/')}/v1/chat/completions",
        headers={"Content-Type": "application/json", "Authorization": "Bearer fake"},
        json={
            "model": NEMO_MODEL,
            "messages": [{"role": "user", "content": text}],
            "max_tokens": 128,
        },
        timeout=20,
        verify=VERIFY_SSL,
    )
    resp.raise_for_status()
    data = resp.json()
    choices = data.get("choices", [])
    if choices:
        return choices[0].get("message", {}).get("content", "")
    messages = data.get("messages", [])
    if messages:
        return messages[0].get("content", "")
    return str(data)


def _blocked(reply: str) -> bool:
    lowered = reply.lower()
    return any(phrase in lowered for phrase in BLOCK_PHRASES)


def check_input(text: str, detectors: list[str] | None = None) -> dict | None:
    """
    Check user input for safety violations.
    Returns violation dict if detected, None if safe.
    """
    logger.debug("NeMo Guardrails input check")
    try:
        reply = _nemo_chat(text)
        logger.debug("NeMo Guardrails input response: %s", reply[:200])
        if _blocked(reply):
            logger.info("NeMo Guardrails input violation")
            return {
                "detector": "nemo-guardrails",
                "score": 1.0,
                "text": text,
                "type": "policy",
            }
        logger.debug("NeMo Guardrails input: SAFE")
    except Exception as e:
        logger.warning("NeMo Guardrails input check failed: %s", e)

    return None


def check_output(text: str, detectors: list[str] | None = None) -> list[dict]:
    """
    Check model output for safety violations.
    Returns list of violation dicts (empty if safe).
    """
    try:
        reply = _nemo_chat(text)
        if _blocked(reply):
            return [{
                "detector": "nemo-guardrails",
                "score": 1.0,
                "text": text,
                "type": "policy",
            }]
    except Exception as e:
        logger.warning("NeMo Guardrails output check failed: %s", e)

    return []


def is_available() -> bool:
    """Check if NeMo Guardrails is reachable."""
    try:
        resp = requests.get(f"{NEMO_GUARDRAILS_URL.rstrip('/')}/health", timeout=3, verify=VERIFY_SSL)
        if resp.status_code == 200:
            return True
        resp = requests.get(f"{NEMO_GUARDRAILS_URL.rstrip('/')}/docs", timeout=3, verify=VERIFY_SSL)
        return resp.status_code in (200, 401, 403)
    except Exception:
        return False
