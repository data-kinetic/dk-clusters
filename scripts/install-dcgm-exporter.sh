#!/usr/bin/env bash
set -euo pipefail

echo "=== DCGM Exporter Installer (A100 GPUs) ==="
echo ""
echo "NOTE: On krang, GPUs are PCI-passthrough to the vllm-minimax VM (192.168.10.101)."
echo "      This script should be run INSIDE the VM, not on the Proxmox host."
echo "      SSH: ssh root@192.168.10.101"
echo ""

# Check for NVIDIA GPUs
echo "--- Checking for NVIDIA GPUs ---"
if ! command -v nvidia-smi &>/dev/null; then
  echo "ERROR: nvidia-smi not found."
  echo "Install NVIDIA drivers first (e.g., apt install nvidia-utils-590-server)"
  exit 1
fi

if ! nvidia-smi &>/dev/null; then
  echo "ERROR: nvidia-smi found but no GPUs detected."
  echo "GPUs may be passed through to a VM. Run this inside the GPU VM."
  exit 1
fi

echo "--- GPUs detected ---"
nvidia-smi --query-gpu=name --format=csv,noheader

# Check if DCGM exporter is already running (Docker or native)
if curl -sf http://localhost:9400/metrics &>/dev/null; then
  echo "--- DCGM exporter already running on :9400, skipping ---"
  exit 0
fi

# Install DCGM daemon if not present
if ! systemctl is-active --quiet nvidia-dcgm 2>/dev/null; then
  echo "--- Installing datacenter-gpu-manager ---"
  DISTRO=$(. /etc/os-release; echo "${ID}${VERSION_ID}" | tr -d '.')
  ARCH=$(dpkg --print-architecture)

  if [[ ! -f /etc/apt/sources.list.d/cuda-*.list ]] && [[ ! -f /usr/share/keyrings/cuda-archive-keyring.gpg ]]; then
    echo "--- Adding NVIDIA CUDA repository ---"
    curl -fsSL "https://developer.download.nvidia.com/compute/cuda/repos/${DISTRO}/${ARCH}/cuda-keyring_1.1-1_all.deb" -o /tmp/cuda-keyring.deb
    dpkg -i /tmp/cuda-keyring.deb
    rm -f /tmp/cuda-keyring.deb
    apt-get update
  fi

  apt-get install -y datacenter-gpu-manager
  systemctl enable --now nvidia-dcgm
  echo "--- DCGM daemon started on :5555 ---"
else
  echo "--- DCGM daemon already running ---"
fi

# Deploy dcgm-exporter via Docker container (standard NVIDIA method)
echo "--- Deploying dcgm-exporter Docker container ---"
if ! command -v docker &>/dev/null; then
  echo "ERROR: Docker not found. Install Docker first."
  exit 1
fi

docker run -d \
  --name dcgm-exporter \
  --restart=always \
  --net=host \
  --gpus all \
  -e DCGM_EXPORTER_LISTEN=":9400" \
  -e DCGM_EXPORTER_REMOTE_HOSTENGINE_INFO="localhost:5555" \
  nvcr.io/nvidia/k8s/dcgm-exporter:3.3.9-3.6.1-ubuntu22.04

echo "--- Waiting for metrics endpoint ---"
sleep 5
if curl -sf http://localhost:9400/metrics | head -3; then
  echo ""
  echo "=== DCGM Exporter Install Complete ==="
  echo "Metrics available at http://$(hostname -I | awk '{print $1}'):9400/metrics"
else
  echo "WARN: Could not reach metrics endpoint yet."
  echo "Check: docker logs dcgm-exporter"
fi
