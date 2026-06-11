# KFP Pipeline Patterns

Use active `stage-*/kfp/` content as the project reference for KFP v2 pipeline
authoring. Until active KFP content exists, treat
`backup/legacy-implementation-2026-06-09/steps/step-12-mlops-pipeline/kfp/` as
a legacy example only.

## Pipeline Definition

Each `kfp/pipeline.py` should include:

- a module docstring with KFP version, purpose, component list, DSPA reuse, and
  official docs reference
- module-level constants for pipeline wiring values such as secret names and PVC
  names
- small private helper functions for repetitive task wiring
- `@dsl.pipeline` with `name`, `description`, and `pipeline_root`
- typed parameters with defaults
- clear step comments
- explicit task ordering with data dependencies or `.after()` where needed
- task resource requests and limits
- caching disabled for demo freshness unless there is a deliberate exception
- a compiler block for local compilation

Compiled YAML should go under repo artifacts and be uploaded by runner scripts,
not committed as continuously reconciled GitOps state unless explicitly required.

## Component Style

- Put each component in its own file under `kfp/components/`.
- Match filename and function name.
- Use `@dsl.component` or `@component` consistently with local style.
- Always specify a base image; do not rely on the KFP default Python image.
- Prefer the RHOAI base image used by the existing demo unless the task requires
  another supported Red Hat image.
- Pin minimum package versions in `packages_to_install`.
- Add `pip_index_urls` only when required by packages unavailable from the Red
  Hat Python index; remember that KFP replaces, not appends, default index URLs.

## Hermetic Components

Lightweight Python Components must be self-contained:

- imports inside the function body
- constants used by the component defined inside the function
- no references to module-level helper symbols unless passed through
  `additional_funcs`
- utility helpers passed through `additional_funcs` must themselves be
  self-contained

## Types And Artifacts

- All component inputs and outputs need type annotations.
- Use KFP artifact types for Dashboard visibility:
  - `Output[Metrics]` for metrics
  - `Output[ClassificationMetrics]` for classification plots
  - `Output[HTML]` for reports
  - `Output[Model]` for model lineage
  - `Output[Dataset]` for dataset lineage
- Use `typing.NamedTuple` for multiple named outputs.
- Use `.output` for single unnamed outputs and `.outputs["name"]` for named
  outputs.

## Runtime Data Flow

Project convention for shared intermediate data is a shared PVC mounted at
`/shared-data`. Use descriptive subdirectories such as:

```python
SHARED = Path("/shared-data")
DATASET_DIR = SHARED / "dataset"
MODEL_DIR = SHARED / "model"
METRICS_DIR = SHARED / "metrics"
```

## Control Flow

Use the simplest control flow that makes the demo clear:

| Pattern | Use when |
|---------|----------|
| `dsl.ParallelFor` | processing independent items |
| `RuntimeError` quality gate | a failed step should be visible in the Dashboard |
| `dsl.If` / `dsl.Else` | branches both produce valid downstream outputs |
| `dsl.ExitHandler` | cleanup must happen regardless of success |

Step 12 uses failure as a visible quality gate because it is clearer in a demo
than a skipped branch.

## Caching

Disable caching for demo tasks because demo runs should execute fresh, external
state changes between runs, and cached results can hide failures. For production
pipelines, enable caching only on expensive deterministic steps.

## Runner Scripts

Runner scripts should:

- source the repo helper library for logging, local config, and login checks
- parse `--key=value` options for non-trivial inputs
- create or reuse the shared KFP virtual environment at repo root
- compile pipeline YAML when needed
- use DSPA-compatible KFP client authentication
- upload a new pipeline version per run
- create or reuse the target experiment
- submit a new run with explicit parameters

Keep runner behavior idempotent: repeated runs should create new versions/runs
without corrupting existing pipeline or experiment objects.

## GitOps Integration

Pipeline infrastructure such as PVCs, RBAC, and supporting services belongs in
GitOps. Pipeline definitions are compiled and uploaded to DSPA through runner
scripts. They are not continuously reconciled resources by default.

## New Pipeline Checklist

- [ ] module docstring with KFP version, purpose, and docs reference
- [ ] module constants for wiring values
- [ ] helper for resource requests and limits
- [ ] typed pipeline parameters with defaults
- [ ] explicit task ordering
- [ ] caching disabled for demo freshness
- [ ] components split into separate files
- [ ] component imports inside function bodies
- [ ] typed component inputs and outputs
- [ ] Dashboard-visible artifacts where useful
- [ ] supported Red Hat/RHOAI base image
- [ ] runner script sources repo helper library
- [ ] pipeline infrastructure in GitOps

## References

- KFP v2 docs: https://www.kubeflow.org/docs/components/pipelines/
- Current RHOAI baseline AI pipelines docs: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_ai_pipelines/
