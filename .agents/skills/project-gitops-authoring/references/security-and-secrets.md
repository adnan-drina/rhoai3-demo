# Security And Secrets

Use these standards for demo secrets, environment files, TLS bypasses, RBAC, and
security posture.

## Secret Sources

Secrets are created either from documented local operator commands or by the
per-step deployment flow reading values from `.env`. Real credentials must not
be committed.

## Demo Secrets In GitOps

Some placeholder demo secrets can be committed for convenience. They must carry
a clear warning comment:

```yaml
# DEMO VALUES ONLY - Replace for production use
# Generate new values: <documented generation method>
```

If adding a new committed placeholder secret:

- use `envFrom.secretRef` or `env.valueFrom.secretKeyRef`
- do not use inline secret values in normal environment variables
- document the secret purpose in the step README

## Production Alternatives

For real deployments, document production alternatives such as:

- External Secrets Operator
- Sealed Secrets
- locally supplied secrets from a private environment

## Self-Signed Certificates

Self-signed clusters are acceptable for this demo. TLS verification bypasses are
allowed for demo operations, but README text should explain where and why they
are used.

## ODH Managed Label Gotcha

Do not add `opendatahub.io/managed: "true"` to GitOps-managed secrets unless
the relevant controller actually owns them. The ODH model controller can delete
secrets with this label if it did not create them, causing a reconcile loop.

## Demo Security Posture

Accepted for the demo when documented:

- self-signed certs
- placeholder demo secrets with warning comments
- broad Argo CD controller permissions
- limited NetworkPolicy coverage
- database credentials injected from Secrets

Not accepted even for the demo:

- real credentials committed to git
- privileged workload containers
- hostPath volume mounts
- container runtime socket mounts
- wildcard RBAC outside the documented Argo CD demo posture

The active OCP baseline enforces Pod Security Admission at namespace level.
These rules document project intent, not only cluster enforcement.

## Environment File

- Template: `env.example`
- User copy: `.env`
- `.env` must remain gitignored
- Shared scripts should load local configuration through the repo helper library
