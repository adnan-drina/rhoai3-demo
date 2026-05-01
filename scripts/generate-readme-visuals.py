#!/usr/bin/env python3
"""Generate layered Red Hat branded SVG capability diagrams for workshop documentation.

Writes to ``docs/assets/architecture/`` with stems ``rhoai3-demo-capability-map`` (root README)
and ``step-NN-capability-map`` (steps; step ``13b`` uses ``step-13b-capability-map``).

README files embed these with a dedicated ``## Architecture`` section — see `.cursor/rules/20-readme-standard.mdc`.
"""

from pathlib import Path
from xml.sax.saxutils import escape

OUT = Path("docs/assets/architecture")

# Filenames referenced from README.md (rhoai3-demo-capability-map.svg) and step READMEs (step-NN-capability-map.svg).
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
W, H = 1800, 1080

CAPS = {
    "lifecycle": ["Ingest", "Train", "Evaluate", "Register", "Deploy", "Monitor"],
    "rhoai": [
        "Model catalog\nand registry",
        "Models\nas-a-service",
        "Model development\nand customization",
        "Model training\nand experimentation",
        "Feature store",
        "Optimized model\nserving",
        "GPU acceleration\nand optimization",
        "Model observability\nand governance",
        "AI pipelines",
        "Agentic AI and GenAI\nuser interfaces",
    ],
    "gpu": ["NFD Operator", "GPU support", "NVIDIA GPU Operator"],
    "ocp": [
        "Data foundation",
        "Pipelines\n(Tekton)",
        "Serverless\n(Knative)",
        "Monitoring\n(Prometheus)",
        "Streams\n(Kafka)",
        "GitOps\n(Argo CD)",
        "Service Mesh\n(Istio)",
        "Access control\nand multitenancy",
    ],
    "infra": ["Bare metal", "Virtualization", "Cloud", "Cloud secured", "Edge"],
}

BASE_INTRODUCED = {
    "lifecycle": set(),
    "rhoai": set(),
    "gpu": set(),
    "ocp": set(),
    "infra": set(),
}

STEPS = [
    ("overview", "Red Hat OpenShift AI Private AI Platform Workshop", "your models, your data, your choice."),
    ("step-01-gpu-and-prereq", "Step 01: GPU Infrastructure And Prerequisites", "Accelerator capacity becomes a governed platform resource."),
    ("step-02-rhoai", "Step 02: Red Hat OpenShift AI Platform", "Infrastructure becomes governed AI self-service."),
    ("step-03-private-ai", "Step 03: Private AI Workspace", "Identity, access, and storage define the private platform boundary."),
    ("step-04-model-registry", "Step 04: Model Registry And Catalog", "Models gain a lifecycle record before they become endpoints."),
    ("step-05-llm-on-vllm", "Step 05: LLM Serving On vLLM", "Private model serving turns GenAI into a platform capability."),
    ("step-06-model-metrics", "Step 06: Model Metrics And Benchmarking", "Observability connects user experience, GPU capacity, and cost."),
    ("step-07-rag", "Step 07: RAG Pipeline", "Enterprise knowledge grounds local model answers."),
    ("step-08-model-evaluation", "Step 08: Model Evaluation", "Repeatable evidence replaces ad hoc answer inspection."),
    ("step-09-guardrails", "Step 09: Guardrails", "Safety checks become a shared platform control point."),
    ("step-10-mcp-integration", "Step 10: MCP Integration", "Agentic tools are explicit, permissioned, and observable."),
    ("step-11-face-recognition", "Step 11: Face Recognition", "The same platform serves predictive computer-vision models."),
    ("step-12-mlops-pipeline", "Step 12: MLOps Pipeline", "Training, validation, promotion, and monitoring become repeatable."),
    ("step-13-edge-ai", "Step 13: Edge AI", "Inference moves outward while lifecycle control stays central."),
    ("step-13b-edge-ai-microshift", "Step 13b: Edge AI On MicroShift", "The edge pattern lands on a smaller OpenShift-derived footprint."),
]

