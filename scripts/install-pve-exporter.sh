#!/usr/bin/env bash
set -euo pipefail

echo "=== PVE Exporter Installer ==="

# Check if already installed
if [[ -f /opt/pve-exporter/venv/bin/pve_exporter ]]; then
  echo "--- pve_exporter already installed, skipping ---"
  echo "--- To reinstall, remove /opt/pve-exporter and re-run ---"
  exit 0
fi

echo "--- Creating /opt/pve-exporter ---"
mkdir -p /opt/pve-exporter

echo "--- Ensuring python3-venv is installed ---"
apt-get install -y python3-venv

echo "--- Creating Python virtual environment ---"
python3 -m venv /opt/pve-exporter/venv

echo "--- Installing prometheus-pve-exporter ---"
/opt/pve-exporter/venv/bin/pip install --quiet prometheus-pve-exporter

echo "--- Writing config to /opt/pve-exporter/pve.yml ---"
cat > /opt/pve-exporter/pve.yml <<'CONFIG'
default:
  user: monitoring@pve
  token_name: monitoring
  token_value: "${PVE_TOKEN_VALUE}"
  verify_ssl: false
CONFIG

echo ""
echo "  *** IMPORTANT: Edit /opt/pve-exporter/pve.yml and replace"
echo "  *** \${PVE_TOKEN_VALUE} with your actual Proxmox API token value."
echo "  *** Create the token in Proxmox: Datacenter > Permissions > API Tokens"
echo ""

echo "--- Installing systemd unit ---"
cat > /etc/systemd/system/pve-exporter.service <<'UNIT'
[Unit]
Description=Prometheus PVE Exporter
Documentation=https://github.com/prometheus-pve/prometheus-pve-exporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/pve-exporter
ExecStart=/opt/pve-exporter/venv/bin/pve_exporter /opt/pve-exporter/pve.yml --port 9221
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

echo "--- Enabling and starting pve-exporter ---"
systemctl daemon-reload
systemctl enable --now pve-exporter

echo "--- Verifying ---"
sleep 2
curl -sf http://localhost:9221/pve?target=localhost | head -3 || echo "WARN: Could not reach metrics endpoint yet (check pve.yml config)"

echo "=== PVE Exporter Install Complete ==="
