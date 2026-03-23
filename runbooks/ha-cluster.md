# HA Cluster Runbook

## Current Cluster State

**Last verified:** 2026-03-22

| Node | Role | IP | Zone Label | Status | K3s Version |
|------|------|----|------------|--------|-------------|
| k3s-master-1 | control-plane, master | 10.0.0.11 | penguin | Ready | v1.33.6+k3s1 |
| k3s-slave-1 | agent | 10.0.0.12 | krang | Ready | v1.33.6+k3s1 |

**Pod distribution (2026-03-22):**
- k3s-master-1: ~243 pods (all application workloads)
- k3s-slave-1: ~5 pods (DaemonSets + reflector + probe replicas)

**Observation:** Workloads are heavily concentrated on k3s-master-1. Only DaemonSets (alloy, svclb-traefik) and a few replicas (reflector, probe) run on k3s-slave-1. This is because:
1. Topology zone labels were not applied until 2026-03-22 — anti-affinity rules had no effect.
2. Most deployments lack pod anti-affinity or use `preferredDuringScheduling` which won't move existing pods.
3. All PVCs are bound to k3s-master-1 via local-path provisioner — stateful workloads cannot migrate without PVC recreation.

**Priority Classes:**

| Name | Value | Purpose |
|------|-------|---------|
| system-node-critical | 2000001000 | K3s system components |
| system-cluster-critical | 2000000000 | Cluster-level services |
| production-critical | 1000000 | Production workloads |
| staging-default | 100000 | Staging workloads (preemptible) |

**CNPG PostgreSQL:**

| Namespace | Cluster | Instances | Status | Current Nodes |
|-----------|---------|-----------|--------|---------------|
| infra | postgres-cluster | 3 | Healthy | All on k3s-master-1 |
| infra-staging | postgres-cluster | 1 | Healthy | k3s-master-1 |

CNPG prod cluster has `enablePodAntiAffinity: true` with `topologyKey: topology.kubernetes.io/zone`. Now that zone labels are applied, new CNPG pods should prefer spreading to k3s-slave-1. However, existing pods will not move automatically — a rolling restart or failover is needed. **Note:** CNPG replicas require PVCs on the target node; local-path provisioner will create new PVCs on k3s-slave-1 only if pods are scheduled there.

## How to Verify HA is Working

### Node Health
```bash
ssh penguin 'sudo ssh ubuntu@10.0.0.11 "kubectl get nodes -o wide"'
```
Both nodes should show `Ready`. If a node shows `NotReady` for >5 minutes, investigate.

### Topology Labels
```bash
ssh penguin 'sudo ssh ubuntu@10.0.0.11 "kubectl get nodes --show-labels"' | grep topology
```
Expected: `topology.kubernetes.io/zone=penguin` on k3s-master-1, `topology.kubernetes.io/zone=krang` on k3s-slave-1.

### Pod Distribution
```bash
ssh penguin 'sudo ssh ubuntu@10.0.0.11 "kubectl get pods -A -o wide --no-headers"' | awk '{print $8}' | sort | uniq -c | sort -rn
```
Healthy HA: significant pods on both nodes (not 95%+ on one node).

### CNPG Replica Status
```bash
ssh penguin 'sudo ssh ubuntu@10.0.0.11 "kubectl get clusters.postgresql.cnpg.io -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,INSTANCES:.spec.instances,READY:.status.readyInstances,PHASE:.status.phase"'
ssh penguin 'sudo ssh ubuntu@10.0.0.11 "kubectl get pods -n infra -l cnpg.io/cluster=postgres-cluster -o wide"'
```
Healthy: all instances running, at least one replica on k3s-slave-1 (after redistribution).

### DaemonSets
```bash
ssh penguin 'sudo ssh ubuntu@10.0.0.11 "kubectl get daemonsets -A"'
```
DESIRED should equal CURRENT and READY for all DaemonSets.

## Drain / Maintenance Procedure