NEW = {
    "overview": {
        "lifecycle": {"Ingest", "Train", "Evaluate", "Register", "Deploy", "Monitor"},
        "rhoai": {
            "Model catalog\nand registry",
            "Model development\nand customization",
            "Model training\nand experimentation",
            "Optimized model\nserving",
            "GPU acceleration\nand optimization",
            "Model observability\nand governance",
            "AI pipelines",
            "Agentic AI and GenAI\nuser interfaces",
        },
        "gpu": {"NFD Operator", "GPU support", "NVIDIA GPU Operator"},
        "ocp": {
            "Data foundation",
            "Pipelines\n(Tekton)",
            "Serverless\n(Knative)",
            "Monitoring\n(Prometheus)",
            "GitOps\n(Argo CD)",
            "Service Mesh\n(Istio)",
            "Access control\nand multitenancy",
        },
        "infra": {"Cloud", "Edge"},
    },
    "step-01-gpu-and-prereq": {
        "gpu": {"NFD Operator", "GPU support", "NVIDIA GPU Operator"},
        "ocp": {"Serverless\n(Knative)", "Monitoring\n(Prometheus)", "GitOps\n(Argo CD)"},
        "infra": {"Cloud"},
    },
    "step-02-rhoai": {
        "rhoai": {
            "Model catalog\nand registry",
            "Model development\nand customization",
            "Model training\nand experimentation",
            "Optimized model\nserving",
            "GPU acceleration\nand optimization",
            "Model observability\nand governance",
            "AI pipelines",
            "Agentic AI and GenAI\nuser interfaces",
        },
        "ocp": {"Service Mesh\n(Istio)"},
    },
    "step-03-private-ai": {
        "ocp": {"Data foundation", "Access control\nand multitenancy"},
    },
    "step-04-model-registry": {
        "lifecycle": {"Register"},
        "rhoai": {"Model catalog\nand registry"},
    },
    "step-05-llm-on-vllm": {
        "lifecycle": {"Deploy"},
        "rhoai": {"Optimized model\nserving", "Models\nas-a-service"},
    },
    "step-06-model-metrics": {
        "lifecycle": {"Monitor"},
        "rhoai": {"Model observability\nand governance"},
    },
    "step-07-rag": {
        "lifecycle": {"Ingest"},
        "rhoai": {"Model development\nand customization", "AI pipelines", "Agentic AI and GenAI\nuser interfaces"},
    },
    "step-08-model-evaluation": {
        "lifecycle": {"Evaluate"},
        "rhoai": {"Model observability\nand governance", "AI pipelines"},
    },
    "step-09-guardrails": {
        "rhoai": {"Model observability\nand governance"},
    },
    "step-10-mcp-integration": {
        "rhoai": {"Agentic AI and GenAI\nuser interfaces"},
    },
    "step-11-face-recognition": {
        "rhoai": {"Model development\nand customization", "Model training\nand experimentation", "Optimized model\nserving"},
    },
    "step-12-mlops-pipeline": {
        "lifecycle": {"Train", "Evaluate", "Register", "Deploy", "Monitor"},
        "rhoai": {"Model training\nand experimentation", "AI pipelines", "Model catalog\nand registry", "Model observability\nand governance"},
        "ocp": {"Pipelines\n(Tekton)"},
    },
    "step-13-edge-ai": {
        "lifecycle": {"Deploy"},
        "infra": {"Edge"},
    },
    "step-13b-edge-ai-microshift": {
        "lifecycle": {"Deploy", "Monitor"},
        "ocp": {"Pipelines\n(Tekton)", "GitOps\n(Argo CD)"},
        "infra": {"Edge"},
    },
}

DEFERRED = {
    "rhoai": {"Feature store", "Models\nas-a-service"},
    "ocp": {"Streams\n(Kafka)"},
    "infra": {"Bare metal", "Virtualization", "Cloud secured"},
}


def lines(text):
    return text.split("\n")


def text_block(x, y, text, size=28, weight=500, fill="#ffffff", anchor="middle", line_height=34):
    parts = []
    for i, line in enumerate(lines(text)):
        parts.append(
            f'<text x="{x}" y="{y + i * line_height}" text-anchor="{anchor}" '
            f'font-family="Red Hat Text, Arial, sans-serif" font-size="{size}" '
            f'font-weight="{weight}" fill="{fill}">{escape(line)}</text>'
        )
    return "\n".join(parts)


