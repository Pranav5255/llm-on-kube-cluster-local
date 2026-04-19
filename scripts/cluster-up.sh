#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$ROOT/bin:$PATH"

command -v kubectl >/dev/null || { echo "Run scripts/install-tools.sh first"; exit 1; }
command -v kind >/dev/null || { echo "Run scripts/install-tools.sh first"; exit 1; }
if [ "${USE_GPU:-}" = "1" ]; then
  command -v helm >/dev/null || { echo "GPU mode requires helm. Run scripts/install-tools.sh first."; exit 1; }
  command -v nvidia-ctk >/dev/null 2>&1 || {
    echo "ERROR: USE_GPU=1 requires nvidia-ctk (NVIDIA Container Toolkit)."
    echo "  1) ./scripts/install-nvidia-container-toolkit-deb.sh   # Debian/Ubuntu"
    echo "  2) ./scripts/setup-gpu-kind-host.sh"
    echo "  3) kind delete cluster --name ${CLUSTER_NAME:-oss-llm}   # if cluster exists without GPU host setup"
    echo "  4) USE_GPU=1 $0"
    exit 1
  }
fi

CLUSTER_NAME="${CLUSTER_NAME:-oss-llm}"

KIND_CONFIG="$ROOT/k8s/kind-cluster.yaml"
if [ "${USE_GPU:-}" = "1" ]; then
  KIND_CONFIG="$ROOT/k8s/kind-cluster-gpu.yaml"
fi

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  if [ "${USE_GPU:-}" = "1" ]; then
    echo "Creating Kind cluster with GPU node config ($KIND_CONFIG)."
  fi
  kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG"
else
  echo "Cluster $CLUSTER_NAME already exists"
  if [ "${USE_GPU:-}" = "1" ]; then
    echo "NOTE: GPU Kind config (extraMounts) only applies at cluster create time."
    echo "      If this cluster was created without GPU config, run: kind delete cluster --name $CLUSTER_NAME"
    echo "      then USE_GPU=1 ./scripts/cluster-up.sh again (after setup-gpu-kind-host.sh)."
  fi
fi

kubectl cluster-info --context "kind-${CLUSTER_NAME}"

echo "Building chat-ui image..."
docker build -t oss-llm-chat-ui:local "$ROOT/chat-ui"

# Ollama: do not `kind load` — Docker 29 + ctr import can fail; cluster pulls from Docker Hub (see README).
echo "Loading local chat-ui image into kind (Ollama image is pulled inside the cluster)..."
kind load docker-image oss-llm-chat-ui:local --name "$CLUSTER_NAME"

echo "Applying manifests..."
kubectl apply -f "$ROOT/k8s/namespaces.yaml"
if [ "${USE_GPU:-}" = "1" ]; then
  echo "Installing NVIDIA device plugin (requires host GPU + nvidia-container-toolkit; see README GPU section)..."
  "$ROOT/scripts/install-nvidia-device-plugin.sh"
  kubectl apply -k "$ROOT/k8s/overlays/gpu"
else
  kubectl apply -f "$ROOT/k8s/base/ollama.yaml"
fi
kubectl apply -f "$ROOT/k8s/chat-ui.yaml"

if [ "${USE_GPU:-}" = "1" ]; then
  echo ""
  echo "Checking that at least one node advertises nvidia.com/gpu (plain Kind usually has none)..."
  gpu_ok=0
  for _ in $(seq 1 45); do
    for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
      g=$(kubectl get node "$node" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}' 2>/dev/null || true)
      if [ -n "$g" ] && [ "$g" != "0" ]; then
        gpu_ok=1
        break 2
      fi
    done
    sleep 2
  done
  if [ "$gpu_ok" != "1" ]; then
    echo ""
    echo "ERROR: No node exposes allocatable nvidia.com/gpu after ~90s."
    echo "  GPU mode does not work with default Kind — the Ollama pod would stay Pending forever."
    echo "  Fix: configure Docker + Kind for NVIDIA (see README → GPU, or https://github.com/NVIDIA/nvkind ),"
    echo "  or use CPU mode: kind delete cluster --name ${CLUSTER_NAME} && ./scripts/cluster-up.sh"
    echo "  Debug: kubectl describe pod -n llm -l app=ollama"
    exit 1
  fi
  echo "  OK: GPU allocatable on cluster."
fi

echo ""
echo "Waiting for chat-ui..."
kubectl rollout status deployment/chat-ui -n llm --timeout=300s

echo ""
echo "Waiting for Ollama (first model pull can take 15–40+ minutes on slow networks / CPU)..."
kubectl rollout status deployment/ollama -n llm --timeout=3600s

echo ""
echo "Done. Chat UI: http://127.0.0.1:8081  |  Ollama: http://127.0.0.1:8080"
echo "Smoke: curl -s http://127.0.0.1:8080/api/tags"
if [ "${USE_GPU:-}" = "1" ]; then
  echo ""
  echo "GPU mode: check logs for GPU backend — kubectl logs -n llm deploy/ollama | tail -50"
fi
echo ""
echo "Grafana / cluster metrics are not installed by this script. Run: ./scripts/install-monitoring.sh"
echo "  Then open http://127.0.0.1:3333 (or see README → Monitoring)."
if [ "${USE_GPU:-}" = "1" ]; then
  echo "  GPU metrics: USE_GPU=1 ./scripts/install-gpu-observability.sh (after monitoring), or USE_GPU=1 ./scripts/setup-full-stack.sh for everything in one go."
fi
