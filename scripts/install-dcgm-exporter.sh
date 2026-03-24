#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# DCGM Exporter Installer — runs INSIDE the vllm-minimax VM (192.168.10.101)
# =============================================================================
# All 8 A100 GPUs are PCI-passthrough from the krang Proxmox host into this VM.
# This script installs the NVIDIA DCGM daemon and runs dcgm-exporter as a
# Docker container exposing GPU metrics on :9400 for Prometheus scraping.
#
# Prerequisites:
#   - Ubuntu 22.04 VM with NVIDIA drivers installed (nvidia-utils-590-server)
#   - Docker installed and running
#   - Run as root: ssh root@192.168.10.101
# =============================================================================

echo "=== DCGM Exporter Installer (vllm-minimax VM — 8× A100 GPU passthrough) ==="

# --- Check nvidia-smi ---
echo "--- Checking for NVIDIA GPU drivers ---"
if ! command -v nvidia-smi &>/dev/null; then
  echo "ERROR: nvidia-smi not found."
  echo "The NVIDIA driver must be installed inside this VM for GPU passthrough to work."
  echo ""
  echo "  Install with: apt-get install -y nvidia-utils-590-server"
  echo ""
  echo "After installing, verify GPUs are visible: nvidia-smi"
  exit 1
fi

if ! nvidia-smi &>/dev/null; then
  echo "ERROR: nvidia-smi is installed but cannot communicate with the GPU driver."
  echo "Check that the NVIDIA kernel module is loaded: lsmod | grep nvidia"
  exit 1
fi

echo "--- GPUs detected ---"
nvidia-smi --query-gpu=index,name,uuid --format=csv
echo ""

# --- Check if already running ---
echo "--- Checking if DCGM exporter is already running on :9400 ---"
if curl -sf http://localhost:9400/metrics &>/dev/null; then
  echo "DCGM exporter is already running and serving metrics on :9400. Nothing to do."
  exit 0
fi

# --- Check Docker ---
echo "--- Checking Docker ---"
if ! command -v docker &>/dev/null; then
  echo "ERROR: Docker is not installed. Install Docker first."
  exit 1
fi

if ! docker info &>/dev/null; then
  echo "ERROR: Docker daemon is not running."
  exit 1
fi

# --- Install datacenter-gpu-manager (DCGM daemon) ---
echo "--- Installing datacenter-gpu-manager ---"
if ! command -v nv-hostengine &>/dev/null; then
  echo "--- Adding NVIDIA CUDA repository ---"
  if [[ ! -f /etc/apt/sources.list.d/cuda-ubuntu2204-x86_64.list ]] && [[ ! -f /usr/share/keyrings/cuda-archive-keyring.gpg ]]; then
    DISTRO=$(. /etc/os-release; echo "${ID}${VERSION_ID}" | tr -d '.')
    ARCH=$(dpkg --print-architecture)
    curl -fsSL "https://developer.download.nvidia.com/compute/cuda/repos/${DISTRO}/${ARCH}/cuda-keyring_1.1-1_all.deb" -o /tmp/cuda-keyring.deb
    dpkg -i /tmp/cuda-keyring.deb
    rm -f /tmp/cuda-keyring.deb
    apt-get update
  else
    echo "--- NVIDIA CUDA repository already configured ---"
    apt-get update
  fi

  apt-get install -y datacenter-gpu-manager
else
  echo "--- datacenter-gpu-manager already installed ---"
fi

echo "--- Enabling and starting DCGM daemon ---"
systemctl enable --now nvidia-dcgm
sleep 2

echo "--- Verifying DCGM daemon ---"
if ! dcgmi discovery -l &>/dev/null; then
  echo "WARN: DCGM daemon may not be fully ready yet, proceeding anyway..."
fi

# --- Deploy dcgm-exporter as Docker container ---
echo "--- Deploying dcgm-exporter Docker container ---"
DCGM_IMAGE="nvcr.io/nvidia/k8s/dcgm-exporter:3.3.9-3.6.1-ubuntu22.04"

# Stop existing container if present but not serving metrics
if docker ps -a --format '{{.Names}}' | grep -q '^dcgm-exporter$'; then
  echo "--- Removing existing dcgm-exporter container ---"
  docker rm -f dcgm-exporter
fi

echo "--- Pulling ${DCGM_IMAGE} ---"
docker pull "${DCGM_IMAGE}"

echo "--- Starting dcgm-exporter container ---"
docker run -d \
  --name dcgm-exporter \
  --restart unless-stopped \
  --net=host \
  --gpus all \
  -e DCGM_EXPORTER_LISTEN=":9400" \
  -e DCGM_EXPORTER_KUBERNETES="false" \
  -e DCGM_REMOTE_HOSTENGINE_INFO="localhost:5555" \
  "${DCGM_IMAGE}"

# --- Verify metrics ---
echo "--- Waiting for metrics endpoint ---"
for i in $(seq 1 10); do
  if curl -sf http://localhost:9400/metrics | head -5; then
    echo ""
    echo "=== DCGM Exporter is running and serving metrics on :9400 ==="
    exit 0
  fi
  echo "  Waiting... (${i}/10)"
  sleep 2
done

echo "WARN: Metrics endpoint not responding yet. Check container logs:"
echo "  docker logs dcgm-exporter"
echo "=== DCGM Exporter Install Complete (verify metrics manually) ==="
