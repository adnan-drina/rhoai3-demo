"""Shared KFP runtime image constants for Stage 230 Docling components."""

import os


PYTHON_BASE_IMAGE = os.getenv(
    "PYTHON_BASE_IMAGE",
    "registry.access.redhat.com/ubi9/python-311:9.6-1755074620",
)
DOCLING_BASE_IMAGE = os.getenv(
    "DOCLING_BASE_IMAGE",
    "quay.io/fabianofranz/docling-ubi9:2.54.0",
)

