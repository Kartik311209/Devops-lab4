# Laboratory Report: Enterprise DevOps Deployment Toolkit (EDDT)

**Course**: Advanced Enterprise DevOps & Cloud-Native Engineering  
**Project**: Enterprise DevOps Deployment Toolkit (EDDT)  
**System Under Test**: Enterprise TaskFlow Application  
**Execution Environment**: Linux / WSL (Ubuntu 22.04 LTS), Minikube (Kubernetes 1.30+), Docker 29.8+, Python 3.12+  
**Date**: November 2026  

---

## Executive Summary

Modern enterprise software systems demand rapid delivery cycles without compromising reliability, security, or compliance. The **Enterprise DevOps Deployment Toolkit (EDDT)** is an end-to-end framework designed to address the challenges of continuous delivery in regulated, high-availability environments.

This report documents the design, implementation, and empirical verification of nine integrated DevOps experiments:
1. **Application Architecture & Micro-Persistence**
2. **Automated Testing Pyramid & Quality Gates**
3. **Container Security & Minimal Packaging**
4. **Declarative CI/CD Pipeline Automation**
5. **Zero-Downtime Blue-Green Deployment & Atomic Rollback**
6. **Progressive Canary Deployment with Approximate Traffic Splitting**
7. **GitOps Continuous Delivery & Automated Self-Healing with Argo CD**
8. **Kubernetes Secret Management & Cryptographic Hygiene**
9. **Disaster Recovery, Checksummed Hot Backups & Verified Point-in-Time Recovery**

---

## Experiment 1: Application Architecture & Micro-Persistence

### 1.1 Objective
Construct a production-style, container-ready application named **Enterprise TaskFlow** featuring user task lifecycle management, RESTful CRUD endpoints, localized database persistence via SQLite, and explicit probe endpoints for Kubernetes lifecycle management.

### 1.2 Design & Implementation
- **Framework**: Python 3.12 with Flask 3.0.3 and Gunicorn 22.0.0 WSGI server.
- **Persistence**: Relational SQLite database (`taskflow.db`) with automatic table creation (`CREATE TABLE IF NOT EXISTS`) and schema idempotency.
- **Probe Endpoints**:
  - `GET /health`: Liveness probe verifying process responsiveness.
  - `GET /ready`: Readiness probe actively querying the persistence layer (`SELECT 1`) to ensure database lock or file accessibility issues trigger a 503 Service Unavailable status before traffic is routed.
  - `GET /version`: Operational probe returning JSON metadata: `version`, `environment`, `color` (active deployment slot), and ISO 8601 UTC timestamp.
- **RESTful Endpoints**: Full CRUD for tasks (`/api/tasks`, `/api/tasks/{id}`) with query-string filtering (`?status=`, `?priority=`).
- **Resilience**: Parameterized SQL queries preventing SQL injection; strict input validation on titles, statuses, and priorities; centralized JSON error handlers (400, 404, 405, 500).

### 1.3 Observations & Results
Live testing confirmed that the application successfully initialized the database schema, handled malformed input gracefully, and reported health status:
```json
// GET /health -> 200 OK
{
  "app": "Enterprise TaskFlow",
  "status": "healthy",
  "timestamp": "2026-11-19T18:30:38+00:00",
  "version": "1.0.0"
}
```

---

## Experiment 2: Automated Testing Pyramid & Quality Gates

### 2.1 Objective
Implement an automated testing harness using `pytest` capable of running in continuous integration pipelines, generating machine-readable JUnit XML reports and statement-level code coverage.

### 2.2 Test Architecture
The test suite is structured into three dedicated modules:
1. [`tests/test_app.py`](../tests/test_app.py): Unit tests verifying database initialization, idempotency, ISO-8601 date formatting, status/priority whitelist validation, edge-case payload validation (blank title, title > 200 characters), and custom error handlers.
2. [`tests/test_health.py`](../tests/test_health.py): Probe tests verifying HTTP status codes, JSON schema compliance, HTTP method restrictions (POST/DELETE rejected with 405), and simulated database failure returning HTTP 503.
3. [`tests/test_api.py`](../tests/test_api.py): Integration tests covering complete CRUD lifecycles, query parameter filters (`?status=pending`, `?priority=high`), ascending ID sequencing, and persistence verification.

