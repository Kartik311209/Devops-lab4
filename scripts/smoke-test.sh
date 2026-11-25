#!/usr/bin/env bash
# =============================================================================
# scripts/smoke-test.sh
# Lab 4 – Post-Deployment Smoke Tests
#
# Usage:
#   ./scripts/smoke-test.sh <color> <namespace> [--quiet]
#   ./scripts/smoke-test.sh green devops-lab
#
# Checks:
#   1. Service IP resolves
#   2. /health returns 200 with status=healthy
#   3. /ready returns 200
#   4. /version returns correct color
#   5. /api/greet returns 200 with a message
#   6. Response time < 2 s for all endpoints
#   7. No 5xx errors in a burst of 10 requests
# =============================================================================

set -euo pipefail

TARGET_COLOR="${1:-green}"
NAMESPACE="${2:-devops-lab}"
QUIET="${3:-}"
SERVICE_NAME="sample-app-service"
TIMEOUT=10          # curl timeout seconds
MAX_RESPONSE_MS=2000
BURST_REQUESTS=10

# ── Logging ───────────────────────────────────────────────────────────────────
pass() { [[ "${QUIET}" != "--quiet" ]] && echo -e "  \033[32m✓\033[0m $*" || true; }
fail() { echo -e "  \033[31m✗\033[0m $*" >&2; FAILED=$((FAILED + 1)); }
heading() { [[ "${QUIET}" != "--quiet" ]] && echo -e "\n\033[34m── $* ──\033[0m" || true; }

FAILED=0

# ── Resolve service IP ────────────────────────────────────────────────────────
heading "Resolving Service IP"
SERVICE_IP=$(kubectl get svc "${SERVICE_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) || \
SERVICE_IP=$(kubectl get svc "${SERVICE_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.clusterIP}')

[[ -n "${SERVICE_IP}" ]] || { fail "Could not resolve service IP"; exit 1; }
pass "Service IP: ${SERVICE_IP}"
BASE_URL="http://${SERVICE_IP}"

# ── Helper: HTTP check ────────────────────────────────────────────────────────
http_check() {
    local name="$1" url="$2" expected_code="$3" jq_check="${4:-}"

    local start_ms response_code body elapsed_ms
    start_ms=$(date +%s%3N)
    body=$(curl -sf --max-time "${TIMEOUT}" -w "\n%{http_code}" "${url}" 2>/dev/null) || body="000"
    response_code=$(echo "${body}" | tail -1)
    body=$(echo "${body}" | head -n -1)
    elapsed_ms=$(( $(date +%s%3N) - start_ms ))

    if [[ "${response_code}" != "${expected_code}" ]]; then
        fail "${name}: expected HTTP ${expected_code}, got ${response_code}"
        return
    fi

    if [[ "${elapsed_ms}" -gt "${MAX_RESPONSE_MS}" ]]; then
        fail "${name}: response time ${elapsed_ms}ms > ${MAX_RESPONSE_MS}ms"
        return
    fi

    if [[ -n "${jq_check}" ]]; then
        if ! echo "${body}" | python3 -c "${jq_check}" 2>/dev/null; then
            fail "${name}: JSON assertion failed"
            return
        fi
    fi

    pass "${name}: HTTP ${response_code} in ${elapsed_ms}ms"
}

# ── Test 1: Health ────────────────────────────────────────────────────────────
heading "Health Check"
http_check "Health endpoint" "${BASE_URL}/health" "200" \
    "import sys,json; d=json.load(sys.stdin); assert d['status']=='healthy'"

# ── Test 2: Readiness ────────────────────────────────────────────────────────
heading "Readiness Check"
http_check "Readiness endpoint" "${BASE_URL}/ready" "200" \
    "import sys,json; d=json.load(sys.stdin); assert 'ready' in d"

# ── Test 3: Version / Color verification ─────────────────────────────────────
heading "Version / Color Check"
http_check "Version endpoint" "${BASE_URL}/version" "200" \
    "import sys,json; d=json.load(sys.stdin); assert d.get('color')=='${TARGET_COLOR}', f'Expected ${TARGET_COLOR}, got {d.get(\"color\")}'"

# ── Test 4: API greet ─────────────────────────────────────────────────────────
heading "API Greet"
http_check "Greet (default)" "${BASE_URL}/api/greet" "200" \
    "import sys,json; d=json.load(sys.stdin); assert 'message' in d"
http_check "Greet (custom name)" "${BASE_URL}/api/greet?name=SmokeTest" "200" \
    "import sys,json; d=json.load(sys.stdin); assert 'SmokeTest' in d['message']"

# ── Test 5: Error handling ────────────────────────────────────────────────────
heading "Error Handling"
http_check "404 handling" "${BASE_URL}/nonexistent-route" "404" ""

# ── Test 6: Burst test – no 5xx under light load ─────────────────────────────
heading "Burst Test (${BURST_REQUESTS} requests)"
ERROR_COUNT=0
for i in $(seq 1 "${BURST_REQUESTS}"); do
    CODE=$(curl -so /dev/null -w "%{http_code}" --max-time 5 "${BASE_URL}/health")
    [[ "${CODE}" =~ ^5 ]] && ERROR_COUNT=$((ERROR_COUNT + 1))
done

if [[ "${ERROR_COUNT}" -eq 0 ]]; then
    pass "Burst test: 0/${BURST_REQUESTS} requests returned 5xx"
else
    fail "Burst test: ${ERROR_COUNT}/${BURST_REQUESTS} requests returned 5xx"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
if [[ "${FAILED}" -eq 0 ]]; then
    echo -e "\033[32m✅ All smoke tests PASSED for '${TARGET_COLOR}'\033[0m"
    exit 0
else
    echo -e "\033[31m❌ ${FAILED} smoke test(s) FAILED for '${TARGET_COLOR}'\033[0m"
    exit 1
fi
