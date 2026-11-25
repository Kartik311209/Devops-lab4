#!/usr/bin/env bash
# =============================================================================
# scripts/canary-promote.sh
# Lab 4 – Gradual Canary Promotion
#
# Usage:
#   ./scripts/canary-promote.sh [--auto] [--namespace devops-lab]
#
# Promotion stages (replica-based traffic split):
#   Stage 0: stable=9, canary=1   →  10%
#   Stage 1: stable=7, canary=3   →  30%
#   Stage 2: stable=5, canary=5   →  50%
#   Stage 3: stable=0, canary=10  → 100% (rename canary→stable)
#
# At each stage, Prometheus metrics are queried. If error rate or P99 latency
# exceed thresholds, the script auto-rolls back.
# =============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
NAMESPACE="devops-lab"
AUTO_PROMOTE=false
WAIT_BETWEEN_STAGES=120   # seconds to observe before promoting
PROMETHEUS_URL="http://prometheus.monitoring.svc.cluster.local:9090"
ERROR_THRESHOLD=1.0       # max error rate % before rollback
P99_THRESHOLD_MS=500      # max P99 latency ms before rollback

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto)        AUTO_PROMOTE=true; shift ;;
        --namespace)   NAMESPACE="$2";    shift 2 ;;
        --wait)        WAIT_BETWEEN_STAGES="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Logging ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()      { echo -e "${GREEN}[CANARY]${NC} $*"; }
warn()     { echo -e "${YELLOW}[CANARY]${NC} $*"; }
err()      { echo -e "${RED}[CANARY]${NC} $*" >&2; }
heading()  { echo -e "\n${BLUE}══ $* ══${NC}"; }

# ── Metric helpers ────────────────────────────────────────────────────────────
query_prometheus() {
    local query="$1"
    curl -sf "${PROMETHEUS_URL}/api/v1/query" \
        --data-urlencode "query=${query}" | \
        python3 -c "import sys,json; r=json.load(sys.stdin)['data']['result']; print(r[0]['value'][1] if r else '0')" \
        2>/dev/null || echo "0"
}

get_canary_error_rate() {
    query_prometheus \
        'sum(rate(http_requests_total{job="sample-app",track="canary",status=~"5.."}[2m])) / sum(rate(http_requests_total{job="sample-app",track="canary"}[2m])) * 100'
}

get_canary_p99_latency() {
    query_prometheus \
        'histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{job="sample-app",track="canary"}[2m])) by (le)) * 1000'
}

# ── Rollback function ─────────────────────────────────────────────────────────
rollback() {
    err "ROLLBACK TRIGGERED: $*"
    warn "Scaling canary to 0 and stable back to 9 replicas…"
    kubectl scale deployment sample-app-canary  -n "${NAMESPACE}" --replicas=0
    kubectl scale deployment sample-app-stable  -n "${NAMESPACE}" --replicas=9
    err "Canary rolled back. Stable serving 100% traffic."
    exit 1
}

# ── Health check at each stage ────────────────────────────────────────────────
check_metrics() {
    local stage="$1"
    log "Checking metrics for stage ${stage}…"

    local error_rate p99
    error_rate=$(get_canary_error_rate)
    p99=$(get_canary_p99_latency)

    log "  Error rate: ${error_rate}% (threshold: ${ERROR_THRESHOLD}%)"
    log "  P99 latency: ${p99}ms (threshold: ${P99_THRESHOLD_MS}ms)"

    if (( $(echo "${error_rate} > ${ERROR_THRESHOLD}" | bc -l) )); then
        rollback "Error rate ${error_rate}% > threshold ${ERROR_THRESHOLD}%"
    fi

    if (( $(echo "${p99} > ${P99_THRESHOLD_MS}" | bc -l) )); then
        rollback "P99 latency ${p99}ms > threshold ${P99_THRESHOLD_MS}ms"
    fi

    log "✓ Metrics healthy at stage ${stage}"
}

# ── Promotion stages ──────────────────────────────────────────────────────────
declare -a STAGES=(
    "stable=7:canary=3:10→30%"
    "stable=5:canary=5:30→50%"
    "stable=2:canary=8:50→80%"
    "stable=0:canary=10:80→100%"
)

heading "Starting Canary Promotion"
log "Namespace : ${NAMESPACE}"
log "Auto      : ${AUTO_PROMOTE}"
log "Wait/stage: ${WAIT_BETWEEN_STAGES}s"
log "Thresholds: error=${ERROR_THRESHOLD}%, P99=${P99_THRESHOLD_MS}ms"

for stage_def in "${STAGES[@]}"; do
    stable_r=$(echo "${stage_def}" | cut -d: -f1 | cut -d= -f2)
    canary_r=$(echo "${stage_def}" | cut -d: -f2 | cut -d= -f2)
    label=$(echo "${stage_def}" | cut -d: -f3)

    heading "Stage: ${label} (stable=${stable_r}, canary=${canary_r})"

    # Scale deployments
    kubectl scale deployment sample-app-stable -n "${NAMESPACE}" --replicas="${stable_r}"
    kubectl scale deployment sample-app-canary -n "${NAMESPACE}" --replicas="${canary_r}"

    # Wait for rollout
    kubectl rollout status deployment/sample-app-canary -n "${NAMESPACE}" --timeout=3m
    [[ "${stable_r}" -gt 0 ]] && \
        kubectl rollout status deployment/sample-app-stable -n "${NAMESPACE}" --timeout=3m

    log "Observing for ${WAIT_BETWEEN_STAGES}s…"
    sleep "${WAIT_BETWEEN_STAGES}"

    # Check metrics
    check_metrics "${label}"

    # Manual gate if not auto
    if [[ "${AUTO_PROMOTE}" == "false" && "${stable_r}" -gt 0 ]]; then
        read -r -p "Proceed to next stage? [y/N] " confirm
        [[ "${confirm}" =~ ^[Yy]$ ]] || rollback "Manual gate: user declined promotion"
    fi
done

# ── Final promotion: rename canary → stable ───────────────────────────────────
heading "Final Promotion: Canary is now 100% — completing promotion"

# Update the stable deployment image to match canary
CANARY_IMAGE=$(kubectl get deployment sample-app-canary -n "${NAMESPACE}" \
    -o jsonpath='{.spec.template.spec.containers[0].image}')

kubectl set image deployment/sample-app-stable \
    sample-app="${CANARY_IMAGE}" \
    -n "${NAMESPACE}"

kubectl scale deployment sample-app-stable -n "${NAMESPACE}" --replicas=9
kubectl rollout status deployment/sample-app-stable -n "${NAMESPACE}" --timeout=5m

kubectl scale deployment sample-app-canary -n "${NAMESPACE}" --replicas=0

log "════════════════════════════════════════"
log "Canary PROMOTION COMPLETE"
log "  New stable image: ${CANARY_IMAGE}"
log "  Stable replicas : 9"
log "  Canary replicas : 0 (idle)"
log "════════════════════════════════════════"
