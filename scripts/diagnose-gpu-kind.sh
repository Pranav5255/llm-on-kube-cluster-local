#!/usr/bin/env bash
# Read-only checks: GPU visibility on host, inside Kind node, and device plugin logs.
set -euo pipefail
CLUSTER_NAME="${CLUSTER_NAME:-oss-llm}"
NODE_CONTAINER="${1:-${CLUSTER_NAME}-control-plane}"

echo "=== Host ==="
command -v nvidia-smi >/dev/null && nvidia-smi -L || echo "no nvidia-smi"

echo ""
echo "=== Kind node container: $NODE_CONTAINER (docker exec) ==="
if docker ps --format '{{.Names}}' | grep -qx "$NODE_CONTAINER"; then
  docker exec "$NODE_CONTAINER" sh -c 'command -v nvidia-smi >/dev/null && nvidia-smi -L' 2>&1 || echo "nvidia-smi failed inside node (GPU not visible to kubelet/device plugin)"
else
  echo "Container not running: $NODE_CONTAINER"
fi

echo ""
echo "=== NVIDIA device plugin pod ==="
kubectl get pods -n nvidia -o wide 2>/dev/null || true
P=$(kubectl get pods -n nvidia -l app.kubernetes.io/name=nvidia-device-plugin -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "${P:-}" ]; then
  echo "--- logs $P ---"
  kubectl logs -n nvidia "$P" --tail=40 2>&1 || true
fi
