#!/usr/bin/env bash
# =============================================================================
# scripts/rollback.sh
# Lab 4 – Unified Rollback Script
#
# Supports rollback for:
#   - Blue-Green  : switch service selector back to previous color
#   - Canary      : scale canary to 0, restore stable replicas
#   - Kubernetes  : kubectl rollout undo (standard rolling update)
#
# Usage:
#   ./scripts/rollback.sh --strategy blue-green --color blue  --ns devops-lab
#   ./scripts/rollback.sh --strategy canary                   --ns devops-lab
#   ./scripts/rollback.sh --strategy rolling   --deploy myapp --ns devops-lab
# =============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
STRATEGY="blue-green"
COLOR="blue"
NAMESPACE="devops-lab"
DEPLOYMENT="sample-app"
REASON="Manual rollback"

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --strategy)   STRATEGY="$2";    shift 2 ;;
        --color)      COLOR="$2";       shift 2 ;;
        --ns)         NAMESPACE="$2";   shift 2 ;;
        --deploy)     DEPLOYMENT="$2";  shift 2 ;;
        --reason)     REASON="$2";      shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Logging ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[ROLLBACK]${NC} $*"; }
warn() { echo -e "${YELLOW}[ROLLBACK]${NC} $*"; }
err()  { echo -e "${RED}[ROLLBACK]${NC} $*" >&2; exit 1; }

ROLLBACK_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
log "════════════════════════════════════════"
log "ROLLBACK INITIATED"
log "  Strategy  : ${STRATEGY}"
log "  Namespace : ${NAMESPACE}"
log "  Reason    : ${REASON}"
log "  Time      : ${ROLLBACK_TIME}"
log "════════════════════════════════════════"

# ── Strategy: Blue-Green ──────────────────────────────────────────────────────
rollback_blue_green() {
    log "Reverting service selector to color=${COLOR}…"

    kubectl patch service sample-app-service \
        -n "${NAMESPACE}" \
        --type=json \
        -p "[
          {\"op\": \"replace\", \"path\": \"/spec/selector/color\", \"value\": \"${COLOR}\"},
          {\"op\": \"add\", \"path\": \"/metadata/annotations/deployment.lab~1rollback-time\", \"value\": \"${ROLLBACK_TIME}\"},
          {\"op\": \"add\", \"path\": \"/metadata/annotations/deployment.lab~1rollback-reason\", \"value\": \"${REASON}\"}
        ]"

    log "✓ Service selector reverted to ${COLOR}"

    # Verify
    sleep 2
    ACTIVE=$(kubectl get svc sample-app-service -n "${NAMESPACE}" \
        -o jsonpath='{.spec.selector.color}')
    [[ "${ACTIVE}" == "${COLOR}" ]] || err "Rollback verification failed! Active color: ${ACTIVE}"
    log "✓ Verified: traffic now flowing to ${COLOR}"
}

# ── Strategy: Canary ──────────────────────────────────────────────────────────
rollback_canary() {
    log "Scaling canary to 0 and restoring stable to 9 replicas…"

    kubectl scale deployment sample-app-canary \
        -n "${NAMESPACE}" --replicas=0

    kubectl scale deployment sample-app-stable \
        -n "${NAMESPACE}" --replicas=9

    kubectl rollout status deployment/sample-app-stable \
        -n "${NAMESPACE}" --timeout=5m

    log "✓ Canary rolled back. Stable serving 100% traffic."
}

# ── Strategy: Rolling (kubectl rollout undo) ──────────────────────────────────
rollback_rolling() {
    log "Executing: kubectl rollout undo deployment/${DEPLOYMENT} -n ${NAMESPACE}"

    kubectl rollout undo deployment/"${DEPLOYMENT}" -n "${NAMESPACE}"
    kubectl rollout status deployment/"${DEPLOYMENT}" -n "${NAMESPACE}" --timeout=5m

    NEW_IMAGE=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.template.spec.containers[0].image}')
    log "✓ Rolled back. Active image: ${NEW_IMAGE}"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "${STRATEGY}" in
    blue-green) rollback_blue_green ;;
    canary)     rollback_canary     ;;
    rolling)    rollback_rolling    ;;
    *) err "Unknown strategy '${STRATEGY}'. Use: blue-green | canary | rolling" ;;
esac

log "════════════════════════════════════════"
log "ROLLBACK COMPLETE"
log "  Time: ${ROLLBACK_TIME}"
log "════════════════════════════════════════"

# Record rollback event in Kubernetes Events
kubectl create event \
    --namespace="${NAMESPACE}" \
    --field-selector="type=Warning" \
    "DevOps-Lab4-Rollback-${ROLLBACK_TIME}" 2>/dev/null || true
