#!/usr/bin/env bash
set -euo pipefail

NODE_EXPORTER_VERSION="1.8.2"

echo "=== Node Exporter Installer ==="

# Check if already installed at correct version
if command -v node_exporter &>/dev/null; then
  INSTALLED_VERSION=$(node_exporter --version 2>&1 | head -1 | grep -oP 'version \K[0-9.]+' || echo "unknown")
  if [[ "$INSTALLED_VERSION" == "$NODE_EXPORTER_VERSION" ]]; then
    echo "--- node_exporter v${NODE_EXPORTER_VERSION} already installed, skipping ---"
    exit 0
  fi
  echo "--- Upgrading node_exporter from v${INSTALLED_VERSION} to v${NODE_EXPORTER_VERSION} ---"
fi

echo "--- Installing node_exporter v${NODE_EXPORTER_VERSION} ---"

TMPDIR=$(mktemp -d)
TARBALL="node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${TARBALL}"

echo "--- Downloading ${DOWNLOAD_URL} ---"
curl -fsSL -o "${TMPDIR}/${TARBALL}" "${DOWNLOAD_URL}"

echo "--- Extracting ---"
tar xzf "${TMPDIR}/${TARBALL}" -C "${TMPDIR}"
cp "${TMPDIR}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/node_exporter
chmod +x /usr/local/bin/node_exporter

echo "--- Creating node_exporter user ---"
useradd --system --no-create-home --shell /bin/false node_exporter || true

echo "--- Installing systemd unit ---"
cat > /etc/systemd/system/node_exporter.service <<'UNIT'
[Unit]
Description=Prometheus Node Exporter
Documentation=https://github.com/prometheus/node_exporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=node_exporter
ExecStart=/usr/local/bin/node_exporter \
  --collector.cpu \
  --collector.diskstats \
  --collector.filesystem \
  --collector.meminfo \
  --collector.netdev \
  --collector.zfs \
  --collector.loadavg \
  --collector.uname \
  --collector.hwmon \
  --collector.nvme \
  --web.listen-address=:9100
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

echo "--- Enabling and starting node_exporter ---"
systemctl daemon-reload
systemctl enable --now node_exporter

echo "--- Verifying ---"
sleep 2
curl -sf http://localhost:9100/metrics | head -3 || echo "WARN: Could not reach metrics endpoint yet, service may still be starting"

echo "--- Cleaning up ---"
rm -rf "${TMPDIR}"

echo "=== Node Exporter Install Complete ==="
