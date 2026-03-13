"""
Guardrails module — calls the FMS Guardrails Orchestrator API
for input/output safety checks (HAP, prompt injection, PII regex).

The orchestrator is deployed by step-09 and accessed directly via HTTP,
bypassing LlamaStack's safety API (which requires rh-dev auto-wiring
the chatbot uses the orchestrator API for fine-grained detector control).
"""

import os
import logging
import requests

logger = logging.getLogger(__name__)

ORCHESTRATOR_URL = os.getenv(
    "GUARDRAILS_ORCHESTRATOR_URL",
    "https://guardrails-orchestrator-service.private-ai.svc:8032"
)
VERIFY_SSL = False
HEALTH_URL = os.getenv(
    "GUARDRAILS_HEALTH_URL",
    "http://guardrails-orchestrator-service.private-ai.svc:8034"
)


def check_input(text: str, detectors: list[str] | None = None) -> dict | None:
    """
    Check user input for safety violations.
    Returns violation dict if detected, None if safe.
    """
    if not detectors:
        detectors = ["hap", "prompt_injection"]

    detector_config = {}
    for d in detectors:
        if d == "regex":
            detector_config[d] = {"regex": ["email", "us-phone-number", "credit-card"]}
        else:
            detector_config[d] = {}

    logger.info("Guardrails input check: detectors=%s text='%s...'", list(detector_config.keys()), text[:50])
    try:
        resp = requests.post(
            f"{ORCHESTRATOR_URL}/api/v2/text/detection/content",
            json={"content": text, "detectors": detector_config},
            timeout=10,
            verify=VERIFY_SSL,
        )
        resp.raise_for_status()
        data = resp.json()
        logger.info("Guardrails input response: %s", str(data)[:200])

        detections = data.get("detections", [])
        if detections:
            top = detections[0]
            logger.info("VIOLATION detected: %s score=%s", top.get("detector_id"), top.get("score"))
            return {
                "detector": top.get("detector_id", "unknown"),
                "score": top.get("score", 0),
                "text": top.get("text", ""),
                "type": top.get("detection_type", ""),
            }
        logger.info("Guardrails input: SAFE")
    except Exception as e:
        logger.warning("Guardrails input check failed: %s", e)

    return None


def check_output(text: str, detectors: list[str] | None = None) -> dict | None:
    """
    Check model output for safety violations (HAP, PII leakage).
    Returns violation dict if detected, None if safe.
    """
    if not detectors:
        detectors = ["hap", "regex"]

    detector_config = {}
    for d in detectors:
        if d == "regex":
            detector_config[d] = {"regex": [
                "email", "us-phone-number", "credit-card",
                r"(?i)\+31[\s-]*\d[\s-]*\d{3,}",
                r"(?i)linkedin\.com/in/\w+",
                r"(?i)github\.com/\w+",
            ]}
        else:
            detector_config[d] = {}

    try:
        resp = requests.post(
            f"{ORCHESTRATOR_URL}/api/v2/text/detection/content",
            json={"content": text, "detectors": detector_config},
            timeout=10,
            verify=VERIFY_SSL,
        )
        resp.raise_for_status()
        data = resp.json()

        detections = data.get("detections", [])
        if detections:
            top = detections[0]
            return {
                "detector": top.get("detector_id", "unknown"),
                "score": top.get("score", 0),
                "text": top.get("text", ""),
                "type": top.get("detection_type", ""),
            }
    except Exception as e:
        logger.warning("Guardrails output check failed: %s", e)

    return None


def is_available() -> bool:
    """Check if the guardrails orchestrator is reachable."""
    try:
        resp = requests.get(f"{HEALTH_URL}/health", timeout=3)
        return resp.status_code == 200
    except Exception:
        return False
