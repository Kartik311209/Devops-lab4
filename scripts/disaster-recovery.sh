#!/usr/bin/env bash
# =============================================================================
# scripts/disaster-recovery.sh
# Lab 4 – Disaster Recovery Failover Orchestration
#
# Implements a full DR failover runbook:
#   1. Detect failure (health checks)
#   2. Notify on-call team
#   3. Trigger database restore from latest backup
#   4. Switch DNS to DR region
#   5. Validate DR environment
#   6. Update status page
#
# RTO target: < 15 minutes
# RPO target: < 1 hour (last S3 backup)
#
# Usage:
#   ./scripts/disaster-recovery.sh --env production --region ap-south-1
# =============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
PRIMARY_REGION="${PRIMARY_REGION:-ap-south-1}"
DR_REGION="${DR_REGION:-ap-southeast-1}"
NAMESPACE="${NAMESPACE:-devops-lab}"
S3_BUCKET="${S3_BUCKET:-devops-lab-dr-backups}"
DB_HOST_DR="${DB_HOST_DR:-postgres-dr.devops-lab.svc.cluster.local}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
DNS_ZONE_ID="${DNS_ZONE_ID:-Z0123456789EXAMPLE}"
RECORD_NAME="${RECORD_NAME:-app.example.com}"
DR_ALB_DNS="${DR_ALB_DNS:-dr-alb.ap-southeast-1.elb.amazonaws.com}"
LOG_FILE="/tmp/dr-failover-$(date +%Y%m%d_%H%M%S).log"

# ── Logging ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()      { local msg; msg="[$(date -u +%H:%M:%S)] $*"; echo -e "${GREEN}${msg}${NC}" | tee -a "${LOG_FILE}"; }
warn()     { local msg; msg="[$(date -u +%H:%M:%S)] WARN: $*"; echo -e "${YELLOW}${msg}${NC}" | tee -a "${LOG_FILE}"; }
err()      { local msg; msg="[$(date -u +%H:%M:%S)] ERROR: $*"; echo -e "${RED}${msg}${NC}" | tee -a "${LOG_FILE}" >&2; }
heading()  { echo -e "\n${BLUE}══════ $* ══════${NC}" | tee -a "${LOG_FILE}"; }
FAILOVER_START=$(date +%s)

notify_slack() {
    local msg="$1"
    if [[ -n "${SLACK_WEBHOOK}" ]]; then
        curl -sf -X POST "${SLACK_WEBHOOK}" \
            -H "Content-type: application/json" \
            --data "{\"text\":\"🚨 *DR FAILOVER*: ${msg}\"}" || true
    fi
    log "NOTIFY: ${msg}"
}

# ── Step 1: Verify primary region is actually down ────────────────────────────
heading "Step 1 — Primary Region Health Check"
PRIMARY_DOWN=false

for i in 1 2 3; do
    if ! curl -sf --max-time 5 "http://${RECORD_NAME}/health" > /dev/null 2>&1; then
        warn "Primary health check failed (attempt ${i}/3)"
        sleep 10
    else
        log "Primary region appears healthy. DR failover not needed."
        exit 0
    fi
done
PRIMARY_DOWN=true
log "✓ Confirmed: primary region is down. Initiating failover…"
notify_slack "Primary region (${PRIMARY_REGION}) confirmed DOWN. Failover initiated. RTO target: 15 min."

# ── Step 2: Find latest S3 backup ────────────────────────────────────────────
heading "Step 2 — Locate Latest Database Backup"
LATEST_BACKUP=$(aws s3 ls "s3://${S3_BUCKET}/postgres-backups/" \
    --region "${DR_REGION}" | \
    sort | tail -1 | awk '{print $4}') || err "Could not list S3 backups!"

[[ -n "${LATEST_BACKUP}" ]] || err "No backups found in s3://${S3_BUCKET}/postgres-backups/"
log "Latest backup: ${LATEST_BACKUP}"

BACKUP_AGE_MIN=$(( ( $(date +%s) - $(date -d "$(echo "${LATEST_BACKUP}" | grep -oP '\d{8}_\d{6}'| sed 's/_/ /' | sed 's/\(....\)\(..\)\(..\)/\1-\2-\3/')" +%s) ) / 60 ))
log "Backup age: ~${BACKUP_AGE_MIN} minutes"

