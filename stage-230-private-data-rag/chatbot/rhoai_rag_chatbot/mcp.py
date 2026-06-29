"""MCP integration boundary for future agentic RAG stages."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .config import ChatbotConfig
from .llama_stack_gateway import LlamaStackGateway


@dataclass(frozen=True)
class McpConnector:
    id: str
    server_label: str
    url: str


class McpRegistry:
    """Discovers MCP connectors without enabling tool-calling in Stage 230."""

    def __init__(self, config: ChatbotConfig, gateway: LlamaStackGateway):
        self.enabled = config.mcp_enabled
        self.gateway = gateway

    def connectors(self) -> list[McpConnector]:
        connectors: list[McpConnector] = []
        for item in self.gateway.list_connectors():
            connector_type = item.get("connector_type") or item.get("type")
            connector_id = item.get("connector_id") or item.get("id") or item.get("name")
            url = item.get("url") or item.get("endpoint")
            if connector_type == "mcp" and connector_id and url:
                connectors.append(
                    McpConnector(
                        id=str(connector_id),
                        server_label=str(item.get("server_label") or connector_id),
                        url=str(url),
                    )
                )
        return connectors

    def response_tools(self) -> list[dict[str, Any]]:
        if not self.enabled:
            return []
        return [
            {
                "type": "mcp",
                "server_label": connector.server_label,
                "server_url": connector.url,
                "require_approval": "never",
            }
            for connector in self.connectors()
        ]
