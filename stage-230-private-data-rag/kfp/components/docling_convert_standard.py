"""Convert PDFs to Markdown and Docling JSON with the standard Docling pipeline."""

from typing import List

from kfp import dsl

from .constants import DOCLING_BASE_IMAGE


@dsl.component(base_image=DOCLING_BASE_IMAGE)
def docling_convert_standard(
    input_path: dsl.Input[dsl.Artifact],
    artifacts_path: dsl.Input[dsl.Artifact],
    output_path: dsl.Output[dsl.Artifact],
    pdf_filenames: List[str],
    pdf_backend: str = "dlparse_v4",
    image_export_mode: str = "embedded",
    table_mode: str = "accurate",
    num_threads: int = 4,
    timeout_per_document: int = 300,
    ocr: bool = False,
    force_ocr: bool = False,
    ocr_engine: str = "tesseract_cli",
    allow_external_plugins: bool = False,
    enrich_code: bool = False,
    enrich_formula: bool = False,
    enrich_picture_classes: bool = False,
    enrich_picture_description: bool = False,
):
    """Convert a split of PDF files to Markdown and Docling JSON artifacts."""

    from importlib import import_module  # pylint: disable=import-outside-toplevel
    from pathlib import Path  # pylint: disable=import-outside-toplevel

    from docling.datamodel.accelerator_options import (  # pylint: disable=import-outside-toplevel
        AcceleratorDevice,
        AcceleratorOptions,
    )
    from docling.datamodel.base_models import InputFormat  # pylint: disable=import-outside-toplevel
    from docling.datamodel.pipeline_options import (  # pylint: disable=import-outside-toplevel
        EasyOcrOptions,
        OcrEngine,
        OcrMacOptions,
        PdfBackend,
        PdfPipelineOptions,
        RapidOcrOptions,
        TableFormerMode,
        TesseractCliOcrOptions,
        TesseractOcrOptions,
    )
    from docling.document_converter import DocumentConverter, PdfFormatOption  # pylint: disable=import-outside-toplevel
    from docling.pipeline.standard_pdf_pipeline import StandardPdfPipeline  # pylint: disable=import-outside-toplevel
    from docling_core.types.doc.base import ImageRefMode  # pylint: disable=import-outside-toplevel

    if not pdf_filenames:
        raise ValueError("pdf_filenames must be provided with the list of files to process")

    allowed_pdf_backends = {backend.value for backend in PdfBackend}
    if pdf_backend not in allowed_pdf_backends:
        raise ValueError(f"Invalid pdf_backend: {pdf_backend}. Must be one of {sorted(allowed_pdf_backends)}")

    allowed_table_modes = {mode.value for mode in TableFormerMode}
    if table_mode not in allowed_table_modes:
        raise ValueError(f"Invalid table_mode: {table_mode}. Must be one of {sorted(allowed_table_modes)}")

    allowed_image_export_modes = {mode.value for mode in ImageRefMode}
    if image_export_mode not in allowed_image_export_modes:
        raise ValueError(
            f"Invalid image_export_mode: {image_export_mode}. Must be one of {sorted(allowed_image_export_modes)}"
        )

    if not allow_external_plugins:
        allowed_ocr_engines = {engine.value for engine in OcrEngine}
        if ocr_engine not in allowed_ocr_engines:
            raise ValueError(f"Invalid ocr_engine: {ocr_engine}. Must be one of {sorted(allowed_ocr_engines)}")

    ocr_engine_map = {
        "easyocr": EasyOcrOptions,
        "tesseract_cli": TesseractCliOcrOptions,
        "tesseract": TesseractOcrOptions,
        "ocrmac": OcrMacOptions,
        "rapidocr": RapidOcrOptions,
    }

    input_dir = Path(input_path.path)
    artifacts_dir = Path(artifacts_path.path)
    output_dir = Path(output_path.path)
    output_dir.mkdir(parents=True, exist_ok=True)

    input_pdfs = [input_dir / name for name in pdf_filenames]
    missing = [str(path) for path in input_pdfs if not path.is_file()]
    if missing:
        raise RuntimeError(f"missing input PDFs: {missing}")

    pipeline_options = PdfPipelineOptions()
    pipeline_options.artifacts_path = artifacts_dir
    pipeline_options.do_code_enrichment = enrich_code
    pipeline_options.do_formula_enrichment = enrich_formula
    pipeline_options.do_picture_classification = enrich_picture_classes
    pipeline_options.do_picture_description = enrich_picture_description
    pipeline_options.do_ocr = ocr
    if ocr and ocr_engine in ocr_engine_map:
        pipeline_options.ocr_options = ocr_engine_map[ocr_engine](force_full_page_ocr=force_ocr)
    pipeline_options.do_table_structure = True
    pipeline_options.table_structure_options.do_cell_matching = True
    pipeline_options.table_structure_options.mode = TableFormerMode(table_mode)
    pipeline_options.generate_page_images = True
    pipeline_options.document_timeout = float(timeout_per_document)
    pipeline_options.accelerator_options = AcceleratorOptions(
        num_threads=num_threads,
        device=AcceleratorDevice.AUTO,
    )

    backend_to_impl = {
        PdfBackend.PYPDFIUM2.value: ("docling.backend.pypdfium2_backend", "PyPdfiumDocumentBackend"),
        PdfBackend.DLPARSE_V1.value: ("docling.backend.docling_parse_backend", "DoclingParseDocumentBackend"),
        PdfBackend.DLPARSE_V2.value: ("docling.backend.docling_parse_v2_backend", "DoclingParseV2DocumentBackend"),
        PdfBackend.DLPARSE_V4.value: ("docling.backend.docling_parse_v4_backend", "DoclingParseV4DocumentBackend"),
    }
    module_name, class_name = backend_to_impl[pdf_backend]
    backend_class = getattr(import_module(module_name), class_name)

    converter = DocumentConverter(
        format_options={
            InputFormat.PDF: PdfFormatOption(
                pipeline_options=pipeline_options,
                backend=backend_class,
                pipeline_cls=StandardPdfPipeline,
            )
        }
    )

    print(f"docling-convert-standard: converting {len(input_pdfs)} PDF file(s)", flush=True)
    for result in converter.convert_all(input_pdfs, raises_on_error=True):
        document_stem = result.input.file.stem
        json_path = output_dir / f"{document_stem}.json"
        markdown_path = output_dir / f"{document_stem}.md"
        result.document.save_as_json(json_path, image_mode=ImageRefMode(image_export_mode))
        result.document.save_as_markdown(markdown_path, image_mode=ImageRefMode(image_export_mode))
        print(f"docling-convert-standard: saved {json_path.name} and {markdown_path.name}", flush=True)

    print("docling-convert-standard: done", flush=True)

