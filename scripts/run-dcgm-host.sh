#!/usr/bin/env bash
# Run NVIDIA DCGM exporter on the Docker *host* (not inside the Kind cluster).
# Kind + in-cluster DCGM often fails NVML/SIGSEGV; host-side metrics are scraped by Prometheus (see helm/values-kps.yaml).
set -euo pipefail

IMG="${DCGM_IMAGE:-nvcr.io/nvidia/k8s/dcgm-exporter:4.5.2-4.8.1-ubuntu22.04}"
PORT="${DCGM_HOST_PORT:-9400}"
NAME="${DCGM_CONTAINER_NAME:-dcgm-host-exporter}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found."
  exit 1
fi

echo "Starting $NAME on the host (image $IMG, port ${PORT}:9400)..."
docker rm -f "$NAME" 2>/dev/null || true
exec docker run -d --restart unless-stopped --name "$NAME" --gpus all -p "${PORT}:9400" "$IMG"
