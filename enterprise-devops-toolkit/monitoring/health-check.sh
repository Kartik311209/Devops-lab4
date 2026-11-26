#!/usr/bin/env bash
# =============================================================================
# monitoring/health-check.sh
# Enterprise DevOps Deployment Toolkit (EDDT)
#
# Production Health & Readiness Verification Script
#
# Probes:
#   1. Application HTTP /health (Liveness)
#   2. Application HTTP /ready  (Readiness + DB check)
#   3. Application HTTP /version (Metadata & active deployment slot)
#   4. Response latency measurement
#   5. Kubernetes In-Cluster Pod and Service health (when available)
# =============================================================================

set -euo pipefail

TARGET_URL="${1:-http://localhost:5000}"
NAMESPACE="${2:-default}"
DRY_RUN=false

if [ "${1:-}" = "--dry-run" ] || [ "${2:-}" = "--dry-run" ]; then
  DRY_RUN=true
  TARGET_URL="http://localhost:5000"
fi

echo "=========================================================="
echo " [Monitoring] Executing Health & Readiness Probes"
echo " Target Base URL : ${TARGET_URL}"
echo " K8s Namespace   : ${NAMESPACE}"
echo " Timestamp       : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=========================================================="

FAILED=0

# Helper function to test an HTTP endpoint
probe_endpoint() {
  local name="$1"
  local url="$2"
  local expected_status="$3"

  echo -n "Checking ${name} (${url})... "

  if [ "${DRY_RUN}" = "true" ]; then
    echo "[SKIPPED] Dry-run mode enabled."
    return 0
  fi

  local http_code
  local start_time
  local end_time
  local duration_ms

  start_time=$(date +%s%3N 2>/dev/null || date +%s)
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "${url}" 2>/dev/null || echo "000")
  end_time=$(date +%s%3N 2>/dev/null || date +%s)
  duration_ms=$((end_time - start_time))

  if [ "${http_code}" = "${expected_status}" ]; then
    echo -e "\033[32m[PASS]\033[0m HTTP ${http_code} (${duration_ms}ms)"
  else
    echo -e "\033[31m[FAIL]\033[0m Expected HTTP ${expected_status}, received ${http_code}"
    FAILED=$((FAILED + 1))
  fi
}

# 1. Probing Application Endpoints
echo "--- Application Endpoint Probes ---"
probe_endpoint "Liveness (/health)"   "${TARGET_URL}/health"  "200"
probe_endpoint "Readiness (/ready)"   "${TARGET_URL}/ready"   "200"
probe_endpoint "Version (/version)"   "${TARGET_URL}/version" "200"

# 2. Extract Deployment Metadata if endpoint is reachable
if [ "${DRY_RUN}" != "true" ] && curl -s --connect-timeout 2 "${TARGET_URL}/version" >/dev/null 2>&1; then
  echo ""
  echo "--- Active Deployment Metadata ---"
  curl -s "${TARGET_URL}/version" | python3 -m json.tool 2>/dev/null || curl -s "${TARGET_URL}/version"
  echo ""
fi

# 3. Kubernetes Infrastructure Probing (if kubectl is installed and cluster is reachable)
echo "--- Kubernetes Cluster Status ---"
if command -v kubectl >/dev/null 2>&1 && kubectl get nodes >/dev/null 2>&1; then
  echo "[+] Kubernetes cluster reachable. Querying resources in namespace '${NAMESPACE}'..."
  
  echo ""
  echo "Deployments:"
  kubectl get deployments -n "${NAMESPACE}" -l app=taskflow 2>/dev/null || echo "No taskflow deployments found."

  echo ""
  echo "Pods:"
  kubectl get pods -n "${NAMESPACE}" -l app=taskflow -o wide 2>/dev/null || echo "No taskflow pods found."

  echo ""
  echo "Services & Endpoints:"
  kubectl get svc,endpoints -n "${NAMESPACE}" -l app=taskflow 2>/dev/null || echo "No taskflow services found."
else
  echo "[i] Kubernetes CLI (kubectl) or cluster not currently reachable. Skipping cluster-level inspection."
fi

echo "=========================================================="
if [ "${FAILED}" -eq 0 ]; then
  echo -e "\033[32m [SUMMARY] All health probes passed successfully!\033[0m"
  exit 0
else
  echo -e "\033[31m [SUMMARY] ${FAILED} health probe(s) failed!\033[0m"
  exit 1
fi
