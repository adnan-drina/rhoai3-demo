"""
Scan Tests Component -- discovers *_tests.yaml files in the eval-configs
directory mounted from the shared PVC.

Adapted from rhoai-genaiops scan_directory_op.
"""

from typing import NamedTuple, List
from kfp.dsl import component


@component(base_image="python:3.11")
def scan_tests_component(
    eval_configs_dir: str = "/eval-configs",
) -> NamedTuple("ScanOutput", [("test_configs", List[dict])]):
    import glob
    import os
    from collections import namedtuple

    print("Scanning for test configurations")
    print("=" * 60)
    print(f"  Directory: {eval_configs_dir}")

    test_configs = []

    for path in glob.glob(os.path.join(eval_configs_dir, "**/*_tests.yaml"), recursive=True):
        rel_path = os.path.relpath(path, eval_configs_dir)
        test_configs.append({"config_path": rel_path})
        print(f"  Found: {rel_path}")

    print(f"\nDiscovered {len(test_configs)} test configuration(s)")

    ScanOutput = namedtuple("ScanOutput", ["test_configs"])
    return ScanOutput(test_configs=test_configs)