if [[ "${BACKUP_AGE_MIN}" -gt 70 ]]; then
    warn "Backup older than 70 min — RPO of 1h may be breached!"
    notify_slack "WARNING: Latest backup is ${BACKUP_AGE_MIN} min old. RPO may be breached."
fi

# ── Step 3: Restore database in DR region ────────────────────────────────────
heading "Step 3 — Database Restore in DR Region"
log "Downloading backup from S3…"
aws s3 cp "s3://${S3_BUCKET}/postgres-backups/${LATEST_BACKUP}" \
    /tmp/restore.dump \
    --region "${DR_REGION}" \
    --sse aws:kms

log "Restoring database…"
pg_restore \
    --host="${DB_HOST_DR}" \
    --port=5432 \
    --username=appuser \
    --dbname=sampledb \
    --clean \
    --if-exists \
    --no-privileges \
    --no-owner \
    --verbose \
    /tmp/restore.dump 2>&1 | tee -a "${LOG_FILE}"

rm -f /tmp/restore.dump
log "✓ Database restored from ${LATEST_BACKUP}"
notify_slack "Database restored in DR region from backup (age: ${BACKUP_AGE_MIN} min)."

# ── Step 4: Scale up DR application pods ─────────────────────────────────────
heading "Step 4 — Scale Up DR Application"
log "Scaling DR deployments to production replica count…"

# Switch kubectl context to DR cluster
kubectl config use-context "dr-cluster-${DR_REGION}"

kubectl scale deployment sample-app-blue \
    -n "${NAMESPACE}" --replicas=3

kubectl rollout status deployment/sample-app-blue \
    -n "${NAMESPACE}" --timeout=5m

log "✓ DR application pods are running"

# ── Step 5: DNS Failover ──────────────────────────────────────────────────────
heading "Step 5 — DNS Failover (Route 53)"
log "Updating DNS record to point to DR ALB…"

aws route53 change-resource-record-sets \
    --hosted-zone-id "${DNS_ZONE_ID}" \
    --region "${DR_REGION}" \
    --change-batch "{
        \"Changes\": [{
            \"Action\": \"UPSERT\",
            \"ResourceRecordSet\": {
                \"Name\": \"${RECORD_NAME}\",
                \"Type\": \"CNAME\",
                \"TTL\": 60,
                \"ResourceRecords\": [{\"Value\": \"${DR_ALB_DNS}\"}]
            }
        }]
    }"

log "DNS TTL is 60s. Waiting 70s for propagation…"
sleep 70
log "✓ DNS updated to DR ALB (${DR_ALB_DNS})"
notify_slack "DNS updated to DR region (${DR_REGION}). App should be reachable in ~1 min."

# ── Step 6: Validate DR environment ──────────────────────────────────────────
heading "Step 6 — DR Validation"
bash "$(dirname "${BASH_SOURCE[0]}")/smoke-test.sh" blue "${NAMESPACE}" || {
    err "DR smoke tests FAILED! Manual intervention required."
    notify_slack "🔴 DR smoke tests FAILED. Manual intervention required!"
    exit 1
}

ELAPSED=$(( $(date +%s) - FAILOVER_START ))
ELAPSED_MIN=$(( ELAPSED / 60 ))

log "✓ DR validation passed!"
notify_slack "✅ DR failover COMPLETE in ${ELAPSED_MIN} min. App validated in DR region (${DR_REGION}). Backup age: ${BACKUP_AGE_MIN} min."

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
log "════════════════════════════════════════════"
log "DISASTER RECOVERY FAILOVER COMPLETE"
log "  Total elapsed   : ${ELAPSED_MIN} min ${ELAPSED}s"
log "  DR region       : ${DR_REGION}"
log "  Backup used     : ${LATEST_BACKUP}"
log "  Backup age      : ${BACKUP_AGE_MIN} min"
log "  RTO achieved    : ${ELAPSED_MIN} min (target: 15 min)"
log "  Log file        : ${LOG_FILE}"
log "════════════════════════════════════════════"

[[ "${ELAPSED_MIN}" -le 15 ]] || warn "RTO target of 15 min was NOT met (${ELAPSED_MIN} min)"
