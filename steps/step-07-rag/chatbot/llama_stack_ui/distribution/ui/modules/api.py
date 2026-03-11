# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the terms described in the LICENSE file in
# the root directory of this source tree.

import os
from typing import Optional

from llama_stack_client import LlamaStackClient

class LlamaStackApi:
    def __init__(self):
        # Timeout of 600 seconds (10 minutes) for large document uploads
        # Default is 60 seconds which is too short for large PDFs
        timeout = float(os.environ.get("LLAMA_STACK_TIMEOUT", "600"))

        self.client = LlamaStackClient(
            base_url=os.environ.get(
                "LLAMA_STACK_URL",
                os.environ.get("LLAMA_STACK_ENDPOINT", "http://lsd-rag-service.private-ai.svc.cluster.local:8321")
            ),
            timeout=timeout,
        )

    def run_scoring(self, row, scoring_function_ids: list[str], scoring_params: Optional[dict]):
        """Run scoring on a single row"""
        if not scoring_params:
            scoring_params = {fn_id: None for fn_id in scoring_function_ids}
        return self.client.scoring.score(input_rows=[row], scoring_functions=scoring_params)

llama_stack_api = LlamaStackApi()
