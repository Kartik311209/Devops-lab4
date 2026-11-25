#!/usr/bin/env bash
# =============================================================================
# scripts/blue-green-switch.sh
# Lab 4 – Atomic Blue-Green Traffic Switch
#
# Usage:
#   ./scripts/blue-green-switch.sh <target-color> <namespace>
#   ./scripts/blue-green-switch.sh green devops-lab
#
# What it does:
#   1. Validates that the target deployment is healthy (all pods ready)
#   2. Patches the Service selector to route traffic to the target color
#   3. Annotates the Service with metadata for auditability
#   4. Verifies the switch with a quick HTTP probe
#   5. Optionally scales down the old (now-idle) deployment
# =============================================================================

set -euo pipefail

# ── Parameters ────────────────────────────────────────────────────────────────
TARGET_COLOR="${1:-green}"
NAMESPACE="${2:-devops-lab}"
SERVICE_NAME="${3:-sample-app-service}"
SCALE_DOWN_OLD="${4:-false}"   # set to 'true' to scale idle slot to 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colors & logging ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[BG-SWITCH]${NC} $*"; }
warn() { echo -e "${YELLOW}[BG-SWITCH]${NC} $*"; }
err()  { echo -e "${RED}[BG-SWITCH]${NC} $*" >&2; exit 1; }

# ── Validate inputs ───────────────────────────────────────────────────────────
[[ "${TARGET_COLOR}" =~ ^(blue|green)$ ]] || \
    err "Invalid color '${TARGET_COLOR}'. Must be 'blue' or 'green'."

# ── Determine current live color ──────────────────────────────────────────────
CURRENT_COLOR=$(kubectl get svc "${SERVICE_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.selector.color}' 2>/dev/null || echo "unknown")

log "Current live: ${CURRENT_COLOR} → Switching to: ${TARGET_COLOR}"

[[ "${CURRENT_COLOR}" == "${TARGET_COLOR}" ]] && {
    warn "Service already pointing at '${TARGET_COLOR}'. Nothing to do."
    exit 0
}

# ── Step 1: Verify target deployment is healthy ───────────────────────────────
log "Verifying deployment sample-app-${TARGET_COLOR} is ready…"

DEPLOY_STATUS=$(kubectl rollout status \
    deployment/sample-app-"${TARGET_COLOR}" \
    -n "${NAMESPACE}" \
    --timeout=5m 2>&1) || err "Deployment not ready: ${DEPLOY_STATUS}"

READY_PODS=$(kubectl get deployment "sample-app-${TARGET_COLOR}" \
    -n "${NAMESPACE}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
DESIRED_PODS=$(kubectl get deployment "sample-app-${TARGET_COLOR}" \
    -n "${NAMESPACE}" \
    -o jsonpath='{.spec.replicas}')

[[ "${READY_PODS}" == "${DESIRED_PODS}" ]] || \
    err "Only ${READY_PODS}/${DESIRED_PODS} pods ready. Aborting switch."

log "✓ Deployment healthy: ${READY_PODS}/${DESIRED_PODS} pods ready"

# ── Step 2: Atomic selector patch ─────────────────────────────────────────────
log "Patching Service selector to color=${TARGET_COLOR}…"

SWITCH_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

kubectl patch service "${SERVICE_NAME}" \
    -n "${NAMESPACE}" \
    --type=json \
    -p "[
      {\"op\": \"replace\", \"path\": \"/spec/selector/color\", \"value\": \"${TARGET_COLOR}\"},
      {\"op\": \"add\",     \"path\": \"/metadata/annotations/deployment.lab~1active-color\",   \"value\": \"${TARGET_COLOR}\"},
      {\"op\": \"add\",     \"path\": \"/metadata/annotations/deployment.lab~1switch-time\",    \"value\": \"${SWITCH_TIME}\"},
      {\"op\": \"add\",     \"path\": \"/metadata/annotations/deployment.lab~1previous-color\", \"value\": \"${CURRENT_COLOR}\"}
    ]"

log "✓ Service selector patched. Traffic now flowing to ${TARGET_COLOR}."

# ── Step 3: Post-switch HTTP probe ────────────────────────────────────────────
log "Running post-switch HTTP verification…"
sleep 3   # allow endpoints to register

SERVICE_IP=$(kubectl get svc "${SERVICE_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || \
    kubectl get svc "${SERVICE_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.clusterIP}')

HEALTH_STATUS=$(curl -sf --max-time 5 "http://${SERVICE_IP}/health" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null || echo "failed")
ACTIVE_COLOR=$(curl -sf --max-time 5 "http://${SERVICE_IP}/version" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('color','unknown'))" 2>/dev/null || echo "failed")

if [[ "${HEALTH_STATUS}" == "healthy" && "${ACTIVE_COLOR}" == "${TARGET_COLOR}" ]]; then
    log "✓ Post-switch probe: health=${HEALTH_STATUS}, color=${ACTIVE_COLOR}"
else
    err "Post-switch probe FAILED (health=${HEALTH_STATUS}, color=${ACTIVE_COLOR}). Rolling back!"
fi

# ── Step 4: Optionally scale down idle slot ───────────────────────────────────
if [[ "${SCALE_DOWN_OLD}" == "true" ]]; then
    log "Scaling down idle slot (sample-app-${CURRENT_COLOR}) to 0 replicas…"
    kubectl scale deployment "sample-app-${CURRENT_COLOR}" \
        -n "${NAMESPACE}" --replicas=0
    warn "Idle slot scaled to 0. Keep it for rollback for at least 30 min."
else
    warn "Idle slot (sample-app-${CURRENT_COLOR}) kept running for instant rollback."
    warn "To scale it down: kubectl scale deploy sample-app-${CURRENT_COLOR} -n ${NAMESPACE} --replicas=0"
fi

log "════════════════════════════════════════"
log "Blue-Green switch COMPLETE"
log "  Live color : ${TARGET_COLOR}"
log "  Switch time: ${SWITCH_TIME}"
log "  Rollback   : ${SCRIPT_DIR}/rollback.sh ${CURRENT_COLOR} ${NAMESPACE}"
log "════════════════════════════════════════"
