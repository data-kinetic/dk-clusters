#!/usr/bin/env bash
set -euo pipefail

echo "=== DCGM Exporter Installer (krang host — A100 GPUs) ==="

# Check for NVIDIA GPUs
echo "--- Checking for NVIDIA GPUs ---"
if ! nvidia-smi &>/dev/null; then
  echo "ERROR: nvidia-smi not found or no GPUs available."
  echo "This script is intended for the krang host with A100 GPUs."
  echo "GPUs may be passed through to VMs. Exiting."
  exit 1
fi

echo "--- GPUs detected ---"
nvidia-smi --query-gpu=name --format=csv,noheader

# Check if already installed
if command -v dcgm-exporter &>/dev/null; then
  echo "--- dcgm-exporter already installed, skipping ---"
  exit 0
fi

echo "--- Adding NVIDIA DCGM repository ---"
if [[ ! -f /etc/apt/sources.list.d/nvidia-dcgm.list ]]; then
  DISTRO=$(. /etc/os-release; echo "${ID}${VERSION_ID}" | tr -d '.')
  ARCH=$(dpkg --print-architecture)
  curl -fsSL "https://developer.download.nvidia.com/compute/cuda/repos/${DISTRO}/${ARCH}/cuda-keyring_1.1-1_all.deb" -o /tmp/cuda-keyring.deb
  dpkg -i /tmp/cuda-keyring.deb
  rm -f /tmp/cuda-keyring.deb
  apt-get update
else
  echo "--- NVIDIA repository already configured ---"
fi

echo "--- Installing datacenter-gpu-manager and dcgm-exporter ---"
apt-get install -y datacenter-gpu-manager dcgm-exporter

echo "--- Installing systemd unit ---"
cat > /etc/systemd/system/dcgm-exporter.service <<'UNIT'
[Unit]
Description=NVIDIA DCGM Exporter
Documentation=https://github.com/NVIDIA/dcgm-exporter
After=network-online.target nvidia-dcgm.service
Wants=network-online.target
Requires=nvidia-dcgm.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/dcgm-exporter --address :9400
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

echo "--- Enabling and starting DCGM services ---"
systemctl daemon-reload
systemctl enable --now nvidia-dcgm
systemctl enable --now dcgm-exporter

echo "--- Verifying ---"
sleep 2
curl -sf http://localhost:9400/metrics | head -3 || echo "WARN: Could not reach metrics endpoint yet, service may still be starting"

echo "=== DCGM Exporter Install Complete ==="
