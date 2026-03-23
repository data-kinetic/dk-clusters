#!/usr/bin/env bash
set -euo pipefail
echo "=== Cluster Health Check ==="

echo ""
echo "--- Proxmox Cluster ---"
ssh penguin 'pvecm status 2>/dev/null | grep -E "Quorate|Nodes|Name"' || echo "FAIL: Cannot reach Proxmox"

echo ""
echo "--- VM Status (penguin) ---"
ssh penguin 'qm list 2>/dev/null' || echo "FAIL: Cannot list VMs"

echo ""
echo "--- VM Status (krang) ---"
ssh krang 'qm list 2>/dev/null' || echo "FAIL: Cannot reach krang"

echo ""
echo "--- K3s Cluster ---"
ssh -J penguin ubuntu@10.0.0.11 'kubectl cluster-info 2>/dev/null | head -2' || echo "FAIL: K3s not reachable"

echo ""
echo "--- ArgoCD Sync Status ---"
ssh -J penguin ubuntu@10.0.0.11 'kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null | head -20' || echo "FAIL: Cannot check ArgoCD"

echo ""
echo "=== Health Check Complete ==="
