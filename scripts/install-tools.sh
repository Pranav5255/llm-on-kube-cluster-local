#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/bin"
mkdir -p "$BIN"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
esac

KVER="1.31.0"
KIND_VER="v0.24.0"

if [[ ! -x "$BIN/kubectl" ]]; then
  echo "Installing kubectl $KVER..."
  curl -fsSL "https://dl.k8s.io/release/v${KVER}/bin/${OS}/${ARCH}/kubectl" -o "$BIN/kubectl"
  chmod +x "$BIN/kubectl"
fi

if [[ ! -x "$BIN/kind" ]]; then
  echo "Installing kind $KIND_VER..."
  curl -fsSL "https://kind.sigs.k8s.io/dl/${KIND_VER}/kind-${OS}-${ARCH}" -o "$BIN/kind"
  chmod +x "$BIN/kind"
fi

if [[ ! -x "$BIN/helm" ]]; then
  echo "Installing helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | HELM_INSTALL_DIR="$BIN" USE_SUDO=false bash
fi

export PATH="$BIN:$PATH"
"$BIN/kubectl" version --client 2>/dev/null | head -1
"$BIN/kind" version
"$BIN/helm" version

echo "Tools ready. Add to PATH:"
echo "  export PATH=\"$BIN:\$PATH\""
