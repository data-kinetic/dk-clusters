# Disaster Recovery Runbook

## Last Verified
2026-03-23

## Current Backup State

### PostgreSQL (CNPG)
- **Scheduled backups:** None configured
- **Manual backups:** None found
- **Barman object store:** Not configured
- **WAL archiving:** Not configured

### MinIO
- **Status:** Running in infra namespace
- **Existing backups:** None found (mc ls returned empty/error)
- **Replication:** None configured

### ArgoCD
- **Git-based state:** All application definitions in dk-alchemy repo
- **Recovery method:** Re-bootstrap from git (no data loss for config)

### Grafana
- **Dashboards:** Stored in ConfigMaps via ArgoCD (recoverable from git)
- **Data (Mimir):** No backup configured

## Bootstrap Order (Full Cluster Recovery)

| Step | Component | Action | Depends On |
|------|-----------|--------|------------|
| 1 | Proxmox | Restore from Proxmox Backup Server or reinstall | Hardware |
| 2 | Network | Verify UDM firewall rules, VLANs, NAT | Proxmox |
| 3 | VMs | Create k3s-master-1 (10.0.0.11), k3s-slave-1 (10.0.0.12) | Proxmox |
| 4 | Edge VMs | Create phantom (10.0.0.2), venom (10.0.0.3) | Proxmox |
| 5 | ZFS pools | Import or recreate nvfast, bulk on penguin | Proxmox |
| 6 | NFS exports | Mount NFS shares into VMs for PVCs | ZFS |
| 7 | K3s master | Install K3s on k3s-master-1, apply zone labels | VMs |
| 8 | K3s agent | Join k3s-slave-1 to cluster | K3s master |
| 9 | cert-manager | Install cert-manager, configure Route53 DNS-01 | K3s |
| 10 | ArgoCD | Install ArgoCD, connect dk-alchemy repo | K3s |
| 11 | Doppler | Install doppler-operator, configure service tokens | ArgoCD |
| 12 | CNPG | Deploy postgres-cluster (restore from backup if available) | ArgoCD |
| 13 | MinIO | Deploy MinIO | ArgoCD |
| 14 | Infra services | Grafana, Alloy, Mimir, kube-state-metrics, reflector | ArgoCD |
| 15 | Edge LB | Configure Traefik + Keepalived on phantom/venom | Edge VMs |
| 16 | Applications | Sync all app-of-apps via ArgoCD | All infra |

## RTO/RPO Targets

| Tier | Examples | RTO | RPO |
|------|----------|-----|-----|
| Critical | behavior-labs-ai (prod), PostgreSQL | 4 hours | 1 hour |
| Important | LiteLLM, DNS/DDNS, ArgoCD | 8 hours | 4 hours |
| Standard | Staging envs, observability, Grafana | 24 hours | 4 hours |

**Current reality:** Without automated backups, actual RPO for PostgreSQL data is unbounded (full data loss possible). ArgoCD config RPO is near-zero (stored in git).

## Per-Data-Store Recovery Procedures

### PostgreSQL Recovery
**If CNPG backups are configured (future):**
```bash
# Restore from barman backup
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-cluster
  namespace: infra
spec:
  instances: 3
  bootstrap:
    recovery:
      source: postgres-cluster
  externalClusters:
    - name: postgres-cluster
      barmanObjectStore:
        destinationPath: s3://dk-backups/postgres/
        endpointURL: http://minio.infra.svc.cluster.local:9000
        s3Credentials:
          accessKeyId:
            name: minio-credentials
            key: access-key
          secretAccessKey:
            name: minio-credentials
            key: secret-key
EOF
```

**Current (no backups):**
- PostgreSQL data lives on local-path PVCs on k3s-master-1
- If the underlying storage (nvfast ZFS pool) survives, PVCs can be remounted
- If nvfast is lost, all PostgreSQL data is lost

### ArgoCD Recovery
```bash
# Reinstall ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Reconnect repo and sync
argocd repo add https://github.com/data-kinetic/dk-alchemy.git --ssh-private-key-path ~/.ssh/id_ed25519
argocd app sync app-of-apps
```

### MinIO Recovery
- Stateless deployment; data stored on PVC
- Re-deploy via ArgoCD, restore data from off-site backup (if configured)

## Test Schedule

| Test | Frequency | Procedure | Owner |
|------|-----------|-----------|-------|
| PostgreSQL restore | Weekly (once configured) | Restore latest backup to test namespace, validate row counts | Auto (CronJob) |
| ArgoCD rebuild | Quarterly | Delete ArgoCD namespace, reinstall, verify all apps sync | Manual |
| Edge LB failover | Monthly | See runbooks/edge-failover.md | Manual |
| Full cluster rebuild | Annually | Full Proxmox restore, follow bootstrap order | Manual |

## Critical Gaps (Action Required)

1. **No PostgreSQL backups** — CNPG scheduled backups must be configured (see plan 03-backup-and-dr.md Phase 1)
2. **No off-site replication** — MinIO mirror to external S3 not configured
3. **No automated restore testing** — Restore test CronJob not built
4. **Sentinel probe not deployed** — External monitoring blocked by SSH connectivity
5. **Keepalived not configured on venom** — No VRRP failover capability
