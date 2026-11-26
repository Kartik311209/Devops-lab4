#!/usr/bin/env bash
# =============================================================================
# scripts/promote-canary.sh
# Enterprise DevOps Deployment Toolkit (EDDT)
#
# Progressive Canary Rollout Procedure:
#   Step 1: Verify current 10% Canary health
#   Step 2: Increase Canary to 30% (Stable=7, Canary=3)
#   Step 3: Increase Canary to 50% (Stable=5, Canary=5)
#   Step 4: Final Promotion -> Upgrade Stable image to v2.0.0 (10 replicas)
#           and scale Canary down to 0 replicas.
#
# If any validation step fails, the operator can abort and rollback.
# =============================================================================

set -euo pipefail

NAMESPACE="${1:-default}"

echo "=========================================================="
echo " [Canary] Progressive Promotion Workflow"
echo " Namespace: ${NAMESPACE}"
echo "=========================================================="

verify_canary_health() {
  local step_name="$1"
  echo "--> Health Verification for: ${step_name}"
  
  CANARY_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=taskflow,track=canary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -z "${CANARY_POD}" ]; then
    echo "[-] ERROR: No canary pods found!"
    exit 1
  fi

  echo "    Testing /health on canary pod ${CANARY_POD}..."
  kubectl exec -n "${NAMESPACE}" "${CANARY_POD}" -- python -c \
    "import urllib.request, sys; r = urllib.request.urlopen('http://localhost:5000/health'); sys.exit(0 if r.status == 200 else 1)"
  echo "    [+] Health probe OK."

  echo "    Testing /ready on canary pod ${CANARY_POD}..."
  kubectl exec -n "${NAMESPACE}" "${CANARY_POD}" -- python -c \
    "import urllib.request, sys; r = urllib.request.urlopen('http://localhost:5000/ready'); sys.exit(0 if r.status == 200 else 1)"
  echo "    [+] Readiness probe OK."
}

# ── Stage 1: Verify Initial 10% Baseline ─────────────────────────────────────
echo "==> [Stage 1/4] Validating Initial Canary Stage (10% approximate traffic)..."
verify_canary_health "Stage 1 (10% exposure)"

read -r -p "Stage 1 verified. Scale to Stage 2 (~30% canary: 7 stable / 3 canary)? [y/N]: " CONFIRM_1
if [[ ! "${CONFIRM_1}" =~ ^[Yy]$ ]]; then
  echo "[!] Promotion paused. Current replica split unchanged."
  exit 0
fi

# ── Stage 2: 30% Traffic Shift ───────────────────────────────────────────────
echo "==> [Stage 2/4] Scaling to ~30% Canary Exposure..."
kubectl scale deployment taskflow-canary --replicas=3 -n "${NAMESPACE}"
kubectl scale deployment taskflow-stable --replicas=7 -n "${NAMESPACE}"
kubectl rollout status deployment/taskflow-canary -n "${NAMESPACE}" --timeout=120s
verify_canary_health "Stage 2 (30% exposure)"

read -r -p "Stage 2 verified. Scale to Stage 3 (~50% canary: 5 stable / 5 canary)? [y/N]: " CONFIRM_2
if [[ ! "${CONFIRM_2}" =~ ^[Yy]$ ]]; then
  echo "[!] Promotion paused at Stage 2."
  exit 0
fi

# ── Stage 3: 50% Traffic Shift ───────────────────────────────────────────────
echo "==> [Stage 3/4] Scaling to ~50% Canary Exposure..."
kubectl scale deployment taskflow-canary --replicas=5 -n "${NAMESPACE}"
kubectl scale deployment taskflow-stable --replicas=5 -n "${NAMESPACE}"
kubectl rollout status deployment/taskflow-canary -n "${NAMESPACE}" --timeout=120s
verify_canary_health "Stage 3 (50% exposure)"

read -r -p "Stage 3 verified. Execute Final Promotion (Upgrade Stable to v2.0.0 and retire Canary)? [y/N]: " CONFIRM_3
if [[ ! "${CONFIRM_3}" =~ ^[Yy]$ ]]; then
  echo "[!] Promotion paused at Stage 3."
  exit 0
fi

# ── Stage 4: Final Promotion ─────────────────────────────────────────────────
echo "==> [Stage 4/4] Executing Final Promotion..."
echo "Updating stable deployment image to taskflow:2.0.0 and scaling to 10 replicas..."
kubectl set image deployment/taskflow-stable taskflow=taskflow:2.0.0 -n "${NAMESPACE}"
kubectl scale deployment taskflow-stable --replicas=10 -n "${NAMESPACE}"
kubectl rollout status deployment/taskflow-stable -n "${NAMESPACE}" --timeout=180s

echo "Decommissioning Canary fleet (replicas -> 0)..."
kubectl scale deployment taskflow-canary --replicas=0 -n "${NAMESPACE}"

echo "=========================================================="
echo " [SUCCESS] Full Canary Promotion Complete!"
echo " Stable is now running version 2.0.0 with 10 replicas (100% traffic)."
echo " Canary deployment is scaled to 0."
echo "=========================================================="
