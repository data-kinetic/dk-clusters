# Backup & Disaster Recovery

## Context
No automated backup testing, no off-site replication, and the sentinel probe (external monitoring) is blocked by SSH connectivity issues. [disaster-recovery.md](https://github.com/data-kinetic/dk-planning/blob/main/docs/disaster-recovery.md) defines RTO/RPO targets that aren't being met because no backups are verified.

## Scope
- Configure PostgreSQL automated backups (CNPG)
- Set up off-site backup replication (S3 or remote)
- Implement automated restore testing
- Complete sentinel probe deployment
- Document and test DR runbook

## Dependencies
- [Plan 01](01-critical-fixes.md) (critical fixes) — stable cluster first
- [Plan 02](02-ha-and-resilience.md) (HA) — multi-node for restore testing namespace

## Existing Work
- dk-alchemy spec-014 (sentinel probe deployment)
- dk-alchemy: scripts/sentinel/ (operational scripts exist)
- dk-planning docs: [disaster-recovery.md](https://github.com/data-kinetic/dk-planning/blob/main/docs/disaster-recovery.md) (bootstrap order, RTO/RPO targets)
- dk-alchemy issues: #239 (off-site replication), #243 (restore testing)

## Implementation Steps

### Phase 1: PostgreSQL Automated Backups
1. Configure CNPG scheduled backups:
   ```yaml
   # k8s/infrastructure/postgres/base/cluster.yaml
   spec:
     backup:
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
       retentionPolicy: "30d"
     scheduledBackup:
       - name: daily-backup
         schedule: "0 2 * * *"
         backupOwnerReference: self
   ```
2. Verify: `kubectl get backups -n infra` shows daily backups
3. Set up Grafana alert for backup failures

### Phase 2: Off-Site Replication (#239)
4. Configure MinIO mc mirror to external S3:
   ```bash
   mc alias set offsite https://s3.amazonaws.com ACCESS_KEY SECRET_KEY
   mc mirror --watch minio/dk-backups offsite/dk-offsite-backups
   ```
5. Schedule via CronJob in K8s or cron on dk-shared-services VM
6. Verify: external bucket receives backup files within 4 hours (RPO target)
7. Set up alert if mirror falls behind

### Phase 3: Automated Restore Testing (#243)
8. Create weekly CronJob: backup -> restore to test namespace -> validate -> cleanup
   ```yaml
   # k8s/infrastructure/postgres/base/restore-test-cronjob.yaml
   apiVersion: batch/v1
   kind: CronJob
   metadata:
     name: postgres-restore-test
     namespace: infra
   spec:
     schedule: "0 4 * * 0"  # Weekly Sunday 4 AM
     jobTemplate:
       spec:
         template:
           spec:
             containers:
               - name: restore-test
                 image: ghcr.io/data-kinetic/dk-alchemy/restore-tester:latest
                 # Script: restore backup, run validation queries, report, cleanup
   ```
9. Build restore-tester image in dk-alchemy/src/restore-tester/
10. Report results to Slack and create Grafana annotation

### Phase 4: Sentinel Probe Deployment (spec-014)
11. Resolve SSH connectivity blocker to AWS instance
12. Deploy sentinel probe service (dk-alchemy/src/sentinel-probe/)
13. Configure targets: all production endpoints from external perspective
14. Configure WireGuard VPN tunnel for internal monitoring
15. Set up Alloy on sentinel to push metrics to Mimir
16. Create sentinel Grafana dashboard

### Phase 5: DR Runbook & Testing
17. Finalize DR runbook in dk-alchemy/docs/disaster-recovery-runbook.md:
    - 16-step bootstrap order (Proxmox -> K3s -> ArgoCD -> infra -> apps)
    - Per-data-store restoration procedures
    - RTO/RPO targets by tier:
      - Critical (behavior-labs-ai): 4h RTO, 1h RPO
      - Important (LiteLLM, DNS): 8h RTO, 4h RPO
      - Standard (staging, observability): 24h RTO, 4h RPO
18. Schedule DR tests:
    - Weekly: PostgreSQL restore test (automated)
    - Quarterly: ArgoCD full rebuild from git
    - Monthly: Edge LB failover test
    - Annually: Full cluster rebuild from scratch

## dk-alchemy Changes
- MODIFY: k8s/infrastructure/postgres/base/cluster.yaml (add backup config)
- CREATE: k8s/infrastructure/postgres/base/restore-test-cronjob.yaml
- CREATE: src/restore-tester/ (restore validation container)
- CREATE: grafana/alerts/backup.yaml (backup failure alerts)
- CREATE: docs/disaster-recovery-runbook.md
- MODIFY: k8s/infrastructure/sentinel-probe/ (deployment manifests)

## Verification
- `kubectl get backups -n infra` shows successful daily backups
- Off-site S3 bucket has backups less than 4 hours old
- Weekly restore test CronJob completes successfully
- Sentinel probe dashboard shows all production endpoints UP from external
- DR runbook successfully tested (quarterly ArgoCD rebuild)

## Options/Recommendations
**Off-site backup target:**
- **Option A (Recommended): AWS S3** — durable, cheap, accessible from sentinel for DR. Use lifecycle rules for cost optimization (Standard -> IA after 30d -> Glacier after 90d).
- **Option B: Second on-prem NAS** — lower latency but same site risk (fire, flood, power).
- **Option C: Backblaze B2** — cheaper than S3, S3-compatible API, works with mc mirror.

**Recommendation:** Option A for production data (S3 durability guarantees). Consider Option C for cost-sensitive bulk data (observability archives).
