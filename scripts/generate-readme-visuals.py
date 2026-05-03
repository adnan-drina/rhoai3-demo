#!/usr/bin/env python3
"""Generate Red Hat layered capability-map SVGs for README architecture sections.

The generator is the source of truth for:

- ``docs/assets/architecture/rhoai3-demo-capability-map.svg``
- ``docs/assets/architecture/step-NN-capability-map.svg``
- ``docs/assets/architecture/step-13b-capability-map.svg``

Do not hand-edit generated SVGs. Update this file and regenerate from the
repository root with ``python3 scripts/generate-readme-visuals.py``.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from xml.sax.saxutils import escape

OUT = Path("docs/assets/architecture")

OUTPUT_STEM = {
    "overview": "rhoai3-demo-capability-map",
    "step-01-gpu-and-prereq": "step-01-capability-map",
    "step-02-rhoai": "step-02-capability-map",
    "step-03-private-ai": "step-03-capability-map",
    "step-04-model-registry": "step-04-capability-map",
    "step-05-llm-on-vllm": "step-05-capability-map",
    "step-06-model-metrics": "step-06-capability-map",
    "step-07-rag": "step-07-capability-map",
    "step-08-model-evaluation": "step-08-capability-map",
    "step-09-guardrails": "step-09-capability-map",
    "step-10-mcp-integration": "step-10-capability-map",
    "step-11-face-recognition": "step-11-capability-map",
    "step-12-mlops-pipeline": "step-12-capability-map",
    "step-13-edge-ai": "step-13-capability-map",
    "step-13b-edge-ai-microshift": "step-13b-capability-map",
}

STEPS = [
    (
        "step-01-gpu-and-prereq",
        "Step 01: GPU Infrastructure and Prerequisites",
        "Accelerator capacity becomes a governed platform resource.",
    ),
    (
        "step-02-rhoai",
        "Step 02: Red Hat OpenShift AI 3.3 Platform",
        "Infrastructure becomes governed AI self-service.",
    ),
    (
        "step-03-private-ai",
        "Step 03: Private AI Workspace",
        "Identity, access, and storage define the private platform boundary.",
    ),
    (
        "step-04-model-registry",
        "Step 04: Model Registry and Catalog",
        "Models gain a lifecycle record before they become endpoints.",
    ),
    (
        "step-05-llm-on-vllm",
        "Step 05: LLM Serving on vLLM",
        "Private model serving turns GenAI into a platform capability.",
    ),
    (
        "step-06-model-metrics",
        "Step 06: Model Metrics and Benchmarking",
        "Observability connects user experience, GPU capacity, and cost.",
    ),
    (
        "step-07-rag",
        "Step 07: RAG Pipeline",
        "Enterprise knowledge grounds local model answers.",
    ),
    (
        "step-08-model-evaluation",
        "Step 08: Model Evaluation",
        "Repeatable evidence replaces ad hoc answer inspection.",
    ),
    (
        "step-09-guardrails",
        "Step 09: Guardrails",
        "Safety checks become a shared platform control point.",
    ),
    (
        "step-10-mcp-integration",
        "Step 10: MCP Integration",
        "Agentic tools are explicit, permissioned, and observable.",
    ),
    (
        "step-11-face-recognition",
        "Step 11: Face Recognition",
        "The same platform serves predictive computer-vision models.",
    ),
    (
        "step-12-mlops-pipeline",
        "Step 12: MLOps Pipeline",
        "Training, validation, promotion, and monitoring become repeatable.",
    ),
    (
        "step-13-edge-ai",
        "Step 13: Edge AI",
        "Inference moves outward while lifecycle control stays central.",
    ),
    (
        "step-13b-edge-ai-microshift",
        "Step 13b: Edge AI on MicroShift",
        "The edge pattern lands on a smaller OpenShift-derived footprint.",
    ),
]

STEP_ORDER = {step_id: idx + 1 for idx, (step_id, _title, _desc) in enumerate(STEPS)}


@dataclass(frozen=True)
class Product:
    label: tuple[str, ...]
    color: str


@dataclass(frozen=True)
class Capability:
    id: str
    introduced: str
    label: tuple[str, ...]


@dataclass(frozen=True)
class Row:
    id: str
    product: str
    label: tuple[str, ...]
    y: int
    h: int
    cols: int
    caps: tuple[Capability, ...]


COLORS = {
    "black": "#000000",
    "gray95": "#151515",
    "gray90": "#1f1f1f",
    "gray80": "#292929",
    "gray70": "#383838",
    "gray60": "#4d4d4d",
    "gray50": "#707070",
    "gray30": "#c7c7c7",
    "gray20": "#e0e0e0",
    "white": "#ffffff",
    "red": "#ee0000",
    "teal": "#147878",
}

PRODUCTS = {
    "openshift_ai": Product(("Red Hat", "OpenShift AI"), COLORS["teal"]),
    "openshift": Product(("Red Hat", "OpenShift"), COLORS["red"]),
}

ROWS = (
    Row(
        id="ai-lifecycle",
        product="openshift_ai",
        label=("AI lifecycle", "and governance"),
        y=130,
        h=190,
        cols=3,
        caps=(
            Capability("data-ingestion", "step-07-rag", ("Data ingestion", "and grounding")),
            Capability(
                "development-customization",
                "step-07-rag",
                ("Model development", "and customization"),
            ),
            Capability(
                "training-experimentation",
                "step-11-face-recognition",
                ("Model training", "and experimentation"),
            ),
            Capability("model-evaluation", "step-08-model-evaluation", ("Evaluation", "and benchmarking")),
            Capability("catalog-registry", "step-04-model-registry", ("Model catalog", "and registry")),
            Capability(
                "observability-governance",
                "step-06-model-metrics",
                ("Model observability", "and governance"),
            ),
        ),
    ),
    Row(
        id="pipelines-ops",
        product="openshift_ai",
        label=("AI pipelines", "and model", "operations"),
        y=345,
        h=170,
        cols=3,
        caps=(
            Capability("ai-pipelines", "step-07-rag", ("AI pipelines", "(KFP v2)")),
            Capability("rag-ingestion-pipeline", "step-07-rag", ("RAG ingestion", "pipeline")),
            Capability("llm-judge-eval", "step-08-model-evaluation", ("LLM-as-judge", "evaluation")),
            Capability("guidellm-benchmarking", "step-06-model-metrics", ("GuideLLM", "benchmarking")),
            Capability("mlops-training-pipeline", "step-12-mlops-pipeline", ("MLOps training", "pipeline")),
            Capability("modelcar-promotion", "step-12-mlops-pipeline", ("ModelCar", "edge promotion")),
        ),
    ),
    Row(
        id="serving-apps",
        product="openshift_ai",
        label=("Serving,", "GenAI, and", "agentic apps"),
        y=540,
        h=260,
        cols=3,
        caps=(
            Capability("optimized-serving", "step-05-llm-on-vllm", ("Optimized", "model serving")),
            Capability("rhaiis-vllm", "step-05-llm-on-vllm", ("Red Hat AI", "Inference Server")),
            Capability("kserve-raw", "step-05-llm-on-vllm", ("KServe", "RawDeployment")),
            Capability("openvino-serving", "step-11-face-recognition", ("OpenVINO", "predictive serving")),
            Capability("genai-studio", "step-02-rhoai", ("GenAI Studio", "and Playground")),
            Capability("llama-stack-rag", "step-07-rag", ("Llama Stack API", "and RAG")),
            Capability("ai-guardrails", "step-09-guardrails", ("AI safety", "and security")),
            Capability("mcp-tools", "step-10-mcp-integration", ("MCP and", "agentic APIs")),
            Capability("edge-inference", "step-13-edge-ai", ("Disconnected", "environments", "and edge")),
        ),
    ),
    Row(
        id="gpu-self-service",
        product="openshift_ai",
        label=("Intelligent GPU", "and hardware", "speed"),
        y=825,
        h=150,
        cols=4,
        caps=(
            Capability(
                "gpu-acceleration",
                "step-01-gpu-and-prereq",
                ("GPU acceleration", "and optimization"),
            ),
            Capability("hardware-profiles", "step-02-rhoai", ("Hardware", "profiles")),
            Capability("self-service-gpu", "step-03-private-ai", ("Self-service", "accelerator access")),
            Capability("gpu-capacity-metrics", "step-06-model-metrics", ("GPU visibility", "and consumption")),
        ),
    ),
    Row(
        id="container-services",
        product="openshift",
        label=("Container", "platform", "services"),
        y=1000,
        h=220,
        cols=4,
        caps=(
            Capability("operators-olm", "step-01-gpu-and-prereq", ("Operators and", "lifecycle management")),
            Capability("gitops-argocd", "step-01-gpu-and-prereq", ("OpenShift GitOps", "and Argo CD")),
            Capability("serverless", "step-01-gpu-and-prereq", ("OpenShift", "Serverless")),
            Capability("service-mesh", "step-02-rhoai", ("Service Mesh", "networking")),
            Capability("identity-rbac", "step-03-private-ai", ("Identity, RBAC,", "and multitenancy")),
            Capability("monitoring", "step-01-gpu-and-prereq", ("Monitoring", "and metrics")),
            Capability("tekton", "step-12-mlops-pipeline", ("OpenShift Pipelines", "(Tekton)")),
            Capability("routes-secrets-storage", "step-03-private-ai", ("Routes, secrets,", "and storage")),
        ),
    ),
    Row(
        id="hybrid-edge",
        product="openshift",
        label=("Hybrid", "infrastructure", "and edge"),
        y=1245,
        h=170,
        cols=3,
        caps=(
            Capability("cloud-gpu-cluster", "step-01-gpu-and-prereq", ("Cloud GPU", "cluster")),
            Capability("gpu-worker-nodes", "step-01-gpu-and-prereq", ("GPU worker", "nodes")),
            Capability("object-storage", "step-03-private-ai", ("Object storage", "and data connections")),
            Capability("edge-target", "step-13-edge-ai", ("Edge deployment", "target")),
            Capability("microshift-runtime", "step-13b-edge-ai-microshift", ("MicroShift", "edge runtime")),
            Capability("embedded-edge-gitops", "step-13b-edge-ai-microshift", ("Embedded", "edge GitOps")),
        ),
    ),
)

LAYOUT = {
    "width": 2400,
    "height": 1535,
    "product_x": 140,
    "product_w": 210,
    "row_x": 365,
    "row_w": 250,
    "content_x": 635,
    "content_w": 1675,
    "gap": 20,
}


def esc(value: object) -> str:
    return escape(str(value), {'"': "&quot;"})


def rect(
    *,
    x: float,
    y: float,
    w: float,
    h: float,
    fill: str,
    stroke: str | None = None,
    stroke_width: float = 2,
    rx: float = 2,
    opacity: str | None = None,
) -> str:
    stroke_value = stroke if stroke is not None else fill
    opacity_attr = f' opacity="{opacity}"' if opacity is not None else ""
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" '
        f'fill="{fill}" stroke="{stroke_value}" stroke-width="{stroke_width}"{opacity_attr}/>'
    )


def text_lines(
    lines: tuple[str, ...],
    x: float,
    y: float,
    size: int,
    fill: str,
    weight: int = 400,
    anchor: str = "middle",
    line_height: int | None = None,
) -> str:
    line_height = line_height or round(size * 1.18)
    first_y = y - ((len(lines) - 1) * line_height) / 2
    return "\n".join(
        (
            f'<text x="{x}" y="{first_y + idx * line_height}" class="body" '
            f'font-size="{size}" fill="{fill}" font-weight="{weight}" '
            f'text-anchor="{anchor}">{esc(line)}</text>'
        )
        for idx, line in enumerate(lines)
    )


def capability_style(cap: Capability, row: Row, step_id: str | None) -> dict[str, object]:
    product_color = PRODUCTS[row.product].color

    if step_id is None:
        return {
            "fill": COLORS["gray80"],
            "stroke": COLORS["gray70"],
            "stroke_width": 2,
            "text": COLORS["white"],
            "weight": 550,
            "filter": "",
            "opacity": None,
            "stripe": product_color,
        }

    current_order = STEP_ORDER[step_id]
    introduced_order = STEP_ORDER[cap.introduced]

    if introduced_order == current_order:
        return {
            "fill": COLORS["gray95"],
            "stroke": product_color,
            "stroke_width": 5,
            "text": COLORS["white"],
            "weight": 700,
            "filter": ' filter="url(#lift)"',
            "opacity": None,
            "stripe": None,
        }

    if introduced_order < current_order:
        return {
            "fill": COLORS["gray80"],
            "stroke": COLORS["gray70"],
            "stroke_width": 2,
            "text": COLORS["white"],
            "weight": 550,
            "filter": "",
            "opacity": None,
            "stripe": product_color,
        }

    return {
        "fill": COLORS["gray90"],
        "stroke": COLORS["gray70"],
        "stroke_width": 2,
        "text": COLORS["gray50"],
        "weight": 450,
        "filter": "",
        "opacity": "0.62",
        "stripe": None,
    }


def capability_font_size(label: tuple[str, ...]) -> int:
    longest = max(len(line) for line in label)
    if len(label) > 2 or longest > 24:
        return 18
    return 19


def draw_capability(cap: Capability, row: Row, idx: int, step_id: str | None) -> str:
    cols = row.cols
    row_index = idx // cols
    col_index = idx % cols
    row_count = (len(row.caps) + cols - 1) // cols
    box_w = (LAYOUT["content_w"] - 60 - LAYOUT["gap"] * (cols - 1)) / cols
    box_h = min(76, (row.h - 48 - LAYOUT["gap"] * (row_count - 1)) / row_count)
    x = LAYOUT["content_x"] + 30 + col_index * (box_w + LAYOUT["gap"])
    y = row.y + 24 + row_index * (box_h + LAYOUT["gap"])
    style = capability_style(cap, row, step_id)
    opacity_attr = f' opacity="{style["opacity"]}"' if style["opacity"] else ""
    font_size = capability_font_size(cap.label)

    parts = [
        f'<g{style["filter"]}{opacity_attr}>',
        rect(
            x=x,
            y=y,
            w=box_w,
            h=box_h,
            fill=str(style["fill"]),
            stroke=str(style["stroke"]),
            stroke_width=float(style["stroke_width"]),
        ),
    ]
    if style["stripe"]:
        parts.append(
            rect(
                x=x,
                y=y,
                w=10,
                h=box_h,
                fill=str(style["stripe"]),
                stroke=str(style["stripe"]),
                stroke_width=0,
                rx=2,
            )
        )
    parts.append(
        text_lines(
            cap.label,
            x + box_w / 2,
            y + box_h / 2 + 7,
            font_size,
            str(style["text"]),
            int(style["weight"]),
        )
    )
    parts.append("</g>")
    return "".join(parts)


def draw_row(row: Row, step_id: str | None) -> str:
    product = PRODUCTS[row.product]
    parts = [
        rect(
            x=LAYOUT["row_x"],
            y=row.y,
            w=LAYOUT["row_w"],
            h=row.h,
            fill=product.color,
            stroke=product.color,
            stroke_width=0,
        ),
        text_lines(
            row.label,
            LAYOUT["row_x"] + LAYOUT["row_w"] / 2,
            row.y + row.h / 2 + 8,
            22,
            COLORS["white"],
            700,
        ),
        rect(
            x=LAYOUT["content_x"],
            y=row.y,
            w=LAYOUT["content_w"],
            h=row.h,
            fill=COLORS["gray90"],
            stroke=COLORS["gray70"],
            stroke_width=2,
        ),
    ]
    parts.extend(draw_capability(cap, row, idx, step_id) for idx, cap in enumerate(row.caps))
    return "".join(parts)


def product_groups() -> list[tuple[str, int, int]]:
    groups: list[tuple[str, int, int]] = []
    start_row = ROWS[0]
    current_product = start_row.product
    start_y = start_row.y
    end_y = start_row.y + start_row.h

    for row in ROWS[1:]:
        if row.product == current_product:
            end_y = row.y + row.h
            continue
        groups.append((current_product, start_y, end_y - start_y))
        current_product = row.product
        start_y = row.y
        end_y = row.y + row.h

    groups.append((current_product, start_y, end_y - start_y))
    return groups


def draw_product_rail() -> str:
    parts = []
    for product_id, y, h in product_groups():
        product = PRODUCTS[product_id]
        parts.append(
            rect(
                x=LAYOUT["product_x"],
                y=y,
                w=LAYOUT["product_w"],
                h=h,
                fill=product.color,
                stroke=product.color,
                stroke_width=0,
            )
        )
        parts.append(
            text_lines(
                product.label,
                LAYOUT["product_x"] + LAYOUT["product_w"] / 2,
                y + h / 2 + 8,
                22,
                COLORS["white"],
                700,
            )
        )
    return "".join(parts)


def draw_striped_legend_box(x: int, y: int, fill: str = COLORS["gray80"], opacity: str | None = None) -> str:
    box_y = y - 23
    parts = [
        rect(x=x, y=box_y, w=34, h=34, fill=fill, stroke=COLORS["gray70"], stroke_width=2, opacity=opacity),
        rect(x=x, y=box_y, w=10, h=17, fill=PRODUCTS["openshift_ai"].color, stroke=PRODUCTS["openshift_ai"].color, stroke_width=0, rx=0),
        rect(x=x, y=box_y + 17, w=10, h=17, fill=PRODUCTS["openshift"].color, stroke=PRODUCTS["openshift"].color, stroke_width=0, rx=0),
        rect(x=x, y=box_y, w=34, h=34, fill="none", stroke=COLORS["gray70"], stroke_width=2),
    ]
    return "".join(parts)


def current_step_products(step_id: str) -> list[str]:
    products: list[str] = []
    for row in ROWS:
        if any(cap.introduced == step_id for cap in row.caps) and row.product not in products:
            products.append(row.product)
    return products


def draw_legend(step_id: str | None) -> str:
    y = 1480

    if step_id is None:
        return "".join(
            [
                draw_striped_legend_box(650, y),
                f'<text x="708" y="{y + 1}" class="body" font-size="22" fill="{COLORS["gray20"]}">Capability used in this demo</text>',
                f'<text x="1125" y="{y + 1}" class="body" font-size="22" fill="{COLORS["gray30"]}">Left stripe and product rail show Red Hat product layer ownership</text>',
            ]
        )

    products = current_step_products(step_id)
    legend_color = PRODUCTS[products[0] if products else "openshift_ai"].color
    return "".join(
        [
            rect(x=440, y=y - 23, w=34, h=34, fill=COLORS["gray95"], stroke=legend_color, stroke_width=5),
            f'<text x="498" y="{y + 1}" class="body" font-size="21" fill="{COLORS["gray20"]}">New in this step</text>',
            draw_striped_legend_box(800, y),
            f'<text x="858" y="{y + 1}" class="body" font-size="21" fill="{COLORS["gray20"]}">Previously introduced</text>',
            rect(
                x=1225,
                y=y - 23,
                w=34,
                h=34,
                fill=COLORS["gray90"],
                stroke=COLORS["gray70"],
                stroke_width=2,
                opacity="0.62",
            ),
            f'<text x="1283" y="{y + 1}" class="body" font-size="21" fill="{COLORS["gray20"]}">Not introduced yet</text>',
            f'<text x="1645" y="{y + 1}" class="body" font-size="21" fill="{COLORS["gray30"]}">Border and stripe colors follow the product layer</text>',
        ]
    )


def title_markup(title: str, step_id: str | None) -> str:
    if step_id is not None and ": " in title:
        prefix, rest = title.split(": ", 1)
        return f'<tspan fill="{COLORS["gray30"]}" font-weight="500">{esc(prefix)}:</tspan> {esc(rest)}'
    return esc(title)


def render_diagram(step_id: str | None, title: str, desc: str) -> str:
    is_root = step_id is None
    image_desc = (
        "Canonical Red Hat OpenShift AI 3.3 demo capability map."
        if is_root
        else f"Capability map showing new, previously introduced, and future capabilities for {title}."
    )

    parts = [
        (
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{LAYOUT["width"]}" '
            f'height="{LAYOUT["height"]}" viewBox="0 0 {LAYOUT["width"]} {LAYOUT["height"]}" '
            'role="img" aria-labelledby="title desc">'
        ),
        f'<title id="title">{esc(title)}</title>',
        f'<desc id="desc">{esc(image_desc)}</desc>',
        (
            "<style>"
            ".display{font-family:'Red Hat Display','Arial',sans-serif}"
            ".body{font-family:'Red Hat Text','Arial',sans-serif}"
            "</style>"
        ),
        (
            "<defs>"
            '<filter id="lift" x="-20%" y="-20%" width="140%" height="140%">'
            '<feDropShadow dx="0" dy="6" stdDeviation="5" flood-color="#000" flood-opacity="0.55"/>'
            "</filter>"
            '<filter id="panelShadow" x="-8%" y="-8%" width="116%" height="116%">'
            '<feDropShadow dx="0" dy="10" stdDeviation="9" flood-color="#000" flood-opacity="0.45"/>'
            "</filter>"
            "</defs>"
        ),
        '<g filter="url(#panelShadow)">',
        rect(
            x=LAYOUT["product_x"],
            y=26,
            w=LAYOUT["content_x"] + LAYOUT["content_w"] - LAYOUT["product_x"],
            h=82,
            fill=COLORS["gray90"],
            stroke=COLORS["gray70"],
            stroke_width=2,
        ),
        (
            f'<text x="{LAYOUT["width"] / 2}" y="60" class="display" font-size="42" '
            f'fill="{COLORS["white"]}" font-weight="700" text-anchor="middle">'
            f"{title_markup(title, step_id)}</text>"
        ),
        (
            f'<text x="{LAYOUT["width"] / 2}" y="91" class="body" font-size="21" '
            f'fill="{COLORS["gray30"]}" text-anchor="middle">{esc(desc)}</text>'
        ),
        draw_product_rail(),
    ]

    parts.extend(draw_row(row, step_id) for row in ROWS)
    parts.append(draw_legend(step_id))
    parts.append("</g>")
    parts.append("</svg>\n")
    return "".join(parts)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    root_svg = render_diagram(
        None,
        "Red Hat OpenShift AI 3.3 demo capability map",
        "One governed platform across private, generative, predictive, and edge AI.",
    )
    (OUT / f"{OUTPUT_STEM['overview']}.svg").write_text(root_svg, encoding="utf-8")

    for step_id, title, desc in STEPS:
        svg = render_diagram(step_id, title, desc)
        (OUT / f"{OUTPUT_STEM[step_id]}.svg").write_text(svg, encoding="utf-8")

    print(f"Generated {len(STEPS) + 1} SVG files in {OUT}")


if __name__ == "__main__":
    main()
