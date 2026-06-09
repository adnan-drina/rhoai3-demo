# Evaluation Development Patterns

Use these constraints when changing Step 08 evaluation code, GitOps manifests,
test assets, or scripts.

## Judge Model

The RAG evaluation judge model is `mistral-3-bf16`. This is deliberate: using
the same small model for candidate and judge produces biased or hallucinated
judgments. Do not change the judge model without re-running all four scenarios
and comparing grade distributions.

## Test Asset Integrity

The YAML files in `eval-configs/` contain curated question and expected-answer
pairs. Changing expected answers changes the baseline.

When updating expected answers:

1. Run pre-RAG evaluation to establish the new baseline.
2. Run post-RAG evaluation to confirm improvement.
3. Update both copies of the test assets:
   - `steps/step-08-model-evaluation/eval-configs/`
   - `gitops/step-08-model-evaluation/base/eval-configs/`

The step-level and GitOps-level copies must remain identical.

## LMEvalJob Pattern

LMEvalJob templates under `gitops/step-08-model-evaluation/base/lmeval/` are
on-demand templates applied by `run-lmeval.sh`. They are intentionally not
ArgoCD-managed because evaluation jobs are one-shot workloads, not continuously
reconciled resources. Do not add them to the ArgoCD Application kustomization.

## Judge Prompt Anchoring

The judge prompt in `scoring-templates/judge_prompt.txt` must preserve the
line that anchors A-E extraction:

```text
Answer:
```

Prompt changes must keep the extraction pattern compatible with
`Answer: (A|B|C|D|E)`.

## EvalHub, KFP, And Pod Paths

EvalHub is the primary path for ACME and whoami pre/post RAG evaluation:

- `run-evalhub-rag-scenarios.sh` submits ACME/whoami pre/post RAG benchmarks.
- `rhoai-rag-scenarios` is the custom EvalHub SDK provider that reads
  `eval-test-cases` and `eval-configs`.
- `run-rag-eval.sh` is the optional KFP compatibility path through DSPA.
- `run-eval-report.sh` is the direct pod path for faster LlamaStack/RAG
  debugging when EvalHub itself is not the issue.

All paths should use the same YAML test assets and judge prompt.

## References

- Current baseline Evaluating AI Systems docs: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/evaluating_ai_systems/
- Current baseline LMEvalJob docs: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/evaluating_ai_systems/evaluating-large-language-models_evaluate
- Current baseline RAGAS docs: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/evaluating_ai_systems/evaluating-rag-systems-with-ragas_evaluate
