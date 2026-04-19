#!/usr/bin/env bash
# One-shot demo: Kind + workloads + kube-prometheus-stack + GPU metrics (when USE_GPU=1).
#
# Host NVIDIA/Docker setup (nvidia-ctk, setup-gpu-kind-host.sh) is NOT run here — do that once before creating a GPU Kind cluster.
#
# Environment:
#   USE_GPU=1     GPU Kind config, device plugin, GPU Ollama, DCGM + Grafana GPU dashboard (default)
#   USE_GPU=0     CPU Kind + workloads + monitoring only (no DCGM)
#   CLUSTER_NAME  Kind cluster name (default: oss-llm)
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$ROOT/bin:$PATH"

export USE_GPU="${USE_GPU:-1}"

echo "=== 1/3 cluster + workloads (cluster-up.sh) ==="
"$ROOT/scripts/cluster-up.sh"

echo ""
echo "=== 2/3 kube-prometheus-stack (install-monitoring.sh) ==="
"$ROOT/scripts/install-monitoring.sh"

echo ""
if [ "$USE_GPU" = "1" ]; then
  echo "=== 3/3 GPU observability (install-gpu-observability.sh) ==="
  USE_GPU=1 "$ROOT/scripts/install-gpu-observability.sh"
else
  echo "=== 3/3 skipped (USE_GPU=0 — no DCGM / GPU dashboard) ==="
fi

echo ""
echo "Done."
echo "  Chat UI:    http://127.0.0.1:8081"
echo "  Ollama:     http://127.0.0.1:8080"
echo "  Grafana:    http://127.0.0.1:3333  (admin / see helm/values-kps.yaml)"
if [ "$USE_GPU" = "1" ]; then
  echo "  GPU charts: Grafana → NVIDIA DCGM Exporter Dashboard"
fi
