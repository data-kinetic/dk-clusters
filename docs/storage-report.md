# Storage Report

**Generated:** 2026-03-22

## Pool Usage — penguin (10.0.0.11 host)

| Pool | Size | Allocated | Free | Fragmentation | Capacity % | Health |
|------|------|-----------|------|---------------|------------|--------|
| nvfast | 1.81T | 180G | 1.64T | 37% | 9% | ONLINE |
| bulk | 23.6T | 339G | 23.3T | 1% | 1% | ONLINE |

### nvfast breakdown
| Dataset | Used | Available | Quota |
|---------|------|-----------|-------|
| nvfast | 1.13T | 642G | none |
| nvfast/vmfast | 1.13T | 379G | 1.50T |
| nvfast/vmfast/vm-200-disk-0 | 1.13T | 1.32T | - |

**Status:** vmfast was at 92.3% during Phase 0. After quota enforcement (1.5T limit) and cleanup, the pool is now at 9% capacity. The vmfast dataset uses 1.13T of its 1.5T quota — healthy headroom. vm-200-disk-0 is k3s-master-1's virtual disk.

### bulk breakdown (selected)
| Dataset | Used | Available |
|---------|------|-----------|
| bulk/images/vm-101-disk-0 | 266G | 22.8T |
| bulk/images/vm-120-disk-0 | 260G | 23.0T |
| bulk/images/vm-110-disk-0 | 102G | 22.9T |
| bulk/images/vm-130-disk-0 | 81.3G | 22.9T |
| bulk/images | 737G total | 22.8T |

**Status:** bulk pool is effectively empty at 1% utilization. No capacity concerns.

### krang storage
krang does not have ZFS pools. Storage is raw disks (multiple 1.6T HDDs visible via lsblk). k3s-slave-1 uses local-path provisioner which writes to the VM's root filesystem.

## PVC Inventory

### Production (infra namespace)

| PVC | Storage Class | Size | Status | Purpose |
|-----|---------------|------|--------|---------|
| postgres-cluster-1 | local-path-fast | 200Gi | Bound | CNPG primary |
| postgres-cluster-2 | local-path-fast | 200Gi | Bound | CNPG replica |
| postgres-cluster-3 | local-path-fast | 200Gi | Bound | CNPG replica |
| data-redis-0 | local-path-fast | 20Gi | Bound | Redis primary |
| data-redis-1 | local-path-fast | 20Gi | Bound | Redis replica |
| data-redis-2 | local-path-fast | 20Gi | Bound | Redis replica |
| data-loki-0 | local-path-bulk | 500Gi | Bound | Loki storage |
| data-mimir-0 | local-path-bulk | 200Gi | Bound | Mimir storage |
| data-tempo-0 | local-path-bulk | 200Gi | Bound | Tempo traces |
| data-opensearch-0 | local-path-bulk | 200Gi | Bound | OpenSearch |
| data-opensearch-1 | local-path-bulk | 200Gi | Bound | OpenSearch |
| data-opensearch-2 | local-path-bulk | 200Gi | Bound | OpenSearch |
| data-minio-0 | local-path-bulk | 500Gi | Bound | MinIO |
| data-minio-1 | local-path-bulk | 500Gi | Bound | MinIO |
| data-minio-2 | local-path-bulk | 500Gi | Bound | MinIO |
| data-minio-3 | local-path-bulk | 500Gi | Bound | MinIO |
| grafana-data | local-path-bulk | 50Gi | Bound | Grafana |

### Staging (infra-staging namespace)

| PVC | Storage Class | Size | Status | Purpose |
|-----|---------------|------|--------|---------|
| postgres-cluster-1 | local-path-fast | 50Gi | Bound | CNPG (single instance) |
| data-redis-0 | local-path-fast | 10Gi | Bound | Redis |
| data-loki-0 | local-path-bulk | 100Gi | Bound | Loki |
| data-mimir-0 | local-path-bulk | 50Gi | Bound | Mimir |
| data-tempo-0 | local-path-bulk | 50Gi | Bound | Tempo |
| data-opensearch-0 | local-path-bulk | 100Gi | Bound | OpenSearch |
| grafana-data | local-path-bulk | 10Gi | Bound | Grafana |
| minio-pvc | local-path | 10Gi | Bound | MinIO |