### 2.3 Empirical Test Execution Results
```text
============================= test session starts =============================
platform win32 -- Python 3.12.10, pytest-8.2.2, pluggy-1.6.0
rootdir: C:\Users\karti\Desktop\Devops4\enterprise-devops-toolkit
configfile: pytest.ini
collected 94 items

tests/test_api.py ..............................................         [ 48%]
tests/test_app.py ......................                                  [ 72%]
tests/test_health.py ..........................                          [100%]

- generated xml file: reports/test-results.xml -

---------- coverage: platform win32, python 3.12.10-final-0 ----------
Name         Stmts   Miss  Cover   Missing
------------------------------------------
app\app.py     162      9    94%   277, 315, 327-328, 335-339
------------------------------------------
TOTAL          162      9    94%

============================== 94 passed in 2.41s ==============================
```
- **Total Tests**: 94 passed (100% success rate).
- **Execution Time**: 2.41 seconds.
- **Statement Coverage**: 94% across all application modules.

---

## Experiment 3: Container Security & Multi-Stage Packaging

### 3.1 Objective
Package the application into an immutable container image following enterprise security hardening practices: multi-stage build, non-root execution, automated health probes, and minimal attack surface.

### 3.2 Security Controls
1. **Multi-Stage Build (`docker/Dockerfile`)**:
   - *Stage 1 (`builder`)*: Compiles wheels and installs dependencies into `/install` using `python:3.12-slim`.
   - *Stage 2 (`runtime`)*: Copies only the pre-built site-packages into a fresh `python:3.12-slim` base, excluding build toolchains, pip caches, and compilers.
2. **Non-Root Execution**:
   - Creates a dedicated non-privileged system user and group (`appuser:1001`, `appgroup:1001`) with no login shell (`/sbin/nologin`).
   - Ensures containers cannot write to root filesystems or access privileged host capabilities.
3. **Container-Native Healthcheck**:
   - Incorporates a native `HEALTHCHECK` directive probing `http://localhost:5000/health` every 30 seconds with 3 retries.
4. **Context Hygiene (`docker/.dockerignore`)**:
   - Excludes `.git`, `.venv`, secrets, tests, coverage files, and unencrypted databases from entering the Docker build context.

---

## Experiment 4: Declarative CI/CD Pipeline Automation

### 4.1 Objective
Construct an enterprise-style Jenkins Declarative Pipeline ([`jenkins/Jenkinsfile`](../jenkins/Jenkinsfile)) automating build, test, inspection, approval, and verification stages.

### 4.2 Pipeline Stages & Failure Handling
```
1. Checkout
   └── SCM checkout with branch and commit metadata logging
2. Environment Validation
   └── Checks python3, pip3, docker, and git availability
3. Dependency Installation
   └── Installs application and testing requirements
4. Automated Testing
   └── Executes pytest with JUnit XML and Cobertura coverage flags
5. Test Report Publishing
   └── Publishes reports/test-results.xml to Jenkins dashboard
6. Docker Image Build
   └── Builds image tagged with ${BUILD_NUMBER}-${GIT_COMMIT}
7. Image Validation
   └── Inspects image metadata and verifies non-root user (1001:appuser)
8. Deployment Approval
   └── Interactive manual confirmation gate on branch 'main' (15 min timeout)
9. Deployment Verification
   └── Invokes automated health probes against the deployment
```
- **Failure Resilience**: `post` block captures build state (`success`, `failure`, `unstable`), emits contextual alerts, and guarantees workspace hygiene via `cleanWs`.
- **Zero-Secret Compliance**: No tokens or passwords are hardcoded; all secrets are bound dynamically via the Jenkins Credentials Store.

---

## Experiment 5: Kubernetes Blue-Green Deployment

### 5.1 Objective
Implement a zero-downtime Blue-Green deployment architecture with private candidate validation and sub-second traffic rollback.

### 5.2 Implementation Details
- **Blue Fleet**: [`kubernetes/blue-green/blue-deployment.yaml`](../kubernetes/blue-green/blue-deployment.yaml) runs version 1.0.0 with 3 replicas labeled `slot: blue`.
- **Green Fleet**: [`kubernetes/blue-green/green-deployment.yaml`](../kubernetes/blue-green/green-deployment.yaml) runs candidate version 2.0.0 with 3 replicas labeled `slot: green`.
- **Routing Switchboard**: [`kubernetes/blue-green/service.yaml`](../kubernetes/blue-green/service.yaml) defines:
  - `taskflow-service`: Production ClusterIP service matching `slot: blue`.
  - `taskflow-preview-service`: Staging preview service matching `slot: green`.
- **Automation Scripts**:
  - `scripts/deploy-blue.sh`: Deploys baseline fleet and aligns production service.
  - `scripts/deploy-green.sh`: Deploys Green fleet, verifies `/health` and `/ready` probes on preview endpoints, and presents a manual confirmation gate before executing the cutover.
  - `scripts/rollback-blue-green.sh`: Instantly patches the Service selector back to `slot: blue` in under 1 second.

### 5.3 Trade-Off Analysis
- **Advantages**: Truly zero downtime; eliminates risk of version skew during cutover; instant rollback mechanism.
- **Disadvantages**: Doubles resource consumption (+100% CPU/memory overhead) while both slots are running. Database schema changes must remain backward-compatible across versions.

