#!/usr/bin/env bash
# Install NVIDIA Container Toolkit on Debian/Ubuntu (provides nvidia-ctk).
# Run BEFORE scripts/setup-gpu-kind-host.sh
# Docs: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script is for apt-based systems (Debian/Ubuntu). See NVIDIA docs for other distros."
  exit 1
fi

if command -v nvidia-ctk >/dev/null 2>&1; then
  echo "nvidia-ctk already on PATH: $(command -v nvidia-ctk)"
  exit 0
fi

echo "Adding NVIDIA container library apt repository..."
sudo mkdir -p /usr/share/keyrings
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

command -v nvidia-ctk >/dev/null 2>&1 || {
  echo "ERROR: nvidia-ctk still not found after install. Check package output above."
  exit 1
}
echo "OK: $(command -v nvidia-ctk)"
echo "Next: ./scripts/setup-gpu-kind-host.sh"
