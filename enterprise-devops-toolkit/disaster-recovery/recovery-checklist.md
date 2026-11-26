# Disaster Recovery Incident Response Checklist

Use this checklist during an active production outage or recovery drill.

---

## Phase 1: Incident Triage (Minutes 0 – 3)

- [ ] **Acknowledge Alert**: Check Prometheus / Alertmanager or Slack notification.
- [ ] **Assess Blast Radius**:
  ```bash
  # Check overall pod status
  kubectl get pods -n eddt-prod -o wide
  # Check service endpoints
  kubectl get endpoints -n eddt-prod
  ```
- [ ] **Check Application Probes**:
  ```bash
  curl -I http://<service-ip>/health
  curl -I http://<service-ip>/ready
  ```
- [ ] **Inspect Recent Logs**:
  ```bash
  kubectl logs -l app=taskflow -n eddt-prod --tail=100
  ```

---

## Phase 2: Containment & Mitigation (Minutes 3 – 8)

### If Failure is Caused by Recent Deployment:
- [ ] **Trigger Instant Rollback**:
  ```bash
  ./scripts/rollback-blue-green.sh eddt-prod
  ```
- [ ] **Verify Traffic Resumed on Stable Slot**:
  ```bash
  curl http://<service-ip>/version
  ```

### If Failure is Database Corruption or Missing Data:
- [ ] **Place Service in Maintenance Mode** (or scale replicas to 1 to freeze writes).
- [ ] **Execute Verified Restore**:
  ```bash
  ./disaster-recovery/restore.sh
  ```
- [ ] **Verify Integrity & Record Count**:
  Ensure `/ready` returns `200 OK` and application tables are intact.

---

## Phase 3: Post-Recovery Validation (Minutes 8 – 15)

- [ ] Run automated health check suite:
  ```bash
  ./monitoring/health-check.sh
  ```
- [ ] Verify database write capability (create a test task via POST `/api/tasks`).
- [ ] Verify test task deletion.
- [ ] Confirm Argo CD sync status:
  ```bash
  kubectl get application taskflow-gitops -n argocd
  ```

---

## Phase 4: Post-Mortem & Evidence Collection

- [ ] Archive incident logs:
  ```bash
  mkdir -p reports/incident-$(date +%Y%m%d)
  kubectl logs -l app=taskflow -n eddt-prod > reports/incident-$(date +%Y%m%d)/pod-logs.txt
  ```
- [ ] Record calculated RTO and RPO metrics for report.
- [ ] Document root cause and corrective actions in laboratory post-mortem notes.
