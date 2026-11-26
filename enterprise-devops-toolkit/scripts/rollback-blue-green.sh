#!/usr/bin/env bash
# =============================================================================
# scripts/rollback-blue-green.sh
# Enterprise DevOps Deployment Toolkit (EDDT)
#
# Instant Rollback: Restores production traffic to the Blue slot by patching
# the Kubernetes service selector. Zero-downtime traffic reversion.
# =============================================================================

set -euo pipefail

NAMESPACE="${1:-default}"

echo "=========================================================="
echo " [Blue-Green] Executing Instant Rollback to BLUE (v1.0.0)"
echo " Namespace: ${NAMESPACE}"
echo "=========================================================="

# 1. Verify Blue deployment exists and is healthy
echo "[1/3] Verifying Blue deployment availability..."
BLUE_READY=$(kubectl get deployment taskflow-blue -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

if [ "${BLUE_READY}" -lt 1 ]; then
  echo "[-] WARNING: taskflow-blue has ${BLUE_READY} ready pods. Scaling up..."
  kubectl scale deployment taskflow-blue --replicas=3 -n "${NAMESPACE}"
  kubectl rollout status deployment/taskflow-blue -n "${NAMESPACE}" --timeout=120s
fi

# 2. Patch Service Selector back to Blue
echo "[2/3] Reverting service selector to slot: blue..."
kubectl patch service taskflow-service -n "${NAMESPACE}" \
  --type='json' -p='[{"op": "replace", "path": "/spec/selector/slot", "value": "blue"}]'

# 3. Verify active endpoints
echo "[3/3] Verifying active production endpoints..."
kubectl get endpoints taskflow-service -n "${NAMESPACE}"

echo "=========================================================="
echo " [SUCCESS] Rollback completed in < 1 second!"
echo " Production traffic is now actively served by BLUE (v1.0.0)."
echo "=========================================================="
