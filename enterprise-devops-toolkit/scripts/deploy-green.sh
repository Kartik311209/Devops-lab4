#!/usr/bin/env bash
# =============================================================================
# scripts/deploy-green.sh
# Enterprise DevOps Deployment Toolkit (EDDT)
#
# Deploys the Green (new candidate v2.0.0) environment, performs automated
# health verification on the preview service, and requires operator
# confirmation before switching production traffic.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../kubernetes/blue-green"
NAMESPACE="${1:-default}"

echo "=========================================================="
echo " [Blue-Green] Deploying Green Environment (Candidate v2.0.0)"
echo " Namespace: ${NAMESPACE}"
echo "=========================================================="

# 1. Apply Green Deployment
echo "[1/5] Applying Green deployment manifest..."
kubectl apply -f "${K8S_DIR}/green-deployment.yaml" -n "${NAMESPACE}"

# 2. Wait for Green rollout to complete
echo "[2/5] Waiting for Green pods to become Ready..."
kubectl rollout status deployment/taskflow-green -n "${NAMESPACE}" --timeout=180s

# 3. Verify Green preview service endpoints
echo "[3/5] Verifying Green pods via preview service..."
kubectl get endpoints taskflow-preview-service -n "${NAMESPACE}"

# 4. Perform Health Check on Green pods
echo "[4/5] Executing automated readiness and health verification..."
GREEN_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=taskflow,slot=green -o jsonpath='{.items[0].metadata.name}')

if [ -z "${GREEN_POD}" ]; then
  echo "[-] ERROR: No green pods found in namespace ${NAMESPACE}!"
  exit 1
fi

echo "Probing /health on pod: ${GREEN_POD}..."
kubectl exec -n "${NAMESPACE}" "${GREEN_POD}" -- python -c \
  "import urllib.request, sys; r = urllib.request.urlopen('http://localhost:5000/health'); sys.exit(0 if r.status == 200 else 1)"
echo "[+] Health check passed on Green candidate!"

echo "Probing /version on pod: ${GREEN_POD}..."
kubectl exec -n "${NAMESPACE}" "${GREEN_POD}" -- python -c \
  "import urllib.request; print(urllib.request.urlopen('http://localhost:5000/version').read().decode())"

# 5. Production Traffic Cutover Gate (Safety check - DO NOT switch automatically without confirmation)
echo "----------------------------------------------------------"
echo " [SAFETY GATE] Candidate version (Green) is healthy and ready."
echo " Current production traffic is still actively served by BLUE."
echo "----------------------------------------------------------"

read -r -p "Do you want to cutover production traffic to GREEN now? [y/N]: " CONFIRM
if [[ "${CONFIRM}" =~ ^[Yy]$ ]]; then
  echo "[5/5] Switching production service selector to slot: green..."
  kubectl patch service taskflow-service -n "${NAMESPACE}" \
    --type='json' -p='[{"op": "replace", "path": "/spec/selector/slot", "value": "green"}]'
  
  echo "=========================================================="
  echo " [SUCCESS] Traffic successfully switched to GREEN (v2.0.0)!"
  echo " Active selector: app=taskflow, slot=green"
  echo " To rollback instantly, run: ./scripts/rollback-blue-green.sh ${NAMESPACE}"
  echo "=========================================================="
else
  echo "[!] Cutover cancelled by operator. Production service remains on BLUE."
  echo "Green environment remains available for testing on taskflow-preview-service."
fi
