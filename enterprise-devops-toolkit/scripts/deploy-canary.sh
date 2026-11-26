#!/usr/bin/env bash
# =============================================================================
# scripts/deploy-canary.sh
# Enterprise DevOps Deployment Toolkit (EDDT)
#
# Deploys the initial Canary topology:
#   - Stable deployment: 9 replicas (v1.0.0)
#   - Canary deployment: 1 replica  (v2.0.0)
#   - Shared service blending both fleets
#
# NOTE: Kubernetes replica ratios only approximate traffic distribution (~90/10).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../kubernetes/canary"
NAMESPACE="${1:-default}"

echo "=========================================================="
echo " [Canary] Deploying Initial Canary Topology"
echo " Namespace: ${NAMESPACE}"
echo " Baseline : Stable=9 pods (v1.0.0), Canary=1 pod (v2.0.0)"
echo " Note     : Replica counts provide ~10% approximate canary exposure"
echo "=========================================================="

# 1. Apply Stable Deployment
echo "[1/4] Applying Stable deployment (9 replicas)..."
kubectl apply -f "${K8S_DIR}/stable-deployment.yaml" -n "${NAMESPACE}"
kubectl rollout status deployment/taskflow-stable -n "${NAMESPACE}" --timeout=180s

# 2. Apply Canary Deployment
echo "[2/4] Applying Canary deployment (1 replica)..."
kubectl apply -f "${K8S_DIR}/canary-deployment.yaml" -n "${NAMESPACE}"
kubectl rollout status deployment/taskflow-canary -n "${NAMESPACE}" --timeout=120s

# 3. Apply Shared Service
echo "[3/4] Applying shared blended service..."
kubectl apply -f "${K8S_DIR}/service.yaml" -n "${NAMESPACE}"

# 4. Display combined endpoints
echo "[4/4] Active combined service endpoints:"
kubectl get endpoints taskflow-canary-shared-service -n "${NAMESPACE}"

echo "=========================================================="
echo " [SUCCESS] Canary deployment active!"
echo " Total Pods: 10 (9 Stable, 1 Canary)"
echo " To promote canary gradually, run: ./scripts/promote-canary.sh ${NAMESPACE}"
echo " To rollback instantly, run        : ./scripts/rollback-canary.sh ${NAMESPACE}"
echo "=========================================================="