### Pre-Drain Checklist
1. Verify both nodes are Ready
2. Verify critical pods have replicas on the other node
3. Ensure CNPG has a healthy standby on the other node (if draining the primary's node)
4. Notify team — services may experience brief interruption

### Drain a Node (Example: k3s-slave-1)
```bash
# Cordon first (prevent new scheduling)
ssh penguin 'sudo ssh ubuntu@10.0.0.11 "kubectl cordon k3s-slave-1"'

# Drain (evict pods gracefully)
ssh penguin 'sudo ssh ubuntu@10.0.0.11 "kubectl drain k3s-slave-1 --ignore-daemonsets --delete-emptydir-data --grace-period=60"'

# Perform maintenance...

# Uncordon when done
ssh penguin 'sudo ssh ubuntu@10.0.0.11 "kubectl uncordon k3s-slave-1"'
```

### Drain k3s-master-1 (CAUTION)
k3s-master-1 runs the control plane. Draining it will:
- Evict all application pods (they can reschedule to k3s-slave-1)
- K3s server process continues running (drain only affects pods, not the K3s process)
- All PVCs using local-path on k3s-master-1 will become unavailable — pods with those PVCs will be Pending on k3s-slave-1

**Current risk:** Draining k3s-master-1 today would cause downtime for ALL stateful services (PostgreSQL, Redis, Loki, Mimir, Tempo, OpenSearch, Grafana, MinIO) because their PVCs are local to k3s-master-1.

### What Happens on Drain Today

| Component | Impact of draining k3s-master-1 | Impact of draining k3s-slave-1 |
|-----------|---|----|
| Application pods (stateless) | Reschedule to k3s-slave-1 | ~5 pods reschedule to k3s-master-1 |
| PostgreSQL (CNPG) | DOWN — PVCs bound to master | No impact (not running there yet) |
| Redis | DOWN — PVCs bound to master | No impact |
| Observability (Loki/Mimir/Tempo) | DOWN — PVCs bound to master | No impact |
| DaemonSets (Alloy, svclb) | Ignored by drain | Ignored by drain |

## Failover Testing Procedure

### Safe Test: Drain k3s-slave-1
This is safe because almost nothing runs there today:
```bash
# 1. Record current state
ssh penguin 'sudo ssh ubuntu@10.0.0.11 "kubectl get pods -A -o wide --no-headers | grep k3s-slave-1"'

# 2. Drain
ssh penguin 'sudo ssh ubuntu@10.0.0.11 "kubectl drain k3s-slave-1 --ignore-daemonsets --delete-emptydir-data"'

# 3. Verify pods moved
ssh penguin 'sudo ssh ubuntu@10.0.0.11 "kubectl get pods -A -o wide --no-headers | grep k3s-slave-1"'
# Should only show DaemonSet pods

# 4. Uncordon
ssh penguin 'sudo ssh ubuntu@10.0.0.11 "kubectl uncordon k3s-slave-1"'

# 5. Verify pods return
ssh penguin 'sudo ssh ubuntu@10.0.0.11 "kubectl get pods -A -o wide --no-headers | grep k3s-slave-1"'
```

### Future Test: CNPG Failover (Once Standby on krang)
```bash
# Trigger CNPG switchover (promotes standby, demotes primary)
ssh penguin 'sudo ssh ubuntu@10.0.0.11 "kubectl cnpg promote postgres-cluster -n infra --instance postgres-cluster-2"'

# Monitor failover
ssh penguin 'sudo ssh ubuntu@10.0.0.11 "kubectl get pods -n infra -l cnpg.io/cluster=postgres-cluster -o wide -w"'
```

### Full DR Test (Planned Downtime Required)
1. Announce maintenance window
2. Drain k3s-master-1
3. Verify services that CAN run on k3s-slave-1 are running
4. Document which services are down (PVC-bound)
5. Uncordon k3s-master-1
6. Verify full recovery

## Next Steps for Improved HA
1. **Redistribute workloads:** Rolling restart deployments with anti-affinity now that zone labels are applied
2. **CNPG standby on krang:** Rolling restart CNPG cluster so at least 1 replica schedules to k3s-slave-1
3. **Scale critical stateless services to 2+ replicas** with anti-affinity
4. **Consider Longhorn or Ceph** for cross-node PVC access (eliminates PVC locality problem)
