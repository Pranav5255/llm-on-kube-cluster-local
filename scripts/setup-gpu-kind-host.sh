#!/usr/bin/env bash
# One-time host setup so Kind node containers can use NVIDIA GPUs (CDI + Docker).
# Run BEFORE: USE_GPU=1 ./scripts/cluster-up.sh
# Requires: proprietary NVIDIA driver (nvidia-smi), nvidia-container-toolkit (nvidia-ctk).
set -euo pipefail

echo "Checking NVIDIA driver..."
if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "ERROR: nvidia-smi not found. Install the NVIDIA driver for your GPU first."
  exit 1
fi
nvidia-smi -L || true

if ! command -v nvidia-ctk >/dev/null 2>&1; then
  echo "ERROR: nvidia-ctk not found (NVIDIA Container Toolkit not installed)."
  echo "On Debian/Ubuntu, run:"
  echo "  ./scripts/install-nvidia-container-toolkit-deb.sh"
  echo "Then re-run this script. Other distros: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html"
  exit 1
fi

if [ "${1:-}" = "--print-only" ]; then
  echo "Commands to run (with sudo):"
  echo "  nvidia-ctk runtime configure --runtime=docker --set-as-default --cdi.enabled"
  echo "  nvidia-ctk config --set accept-nvidia-visible-devices-as-volume-mounts=true --in-place"
  echo "  systemctl restart docker"
  exit 0
fi

echo "Configuring Docker for NVIDIA (sets nvidia as default runtime; may affect other containers)..."
sudo nvidia-ctk runtime configure --runtime=docker --set-as-default --cdi.enabled
sudo nvidia-ctk config --set accept-nvidia-visible-devices-as-volume-mounts=true --in-place
sudo systemctl restart docker
echo "Waiting for Docker to come back..."
sleep 5

echo "Smoke test: GPU visible in a container with the Kind CDI mount..."
if docker run --rm -v /dev/null:/var/run/nvidia-container-devices/all ubuntu:22.04 nvidia-smi -L 2>/dev/null; then
  echo "OK: GPU passthrough test passed."
else
  echo "WARNING: GPU smoke test failed. See https://github.com/NVIDIA/nvkind#setup"
  echo "You may still try creating the cluster; some setups need a reboot or driver reload."
fi

echo ""
echo "Next: delete any existing CPU-only Kind cluster, then:"
echo "  export PATH=\"\$(pwd)/bin:\$PATH\""
echo "  USE_GPU=1 ./scripts/cluster-up.sh"
