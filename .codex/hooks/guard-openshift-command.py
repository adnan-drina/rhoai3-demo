#!/usr/bin/env python3
"""Compatibility bridge to the shared OpenShift command guard."""

import runpy
from pathlib import Path


SHARED_HOOK = Path(__file__).resolve().parents[2] / ".agents/hooks/guard-openshift-command.py"


if __name__ == "__main__":
    runpy.run_path(str(SHARED_HOOK), run_name="__main__")
