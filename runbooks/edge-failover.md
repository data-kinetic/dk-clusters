# Edge Failover Runbook

## Last Verified
2026-03-23

## Architecture

```
Internet → UDM Pro (port forward 80/443) → VIP 192.168.1.100 (Core LAN)
                                              ↓ (VRRP)
                                    phantom (10.0.0.2) — MASTER for WAN1 + Core
                                    venom   (10.0.0.3) — MASTER for WAN2
                                              ↓
                                    Traefik → K3s cluster (10.0.0.11/12)
```

### VIP Assignments

| VRRP Instance | VIP | phantom | venom |
|---------------|-----|---------|-------|
| VI_WAN1 (id 51) | 172.16.100.100 | MASTER (priority 101+2) | BACKUP (priority 100+2) |
| VI_WAN2 (id 52) | 172.16.100.101 | BACKUP (priority 100+2) | MASTER (priority 101+2) |
| VI_CORE (id 53) | 192.168.1.100 | MASTER (priority 101+2) | BACKUP (priority 100+2) |

The +2 comes from the `chk_traefik` track script weight when Traefik is healthy.

## Current State

| Component | phantom (10.0.0.2) | venom (10.0.0.3) |
|-----------|-------------------|-------------------|
| K3s | Active (control-plane) | Active (control-plane) |
| Keepalived | Running (K8s DaemonSet in edge-system) | Running (K8s DaemonSet in edge-system) |
| Traefik | Running, healthy (/ping returns OK) | Running, healthy (/ping returns OK) |
| VIP 172.16.100.100 | Held (MASTER) | Not held (BACKUP) |
| VIP 172.16.100.101 | Not held (BACKUP) | Held (MASTER) |
| VIP 192.168.1.100 | Held (MASTER) | Not held (BACKUP) |

**VRRP failover is operational.** Keepalived runs as a K8s DaemonSet (not systemd), deployed via dk-alchemy kustomize overlays. VRRP unicast peers communicate over DMZ (172.16.100.x) and Core LAN (192.168.1.x) networks.

## Access Notes

- phantom is reachable from penguin via cluster network: `ssh penguin 'sudo ssh ubuntu@10.0.0.2 ...'`
- venom is NOT reachable from penguin on cluster network (10.0.0.3 — cross-host vmbr1 routing gap)
- venom IS reachable from krang: `ssh penguin 'sudo ssh root@192.168.10.100 "ssh ubuntu@10.0.0.3 ..."'`
- venom IS reachable on DMZ (172.16.100.13) and Core LAN (192.168.1.21) from penguin
- krang SSH requires `sudo ssh` from penguin (no direct SSH key configured for krang from local machine)

## Health Check

```bash
# Quick status check from penguin
ssh penguin '
echo "=== PHANTOM ==="
sudo ssh ubuntu@10.0.0.2 "sudo kubectl get pods -n edge-system; ip addr show | grep -E \"172.16.100|192.168.1.100\"" 2>/dev/null
echo ""
echo "=== VENOM (via DMZ ping + Traefik check) ==="
curl -sf http://172.16.100.13:80/ping && echo " (venom traefik OK)" || echo " (venom traefik FAIL)"
curl -sf http://172.16.100.12:80/ping && echo " (phantom traefik OK)" || echo " (phantom traefik FAIL)"
'
```

## Failover Test Procedure

### Prerequisites
- Both keepalived pods running in edge-system namespace
- Both Traefik instances healthy (curl /ping returns OK)
- External monitoring ready to verify access during failover

### Test Steps

1. **Verify pre-test state:**
   ```bash
   # Phantom VIPs and pods
   ssh penguin 'sudo ssh ubuntu@10.0.0.2 "sudo kubectl get pods -n edge-system; ip addr show | grep -E \"172.16.100|192.168.1.100\""'
   # Venom VIPs (check via krang jump)
   ssh penguin 'sudo ssh root@192.168.10.100 "ssh ubuntu@10.0.0.3 \"ip addr show | grep -E \\\"172.16.100|192.168.1.100\\\"\""'
   ```

2. **Verify external access works:**
   ```bash
   curl -sk https://app.behaviorlabs.ai/health
   ```

3. **Trigger failover (delete phantom keepalived pod — it will restart via DaemonSet):**
   ```bash
   ssh penguin 'sudo ssh ubuntu@10.0.0.2 "sudo kubectl delete pod -n edge-system -l app=keepalived"'
   ```

4. **Verify VIP migration to venom (within 3-5 seconds):**
   ```bash
   ssh penguin 'sudo ssh root@192.168.10.100 "ssh ubuntu@10.0.0.3 \"ip addr show | grep -E \\\"172.16.100.100|192.168.1.100\\\"\""'
   ```

5. **Verify external access via venom:**
   ```bash
   curl -sk https://app.behaviorlabs.ai/health
   ```

6. **Wait for phantom pod to restart (DaemonSet auto-recreates):**
   ```bash
   ssh penguin 'sudo ssh ubuntu@10.0.0.2 "sudo kubectl get pods -n edge-system -l app=keepalived -w"'
   ```

7. **Verify VIP returns to phantom (preempt mode, higher priority):**
   ```bash
   ssh penguin 'sudo ssh ubuntu@10.0.0.2 "ip addr show | grep -E \"172.16.100.100|192.168.1.100\""'
   ```

### Expected Results
- VIPs 172.16.100.100 and 192.168.1.100 migrate to venom within 3-5 seconds
- VIP 172.16.100.101 stays on venom (already MASTER there)
- External HTTPS access continues (brief TCP reset acceptable)
- VIPs return to phantom once its keepalived pod restarts

### Rollback
If keepalived pod won't restart on phantom:
```bash
# Check pod status
ssh penguin 'sudo ssh ubuntu@10.0.0.2 "sudo kubectl describe pod -n edge-system -l app=keepalived"'
# If Doppler secret issue, manually re-add VIP as emergency measure
ssh penguin 'sudo ssh ubuntu@10.0.0.2 "sudo ip addr add 192.168.1.100/24 dev eth2; sudo ip addr add 172.16.100.100/24 dev eth0"'
```

## Known Limitations
1. Cluster network (10.0.0.x) does not route between penguin and krang VMs — venom must be accessed via krang jump or DMZ/Core LAN
2. No SSH config entry for krang on local machine — requires `sudo ssh` from penguin
3. Keepalived track script checks Traefik on port 80 — if Traefik config changes its ping endpoint, keepalived will demote the node

## Managed By
- Keepalived manifests: dk-alchemy `k8s/edge/keepalived/` (kustomize overlays per node)
- Phantom overlay: `k8s/edge/keepalived/overlays/phantom/`
- Venom overlay: `k8s/edge/keepalived/overlays/venom/`
- Each edge node runs its own independent K3s server (not a shared cluster)
