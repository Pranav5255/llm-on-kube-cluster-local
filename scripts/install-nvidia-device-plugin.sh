#!/usr/bin/env bash
# Install NVIDIA k8s device plugin (DaemonSet) so nodes expose nvidia.com/gpu.
# Kind has no Node Feature Discovery, so the chart's default nodeAffinity matches
# no nodes unless we label them (same idea as NVIDIA nvkind issue #20).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$ROOT/bin:$PATH"

command -v helm >/dev/null || {
  echo "helm not found. Run scripts/install-tools.sh first."
  exit 1
}

CLUSTER_NAME="${CLUSTER_NAME:-oss-llm}"
CTX="kind-${CLUSTER_NAME}"

echo "Labeling nodes so device plugin DaemonSet can schedule (Kind lacks NFD pci labels)..."
kubectl --context "$CTX" get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | while read -r node; do
  [ -z "$node" ] && continue
  kubectl --context "$CTX" label node "$node" feature.node.kubernetes.io/pci-10de.present=true --overwrite
done

helm repo add nvdp https://nvidia.github.io/k8s-device-plugin 2>/dev/null || true
helm repo update

helm upgrade --install nvidia-device-plugin nvdp/nvidia-device-plugin \
  --kube-context "$CTX" \
  --namespace nvidia \
  --create-namespace \
  -f "$ROOT/helm/values-nvidia-device-plugin-kind.yaml" \
  --wait --timeout 5m

echo "NVIDIA device plugin installed. Check: kubectl --context=$CTX get pods -n nvidia"