---

## Experiment 6: Kubernetes Canary Deployment

### 6.1 Objective
Implement a progressive canary deployment strategy that minimizes blast radius by exposing only a small fraction of traffic to candidate releases before fleet-wide rollout.

### 6.2 Traffic Mechanics & Technical Nuance
In native Kubernetes (without an Ingress Controller or Service Mesh like Istio), traffic across pods behind a common Service is distributed via kube-proxy iptables/IPVS rules.
- **Stable Deployment**: [`kubernetes/canary/stable-deployment.yaml`](../kubernetes/canary/stable-deployment.yaml) (9 replicas, v1.0.0).
- **Canary Deployment**: [`kubernetes/canary/canary-deployment.yaml`](../kubernetes/canary/canary-deployment.yaml) (1 replica, v2.0.0).
- **Shared Service**: [`kubernetes/canary/service.yaml`](../kubernetes/canary/service.yaml) matches only `app: taskflow`, blending both deployments into a 10-pod pool (~90% stable, ~10% canary).

> [!IMPORTANT]
> **Engineering Note**: Kubernetes replica ratios only **approximate** traffic distribution. Packet distribution is stochastic. Exact percentage splitting or header-based routing requires an Ingress controller (e.g. NGINX canary annotations) or Service Mesh.

### 6.3 Progressive Promotion Workflow
Implemented in [`scripts/promote-canary.sh`](../scripts/promote-canary.sh):
1. **Stage 1 (10% Exposure)**: Canary=1, Stable=9. Automated health probe verification.
2. **Stage 2 (30% Exposure)**: Canary=3, Stable=7. Re-verify health.
3. **Stage 3 (50% Exposure)**: Canary=5, Stable=5. Re-verify health.
4. **Stage 4 (Final Promotion)**: Stable image upgraded to v2.0.0 with 10 replicas; Canary scaled to 0 replicas.
5. **Rollback Safety**: [`scripts/rollback-canary.sh`](../scripts/rollback-canary.sh) immediately scales Canary to 0 replicas if errors occur, protecting 100% of users.

---

## Experiment 7: GitOps Continuous Delivery with Argo CD

### 7.1 Objective
Implement declarative continuous delivery where a Git repository is the single source of truth for desired cluster state, continuously reconciled by an in-cluster Argo CD operator.

### 7.2 Implementation & Directory Structure
- [`gitops/application.yaml`](../gitops/application.yaml): Argo CD Application Custom Resource watching `gitops/environments/production`.
- **Environment Overlays**:
  - `gitops/environments/development/`: 1 replica, minimal memory (64Mi), tag `dev-latest`.
  - `gitops/environments/staging/`: 2 replicas, moderate resources, tag `staging-rc`.
  - `gitops/environments/production/`: 3 replicas, full production resources, tag `1.0.0`.
- **Self-Healing Demonstration**:
  When an engineer manually alters the cluster state (e.g. `kubectl scale deployment --replicas=1`), Argo CD detects drift against Git within its reconciliation loop and automatically forces the cluster back to the Git-declared state (3 replicas).
- **Git-Based Rollback**:
  Rollbacks are executed via `git revert <commit-sha>`. Pushing the revert triggers Argo CD to converge the cluster to the prior configuration, maintaining a complete cryptographic audit trail.

---

## Experiment 8: Kubernetes Secret Management & Cryptographic Hygiene

### 8.1 Objective
Establish enterprise secret hygiene, demonstrate the difference between serialization and encryption, and model external secret integration.

### 8.2 Security Principles & Architecture
1. **Base64 Is NOT Encryption**:
   Base64 is an encoding format designed for safe text transport. Anyone with read access to a Secret can decode it immediately (`echo <secret> | base64 -d`).
2. **Enterprise Secret Controls**:
   - **Encryption at Rest**: Must be enabled in Kubernetes API server using `EncryptionConfiguration` with a Key Management Service (KMS).
   - **RBAC Hardening**: Workload service accounts are granted least-privilege access to specific secret names via `Role` bindings (disallowing wildcard secret listing).
   - **Git Hygiene**: Strict `.gitignore` rules prevent credentials (`*.key`, `*.pem`, `*.db`, `secrets.yaml`) from being committed. Only sanitized templates ([`kubernetes/secrets/secret-example.yaml`](../kubernetes/secrets/secret-example.yaml)) are versioned.
3. **External Secrets Integration (Vault / ESO)**:
   Documented the architecture for synchronizing secrets dynamically from HashiCorp Vault into Kubernetes via the External Secrets Operator (ESO), eliminating static secrets entirely.

---

## Experiment 9: Disaster Recovery, Cryptographic Verification & Resilience

