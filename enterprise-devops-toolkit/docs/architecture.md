# System Architecture: Enterprise DevOps Deployment Toolkit (EDDT)

This document describes the end-to-end architecture, communication flows, component topologies, and deployment models implemented across the EDDT platform.

---

## 1. High-Level System Architecture

```mermaid
flowchart TD
    subgraph DeveloperWorkstation ["Developer Workstation"]
        Dev[Software Engineer] -->|git push| GitRepo[GitHub Repository]
    end

    subgraph ContinuousIntegration ["Continuous Integration (Jenkins)"]
        GitRepo -->|Webhook Trigger| Jenkins[Jenkins CI Pipeline]
        Jenkins -->|Run Tests| Pytest[Pytest Test Suite\n94 Tests, 94% Cov]
        Pytest -->|Publish Results| JUnit[JUnit XML & Cobertura]
        JUnit -->|Build & Tag| DockerBuild[Multi-Stage Docker Build\ntaskflow:tag]
        DockerBuild -->|Scan & Push| Registry[Container Registry\nGHCR / Local Registry]
    end

    subgraph GitOpsDelivery ["Continuous Delivery (Argo CD)"]
        GitRepo -.->|Watches gitops/| ArgoCD[Argo CD Controller]
        ArgoCD -->|Reconciliation Loop| K8sAPI[Kubernetes API Server]
    end

    subgraph KubernetesCluster ["Kubernetes Cluster (Minikube / Production)"]
        K8sAPI --> K8sCore[Kubernetes Engine]

        subgraph Deployments ["Deployment Strategies"]
            K8sCore --> BlueGreen["Blue-Green Strategy\n(taskflow-blue & taskflow-green)"]
            K8sCore --> Canary["Canary Strategy\n(taskflow-stable & taskflow-canary)"]
        end

        subgraph Security ["Secret Management"]
            K8sCore --> K8sSecrets[Kubernetes Secrets\n(taskflow-secret)]
            K8sSecrets -->|Inject via env| AppPods[Application Pods]
        end

        subgraph DisasterRecovery ["Disaster Recovery"]
            K8sCore --> DRBackup[Automated Backup Script\nPRAGMA integrity_check + SHA-256]
            DRBackup --> S3Storage[Persistent Backups Volume]
        end

        subgraph Monitoring ["Observability & Health"]
            AppPods --> HealthProbe["/health (Liveness)"]
            AppPods --> ReadyProbe["/ready (Readiness & DB)"]
            AppPods --> VersionProbe["/version (Metadata)"]
        end
    end
```

---

## 2. Core Architectural Components

### A. Application Layer: Enterprise TaskFlow
- **Framework**: Python 3.12 Flask REST application.
- **Data Persistence**: SQLite database engine running on localized storage volumes with table auto-initialization.
- **Probe Endpoints**:
  - `GET /health`: Liveness probe. Indicates container process vitality.
  - `GET /ready`: Readiness probe. Actively queries SQLite to ensure the database layer is responsive.
  - `GET /version`: Exposes current active version, environment name, and active deployment slot (blue/green/canary).
- **Security Hardening**:
  - Runs strictly as non-root user `appuser` (UID: 1001, GID: 1001).
  - Minimal container footprint using Python slim multi-stage base.

### B. CI Pipeline: Jenkins Declarative Engine
- **Trigger**: SCM change detection / Webhook.
- **Isolation**: Agent steps isolate dependency installation, pytest suite execution, and artifact generation.
- **Quality Gates**: Requires 100% pass rate across unit, API, and probe test suites before container image build is allowed.
- **Manual Gate**: `Deployment Approval` stage pauses execution on `main` branch until an authorized operator verifies pre-deployment artifacts.

### C. GitOps Controller: Argo CD
- **Model**: Pull-based declarative reconciliation.
- **Source of Truth**: Version-controlled Kustomize manifests in `gitops/environments/`.
- **Self-Healing**: Continuously monitors live etcd state against target Git revisions and reverts manual tampering without administrator intervention.

---

## 3. Network Topology & Traffic Routing

### Blue-Green Network Path
```
Client Request ──> Service (taskflow-service) ──> Selector: slot=blue ──> Pods (v1.0.0)
                                            │
               [Operator executes cutover]  └──> Selector: slot=green ──> Pods (v2.0.0)
```

### Canary Network Path
```
Client Request ──> Blended Service (taskflow-canary-shared-service)
                   ├── kube-proxy (~90% traffic) ──> Stable Pods (9 Replicas, v1.0.0)
                   └── kube-proxy (~10% traffic) ──> Canary Pods (1 Replica,  v2.0.0)
```
