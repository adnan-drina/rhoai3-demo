"""Select the Stage 230 RHOAI product-document source PDFs for a KFP run."""

from typing import NamedTuple

from kfp import dsl

from .constants import PYTHON_BASE_IMAGE


@dsl.component(base_image=PYTHON_BASE_IMAGE)
def select_rhoai_product_doc_sources(
    manifest_json: str,
    max_documents: int = 0,
) -> NamedTuple(
    "Outputs",
    [
        ("pdf_filenames", str),
        ("selected_manifest_json", str),
        ("guide_slugs_json", str),
    ],
):
    """Return comma-separated PDF names and a manifest narrowed for this run."""

    import json  # pylint: disable=import-outside-toplevel
    from typing import NamedTuple as _NamedTuple  # pylint: disable=import-outside-toplevel

    outputs = _NamedTuple(
        "Outputs",
        [
            ("pdf_filenames", str),
            ("selected_manifest_json", str),
            ("guide_slugs_json", str),
        ],
    )

    manifest = json.loads(manifest_json)
    documents = list(manifest.get("documents", []))
    if max_documents and max_documents > 0:
        documents = documents[:max_documents]
    if not documents:
        raise RuntimeError("manifest does not contain any documents to process")

    selected_manifest = dict(manifest)
    selected_manifest["documents"] = documents
    filenames = [document["source_file"] for document in documents]
    guide_slugs = [document["guide_slug"] for document in documents]
    return outputs(
        pdf_filenames=",".join(filenames),
        selected_manifest_json=json.dumps(selected_manifest, ensure_ascii=False, separators=(",", ":")),
        guide_slugs_json=json.dumps(guide_slugs, ensure_ascii=False, separators=(",", ":")),
    )

