# Edge Failover Runbook

## Last Verified
2026-03-23

## Architecture

```
Internet → UDM Pro (port forward 80/443) → VIP 192.168.1.100
                                              ↓ (VRRP)
                                    phantom (10.0.0.2) — MASTER
                                    venom   (10.0.0.3) — BACKUP (not configured)
                                              ↓
                                    Traefik → K3s cluster (10.0.0.11/12)
```

## Current State

| Component | phantom (10.0.0.2) | venom (10.0.0.3) |
|-----------|-------------------|-------------------|
| Keepalived | Installed, **inactive** | Not installed/configured |
| VIP (192.168.1.100) | Held (static assignment on eth2) | Not configured |
| Traefik | Assumed configured | Status unknown |

**VRRP failover is not operational.** The VIP is held by phantom as a static secondary address, not managed by Keepalived (keepalived is inactive). Venom does not have keepalived configured.

## Failover Test Procedure

### Prerequisites
- Ensure venom has Keepalived installed and configured with matching VRRP instance
- Both nodes must have Traefik configured and routing to K3s cluster
- Have external monitoring ready to verify access during failover

### Test Steps

1. **Verify pre-test state:**
   ```bash
   # On phantom
   ssh penguin 'sudo ssh ubuntu@10.0.0.2 "systemctl status keepalived; ip addr show | grep 192.168.1.100"'
   # On venom
   ssh penguin 'sudo ssh ubuntu@10.0.0.3 "systemctl status keepalived; ip addr show | grep 192.168.1.100"'
   ```

2. **Verify external access works:**
   ```bash
   curl -sk https://app.behaviorlabs.ai/health
   ```

3. **Trigger failover (stop phantom Keepalived):**
   ```bash
   ssh penguin 'sudo ssh ubuntu@10.0.0.2 "sudo systemctl stop keepalived"'
   ```

4. **Verify VIP migration (within 3 seconds):**
   ```bash
   ssh penguin 'sudo ssh ubuntu@10.0.0.3 "ip addr show | grep 192.168.1.100"'
   ```

5. **Verify external access via venom:**
   ```bash
   curl -sk https://app.behaviorlabs.ai/health
   ```

6. **Restore phantom (start Keepalived):**
   ```bash
   ssh penguin 'sudo ssh ubuntu@10.0.0.2 "sudo systemctl start keepalived"'
   ```

7. **Verify VIP returns to phantom (if higher priority):**
   ```bash
   ssh penguin 'sudo ssh ubuntu@10.0.0.2 "ip addr show | grep 192.168.1.100"'
   ```

### Expected Results
- VIP migrates to venom within 3 seconds of phantom Keepalived stop
- External HTTPS access continues without interruption (brief TCP reset acceptable)
- VIP returns to phantom when Keepalived restarts (preempt mode)

### Rollback
If venom fails to accept VIP:
```bash
# Restore phantom immediately
ssh penguin 'sudo ssh ubuntu@10.0.0.2 "sudo systemctl start keepalived"'
# If Keepalived won't start, manually re-add VIP
ssh penguin 'sudo ssh ubuntu@10.0.0.2 "sudo ip addr add 192.168.1.100/24 dev eth2"'
```

## Blockers for Live Testing
1. Keepalived not installed/configured on venom — must be set up before testing
2. Keepalived is inactive on phantom — VIP is static, not VRRP-managed
3. Traefik status on venom unknown — must verify routing works before failover test
