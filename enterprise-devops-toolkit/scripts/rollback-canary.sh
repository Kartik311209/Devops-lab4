#!/usr/bin/env bash
# =============================================================================
# scripts/rollback-canary.sh
# Enterprise DevOps Deployment Toolkit (EDDT)
#
# Instant Canary Rollback:
# Immediately scales taskflow-canary down to 0 replicas, eliminating all
# traffic to the candidate version, and restores taskflow-stable to full capacity.
# =============================================================================

set -euo pipefail

NAMESPACE="${1:-default}"

echo "=========================================================="
echo " [Canary] Executing Instant Rollback"
echo " Namespace: ${NAMESPACE}"
echo " Action   : Terminating Canary traffic and restoring Stable"
echo "=========================================================="

# 1. Scale Canary deployment to 0 replicas
echo "[1/2] Scaling taskflow-canary to 0 replicas..."
kubectl scale deployment taskflow-canary --replicas=0 -n "${NAMESPACE}"

# 2. Restore Stable deployment to full capacity (10 replicas)
echo "[2/2] Restoring taskflow-stable to full production capacity (10 replicas)..."
kubectl scale deployment taskflow-stable --replicas=10 -n "${NAMESPACE}"
kubectl rollout status deployment/taskflow-stable -n "${NAMESPACE}" --timeout=120s

echo "=========================================================="
echo " [SUCCESS] Canary traffic eliminated!"
echo " Stable deployment is now serving 100% of production traffic."
echo "=========================================================="
