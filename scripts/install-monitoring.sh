#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$ROOT/bin:$PATH"

command -v helm >/dev/null || { echo "Run scripts/install-tools.sh first"; exit 1; }

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

CLUSTER_NAME="${CLUSTER_NAME:-oss-llm}"
kubectl config use-context "kind-${CLUSTER_NAME}"

kubectl apply -f "$ROOT/k8s/namespaces.yaml"

helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f "$ROOT/helm/values-kps.yaml" \
  -f "$ROOT/helm/values-kps-dcgm-host.yaml" \
  --wait --timeout 15m

echo ""
echo "Grafana UI:"
echo "  - Kind + kind-cluster.yaml port map: http://127.0.0.1:3333"
echo "  - Or: kubectl port-forward -n monitoring svc/kps-grafana 3333:80"
echo "  - Login: admin / (see helm/values-kps.yaml grafana.adminPassword)"
