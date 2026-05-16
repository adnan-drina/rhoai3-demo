# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the terms described in the LICENSE file in
# the root directory of this source tree.

import os
import logging
from typing import Any
from typing import Optional

import requests
from llama_stack_client import LlamaStackClient


logger = logging.getLogger(__name__)


class LlamaStackApi:
    def __init__(self):
        # Timeout of 600 seconds (10 minutes) for large document uploads
        # Default is 60 seconds which is too short for large PDFs
        timeout = float(os.environ.get("LLAMA_STACK_TIMEOUT", "600"))
        self.base_url = os.environ.get(
            "LLAMA_STACK_URL",
            os.environ.get("LLAMA_STACK_ENDPOINT", "http://lsd-rag-service.enterprise-rag.svc.cluster.local:8321")
        ).rstrip("/")

        self.client = LlamaStackClient(
            base_url=self.base_url,
            timeout=timeout,
        )

    def get_json(self, path: str, default: Any = None):
        """Fetch JSON from Llama Stack endpoints not yet covered by the client."""
        endpoint = path if path.startswith("/") else f"/{path}"
        try:
            response = requests.get(f"{self.base_url}{endpoint}", timeout=15)
            response.raise_for_status()
            return response.json()
        except Exception as exc:  # pylint: disable=broad-exception-caught
            logger.debug("Failed to fetch Llama Stack endpoint %s: %s", endpoint, exc)
            return default

    @staticmethod
    def _data_list(payload):
        if isinstance(payload, dict):
            data = payload.get("data", [])
            return data if isinstance(data, list) else []
        return payload if isinstance(payload, list) else []

    def list_tools(self):
        return self._data_list(self.get_json("/v1/tools", {"data": []}))

    def list_connectors(self):
        return self._data_list(self.get_json("/v1beta/connectors", {"data": []}))

    def run_scoring(self, row, scoring_function_ids: list[str], scoring_params: Optional[dict]):
        """Run scoring on a single row"""
        if not scoring_params:
            scoring_params = {fn_id: None for fn_id in scoring_function_ids}
        return self.client.scoring.score(input_rows=[row], scoring_functions=scoring_params)

llama_stack_api = LlamaStackApi()
