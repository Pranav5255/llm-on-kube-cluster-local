#!/usr/bin/env bash
# Runtime checks for host DCGM + Prometheus scrape (Kind).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-oss-llm}"
CTX="kind-${CLUSTER_NAME}"
NODE="${CLUSTER_NAME}-control-plane"

echo "=== DCGM observability diagnostics (cluster=${CTX}) ==="

KIND_GW=""
if docker exec "$NODE" true 2>/dev/null; then
  KIND_GW="$(docker exec "$NODE" ip -4 route show default 2>/dev/null | awk '{print $3}' | head -1 || true)"
fi

DCGM_LINES="0"
DCGM_DOCKER=""
if command -v docker >/dev/null 2>&1; then
  DCGM_DOCKER="$(docker ps --filter name=dcgm-host-exporter --format '{{.Status}}' 2>/dev/null | head -1 || true)"
fi
if MET="$(curl -sS --max-time 2 "http://127.0.0.1:${DCGM_HOST_PORT:-9400}/metrics" 2>/dev/null)"; then
  DCGM_LINES="$(echo "$MET" | grep -c '^DCGM_' || echo 0)"
fi

PROM_NAME=""
if kubectl --context "$CTX" get prometheus -n monitoring >/dev/null 2>&1; then
  PROM_NAME="$(kubectl --context "$CTX" get prometheus -n monitoring -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi

PROM_POD="$(kubectl --context "$CTX" get pods -n monitoring -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -E '^prometheus-.*kube-prometheus-stack-prometheus' | head -1 || true)"
probe_wget() {
  local ip="$1"
  if [ -z "${PROM_POD:-}" ]; then
    echo "no_pod"
    return 0
  fi
  if kubectl --context "$CTX" exec -n monitoring "$PROM_POD" -c prometheus -- \
    wget -qO- --timeout=3 "http://${ip}:${DCGM_HOST_PORT:-9400}/metrics" 2>/dev/null | head -1 | grep -q .; then
    echo ok
  else
    echo fail
  fi
}
W17="$(probe_wget 172.17.0.1)"
W18="$(probe_wget 172.18.0.1)"

Q_SNIP=""
if [ -n "${PROM_POD:-}" ]; then
  Q_SNIP="$(kubectl --context "$CTX" exec -n monitoring "$PROM_POD" -c prometheus -- \
    wget -qO- --timeout=5 'http://127.0.0.1:9090/api/v1/query?query=count(DCGM_FI_DEV_SM_CLOCK)' 2>/dev/null | head -c 500 || true)"
fi

echo "Kind default gateway (from ${NODE}): ${KIND_GW:-<unavailable>}"
echo "Host DCGM lines (127.0.0.1:${DCGM_HOST_PORT:-9400}): ${DCGM_LINES}"
echo "docker dcgm-host-exporter: ${DCGM_DOCKER:-not running}"
echo "Prometheus CR: ${PROM_NAME:-<none>}"
echo "Prometheus pod: ${PROM_POD:-<none>}"
echo "  wget from pod → 172.17.0.1: ${W17}  |  172.18.0.1: ${W18}"
echo "Prometheus API (truncated): ${Q_SNIP:0:160}"
echo "Done."
