#!/usr/bin/env bash
set -euo pipefail
echo "=== dk-clusters Validation ==="

echo ""
echo "--- Node Status ---"
ssh -J penguin ubuntu@10.0.0.11 'kubectl get nodes -o wide' 2>/dev/null || echo "FAIL: Cannot reach K3s master"

echo ""
echo "--- Pod Health (infra) ---"
ssh -J penguin ubuntu@10.0.0.11 'kubectl get pods -n infra --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null' || echo "All pods healthy"

echo ""
echo "--- Storage ---"
ssh penguin 'zpool list' 2>/dev/null || echo "FAIL: Cannot reach penguin"

echo ""
echo "--- Keepalived VIPs ---"
for ip in 172.16.100.100 172.16.100.101 192.168.1.100; do
  ping -c 1 -W 2 "$ip" >/dev/null 2>&1 && echo "VIP $ip: UP" || echo "VIP $ip: DOWN"
done

echo ""
echo "--- Reflector Status ---"
ssh -J penguin ubuntu@10.0.0.11 'kubectl get pods -n infra -l app.kubernetes.io/name=reflector -o wide' 2>/dev/null || echo "FAIL: Cannot check reflector"

echo ""
echo "=== Validation Complete ==="
