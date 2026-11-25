# Lab 4: Advanced Deployment Strategies & Enterprise DevOps
## Complete Toolkit README

### Repository Structure
```
Devops4/
├── app/                          # Sample Flask application
│   ├── app.py                    # Application source code
│   ├── Dockerfile                # Multi-stage Docker build
│   └── requirements.txt          # Python dependencies
├── Jenkinsfile                   # Declarative CI/CD pipeline (13 stages)
├── k8s/
│   ├── blue-green/               # Blue-Green deployment manifests
│   │   ├── blue-deployment.yaml
│   │   ├── green-deployment.yaml
│   │   └── service.yaml
│   ├── canary/                   # Canary deployment manifests
│   │   ├── stable-deployment.yaml
│   │   ├── canary-deployment.yaml
│   │   └── service.yaml          # + HPA
│   ├── gitops/                   # GitOps manifests
│   │   ├── argocd-application.yaml
│   │   ├── kustomization.yaml
│   │   └── flux/gotk-sync.yaml
│   ├── secrets/                  # Secret management
│   │   ├── external-secret.yaml  # ESO + Vault
│   │   └── vault-secret.yaml     # Vault Agent Injector
│   └── disaster-recovery/        # DR resources
│       ├── backup-cronjob.yaml
│       └── pvc.yaml
├── scripts/                      # Automation scripts
│   ├── blue-green-switch.sh
│   ├── canary-promote.sh
│   ├── rollback.sh
│   ├── smoke-test.sh
│   └── disaster-recovery.sh
├── tests/
│   ├── unit/test_app.py
│   ├── integration/test_integration.py
│   └── performance/locustfile.py
└── monitoring/
    ├── prometheus-config.yaml
    └── alertmanager-config.yaml
```

### Quick Start

#### Prerequisites
- Kubernetes cluster (Minikube, kind, or cloud)
- kubectl, helm, docker
- Jenkins (or any CI/CD tool)

#### 1. Deploy the Application
```bash
# Create namespace
kubectl create namespace devops-lab

# Apply blue deployment
kubectl apply -f k8s/blue-green/blue-deployment.yaml
kubectl apply -f k8s/blue-green/service.yaml

# Verify
kubectl get pods -n devops-lab
```

#### 2. Run Unit Tests
```bash
pip install -r app/requirements.txt
pytest tests/unit/ -v --cov=app --cov-fail-under=80
```

#### 3. Blue-Green Switch
```bash
# After deploying green
kubectl apply -f k8s/blue-green/green-deployment.yaml
bash scripts/blue-green-switch.sh green devops-lab
```

#### 4. Canary Promotion
```bash
kubectl apply -f k8s/canary/canary-deployment.yaml
bash scripts/canary-promote.sh --namespace devops-lab
```

#### 5. Run Smoke Tests
```bash
bash scripts/smoke-test.sh blue devops-lab
```

### Key Design Decisions
| Decision | Choice | Rationale |
|----------|--------|-----------|
| Secret management | ESO + Vault | Secrets never stored in Git; auto-rotation |
| GitOps tool | Argo CD (+ Flux alternate) | Declarative, drift correction, RBAC |
| Traffic splitting | Replica-count ratio | No service mesh required; simple & reliable |
| DR backup | pg_dump → S3 (encrypted) | Cloud-native, cost-effective, auditable |
| Container registry | GHCR | Free for public; integrated with GitHub Actions |
