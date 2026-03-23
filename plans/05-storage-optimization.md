# Storage Optimization

## Context
vmfast (NVMe ZFS pool) is at 92.3% capacity — nearly all consumed by k3s-master-1 (VM 200, 1.08TB). ZFS performance degrades above 80% and risks write failures. Additionally, storage classes need review for optimal placement of different workload types.

## Scope
- Immediate vmfast capacity relief
- K3s storage class optimization
- Capacity monitoring and alerting
- Long-term storage strategy (including Ceph consideration)

## Dependencies
- None for immediate fixes
- Plan 02 (HA) for cross-host storage

## Existing Work
- dk-alchemy spec-007 (storage consolidation)
- dk-alchemy: proxmox-cluster/storage-plan.md
- dk-planning docs: [infrastructure.md](https://github.com/data-kinetic/dk-planning/blob/main/docs/infrastructure.md) (storage classes section)

## Implementation Steps

### Phase 1: Immediate Capacity Relief
1. Audit vmfast usage:
   ```bash
   ssh penguin 'zfs list -r vmfast -o name,used,refer,mountpoint -s used'
   ssh penguin 'zfs list -t snapshot vmfast -o name,used -s used'
   ```
2. Delete old/unused snapshots:
   ```bash
   ssh penguin 'zfs list -t snapshot vmfast | grep -v "^NAME"'
   # Review and delete: zfs destroy vmfast/vm-200-disk-0@snapshot-name
   ```
3. Trigger TRIM to reclaim freed blocks:
   ```bash
   ssh penguin 'zpool trim vmfast'
   ```
4. Check if thin provisioning is inflating reported usage:
   ```bash
   ssh penguin 'zfs get volsize,used,referenced vmfast/vm-200-disk-0'
   ```

### Phase 2: VM Disk Migration (if needed)
5. If vmfast remains > 85% after cleanup:
   - **Option A (Recommended): Move k3s-master-1 to local-lvm**
     - local-lvm has 1.67TB at 7.6% — plenty of space
     - LVM-thin is faster than ZFS for VM disks (no compression overhead)
     - Procedure: snapshot → clone to local-lvm → update VM config → verify → delete old
   - **Option B: Add NVMe to vmfast pool**
     - Requires physical access and NVMe slot availability
     - Best for long-term capacity
   - **Option C: Shrink VM disk**
     - Risky, requires careful data migration within the VM
6. After migration, verify k3s-master-1 boots and K3s starts normally

### Phase 3: K8s Storage Class Review
7. Current storage classes:
   - `local-path-fast`: NVMe (vmfast) → databases, high-IOPS
   - `local-path-bulk`: HDD (bulk-images) → observability backends, backups
8. Verify PVC placement:
   - PostgreSQL should be on `local-path-fast` ✓
   - Redis should be on `local-path-fast` ✓
   - Loki (500Gi) should be on `local-path-bulk` ✓
   - Mimir (200Gi) should be on `local-path-bulk` ✓
   - Tempo (200Gi) should be on `local-path-bulk` ✓
   - OpenSearch (100Gi) should be on `local-path-bulk` ✓
9. If any PVCs are on wrong storage class, plan migration

### Phase 4: Capacity Monitoring
10. Create Grafana dashboard for Proxmox storage:
    - Per-pool usage percentage
    - Growth rate (projected time to full)
    - Per-VM disk usage breakdown
11. Create alerts:
    - Warning: any pool > 75%
    - Critical: any pool > 85%
    - Emergency: any pool > 90%
12. Data source: node_exporter on Proxmox hosts or Proxmox API scraping via Alloy

### Phase 5: Long-term Strategy
13. Evaluate Ceph for cross-host shared storage (spec-013 P7)
14. If Ceph: requires at least 3 nodes (penguin + krang + scarecrow) for quorum
15. Alternative: CNPG standby replicas ([Plan 02](https://github.com/data-kinetic/dk-planning/blob/main/plans/dk-alchemy/02-ha-and-reliability.md)) for database HA without Ceph
16. Keep local-path provisioner for non-critical workloads (simpler, faster)

## dk-alchemy Changes
- MODIFY: proxmox-cluster/storage-plan.md (update with current state)
- CREATE: grafana/dashboards/infrastructure/proxmox-storage.json
- CREATE: grafana/alerts/storage.yaml
- Potentially MODIFY: k8s/infrastructure/storage-classes/ (if restructuring)

## Verification
- vmfast usage < 85% after cleanup/migration
- Grafana storage dashboard shows all pools with usage
- Alert fires when test condition exceeds 75%
- All PVCs on appropriate storage classes
- K3s operates normally after any disk migrations
