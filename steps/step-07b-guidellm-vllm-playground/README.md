# Step 07B: GuideLLM + vLLM-Playground

> **⚠️ WORK IN PROGRESS** - This step is parked for future implementation.

## Goal

Deploy a custom vLLM-Playground configured for **benchmark testing only** using the [Kubernetes Job Pattern (Option 3)](https://github.com/micytao/vllm-playground/blob/main/openshift/README.md#option-3-kubernetes-job-pattern-good-middle-ground).

## Current Status

| Item | Status |
|------|--------|
| Design documented | ✅ Complete |
| GitOps manifests | ✅ Created (needs custom image) |
| Custom image build | ❌ Not started |
| Deployment | ❌ Blocked on custom image |

## Design Preferences

### Architecture: Option 3 - Kubernetes Job Pattern

```
┌─────────────────┐  Run Benchmark   ┌──────────────────┐
│  vLLM-Playground│─────────────────>│  GuideLLM Job    │
│  (Web UI)       │                  │  (Runs to        │
│                 │<─────────────────│   Completion)    │
│  View Results   │    Results       └────────┬─────────┘
└─────────────────┘                           │
                                              ▼
                                 ┌──────────────────────────────┐
                                 │ Existing InferenceServices   │
                                 │ • mistral-3-int4 (1-GPU $)   │
                                 │ • mistral-3-bf16 (4-GPU $$$$)│
                                 │ • devstral-2                 │
                                 │ • granite-8b-agent           │
                                 │ • gpt-oss-20b                │
                                 └──────────────────────────────┘
```

**Why Option 3:**
- ✅ Best for benchmark workloads (batch inference)
- ✅ Automatic cleanup via Kubernetes Jobs
- ✅ Job tracking and retry logic
- ✅ No long-running vLLM pods needed (use existing InferenceServices)

### Key Requirements

1. **Benchmark existing models** - Not create new vLLM pods
2. **GuideLLM integration** - Run Poisson stress tests from UI
3. **Result visualization** - View and analyze benchmark results
4. **Pre-configured endpoints** - Our InferenceService URLs built-in

### Tool Responsibilities

| Use Case | Tool |
|----------|------|
| **Model experimentation** | RHOAI GenAI Playground (Step 06) |
| **API access to models** | LiteMaaS (Step 06B) |
| **Benchmark testing UI** | vLLM-Playground (Step 07B) ← This |
| **Automated benchmarks** | GuideLLM CronJob (Step 07) |
| **Result visualization** | Grafana Dashboard (Step 07) |

## Implementation Plan

### Phase 1: Custom Image Build

Fork and modify [vLLM-Playground](https://github.com/micytao/vllm-playground) to:

1. **Replace pod creation with Job creation**
   - Modify `kubernetes_container_manager.py`
   - Create GuideLLM Jobs instead of vLLM pods
   - Target existing InferenceService endpoints

2. **Add endpoint configuration UI**
   - Dropdown/list of pre-configured endpoints
   - Or text input for custom OpenAI-compatible URLs

3. **Simplify permissions**
   - Remove pod creation RBAC
   - Add Job creation RBAC only

```dockerfile
# Custom Containerfile additions
COPY custom_job_manager.py ${HOME}/vllm-playground/container_manager.py
```

### Phase 2: GitOps Integration

Update manifests to use custom image:

```yaml
image: quay.io/<your-repo>/vllm-playground-benchmarks:latest
```

### Phase 3: Documentation & Testing

- Update README with usage instructions
- Test against all InferenceServices
- Integrate with Grafana dashboards

## Pre-configured Model Endpoints

When implemented, the UI will offer these endpoints:

| Model | Endpoint | GPUs | Description |
|-------|----------|------|-------------|
| `mistral-3-int4` | `http://mistral-3-int4-predictor.private-ai.svc:80/v1` | 1 | Quantized, cost-efficient |
| `mistral-3-bf16` | `http://mistral-3-bf16-predictor.private-ai.svc:80/v1` | 4 | Full precision, high throughput |
| `devstral-2` | `http://devstral-2-predictor.private-ai.svc:80/v1` | 4 | Agentic coding model |
| `granite-8b-agent` | `http://granite-8b-agent-predictor.private-ai.svc:80/v1` | 1 | Agent-capable |
| `gpt-oss-20b` | `http://gpt-oss-20b-predictor.private-ai.svc:80/v1` | 4 | Large OSS model |

## GitOps Structure

```
gitops/step-07b-guidellm-vllm-playground/
├── base/
│   ├── kustomization.yaml
│   └── vllm-playground/
│       ├── kustomization.yaml
│       └── deployment.yaml      # SA, RBAC, ConfigMap, Deployment, Route
└── kustomization.yaml           # (not created yet)
```

## Current Workaround

Until this step is implemented, use **Step 07** for benchmarking:

```bash
# Run benchmarks via GuideLLM CronJob
./steps/step-07-model-performance-metrics/deploy.sh --benchmark

# View results in Grafana
open "https://grafana-private-ai.apps.<cluster>/d/vllm-overview"
```

## References

### Community Project
- [vLLM-Playground GitHub](https://github.com/micytao/vllm-playground)
- [OpenShift Deployment Guide](https://github.com/micytao/vllm-playground/blob/main/openshift/README.md)
- [Option 3 Architecture](https://github.com/micytao/vllm-playground/blob/main/openshift/README.md#option-3-kubernetes-job-pattern-good-middle-ground)

### Related Steps
- [Step 07: Model Performance Metrics](../step-07-model-performance-metrics/README.md) - GuideLLM + Grafana
- [Step 06: GenAI Playground](../step-06-private-ai-playground-maas/README.md) - Model experimentation
- [Step 06B: LiteMaaS](../step-06b-private-ai-litemaas/README.md) - API access

## Next Steps

1. Fork vLLM-Playground repository
2. Implement custom Job-based container manager
3. Build and push custom image
4. Update GitOps manifests
5. Test and document

