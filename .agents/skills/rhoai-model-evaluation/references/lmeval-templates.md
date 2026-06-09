# LM-Eval Templates Reference

## Table of Contents

- [Overview](#overview)
- [LMEvalJob CR Structure](#lmevaljob-cr-structure)
- [Available Templates](#available-templates)
- [Task Selection](#task-selection)
- [Running Benchmarks](#running-benchmarks)
- [Interpreting Results](#interpreting-results)
- [Troubleshooting](#troubleshooting)

## Overview

LM-Eval benchmarks use the TrustyAI operator's `LMEvalJob` custom resource
(`trustyai.opendatahub.io/v1alpha1`). Templates are in
`gitops/step-08-model-evaluation/base/lmeval/` and applied on-demand (not
ArgoCD-managed).

## LMEvalJob CR Structure

```yaml
apiVersion: trustyai.opendatahub.io/v1alpha1
kind: LMEvalJob
metadata:
  name: <model>-eval-<timestamp>
  namespace: private-ai
spec:
  model: local-completions
  modelArgs:
    - name: base_url
      value: "http://<model>-predictor.private-ai.svc.cluster.local:8080/v1/completions"
    - name: model
      value: "<model>"
    - name: tokenizer
      value: "<hf-tokenizer-id>"
    - name: num_concurrent
      value: "4"
    - name: max_retries
      value: "5"
    - name: tokenized_requests
      value: "false"
  taskList:
    taskNames:
      - hellaswag
      - arc_challenge
      - winogrande
      - boolq
  limit: "50"
  logSamples: true
  batchSize: "1"
  allowOnline: true
  allowCodeExecution: true
  outputs:
    pvcManaged:
      size: 2Gi
```

### Key Fields

| Field | Description | Notes |
|-------|-------------|-------|
| `model` | Always `local-completions` | Uses vLLM's OpenAI-compatible endpoint |
| `modelArgs.base_url` | vLLM completions endpoint | Must be cluster-internal URL |
| `modelArgs.tokenizer` | HuggingFace tokenizer ID | Must match the served model |
| `taskList.taskNames` | Evaluation tasks | See [Task Selection](#task-selection) |
| `limit` | Samples per task | `"50"` for demos, remove for full runs |
| `batchSize` | Inference batch size | `"1"` is safest for vLLM |
| `outputs.pvcManaged.size` | Storage for results | 2Gi is sufficient |

## Available Templates

### granite-8b-eval.yaml

| Field | Value |
|-------|-------|
| base_url | `http://granite-8b-agent-predictor.private-ai.svc.cluster.local:8080/v1/completions` |
| tokenizer | `ibm-granite/granite-3.1-8b-instruct` |
| limit | 50 |

### mistral-bf16-eval.yaml

| Field | Value |
|-------|-------|
| base_url | `http://mistral-3-bf16-predictor.private-ai.svc.cluster.local:8080/v1/completions` |
| tokenizer | `mistralai/Mistral-Small-24B-Instruct-2501` |
| limit | 50 |

## Task Selection

Standard tasks included in the demo:

| Task | Category | Measures | Metric |
|------|----------|----------|--------|
| hellaswag | Commonsense | Sentence completion reasoning | acc_norm |
| arc_challenge | Science | Grade-school science questions | acc_norm |
| winogrande | Commonsense | Pronoun resolution | acc |
| boolq | Reading | Yes/no reading comprehension | acc |

These four tasks provide a balanced assessment across reasoning categories.
Full benchmark suites (MMLU, GSM8K, etc.) can be added to `taskNames` but
increase runtime significantly.

## Running Benchmarks

### Via script

```bash
# Default: granite-8b-agent, 50 samples
./steps/step-08-model-evaluation/run-lmeval.sh granite-8b-agent

# Custom: mistral, 200 samples
./steps/step-08-model-evaluation/run-lmeval.sh mistral-3-bf16 200
```

### Manual CR application

```bash
oc apply -f gitops/step-08-model-evaluation/base/lmeval/granite-8b-eval.yaml
```

### Monitoring

```bash
# Watch job status
oc get lmevaljob -n private-ai -w

# Check pod logs
oc logs -n private-ai -l app=lmeval --tail=50 -f
```

### Runtime Estimates

| Model | Tasks | Limit | Approximate Time |
|-------|-------|-------|-----------------|
| granite-8b-agent | 4 | 50 | ~10 minutes |
| granite-8b-agent | 4 | full | ~2 hours |
| mistral-3-bf16 | 4 | 50 | ~15 minutes |
| mistral-3-bf16 | 4 | full | ~4 hours |

## Interpreting Results

### Via Dashboard

RHOAI Dashboard → Develop & train → Evaluations

Shows per-task accuracy scores in a tabular view.

### Via CLI

```bash
oc get lmevaljob <name> -n private-ai -o jsonpath='{.status.results}'
```

### Score Expectations (50-sample approximation)

| Model | hellaswag | arc_challenge | winogrande | boolq |
|-------|-----------|---------------|------------|-------|
| granite-8b-agent | ~0.65 | ~0.55 | ~0.68 | ~0.78 |
| mistral-3-bf16 | ~0.78 | ~0.68 | ~0.75 | ~0.85 |

These are approximate — 50-sample runs have high variance. Full runs are more stable.

## Troubleshooting

### LMEvalJob stuck in Pending

```bash
# Check pod status
oc get pods -n private-ai -l app=lmeval

# Common cause: no available compute
oc describe pod <lmeval-pod> -n private-ai
```

LMEvalJob pods run on CPU — they don't need GPU. If stuck, check resource quotas.

### Connection refused to model endpoint

```bash
# Verify model is serving
oc get inferenceservice -n private-ai
oc get pods -n private-ai -l serving.kserve.io/inferenceservice=<model>
```

The model must have `READY=True` before starting LM-Eval.

### Results empty or zero

- Check `logSamples: true` is set
- Verify `tokenizer` matches the model (wrong tokenizer = garbage results)
- Check `batchSize: "1"` — larger batches can OOM on some models
