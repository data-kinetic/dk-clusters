# HA & Resilience

## Context
Production runs on a single K3s node (penguin). A hardware failure, kernel panic, or even a planned maintenance window takes down all services. The target is a 2-node HA cluster across physical hosts (penguin + krang), with scarecrow as a future third node.

## Scope
- Join krang's k3s-slave-1 to cluster (continuation of Fix 4 in Plan 01)
- Configure workload distribution across nodes
- Set up node affinity and pod anti-affinity
- Plan scarecrow provisioning (third node)
- Cross-host storage strategy

## Dependencies
- [Plan 01](01-critical-fixes.md) Fix 4 (k3s-slave-1 join) must complete first
- [Plan 05](05-storage-optimization.md) (storage) — cross-host PVC migration

## Existing Work
- dk-alchemy spec-013 (DC Consolidation HA) — comprehensive 9-phase plan
- dk-alchemy spec-012 (K3s Cluster Reconciliation) — superseded by 013
- dk-planning docs: [disaster-recovery.md](https://github.com/data-kinetic/dk-planning/blob/main/docs/disaster-recovery.md) (multi-cluster capability section)

## Implementation Steps

### Phase 1: 2-Node Cluster (krang join)
1. Complete Plan 01 Fix 4 — k3s-slave-1 joins cluster
2. Verify node labels:
   ```bash
   kubectl label node k3s-slave-1 topology.kubernetes.io/zone=krang
   kubectl label node k3s-master-1 topology.kubernetes.io/zone=penguin
   ```
3. Verify K3s version consistency (match versions across nodes)

### Phase 2: Workload Distribution
4. Add pod anti-affinity to all production Deployments:
   ```yaml
   affinity:
     podAntiAffinity:
       preferredDuringSchedulingIgnoredDuringExecution:
         - weight: 100
           podAffinityTerm:
             labelSelector:
               matchExpressions:
                 - key: app.kubernetes.io/name
                   operator: In
                   values: ["{{service}}"]
             topologyKey: topology.kubernetes.io/zone
   ```
5. Scale critical services to 2+ replicas:
   - behavior-labs-api: 2 replicas (one per node)
   - grafana: 2 replicas
   - All services with HPA: ensure minReplicas >= 2
6. Verify distribution: `kubectl get pods -o wide -A | grep -v Completed`

### Phase 3: Priority Classes
7. Verify priority classes enforced:
   - `production-critical` (1000000): production workloads
   - `staging-default` (100000): staging workloads (can be preempted)
8. Label all production workloads with production-critical priority

### Phase 4: Storage Resilience
9. Current state: PVCs are node-local (local-path provisioner)
10. Problem: PostgreSQL data on penguin cannot failover to krang
11. Options:
    - **Option A: CNPG Standby** — CloudNativePG supports standby replicas on different nodes. Read-replica on krang, promote on failure. Best for databases.
    - **Option B: Proxmox Ceph** — Shared storage across nodes. Any pod can mount any PVC. Requires Ceph setup on both nodes.
    - **Option C: Accept locality** — Keep PVCs node-local, rely on backup/restore for DR. Simplest but highest RTO.
12. **Recommendation:** Option A for PostgreSQL (critical data), Option C for observability backends (ephemeral, 30-day retention)

### Phase 5: Scarecrow (Future Third Node)
13. Provision scarecrow VM (spec-013 P6)
14. Join as K3s agent node
15. With 3 nodes: true HA with 2 of 3 quorum
16. QDevice may be removable with 3-node cluster

## dk-alchemy Changes
- MODIFY: k8s/apps/*/base/deployment.yaml (add anti-affinity)
- MODIFY: k8s/infrastructure/*/base/ (scale critical infra to 2 replicas)
- CREATE: k8s/infrastructure/postgres/overlays/prod/standby.yaml (CNPG standby config)

## Verification
- `kubectl get nodes` shows 2 (or 3) nodes Ready
- `kubectl get pods -o wide` shows production pods distributed across nodes
- Drain one node: `kubectl drain k3s-slave-1 --ignore-daemonsets` — services remain available
- Uncordon and verify pods redistribute
- PostgreSQL standby replica running on krang (if Option A chosen)

## Options/Recommendations
**Storage approach for HA:**
- **Option A (Recommended): CNPG standby for PostgreSQL + local PVCs for everything else.** Provides database HA without the complexity of Ceph. Observability data (Loki, Mimir, Tempo) is ephemeral and can be rebuilt from scratch.
- **Option B: Full Ceph.** True shared storage but significant operational overhead for a 2-node setup.

**Recommendation:** Option A. CNPG standby is database-native, well-documented, and doesn't require additional infrastructure.
