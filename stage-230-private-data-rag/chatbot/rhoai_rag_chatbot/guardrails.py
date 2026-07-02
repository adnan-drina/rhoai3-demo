"""Future guardrails boundary for the Stage 230 chatbot."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class GuardrailDecision:
    allowed: bool
    message: str


def check_input(enabled: bool, endpoint: str, text: str) -> GuardrailDecision:
    if not enabled:
        return GuardrailDecision(True, "")
    if not endpoint:
        return GuardrailDecision(False, "Guardrails are enabled, but no reviewed guardrails endpoint is configured.")
    if not text.strip():
        return GuardrailDecision(False, "Empty prompts are not accepted when guardrails are enabled.")
    return GuardrailDecision(False, "Guardrails are reserved for a later stage and are not active in Stage 230.")


def check_output(enabled: bool, endpoint: str, text: str) -> GuardrailDecision:
    if not enabled:
        return GuardrailDecision(True, "")
    if not endpoint:
        return GuardrailDecision(False, "Guardrails are enabled, but no reviewed guardrails endpoint is configured.")
    if not text.strip():
        return GuardrailDecision(False, "The model returned an empty response.")
    return GuardrailDecision(False, "Guardrails are reserved for a later stage and are not active in Stage 230.")
