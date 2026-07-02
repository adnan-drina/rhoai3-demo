"""Future MCP integration boundary for the Stage 230 chatbot."""

from __future__ import annotations

from typing import Any


def mcp_status(enabled: bool, tools: list[str]) -> dict[str, Any]:
    return {
        "enabled": enabled,
        "tool_count": len(tools),
        "tools": tools,
        "note": (
            "MCP is intentionally disabled in Stage 230. A later stage can add "
            "an agent/tool execution path after product-side connectors are registered."
        ),
    }
