# Evidence and Screenshots Guide

This directory is designated for laboratory execution evidence, command outputs, and screenshots for academic review.

---

## Required Laboratory Evidence Checklist

| Screenshot ID | Phase / Experiment | Description | How to Capture |
|:--------------|:-------------------|:------------|:---------------|
| `screenshot-01-dashboard.png` | Phase 1: App | Web dashboard running at `http://localhost:5000` showing task statistics and active task cards. | Open browser at `http://localhost:5000` |
| `screenshot-02-probes.png` | Phase 1: Probes | Terminal showing `curl /health`, `curl /ready`, and `curl /version` JSON output. | Run `curl -s http://localhost:5000/{health,ready,version}` |
| `screenshot-03-pytest-results.png` | Phase 2: Testing | Pytest terminal output showing `94 passed` and 94% statement coverage table. | Run `pytest -v --cov=app` |
| `screenshot-04-docker-build.png` | Phase 2: Docker | Terminal output of `docker build` showing multi-stage steps and non-root user `1001`. | Run `docker inspect taskflow:1.0.0 --format '{{.Config.User}}'` |
| `screenshot-05-jenkins-pipeline.png` | Phase 3: Jenkins | Jenkins UI showing all 9 pipeline stages marked green with stage execution times. | Open Jenkins project dashboard |
| `screenshot-06-blue-green-deploy.png` | Phase 4: Blue-Green | Terminal output of `./scripts/deploy-blue.sh` and `./scripts/deploy-green.sh`. | Run deployment scripts |
| `screenshot-07-blue-green-switch.png` | Phase 4: Switch | Output showing service selector cutover from `slot: blue` to `slot: green`. | Run `kubectl get svc taskflow-service -o jsonpath='{.spec.selector}'` |
| `screenshot-08-blue-green-rollback.png`| Phase 4: Rollback | Sub-second rollback execution using `./scripts/rollback-blue-green.sh`. | Run rollback script |
| `screenshot-09-canary-deploy.png` | Phase 5: Canary | Kubernetes pods showing 9 stable pods and 1 canary pod (`kubectl get pods`). | Run `./scripts/deploy-canary.sh` |
| `screenshot-10-canary-promotion.png` | Phase 5: Promotion| Interactive multi-stage promotion prompts in terminal from `./scripts/promote-canary.sh`. | Run promotion script |
| `screenshot-11-argocd-dashboard.png` | Phase 6: GitOps | Argo CD Web UI showing `taskflow-gitops` in `Synced` and `Healthy` state. | Open `https://localhost:8080` in browser |
| `screenshot-12-argocd-selfheal.png` | Phase 6: Drift | Demonstration of Argo CD detecting manual pod scale and self-healing to Git state. | Run `kubectl scale` then observe Argo CD revert |
| `screenshot-13-k8s-secret.png` | Phase 7: Secrets | Terminal showing sanitized Kubernetes secret creation and environment injection. | Run `kubectl describe secret taskflow-secret` |
| `screenshot-14-dr-backup.png` | Phase 8: Backup | Terminal showing `./disaster-recovery/backup.sh` with `PRAGMA integrity_check: ok` and SHA-256 hash. | Run backup script |
| `screenshot-15-dr-restore.png` | Phase 8: Restore | Terminal showing safe pre-restore snapshot generation and verified post-restore task count. | Run restore script |
| `screenshot-16-monitoring.png` | Phase 9: Monitoring| Output of `./monitoring/health-check.sh` and `./monitoring/deployment-status.sh`. | Run monitoring scripts |

---

*Place captured image files (`.png` / `.jpg`) directly in this directory for laboratory report compilation.*
