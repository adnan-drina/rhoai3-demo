"""Guardrails integration boundary for future safety stages."""

from __future__ import annotations

from dataclasses import dataclass

import requests

from .config import ChatbotConfig


@dataclass(frozen=True)
class GuardrailDecision:
    allowed: bool
    status: str
    reason: str = ""


class GuardrailsGateway:
    """Disabled-by-default guardrails adapter.

    Stage 230 does not deploy guardrails. Later stages can enable this gateway
    with product-backed NeMo or FMS guardrails endpoints without changing the
    chat flow.
    """

    def __init__(self, config: ChatbotConfig):
        self.enabled = config.guardrails_enabled
        self.endpoint = config.guardrails_endpoint
        self.timeout = config.guardrails_timeout
        self.verify_tls = config.guardrails_verify_tls

    def status(self) -> GuardrailDecision:
        if not self.enabled:
            return GuardrailDecision(True, "disabled", "Guardrails are deferred to a later stage.")
        if not self.endpoint:
            return GuardrailDecision(False, "misconfigured", "GUARDRAILS_ENDPOINT is not set.")
        try:
            response = requests.get(
                f"{self.endpoint}/v1/models",
                timeout=min(self.timeout, 5),
                verify=self.verify_tls,
            )
            if response.status_code < 500:
                return GuardrailDecision(True, "available")
        except Exception as exc:  # pylint: disable=broad-exception-caught
            return GuardrailDecision(False, "unavailable", str(exc))
        return GuardrailDecision(False, "unavailable")

    def check_input(self, text: str) -> GuardrailDecision:
        if not text:
            return GuardrailDecision(True, "empty")
        status = self.status()
        if status.status == "disabled":
            return GuardrailDecision(True, status.status, status.reason)
        if status.status == "available":
            return GuardrailDecision(
                False,
                "not-implemented",
                "Guardrails are enabled, but this stage has no reviewed guardrail check payload.",
            )
        return status

    def check_output(self, text: str) -> GuardrailDecision:
        if not text:
            return GuardrailDecision(True, "empty")
        return self.check_input(text)
