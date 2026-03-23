# Critical Fixes (P0)

## Context
Four P0 issues threaten production stability: reflector crash loop blocks secret mirroring, Alloy scraping gap blinds us to app-layer metrics, vmfast at 92.3% risks storage exhaustion for the K3s master, and k3s-slave-1 on krang isn't joined to the cluster (zero HA).

## Scope
- Fix reflector CrashLoopBackOff (#290)
- Fix Alloy namespace scraping (#295)
- Address vmfast storage capacity (92.3%)
- Join k3s-slave-1 to cluster (#292)

## Dependencies
None — these are all independent and should start immediately.

## Implementation Steps

### Fix 1: Reflector CrashLoopBackOff (#290)
**Issue:** reflector pod has been crash-looping for 10+ days, blocking secret/configmap mirroring
**Impact:** TLS certs and GHCR pull secrets not propagated to app namespaces

1. SSH to k3s-master-1: `ssh -J penguin ubuntu@10.0.0.11`
2. Check reflector logs: `kubectl logs -n infra deployment/reflector --previous`
3. Common causes:
   - RBAC insufficient — check ClusterRole permissions
   - Resource exhaustion — check pod resource limits
   - CRD version mismatch — verify reflector version matches CRD
4. Restart reflector: `kubectl rollout restart deployment/reflector -n infra`
5. If persistent: delete and redeploy from dk-alchemy manifests
6. Verify: `kubectl get pods -n infra -l app=reflector` shows Running
7. Verify: secrets propagated to app namespaces: `kubectl get secrets -A | grep ghcr`

### Fix 2: Alloy Namespace Scraping (#295)
**Issue:** Alloy only scrapes `infra` namespace — all app namespaces (behaviorlabs-prod, dk-data-prod, etc.) have no metrics in Mimir
**Impact:** No application-level dashboards, alerts don't fire for app services

1. Review Alloy config: `dk-alchemy/k8s/infrastructure/alloy/base/values.yaml`
2. Check Kubernetes service discovery config — likely has namespace filter restricting to `infra`
3. Fix: Remove namespace restriction from pod/service discovery, or add explicit namespace list
4. Options:
   - **Option A (Recommended):** Remove namespace filter — scrape all namespaces with `prometheus.io/scrape: "true"` annotation
   - **Option B:** Explicit namespace list — add each app namespace. More controlled but requires updates when namespaces change.
5. Apply config change and verify: `kubectl rollout restart daemonset/alloy -n infra`
6. Verify: `curl -s http://mimir:8080/api/v1/query?query=up | jq` shows targets from app namespaces
7. Verify: Grafana application dashboards populate with data

### Fix 3: vmfast Storage (92.3%)
**Issue:** vmfast ZFS pool (NVMe) at 92.3% — k3s-master-1 (VM 200) uses ~1.08TB of 1.2TB
**Impact:** ZFS performance degrades severely above 80%, risk of write failures

1. Immediate: Check current usage: `ssh penguin 'zpool list vmfast'`
2. Identify what's consuming space: `ssh penguin 'zfs list -r vmfast -o name,used,referenced,mountpoint'`
3. Quick wins:
   - Clean up old snapshots: `zfs list -t snapshot vmfast`
   - Trim deleted blocks: `zpool trim vmfast`
4. Medium-term options:
   - **Option A (Recommended):** Migrate k3s-master-1 boot disk to bulk-images or local-lvm — frees vmfast entirely
   - **Option B:** Add NVMe capacity to vmfast pool — requires physical hardware change
   - **Option C:** Shrink k3s-master-1 disk — destructive, requires backup/restore
5. Set up capacity alert: Grafana alert when any ZFS pool exceeds 80%
6. See [Plan 05](05-storage-optimization.md) for comprehensive storage strategy

### Fix 4: Join k3s-slave-1 (#292)
**Issue:** k3s-slave-1 (VM 201 on krang, 10.0.0.12) is not joined to the K3s cluster
**Impact:** Zero HA — all production workloads on single node, any penguin failure = full outage

1. SSH to krang: `ssh krang` (192.168.10.100)
2. SSH to k3s-slave-1: `ssh ubuntu@10.0.0.12`
3. Check K3s agent status: `sudo systemctl status k3s-agent`
4. If not installed:
   ```bash
   curl -sfL https://get.k3s.io | K3S_URL=https://10.0.0.11:6443 \
     K3S_TOKEN=$(ssh ubuntu@10.0.0.11 'sudo cat /var/lib/rancher/k3s/server/node-token') \
     INSTALL_K3S_VERSION="v1.33.6+k3s1" \
     sh -s - agent
   ```
5. If installed but not connecting: check network routes from krang to 10.0.0.11 (cluster network)
6. Verify cross-host routing: `ping -c 3 10.0.0.11` from k3s-slave-1
7. If routing fails: verify iptables forwarding rules on both penguin and krang (vmbr0 <-> vmbr1)
8. Verify: `kubectl get nodes` shows 2 nodes Ready
9. After join: schedule workloads across both nodes with pod anti-affinity

## dk-alchemy Changes
- MODIFY: k8s/infrastructure/alloy/base/values.yaml (namespace scraping)
- Potentially MODIFY: k8s/infrastructure/reflector/ (if config change needed)

## Verification
- `kubectl get pods -n infra -l app=reflector` -> Running (not CrashLoopBackOff)
- `kubectl get secrets -n behaviorlabs-prod` shows mirrored secrets
- Grafana app dashboards show metrics for behaviorlabs-prod namespace
- `zpool list vmfast` shows < 85% usage after cleanup/migration
- `kubectl get nodes` shows 2 nodes: k3s-master-1 + k3s-slave-1
