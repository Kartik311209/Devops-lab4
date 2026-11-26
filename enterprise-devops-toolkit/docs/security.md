# Enterprise DevOps Security Architecture

This document outlines the defense-in-depth security controls implemented across the **Enterprise DevOps Deployment Toolkit (EDDT)**.

---

## 1. Security Architecture Overview

Security in EDDT follows the principle of **Defense-in-Depth** across code, containers, cluster, and pipelines:

```
          ┌───────────────────────────────────┐
          │      Code & Dependency Security   │ (No hardcoded secrets, input validation)
          ├───────────────────────────────────┤
          │      Container Security           │ (Non-root user 1001, minimal slim base)
          ├───────────────────────────────────┤
          │      Kubernetes Cluster Security  │ (Readiness/Liveness probes, securityContext)
          ├───────────────────────────────────┤
          │      Secret Management            │ (K8s Secrets, Base64 warning, Vault extension)
          ├───────────────────────────────────┤
          │      Pipeline & GitOps Security   │ (Zero cluster keys in CI, pull-based Argo CD)
          └───────────────────────────────────┘
```

---

## 2. Container Security Hardening

### Non-Root Execution
Running containers as root (UID 0) presents a severe privilege escalation risk if a vulnerability (e.g., container breakout) occurs.
TaskFlow's [`docker/Dockerfile`](../docker/Dockerfile) explicitly configures a dedicated user and group:

```dockerfile
# Create non-privileged system user and group
RUN groupadd --gid 1001 appgroup && \
    useradd  --uid 1001 --gid appgroup --no-create-home --shell /sbin/nologin appuser

# Switch execution context
USER appuser
```

### SecurityContext in Kubernetes Manifests
Every Kubernetes Deployment enforces non-root execution at the admission level:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1001
  runAsGroup: 1001
  fsGroup: 1001
```

---

## 3. Secret Management & Compliance Rules

1. **Zero Credentials in Version Control**:
   - The `.gitignore` file strictly excludes `.env`, `*.key`, `*.pem`, `*.db`, and `secrets.yaml`.
   - Only sanitized templates with explicit placeholders (such as `kubernetes/secrets/secret-example.yaml`) are committed.
2. **Base64 Demystification**:
   - Educational awareness: Base64 encoding is for serialization, not encryption.
   - Production recommendation: Enable Kubernetes etcd Encryption at Rest with AWS KMS or HashiCorp Vault.
3. **Least Privilege RBAC**:
   - Service accounts running application workloads must never have cluster-admin privileges.
   - Restrict secret access via targeted Kubernetes `Role` bindings.

---

## 4. Input Sanitization & Application Resilience

- **SQL Injection Prevention**: SQLite queries in `app/app.py` strictly utilize parameterized SQL statements (`?` placeholders). No string concatenation is used in query building.
- **Payload Validation**: Title length is capped at 200 characters; status and priority fields are validated against strict whitelist sets (`VALID_STATUSES`, `VALID_PRIORITIES`).
- **HTTP Error Handling**: Custom error handlers mask internal traceback details from API responses, returning structured JSON errors.
