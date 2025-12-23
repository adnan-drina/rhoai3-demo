# Step 05: LLM Inference with vLLM

> **Status**: 🚧 Placeholder - Implementation pending

Deploys the **Granite 3.1 8B Instruct FP8** model registered in Step 04 to a KServe inference endpoint using vLLM.

---

## Overview

This step completes the model deployment workflow:

```
Step 04: Model Registry          Step 05: Inference
════════════════════════         ════════════════════════
                                 
┌─────────────────────┐          ┌─────────────────────┐
│  Granite 3.1 FP8    │          │  KServe Endpoint    │
│  ─────────────────  │          │  ─────────────────  │
│  Status: Registered │ ───────▶ │  Status: Serving    │
│  URI: s3://...      │          │  URL: https://...   │
│  Ready to Deploy    │          │  GPU: NVIDIA L4     │
└─────────────────────┘          └─────────────────────┘
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          private-ai namespace                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────┐                                                       │
│   │   InferenceService                                                      │
│   │   granite-3-1-8b-instruct                                              │
│   │                                                                         │
│   │   ┌─────────────────────────────────────────────────────────────────┐  │
│   │   │                    Predictor Pod                                │  │
│   │   │   ┌─────────────────┐    ┌─────────────────┐                   │  │
│   │   │   │   vLLM Engine   │    │   Model Weights │                   │  │
│   │   │   │   OpenAI API    │◀───│   From MinIO    │                   │  │
│   │   │   │   :8000         │    │   FP8 Dynamic   │                   │  │
│   │   │   └─────────────────┘    └─────────────────┘                   │  │
│   │   │                              │                                  │  │
│   │   │                              ▼                                  │  │
│   │   │                    ┌─────────────────┐                          │  │
│   │   │                    │   NVIDIA L4     │                          │  │
│   │   │                    │   16GB VRAM     │                          │  │
│   │   │                    │   Kueue-managed │                          │  │
│   │   │                    └─────────────────┘                          │  │
│   │   └─────────────────────────────────────────────────────────────────┘  │
│   └─────────────────┘                                                       │
│                                                                             │
│   Exposed via: OpenShift Route (HTTPS)                                     │
│   API: OpenAI-compatible (/v1/chat/completions)                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Components

### ServingRuntime: vLLM

| Property | Value |
|----------|-------|
| **Name** | `vllm-runtime` |
| **Engine** | vLLM |
| **API** | OpenAI-compatible |
| **Port** | 8000 |

### InferenceService: Granite

| Property | Value |
|----------|-------|
| **Name** | `granite-3-1-8b-instruct` |
| **Model** | Granite 3.1 8B Instruct FP8 |
| **Source** | Model Registry (Step 04) |
| **GPU** | 1x NVIDIA L4 |
| **Quantization** | FP8-dynamic |

---

## Prerequisites

- [x] Step 01: GPU infrastructure with NVIDIA L4
- [x] Step 02: RHOAI 3.0 with KServe
- [x] Step 03: MinIO storage with model artifacts
- [x] Step 04: Model registered in registry

---

## Deploy

```bash
./steps/step-05-llm-on-vllm/deploy.sh
```

---

## Validation

```bash
# TODO: Add validation commands
# - Check InferenceService status
# - Test inference endpoint
# - Verify GPU allocation
```

---

## API Usage

```bash
# TODO: Add curl examples for OpenAI-compatible API
# POST /v1/chat/completions
```

---

## Documentation Links

- [Serving Models - RHOAI 3.0](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/serving_models/index)
- [vLLM Documentation](https://docs.vllm.ai/)
- [KServe Documentation](https://kserve.github.io/website/)

---

## TODO

- [ ] Implement vLLM ServingRuntime manifest
- [ ] Implement InferenceService manifest
- [ ] Configure model loading from MinIO
- [ ] Integrate with Kueue for GPU scheduling
- [ ] Add route/ingress configuration
- [ ] Implement deploy.sh script
- [ ] Add validation commands
- [ ] Document API usage examples

