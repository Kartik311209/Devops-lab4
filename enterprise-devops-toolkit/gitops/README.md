# GitOps Continuous Delivery with Argo CD

This directory contains the declarative GitOps delivery configurations for **Enterprise TaskFlow**.

---

## 1. GitOps Core Principles

In this architecture, **Git is the Single Source of Truth** for desired cluster state:

```
Developer / PR ──> Git Repo (Main) ──> Argo CD Controller (Watches Repo)
                                                 │
                                     Reconciliation Loop (Diff & Sync)
                                                 ▼
                                     Kubernetes Target Cluster
```

1. **Declarative State**: All Kubernetes workloads are declared in version-controlled manifests (`gitops/environments/`).
2. **Automated Pull Reconciliation**: The cluster pulls changes from Git; external CI pipelines do not require direct cluster credentials.
3. **Drift Detection & Self-Healing**: Out-of-band changes (e.g. manual `kubectl` edits) are detected and reverted automatically.
4. **Git-Driven Rollbacks**: Rollbacks are executed by running `git revert` or checking out previous commits.

---

## 2. Installing Argo CD (Minikube / Local K8s)

```bash
# 1. Create the argocd namespace
kubectl create namespace argocd

# 2. Install official Argo CD manifests
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. Wait for all Argo CD pods to be ready
kubectl wait --for=condition=available deployment -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# 4. Access the Argo CD Web UI via port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Retrieve the initial `admin` password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
```
Login via browser at `https://localhost:8080` (Username: `admin`).

---

## 3. Applying the GitOps Application

```bash
# Apply the root Application resource
kubectl apply -f gitops/application.yaml
```

Inspect synchronization status:
```bash
# Using Argo CD CLI (if installed)
argocd app get taskflow-gitops

# Or via kubectl
kubectl get application taskflow-gitops -n argocd -o yaml
```

---

## 4. Synchronization Modes

### A. Automatic Synchronization (`syncPolicy.automated`)

Configured in [`gitops/application.yaml`](application.yaml):
- **`prune: true`**: Deletes Kubernetes resources that have been deleted from the Git repository.
- **`selfHeal: true`**: Reconciles drift. If an engineer manually changes replica count or image tag via `kubectl`, Argo CD overwrites the manual edit with the version declared in Git.

### B. Manual Synchronization Option

To switch from automatic to manual sync (useful for maintenance windows or high-risk changes), edit `application.yaml`:

```yaml
spec:
  syncPolicy: {} # Omits the automated block
```

Trigger manual sync via CLI:
```bash
argocd app sync taskflow-gitops
```

---

## 5. Self-Healing Demonstration (Evidence of Drift Correction)

You can demonstrate Argo CD self-healing during a laboratory presentation:

```bash
# 1. Deliberately tamper with the live cluster state
kubectl scale deployment prod-taskflow-blue -n eddt-prod --replicas=1

# 2. Observe the deployment
kubectl get deployment prod-taskflow-blue -n eddt-prod
# Replicas briefly drops to 1

# 3. Within seconds, Argo CD detects the difference from Git (which specifies 3 replicas)
# and restores the replica count back to 3 automatically:
kubectl get deployment prod-taskflow-blue -n eddt-prod -w
```

---

## 6. Git-Based Rollback Workflow

Unlike imperative rollbacks (`kubectl rollout undo`), GitOps rollbacks are auditable git commits:

```bash
# 1. Identify bad commit
git log --oneline -5

# 2. Revert the commit in Git
git revert HEAD --no-edit

# 3. Push the reversion
git push origin main

# 4. Argo CD immediately detects the reversion and reconciles the cluster to the previous state.
```
