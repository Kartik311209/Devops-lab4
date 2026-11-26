# Disaster Recovery & High Availability Guide

This guide documents the resilience and disaster recovery capabilities of the **Enterprise DevOps Deployment Toolkit (EDDT)**.

---

## 1. Key Recovery Metrics

### Recovery Point Objective (RPO)
- **Target**: **< 1 hour**
- **Definition**: The maximum acceptable age of data that must be recovered from storage after a major disruption.
- **Implementation**: Scheduled hourly SQLite backups using the atomic online backup API in [`disaster-recovery/backup.sh`](../disaster-recovery/backup.sh).

### Recovery Time Objective (RTO)
- **Target**: **< 15 minutes** (for database restore); **< 10 seconds** (for traffic rollback)
- **Definition**: The maximum acceptable duration of service unavailability following an incident.
- **Implementation**:
  - Code/deployment failure: Instant rollback via Service selector switch (`rollback-blue-green.sh`).
  - Storage/data failure: Automated, integrity-verified restore via `restore.sh`.

---

## 2. Failure Scenarios and Runbooks

### Scenario A: Flawed Version Release (Bad Code)
1. **Detection**: Monitoring detects elevated HTTP 500 error rates or failed probe responses.
2. **Mitigation**: Execute instant traffic reversion:
   ```bash
   ./scripts/rollback-blue-green.sh default
   ```
3. **Outcome**: Production traffic shifts back to the Blue baseline within 1 second.

### Scenario B: Database File Corruption
1. **Detection**: Application returns HTTP 503 on `/ready` with `"checks": {"database": "error"}`.
2. **Mitigation**: Execute safe database restoration:
   ```bash
   ./disaster-recovery/restore.sh
   ```
   *Safety feature*: The script automatically creates a `.pre-restore.bak` snapshot of the corrupt file before replacing it, ensuring no forensic evidence is lost.
3. **Verification**: Script runs `PRAGMA integrity_check` and queries the task table count.

---

## 3. Cryptographic Verification & Audit Trails

To prevent silent database corruption from propagating into backups:
1. Every backup execution runs SQLite's native `PRAGMA integrity_check`.
2. A cryptographic SHA-256 digest is generated and saved as `<backup-file>.sha256`.
3. During restore, `restore.sh` computes the hash of the backup file and confirms it matches the recorded SHA-256 checksum before touching the destination database.
