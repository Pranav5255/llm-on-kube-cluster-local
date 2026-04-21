#!/usr/bin/env bash
# Track DCGM host scrape in Prometheus (kube-prometheus-stack). Uses in-cluster HTTP — no port-forward required.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-oss-llm}"
CTX="kind-${CLUSTER_NAME}"
NS=monitoring

PROM_POD="$(kubectl --context "$CTX" get pods -n "$NS" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -E '^prometheus-.*kube-prometheus-stack-prometheus' | head -1 || true)"
if [ -z "$PROM_POD" ]; then
  echo "No Prometheus pod found in $NS (context $CTX)."
  exit 1
fi

echo "=== DCGM target (from GET /api/v1/targets) ==="
kubectl --context "$CTX" exec -n "$NS" "$PROM_POD" -c prometheus -- \
  wget -qO- 'http://127.0.0.1:9090/api/v1/targets' 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
for t in d.get('data', {}).get('activeTargets', []):
    job = t.get('labels', {}).get('job', '')
    if job == 'dcgm-host' or 'dcgm' in job.lower():
        print('job:          ', job)
        print('scrapeUrl:    ', t.get('scrapeUrl'))
        print('health:       ', t.get('health'))
        print('lastError:    ', repr(t.get('lastError') or ''))
        print('lastScrape:   ', t.get('lastScrape'))
        print('lastDuration: ', t.get('lastScrapeDuration'))
"

echo ""
echo "=== Sample DCGM series (instant query) ==="
kubectl --context "$CTX" exec -n "$NS" "$PROM_POD" -c prometheus -- \
  wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=count(DCGM_FI_DEV_SM_CLOCK)' 2>/dev/null | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin), indent=2))"

echo ""
echo "Tip: Prometheus UI → Status → Targets → filter dcgm-host"
echo "     Or: watch -n 30 $ROOT/scripts/track-dcgm-prometheus.sh"
