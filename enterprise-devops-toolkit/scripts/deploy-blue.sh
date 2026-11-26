#!/usr/bin/env bash
# =============================================================================
# scripts/deploy-blue.sh
# Enterprise DevOps Deployment Toolkit (EDDT)
#
# Deploys the Blue (baseline/stable v1.0.0) environment and points the
# production service to slot: blue.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../kubernetes/blue-green"
NAMESPACE="${1:-default}"

echo "=========================================================="
echo " [Blue-Green] Deploying Blue Environment (Baseline v1.0.0)"
echo " Namespace: ${NAMESPACE}"
echo "=========================================================="

# 1. Apply Blue Deployment manifest
echo "[1/4] Applying Blue deployment manifest..."
kubectl apply -f "${K8S_DIR}/blue-deployment.yaml" -n "${NAMESPACE}"

# 2. Wait for Blue pods rollout to be ready
echo "[2/4] Awaiting rollout completion of deployment/taskflow-blue..."
kubectl rollout status deployment/taskflow-blue -n "${NAMESPACE}" --timeout=120s

# 3. Apply Service manifests (points to blue)
echo "[3/4] Ensuring production service targets slot: blue..."
kubectl apply -f "${K8S_DIR}/service.yaml" -n "${NAMESPACE}"
kubectl patch service taskflow-service -n "${NAMESPACE}" \
  --type='json' -p='[{"op": "replace", "path": "/spec/selector/slot", "value": "blue"}]'

# 4. Verify deployment health
echo "[4/4] Verifying active service endpoints..."
kubectl get endpoints taskflow-service -n "${NAMESPACE}"

echo "=========================================================="
echo " [SUCCESS] Blue environment deployed and serving live traffic!"
echo " Service selector: app=taskflow, slot=blue"
echo "=========================================================="
