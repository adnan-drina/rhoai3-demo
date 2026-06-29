# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the terms described in the LICENSE file in
# the root directory of this source tree.

"""Compatibility helpers for RHOAI 3.4 Llama Stack 0.7 REST endpoints."""

import logging
from typing import Any

import requests


logger = logging.getLogger(__name__)


class LlamaStackCompat:
    """Small adapter for endpoints not exposed by the 0.7 Python client."""

    def __init__(self, base_url: str, timeout: int = 15):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    @staticmethod
    def _data_list(payload: Any):
        if isinstance(payload, dict):
            data = payload.get("data", [])
            return data if isinstance(data, list) else []
        return payload if isinstance(payload, list) else []

    def get_json(self, path: str, default: Any = None):
        endpoint = path if path.startswith("/") else f"/{path}"
        try:
            response = requests.get(
                f"{self.base_url}{endpoint}",
                timeout=self.timeout,
            )
            response.raise_for_status()
            return response.json()
        except Exception as exc:  # pylint: disable=broad-exception-caught
            logger.debug("Failed to fetch Llama Stack endpoint %s: %s", endpoint, exc)
            return default

    def list_tools(self):
        """Return tools from RHOAI 3.4 Llama Stack `/v1/tools`."""
        return self._data_list(self.get_json("/v1/tools", {"data": []}))

    def list_connectors(self):
        """Return MCP connectors from RHOAI 3.4 Llama Stack `/v1beta/connectors`."""
        return self._data_list(self.get_json("/v1beta/connectors", {"data": []}))
