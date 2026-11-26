#!/usr/bin/env bash
# =============================================================================
# monitoring/deployment-status.sh
# Enterprise DevOps Deployment Toolkit (EDDT)
#
# Comprehensive Deployment Status, Diagnostics & Log Inspection Script
#
# Output:
#   - Active Kubernetes deployment status & replica counts
#   - Pod distribution, restart counts, and lifecycle phases
#   - Service routing and endpoint mapping
#   - Tail of recent application container logs
#   - Diagnostic guidance for common failure modes (CrashLoopBackOff, ImagePullBackOff, etc.)
# =============================================================================

set -euo pipefail

NAMESPACE="${1:-default}"
APP_LABEL="${2:-taskflow}"

echo "=========================================================="
echo " [Monitoring] Deployment Diagnostics & Health Status"
echo " Target Namespace : ${NAMESPACE}"
echo " Application Label: app=${APP_LABEL}"
echo " Timestamp        : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=========================================================="

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[-] ERROR: 'kubectl' command-line tool is not installed or not in PATH."
  exit 1
fi

if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "[-] WARNING: Target namespace '${NAMESPACE}' is not reachable or does not exist."
  echo "    Ensure your Kubernetes cluster (e.g., Minikube) is running: minikube status"
  exit 1
fi

# ── 1. Deployment Overview ───────────────────────────────────────────────────
echo ""
echo "=== 1. DEPLOYMENTS IN NAMESPACE '${NAMESPACE}' ==="
kubectl get deployments -n "${NAMESPACE}" -l "app=${APP_LABEL}" -o wide

# ── 2. Pod Health & Restart Counters ─────────────────────────────────────────
echo ""
echo "=== 2. POD HEALTH, RESTARTS & DISTRIBUTION ==="
kubectl get pods -n "${NAMESPACE}" -l "app=${APP_LABEL}" \
  -o custom-columns=NAME:.metadata.name,SLOT:.metadata.labels.slot,TRACK:.metadata.labels.track,VERSION:.metadata.labels.version,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,IP:.status.podIP,NODE:.spec.nodeName

# Detect abnormal pods
UNHEALTHY_PODS=$(kubectl get pods -n "${NAMESPACE}" -l "app=${APP_LABEL}" --no-headers 2>/dev/null | grep -v -E "Running|Completed" || echo "")
if [ -n "${UNHEALTHY_PODS}" ]; then
  echo ""
  echo "[-] ALERT: Abnormal pod states detected:"
  echo "${UNHEALTHY_PODS}"
  echo ""
  echo "=== FAILURE DETECTION & DIAGNOSTIC GUIDANCE ==="
  echo " * CrashLoopBackOff  : Application crashed on boot. Check logs: kubectl logs <pod-name> -n ${NAMESPACE}"
  echo " * ImagePullBackOff  : Image tag not found or registry requires credentials. Check: kubectl describe pod <pod-name> -n ${NAMESPACE}"
  echo " * Pending           : Insufficient CPU/Memory resources on node or missing PersistentVolumeClaim."
  echo " * OOMKilled         : Memory limit exceeded. Increase resources.limits.memory in deployment manifest."
fi

# ── 3. Services & Active Routing Endpoints ────────────────────────────────────
echo ""
echo "=== 3. SERVICE ROUTING & ENDPOINTS ==="
kubectl get services -n "${NAMESPACE}" -l "app=${APP_LABEL}"
echo ""
echo "Endpoints matching service selectors:"
kubectl get endpoints -n "${NAMESPACE}" -l "app=${APP_LABEL}"

# ── 4. Tail Recent Container Logs ─────────────────────────────────────────────
echo ""
echo "=== 4. RECENT CONTAINER LOG SAMPLES ==="
FIRST_POD=$(kubectl get pods -n "${NAMESPACE}" -l "app=${APP_LABEL}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "${FIRST_POD}" ]; then
  echo "Tailing last 15 log lines from pod: ${FIRST_POD}..."
  kubectl logs "${FIRST_POD}" -n "${NAMESPACE}" --tail=15 2>/dev/null || echo "Logs unavailable."
else
  echo "No pods currently running for app=${APP_LABEL}."
fi

# ── 5. Recommended Diagnostic Commands ────────────────────────────────────────
echo ""
echo "=== 5. QUICK COMMAND REFERENCE ==="
echo " * Live follow logs        : kubectl logs -f -l app=${APP_LABEL} -n ${NAMESPACE}"
echo " * Describe failing pod    : kubectl describe pod <pod-name> -n ${NAMESPACE}"
echo " * Interactive pod shell   : kubectl exec -it <pod-name> -n ${NAMESPACE} -- /bin/sh"
echo " * Forward port to local   : kubectl port-forward svc/taskflow-service 5000:80 -n ${NAMESPACE}"
echo "=========================================================="
