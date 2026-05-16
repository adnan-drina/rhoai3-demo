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
import time

logger = logging.getLogger(__name__)

NEMO_GUARDRAILS_URL = os.getenv(
    "NEMO_GUARDRAILS_URL",
    "http://nemo-guardrails.enterprise-rag.svc.cluster.local:8000"
)
NEMO_MODEL = os.getenv("NEMO_GUARDRAILS_MODEL", "granite-8b-agent")
NEMO_TOKEN = os.getenv("NEMO_GUARDRAILS_TOKEN")
NEMO_TOKEN_FILE = os.getenv(
    "NEMO_GUARDRAILS_TOKEN_FILE",
    "/var/run/secrets/kubernetes.io/serviceaccount/token",
)
REQUEST_TIMEOUT = int(os.getenv("NEMO_GUARDRAILS_TIMEOUT_SECONDS", "20"))
AVAILABILITY_TTL_SECONDS = int(os.getenv("NEMO_GUARDRAILS_AVAILABILITY_TTL_SECONDS", "30"))
VERIFY_SSL = False
if not VERIFY_SSL:
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

BLOCK_PHRASES = (
    "i can't help with that type of request",
    "i don't know the answer to that",
    "please keep your message under 100 words",
)

_availability_cache: tuple[bool, float] | None = None


def _auth_token() -> str | None:
    if NEMO_TOKEN:
        return NEMO_TOKEN
    try:
        with open(NEMO_TOKEN_FILE, "r", encoding="utf-8") as token_file:
            token = token_file.read().strip()
            return token or None
    except OSError:
        return None


def _headers() -> dict[str, str]:
    headers = {"Content-Type": "application/json"}
    token = _auth_token()
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def _nemo_chat(text: str) -> str:
    resp = requests.post(
        f"{NEMO_GUARDRAILS_URL.rstrip('/')}/v1/chat/completions",
        headers=_headers(),
        json={
            "model": NEMO_MODEL,
            "messages": [{"role": "user", "content": text}],
            "max_tokens": 128,
            "stream": False,
        },
        timeout=REQUEST_TIMEOUT,
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
                "message": reply,
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
                "message": reply,
                "score": 1.0,
                "text": "",
                "type": "policy",
            }]
    except Exception as e:
        logger.warning("NeMo Guardrails output check failed: %s", e)

    return []


def is_available() -> bool:
    """Check if NeMo Guardrails is reachable."""
    global _availability_cache  # pylint: disable=global-statement

    now = time.time()
    if _availability_cache and now < _availability_cache[1]:
        return _availability_cache[0]

    available = False
    try:
        resp = requests.get(
            f"{NEMO_GUARDRAILS_URL.rstrip('/')}/v1/models",
            headers=_headers(),
            timeout=3,
            verify=VERIFY_SSL,
        )
        available = resp.status_code == 200
        if not available:
            resp = requests.get(
                f"{NEMO_GUARDRAILS_URL.rstrip('/')}/docs",
                headers=_headers(),
                timeout=3,
                verify=VERIFY_SSL,
            )
            available = resp.status_code == 200
    except Exception:
        available = False

    _availability_cache = (available, now + AVAILABILITY_TTL_SECONDS)
    return available
