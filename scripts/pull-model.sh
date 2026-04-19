#!/usr/bin/env bash
# Pull GGUF weights into the Ollama PVC (default: phi3:mini).
set -euo pipefail
NS="${NS:-llm}"
MODEL="${1:-phi3:mini}"

echo "Pulling model '$MODEL' into Ollama in namespace $NS..."
kubectl exec -n "$NS" deploy/ollama -- ollama pull "$MODEL"
echo "Done. Verify: kubectl exec -n $NS deploy/ollama -- ollama list"
