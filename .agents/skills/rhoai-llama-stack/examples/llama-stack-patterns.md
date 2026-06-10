# Llama Stack Patterns

These examples are review patterns. Verify active CRDs, installed distributions,
provider support, Secrets, model endpoints, and vector store services before
copying anything into GitOps.

## Activate The Llama Stack Operator

```yaml
apiVersion: datasciencecluster.opendatahub.io/v1
kind: DataScienceCluster
metadata:
  name: default-dsc
spec:
  components:
    llamastackoperator:
      managementState: Managed
```

Verification:

```bash
oc get pods -n redhat-ods-applications | rg llama-stack-operator-controller-manager
```

## Minimal LlamaStackDistribution Review Shape

```yaml
apiVersion: llamastack.io/v1alpha1
kind: LlamaStackDistribution
metadata:
  name: demo-llama-stack
  namespace: <namespace>
spec:
  replicas: 1
  server:
    distribution:
      name: rh-dev
    containerSpec:
      name: llama-stack
      port: 8321
      env:
      - name: VLLM_URL
        value: <model-serving-url>
      - name: INFERENCE_MODEL
        value: <model-id>
      - name: VLLM_TLS_VERIFY
        value: "false"
      - name: POSTGRES_HOST
        valueFrom:
          secretKeyRef:
            name: <postgres-secret>
            key: host
      - name: POSTGRES_PASSWORD
        valueFrom:
          secretKeyRef:
            name: <postgres-secret>
            key: password
```

Review points:

- Keep database credentials in Secrets.
- Confirm `rh-dev` and port `8321` against the active distribution.
- Confirm model endpoint and model ID through the active model-serving skill.
- Add vector provider variables only for providers actually enabled.

## Base URL Rules

```text
OpenAI SDK base_url: https://<llama-stack-route>/v1
Raw OpenAI-compatible HTTP: https://<llama-stack-route>/v1/...
LlamaStackClient base_url: https://<llama-stack-route>
```

Review points:

- Wrong suffixes cause request failures.
- Use bearer tokens when OAuth is enabled.

## RAG Provider Selection Matrix

| Provider | Good fit | Watchpoints |
|----------|----------|-------------|
| `inline::milvus` | development and testing | local path storage, not the durable default |
| `inline::faiss` | small local experiments | file-backed index, not the durable default |
| `remote::pgvector` | durable PostgreSQL-backed RAG | database lifecycle, backup, sizing, credentials |
| `remote::milvus` | external Milvus service | token, database, timeout, service operations |
| `remote::qdrant` | external Qdrant service | API key, vector size, service operations |

## Responses API RAG Request Shape

```json
{
  "model": "<model-id>",
  "input": "What does the ACME policy say?",
  "tools": [
    {
      "type": "file_search",
      "vector_store_ids": ["<vector-store-id>"]
    }
  ]
}
```

Review points:

- Use Responses API when file citations are required.
- Expect document-level `file_citation` annotations only.
- Confirm vector store IDs exist before testing.

## OAuth Environment Shape

```yaml
env:
- name: AUTH_ISSUER
  value: https://<issuer>
- name: AUTH_AUDIENCE
  value: <audience>
- name: AUTH_JWKS_URI
  value: https://<issuer>/.well-known/jwks.json
- name: AUTH_JWKS_RECHECK_PERIOD
  value: "300"
- name: AUTH_VERIFY_TLS
  value: "true"
```

Review points:

- Match values to the chosen identity provider.
- Test bearer-token requests after enabling authentication.
- Pair with ABAC policy review.

## Custom CA Shape

```yaml
spec:
  server:
    tlsConfig:
      caBundle:
        caCertConfigMapName: <trusted-ca-configmap>
```

Review points:

- ConfigMap must contain the trusted CA bundle.
- Restart Llama Stack pods after changing CA trust.
- Keep broader CA policy aligned with `rhoai-certificate-management`.

## HA And Autoscaling Shape

```yaml
spec:
  replicas: 2
  server:
    podDisruptionBudget:
      maxUnavailable: 1
    topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: ScheduleAnyway
  autoscaling:
    minReplicas: 2
    maxReplicas: 4
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 80
```

Review points:

- Verify the active schema before using these fields.
- Do not scale Llama Stack beyond database, vector store, and model-serving
  endpoint capacity.
- Test endpoint behavior during pod restarts and scale changes.