## Storage Class Mapping

| Storage Class | Provisioner | Backend | Use Case |
|---------------|-------------|---------|----------|
| local-path (default) | rancher.io/local-path | VM root disk | General (avoid for production) |
| local-path-fast | rancher.io/local-path | NVMe (vmfast) | Databases, high-IOPS workloads |
| local-path-bulk | rancher.io/local-path | HDD (bulk pool) | Observability, backups, large datasets |

### Placement Audit

All PVCs are correctly placed:
- **PostgreSQL** on `local-path-fast` — correct (high-IOPS database)
- **Redis** on `local-path-fast` — correct (low-latency key-value store)
- **Loki, Mimir, Tempo** on `local-path-bulk` — correct (write-heavy, large, ephemeral)
- **OpenSearch** on `local-path-bulk` — correct (search index, large)
- **MinIO (prod)** on `local-path-bulk` — correct (object storage, large)
- **MinIO (staging)** on `local-path` (default) — minor issue, should be `local-path-bulk`
- **Grafana** on `local-path-bulk` — correct (dashboard storage, not I/O sensitive)

## Capacity Alerts — Recommended Thresholds

| Severity | Threshold | Action |
|----------|-----------|--------|
| Warning | Any pool > 75% | Investigate growth, plan cleanup |
| Critical | Any pool > 85% | Immediate action required — cleanup or expand |
| Emergency | Any pool > 90% | Risk of write failures, ZFS performance degradation |

### Current Risk Assessment
- **nvfast:** 9% — no risk
- **bulk:** 1% — no risk
- **Total PVC claims (prod):** ~3,810Gi allocated across storage classes. Actual usage will be lower (thin provisioning).

## Grafana Dashboard Proposal

### Proxmox Storage Monitoring Dashboard

**Data source:** Prometheus (via node_exporter on Proxmox hosts or Alloy scraping Proxmox API)

**Required metrics:**
- `node_filesystem_size_bytes` / `node_filesystem_avail_bytes` (for ZFS datasets mounted as filesystems)
- Or custom Proxmox API metrics via Alloy integration: `proxmox_storage_used_bytes`, `proxmox_storage_total_bytes`

**Panels:**

1. **Pool Overview (Stat panels)**
   - One stat per pool: nvfast, bulk
   - Shows current usage % with color thresholds (green <75%, yellow 75-85%, red >85%)

2. **Pool Usage Over Time (Time series)**
   - Line chart showing usage % for each pool over 30/90 days
   - Enables trend analysis and capacity forecasting

3. **Per-VM Disk Usage (Table)**
   - Columns: VM ID, VM Name, Pool, Disk Size, Used
   - Sorted by used descending

4. **PVC Usage (Table)**
   - Columns: Namespace, PVC Name, Storage Class, Requested Size, Actual Usage
   - Requires kubelet_volume_stats_used_bytes metric

5. **Growth Rate (Stat panel)**
   - Projected days until each pool reaches 85%
   - Formula: `(threshold - current) / avg_daily_growth`

6. **Alerts Panel (Alert list)**
   - Shows active storage alerts

**Alert rules (Prometheus/Alertmanager):**

```yaml
groups:
  - name: storage
    rules:
      - alert: StoragePoolWarning
        expr: (node_filesystem_size_bytes - node_filesystem_avail_bytes) / node_filesystem_size_bytes > 0.75
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Storage pool {{ $labels.mountpoint }} is above 75%"

      - alert: StoragePoolCritical
        expr: (node_filesystem_size_bytes - node_filesystem_avail_bytes) / node_filesystem_size_bytes > 0.85
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Storage pool {{ $labels.mountpoint }} is above 85%"

      - alert: StoragePoolEmergency
        expr: (node_filesystem_size_bytes - node_filesystem_avail_bytes) / node_filesystem_size_bytes > 0.90
        for: 1m
        labels:
          severity: emergency
        annotations:
          summary: "Storage pool {{ $labels.mountpoint }} is above 90% - risk of write failures"
```

**Implementation notes:**
- Proxmox hosts need node_exporter installed, OR
- Use Alloy's `prometheus.exporter.proxmox` integration to scrape Proxmox API
- PVC usage metrics require kubelet stats to be scraped (usually available via kube-prometheus-stack)