### 9.1 Objective
Implement an automated disaster recovery engine for SQLite data with point-in-time recovery, cryptographic validation, pre-restore safety copies, and defined operational metrics.

### 9.2 Disaster Recovery Metrics
- **Recovery Point Objective (RPO)**: **< 1 hour** (hourly hot backups).
- **Recovery Time Objective (RTO)**: **< 15 minutes** (database restoration); **< 1 second** (traffic rollback).

### 9.3 Empirical Verification of Backup & Restore Suite
The automated scripts were tested live:
1. **Automated Backup ([`disaster-recovery/backup.sh`](../disaster-recovery/backup.sh))**:
   - Leveraged SQLite's atomic online backup API.
   - Verified backup internal integrity using `PRAGMA integrity_check`.
   - Computed cryptographic SHA-256 digest (`.sha256`) for tamper detection.
   - Applied a rolling 7-day retention policy.
2. **Safe Restoration ([`disaster-recovery/restore.sh`](../disaster-recovery/restore.sh))**:
   - Verified SHA-256 checksum against recorded digest.
   - Tested internal integrity before touching target destination.
   - **Pre-restore Safety Snapshot**: Automatically created `<db>.pre-restore-<timestamp>.bak` before restoration to guarantee zero accidental data loss.
   - Executed restore and verified queryability (`SELECT COUNT(*) FROM tasks`).

### 9.4 Verification Execution Output
```text
==========================================================
 [Disaster Recovery] Database Restore Procedure
 Target DB : app/taskflow.db
==========================================================
[1/5] Using backup file: disaster-recovery/backups/taskflow_backup_20261119_154241Z.db
[2/5] Verifying backup checksum and internal integrity...
Verifying SHA-256 checksum...
Checksum verified OK.
[+] Backup integrity verified.
[3/5] Existing database detected. Creating safety snapshot at:
      app/taskflow.db.pre-restore-20261119_155101.bak
[4/5] Restoring database file...
[5/5] Running post-restore verification query...
[+] Database successfully verified. Current task count: 1
==========================================================
 [SUCCESS] Database Restore Complete!
==========================================================
```

---

## Strategy Comparison & Trade-Off Matrix

| Evaluation Dimension | Blue-Green Deployment | Canary Deployment | GitOps Continuous Delivery |
|:---------------------|:----------------------|:------------------|:---------------------------|
| **Downtime** | **Zero Downtime**: Atomic Service selector cutover. | **Zero Downtime**: Progressive traffic shift across pod pools. | **Zero Downtime**: Declarative rollout management. |
| **Rollback Speed** | **< 1 second**: Revert Service selector to `slot: blue`. | **< 2 seconds**: Scale Canary to `0`, restore Stable to full count. | Dependent on Git commit and sync interval (~30–90s). |
| **Infrastructure Cost** | **High (+100%)**: Requires 2× compute capacity during validation. | **Low (+10%)**: Requires minimal extra replicas. | **Zero**: Uses existing cluster compute. |
| **Blast Radius** | **All-or-Nothing**: 100% of traffic switches at cutover. | **Minimal**: Only ~10% sample exposed initially. | Governed by deployment manifest configuration. |
| **Traffic Precision** | Binary (100% Blue or 100% Green). | Approximate via replica ratios (exact requires Ingress/Mesh). | Declarative; matches workload definition. |
| **Operational Complexity** | Low to Medium: Easy to reason about and script. | Medium to High: Requires metrics analysis and stepped scripts. | Medium: Requires Git branching discipline and Argo CD toolchain. |
| **Best Use Cases** | Monoliths, Financial services, strict zero-downtime cutovers. | High-traffic web applications, microservices. | Multi-environment cloud-native fleets, regulatory audit compliance. |

---

## Conclusion & Key Takeaways

The **Enterprise DevOps Deployment Toolkit (EDDT)** demonstrates that modern software delivery requires an interconnected, defense-in-depth approach spanning code, tests, containers, orchestration, security, and business continuity.

### Key Conclusions:
1. **Automated Testing as a Hard Gate**: 94 pytest cases covering 94% of statements prevent defective code from ever reaching the containerization phase.
2. **Strategy Selection Depends on Architecture**: Blue-Green is optimal for systems requiring instant zero-downtime cutover where double resource cost is acceptable. Canary is essential for large-scale consumer services where blast radius reduction is paramount.
3. **GitOps Enforces Compliance**: Argo CD eliminates human error, secures production clusters by removing the need for external admin credentials in CI, and prevents configuration drift.
4. **Defense-in-Depth Is Mandatory**: Non-root containers, etcd encryption awareness, RBAC, and cryptographically verified disaster recovery routines ensure that production environments remain resilient against both human error and infrastructure failures.