def rect(x, y, w, h, state="none"):
    if state == "new":
        return (
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="3" '
            f'fill="#3f1f1f" stroke="#ee0000" stroke-width="5" filter="url(#shadow)"/>'
        )
    if state == "prev":
        return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="3" fill="#4d4d4d" stroke="#707070" stroke-width="2"/>'
    if state == "support":
        return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="3" fill="#2b2020" stroke="#ee0000" stroke-width="2" opacity=".92"/>'
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="3" fill="#151515" stroke="#707070" stroke-width="2"/>'


def state_for(layer, cap, new, prev):
    if cap in new.get(layer, set()):
        return "new"
    if cap in prev.get(layer, set()):
        return "prev"
    if cap in DEFERRED.get(layer, set()):
        return "none"
    if layer in {"ocp", "infra"} and cap in {"Cloud", "Serverless\n(Knative)", "Monitoring\n(Prometheus)", "Service Mesh\n(Istio)", "Access control\nand multitenancy", "Data foundation", "GitOps\n(Argo CD)", "Pipelines\n(Tekton)", "Edge"}:
        return "support"
    return "none"


def draw_row(label, x, y, w, h, red=False):
    color = "#ee0000" if red else "#000000"
    return (
        f'<rect x="42" y="{y}" width="270" height="{h}" rx="3" fill="{color}"/>'
        + text_block(177, y + h / 2 - 14, label, size=28, weight=800, anchor="middle", line_height=34)
        + f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="3" fill="#000000" fill-opacity=".12" stroke="{("#f56e6e" if red else "#707070")}" stroke-width="3"/>'
    )


def capability(x, y, w, h, label, state, size=24):
    fill = "#ffffff" if state != "prev" else "#151515"
    return rect(x, y, w, h, state) + text_block(x + w / 2, y + h / 2 - (12 if "\n" not in label else 26), label, size=size, weight=700 if state == "new" else 500, fill=fill, anchor="middle", line_height=30)


