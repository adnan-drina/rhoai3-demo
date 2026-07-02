"""Download Docling conversion model artifacts for the standard pipeline."""

from kfp import dsl

from .constants import DOCLING_BASE_IMAGE


@dsl.component(base_image=DOCLING_BASE_IMAGE)
def download_docling_models(
    output_path: dsl.Output[dsl.Artifact],
    pipeline_type: str = "standard",
    remote_model_endpoint_enabled: bool = False,
):
    """Download Docling model artifacts required by the selected pipeline type."""

    from pathlib import Path  # pylint: disable=import-outside-toplevel

    from docling.utils.model_downloader import download_models  # pylint: disable=import-outside-toplevel

    output_dir = Path(output_path.path)
    output_dir.mkdir(parents=True, exist_ok=True)

    if pipeline_type == "standard":
        download_models(
            output_dir=output_dir,
            progress=True,
            with_layout=True,
            with_tableformer=True,
            with_easyocr=False,
        )
    elif pipeline_type == "vlm" and remote_model_endpoint_enabled:
        download_models(
            output_dir=output_dir,
            progress=False,
            force=False,
            with_layout=True,
            with_tableformer=True,
            with_code_formula=False,
            with_picture_classifier=False,
            with_smolvlm=False,
            with_smoldocling=False,
            with_smoldocling_mlx=False,
            with_granite_vision=False,
            with_easyocr=False,
        )
    elif pipeline_type == "vlm":
        download_models(
            output_dir=output_dir,
            progress=False,
            force=False,
            with_layout=False,
            with_tableformer=False,
            with_code_formula=False,
            with_picture_classifier=False,
            with_smolvlm=True,
            with_smoldocling=True,
            with_smoldocling_mlx=False,
            with_granite_vision=False,
            with_easyocr=False,
        )
    else:
        raise ValueError(f"Invalid pipeline_type: {pipeline_type}. Must be 'standard' or 'vlm'")

    print(f"download-docling-models: downloaded artifacts for {pipeline_type}", flush=True)

