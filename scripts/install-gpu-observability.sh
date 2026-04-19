#!/usr/bin/env bash
# NVIDIA DCGM exporter (Prometheus scrape) + official DCGM Grafana dashboard ConfigMap.
# Requires: GPU-capable cluster, kube-prometheus-stack (./scripts/install-monitoring.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$ROOT/bin:$PATH"

CLUSTER_NAME="${CLUSTER_NAME:-oss-llm}"
CTX="kind-${CLUSTER_NAME}"

if [ "${USE_GPU:-0}" != "1" ]; then
  echo "Skipping GPU observability (set USE_GPU=1 to install DCGM exporter + Grafana GPU dashboard)."
  exit 0
fi

command -v helm >/dev/null || {
  echo "helm not found. Run scripts/install-tools.sh first."
  exit 1
}

echo "Adding NVIDIA dcgm-exporter Helm repo..."
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts 2>/dev/null || true
helm repo update

echo "Installing DCGM exporter in namespace monitoring (ServiceMonitor label release=kps)..."
helm upgrade --install dcgm-exporter gpu-helm-charts/dcgm-exporter \
  --kube-context "$CTX" \
  --namespace monitoring \
  --create-namespace \
  -f "$ROOT/helm/values-dcgm-exporter.yaml" \
  --wait --timeout 5m

echo "Loading NVIDIA DCGM Exporter dashboard into Grafana (sidecar picks up ConfigMaps labeled grafana_dashboard=1)..."
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
curl -sSL -o "$TMP" \
  https://raw.githubusercontent.com/NVIDIA/dcgm-exporter/main/grafana/dcgm-exporter-dashboard.json

kubectl --context "$CTX" create configmap grafana-dashboard-dcgm-exporter \
  --namespace=monitoring \
  --from-file=dcgm-exporter-dashboard.json="$TMP" \
  -o yaml --dry-run=client | kubectl --context "$CTX" apply -f -

kubectl --context "$CTX" label configmap -n monitoring grafana-dashboard-dcgm-exporter grafana_dashboard=1 --overwrite

echo ""
echo "GPU observability ready."
echo "  - Prometheus: scrape target for DCGM (dcgm-exporter in monitoring)"
echo "  - Grafana: Dashboards → browse for \"NVIDIA DCGM Exporter Dashboard\""
echo "  - If the dashboard does not appear within ~1–2 minutes: kubectl rollout restart -n monitoring deploy/kps-grafana"
