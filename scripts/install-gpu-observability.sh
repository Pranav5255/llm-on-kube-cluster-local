#!/usr/bin/env bash
# GPU metrics for Grafana: DCGM on the Docker host + NVIDIA dashboard ConfigMap.
# Prometheus scrape is defined in helm/values-kps-dcgm-host.yaml (merged by install-monitoring.sh).
#
# Definitive approach for Kind:
#   - In-cluster DCGM DaemonSet often fails (NVML) or crashes (SIGSEGV) when mixing host/user libs.
#   - Host-side: scripts/run-dcgm-host.sh (Docker --gpus all). This script probes which host IP reaches DCGM from the
#     Kind control-plane (172.17.0.1 / 172.18.0.1 / default gateway) before configuring Prometheus.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$ROOT/bin:$PATH"

CLUSTER_NAME="${CLUSTER_NAME:-oss-llm}"
CTX="kind-${CLUSTER_NAME}"
NODE="${CLUSTER_NAME}-control-plane"

if [ "${USE_GPU:-0}" != "1" ]; then
  echo "Skipping GPU observability (set USE_GPU=1 to start host DCGM + load Grafana GPU dashboard)."
  exit 0
fi

command -v helm >/dev/null || {
  echo "helm not found. Run scripts/install-tools.sh first."
  exit 1
}

discover_kind_host_ip() {
  if docker exec "$NODE" true 2>/dev/null; then
    docker exec "$NODE" ip -4 route show default 2>/dev/null | awk '{print $3}' | head -1
  fi
}

# Pick host IP reachable from the Kind node for published host ports (DCGM). The node's default gateway is often
# NOT the right address (e.g. 172.18.0.1 may be unreachable while docker0 172.17.0.1 works). Probe in stable order.
pick_host_ip_for_dcgm_scrape() {
  local ip tried="" gw
  gw="$(discover_kind_host_ip || true)"
  for ip in 172.17.0.1 172.18.0.1 ${gw}; do
    [ -z "$ip" ] && continue
    case " $tried " in *" $ip "*) continue ;; esac
    tried="$tried $ip"
    if docker exec "$NODE" wget -qO- --timeout=3 "http://${ip}:${PORT}/metrics" 2>/dev/null | head -1 | grep -q .; then
      echo "$ip"
      return 0
    fi
  done
  return 1
}

echo "Removing in-cluster dcgm-exporter Helm release if present (Kind: use host exporter)..."
helm uninstall dcgm-exporter -n monitoring --kube-context "$CTX" 2>/dev/null || true

echo "Starting DCGM exporter on the Docker host..."
chmod +x "$ROOT/scripts/run-dcgm-host.sh"
"$ROOT/scripts/run-dcgm-host.sh"

PORT="${DCGM_HOST_PORT:-9400}"
if [ -n "${DCGM_SCRAPE_HOST:-}" ]; then
  GW="${DCGM_SCRAPE_HOST}"
else
  GW="$(pick_host_ip_for_dcgm_scrape || true)"
  GW="${GW:-172.17.0.1}"
fi
TARGET="${GW}:${PORT}"

echo "Re-applying kube-prometheus-stack with DCGM scrape target ${TARGET} (reachable from Prometheus pod)..."
TMP="$(mktemp)"
sed -e "s|172.17.0.1:${PORT}|${TARGET}|g" \
  -e "s|172.18.0.1:${PORT}|${TARGET}|g" \
  "$ROOT/helm/values-kps-dcgm-host.yaml" > "$TMP"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update
helm upgrade kps prometheus-community/kube-prometheus-stack \
  --kube-context "$CTX" \
  --namespace monitoring \
  -f "$ROOT/helm/values-kps.yaml" \
  -f "$TMP" \
  --wait --timeout 10m
rm -f "$TMP"

echo "Verifying Prometheus can reach DCGM (best effort)..."
SCRAPE="${TARGET}"
PROM_POD="$(kubectl --context "$CTX" get pods -n monitoring -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -E '^prometheus-.*kube-prometheus-stack-prometheus' | head -1)"
if [ -n "$PROM_POD" ]; then
  if kubectl --context "$CTX" exec -n monitoring "$PROM_POD" -c prometheus -- \
    wget -qO- --timeout=3 "http://${SCRAPE}/metrics" 2>/dev/null | head -1 | grep -q .; then
    echo "  OK: scrape endpoint returned data from inside Prometheus pod."
  else
    echo "  WARNING: could not wget http://${SCRAPE}/metrics from Prometheus pod."
    echo "  Fix: export DCGM_SCRAPE_HOST=<host-ip-from-kind-node> USE_GPU=1 $0"
    echo "  Hint: ./scripts/diagnose-dcgm-observability.sh  (or docker exec ${NODE} wget http://<ip>:${PORT}/metrics)"
  fi
else
  echo "  (Skip verify: Prometheus pod not found.)"
fi

echo "Loading NVIDIA DCGM Exporter dashboard into Grafana (sidecar picks up ConfigMaps labeled grafana_dashboard=1)..."
TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT
curl -sSL -o "$TMP_JSON" \
  https://raw.githubusercontent.com/NVIDIA/dcgm-exporter/main/grafana/dcgm-exporter-dashboard.json

kubectl --context "$CTX" create configmap grafana-dashboard-dcgm-exporter \
  --namespace=monitoring \
  --from-file=dcgm-exporter-dashboard.json="$TMP_JSON" \
  -o yaml --dry-run=client | kubectl --context "$CTX" apply -f -

kubectl --context "$CTX" label configmap -n monitoring grafana-dashboard-dcgm-exporter grafana_dashboard=1 --overwrite

echo ""
echo "GPU observability ready (host DCGM)."
echo "  - Host: curl -s http://127.0.0.1:${PORT}/metrics | head"
echo "  - Grafana: NVIDIA DCGM Exporter Dashboard (refresh after ~1–2 min)"
echo "  - Prometheus: Status → Targets → dcgm-host should be UP"