def render(step_id, title, subtitle, prev):
    new = NEW[step_id]
    out = []
    out.append(f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" aria-labelledby="title desc">
  <title id="title">{escape(title)}</title>
  <desc id="desc">Dark themed layered architecture capability map showing newly introduced and previously introduced platform capabilities for {escape(title)}.</desc>
  <defs>
    <filter id="shadow" x="-10%" y="-10%" width="120%" height="130%">
      <feDropShadow dx="0" dy="5" stdDeviation="4" flood-color="#ee0000" flood-opacity=".42"/>
    </filter>
    <style>
      .heading {{ font-family: "Red Hat Display", "Red Hat Text", Arial, sans-serif; }}
      .mono {{ font-family: "Red Hat Mono", monospace; }}
    </style>
  </defs>
  <rect width="{W}" height="{H}" fill="#000000"/>
  <circle cx="1520" cy="120" r="390" fill="#ee0000" opacity=".12"/>
''')
    out.append(f'<text x="48" y="74" class="heading" font-size="48" font-weight="800" fill="#ffffff">{escape(title)}</text>')
    out.append(f'<text x="48" y="116" font-family="Red Hat Text, Arial, sans-serif" font-size="26" font-weight="500" fill="#c7c7c7">{escape(subtitle)}</text>')

    x0, row_w = 330, 1428
    out.append(draw_row("AI Lifecycle", x0, 150, row_w, 168))
    life_xs = [x0 + 48 + i * 205 for i in range(6)]
    for x, cap in zip(life_xs, CAPS["lifecycle"]):
        out.append(capability(x, 222, 170, 68, cap, state_for("lifecycle", cap, new, prev), size=23))
    out.append('<rect x="830" y="170" width="460" height="44" rx="2" fill="#000000" stroke="#707070" stroke-width="2"/>')
    out.append(text_block(1060, 201, "Retrain", size=23, weight=800))
    out.append('<path d="M1060 170 L432 170 L432 210" fill="none" stroke="#c7c7c7" stroke-width="2"/>')

    out.append(draw_row("OpenShift\nAI/ML\nplatform", x0, 334, row_w, 230))
    rhoai_positions = [
        (350, 354), (590, 354), (830, 354), (1070, 354), (1310, 354), (1550, 354),
        (830, 470), (1070, 470), (1310, 470), (1550, 470),
    ]
    for (x, y), cap in zip(rhoai_positions, CAPS["rhoai"]):
        out.append(capability(x, y, 210, 86, cap, state_for("rhoai", cap, new, prev), size=21))
    out.append('<text x="376" y="528" class="heading" font-size="34" font-weight="800" fill="#ffffff">Red Hat</text>')
    out.append('<text x="376" y="560" class="heading" font-size="34" font-weight="500" fill="#ffffff">OpenShift AI</text>')
    out.append('<ellipse cx="344" cy="520" rx="34" ry="17" fill="#ee0000" transform="rotate(12 344 520)"/>')

    out.append(draw_row("GPU accelerators", x0, 580, row_w, 88))
    out.append(capability(350, 604, 465, 44, "NFD Operator", state_for("gpu", "NFD Operator", new, prev), size=22))
    out.append(text_block(1044, 635, "GPU support", size=27, weight=800))
    out.append(capability(1324, 604, 410, 44, "NVIDIA GPU Operator", state_for("gpu", "NVIDIA GPU Operator", new, prev), size=22))

    out.append(draw_row("OpenShift\nContainer\nPlatform", x0, 686, row_w, 216, red=True))
    ocp_positions = [(820, 708), (1060, 708), (1300, 708), (1540, 708), (820, 812), (1060, 812), (1300, 812), (1540, 812)]
    for (x, y), cap in zip(ocp_positions, CAPS["ocp"]):
        out.append(capability(x, y, 210, 86, cap, state_for("ocp", cap, new, prev), size=21))
    out.append('<text x="376" y="846" class="heading" font-size="34" font-weight="800" fill="#ffffff">Red Hat</text>')
    out.append('<text x="376" y="878" class="heading" font-size="34" font-weight="500" fill="#ffffff">OpenShift</text>')
    out.append('<ellipse cx="344" cy="838" rx="34" ry="17" fill="#ee0000" transform="rotate(12 344 838)"/>')

    out.append(draw_row("Infrastructure", x0, 918, row_w, 92, red=True))
    for x, cap in zip([505, 735, 970, 1215, 1480], CAPS["infra"]):
        state = state_for("infra", cap, new, prev)
        color = "#ee0000" if state == "new" else ("#c7c7c7" if state == "prev" else "#707070")
        out.append(f'<circle cx="{x}" cy="954" r="22" fill="none" stroke="{color}" stroke-width="4"/>')
        out.append(text_block(x, 996, cap, size=22, weight=700, fill="#ffffff"))

    out.append('<rect x="430" y="1032" width="34" height="34" rx="2" fill="#3f1f1f" stroke="#ee0000" stroke-width="4"/>')
    out.append(text_block(482, 1057, "New in this step", size=21, anchor="start"))
    out.append('<rect x="765" y="1032" width="34" height="34" rx="2" fill="#4d4d4d" stroke="#707070" stroke-width="2"/>')
    out.append(text_block(817, 1057, "Previously introduced", size=21, anchor="start"))
    out.append('<rect x="1165" y="1032" width="34" height="34" rx="2" fill="#151515" stroke="#707070" stroke-width="2"/>')
    out.append(text_block(1217, 1057, "Not yet covered / not demonstrated", size=21, anchor="start"))
    out.append("</svg>\n")
    return "\n".join(out)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    prev = {k: set(v) for k, v in BASE_INTRODUCED.items()}
    for step_id, title, subtitle in STEPS:
        svg = render(step_id, title, subtitle, prev)
        stem = OUTPUT_STEM[step_id]
        (OUT / f"{stem}.svg").write_text(svg)
        if step_id != "overview":
            for layer, caps in NEW[step_id].items():
                prev[layer].update(caps)
    print(f"Generated {len(STEPS)} SVG files in {OUT}")


if __name__ == "__main__":
    main()
