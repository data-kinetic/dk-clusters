# CLAUDE.md

Guidance for Claude Code when working in the dk-clusters repository.

## Project Overview

dk-clusters manages the Proxmox cluster infrastructure for Data Kinetic: host configuration, VM lifecycle, storage, networking, K3s cluster operations, and disaster recovery across **penguin** and **krang**.

## Cluster Inventory

### penguin (Node 1 — Primary)
- **IP:** 192.168.10.8 | **SSH:** `ssh penguin`
- **CPU:** AMD EPYC 7773X (64C/128T) | **RAM:** 995 GiB
- **Role:** K3s master, shared services, edge LB (phantom)
- **VMs:** k3s-master-1 (200), litellm (100), preview-stack (101), dk-shared-services (102), phantom (210)
- **Storage ALERT:** vmfast NVMe at 92.3% — see plans/01-critical-fixes.md

### krang (Node 2 — GPU/Compute)
- **IP:** 192.168.10.100 | **SSH:** `ssh krang`
- **CPU:** AMD EPYC 7763 × 2 (128C/256T) | **RAM:** 1 TiB | **GPUs:** 8× A100
- **Role:** K3s worker (PENDING JOIN #292), edge LB (venom), GPU inference
- **VMs:** k3s-slave-1 (201, NOT JOINED), venom (211), vllm-minimax (220)

### Network Bridges
| Bridge | Network | CIDR | Purpose |
|--------|---------|------|---------|
| vmbr0 | Corpnet | 192.168.10.0/24 | Management, inter-node routing |
| vmbr1 | Cluster | 10.0.0.0/24 | K3s internal (virtual, no physical uplink) |
| vmbr2 | DMZ | 172.16.100.0/24 | Ingress, Keepalived VIPs |
| vmbr3 | Core LAN | 192.168.1.0/24 | Hairpin access |

### SSH Access Patterns
```bash
ssh penguin                              # Proxmox node 1
ssh krang                                # Proxmox node 2
ssh -J penguin ubuntu@10.0.0.11          # K3s master
ssh -J penguin ubuntu@10.0.0.12          # K3s slave (krang)
ssh vm100-litellm                        # LiteLLM VM
ssh vm101-preview-stack                  # Preview stack VM
ssh -J penguin ubuntu@10.0.0.2           # phantom edge LB
ssh -J krang ubuntu@10.0.0.3             # venom edge LB
```

## Repository Structure

```
dk-clusters/
├── plans/                 # Implementation plans (from dk-planning)
├── scripts/
│   ├── validate-cluster.sh   # K3s node/pod/storage/VIP validation
│   └── health-check.sh       # Proxmox + K3s + ArgoCD health check
├── docs/
│   └── doppler-alignment.md  # Cluster-related Doppler config
├── penguin/               # (planned) Host-specific configs
├── krang/                 # (planned) Host-specific configs
├── shared/                # (planned) Cross-host configs (corosync, keepalived, templates)
├── runbooks/              # (planned) DR, maintenance, failover procedures
└── monitoring/            # (planned) Proxmox-specific dashboards/alerts
```

## Sibling Repositories

| Repo | Local Path | Purpose | Relationship |
|------|-----------|---------|-------------|
| [dk-planning](https://github.com/data-kinetic/dk-planning) | `/Users/nick/Code/dk-planning` | Docs + plans (source of truth) | Plans originate here |
| [dk-alchemy](https://github.com/data-kinetic/dk-alchemy) | `/Users/nick/Code/dk-alchemy` | K8s manifests, ArgoCD, observability | Runs ON this cluster |
| [dk-template](https://github.com/data-kinetic/dk-template) | `/Users/nick/Code/dk-template` | Repo scaffolding | Uses this cluster |

## Implementation Plan

This repo tracks **dk-clusters** workstream from `dk-planning/01-implementation-plan-baseline.md`:

| Phase | Issues | Focus |
|-------|--------|-------|
| Phase 0 (P0) | #1-#4 | Fix reflector, Alloy scraping, vmfast, join krang |
| Phase 1 | #5-#6 | HA cluster, storage optimization |
| Phase 2 | #7-#8 | Backup/DR, network hardening |
| Phase 3 | #9 | VM lifecycle |

```bash
# Check current milestone progress
gh api repos/data-kinetic/dk-clusters/milestones --jq '.[] | "\(.title): \(.open_issues) open, \(.closed_issues) closed"'

# Check P0 blockers
gh issue list --repo data-kinetic/dk-clusters --label priority/p0

# Check what dk-alchemy issues depend on cluster work
gh issue list --repo data-kinetic/dk-alchemy --label priority/p0
```

## Cross-Repo Impact

Changes in dk-clusters affect dk-alchemy directly:
- **Joining k3s-slave-1 (#4)** enables dk-alchemy HA workload distribution
- **Fixing Alloy (#2)** restores dk-alchemy observability for app namespaces
- **Storage changes (#3, #6)** affect dk-alchemy PVC placement
- **Network changes (#8)** affect dk-alchemy edge routes and TLS

Always check dk-alchemy impact before making infrastructure changes:
```bash
# Check dk-alchemy ArgoCD sync status
ssh -J penguin ubuntu@10.0.0.11 'kubectl get applications -n argocd --no-headers' 2>/dev/null

# Check dk-alchemy infrastructure components
ssh -J penguin ubuntu@10.0.0.11 'kubectl get pods -n infra --no-headers' 2>/dev/null
```

## Doppler Config

| Project | Config | Used By |
|---------|--------|---------|
| `dk-cluster` | `prd` | ArgoCD admin, repo credentials |
| `dk-infrastructure` | `prd` | All infra DopplerSecrets |
| `00-dk-tools` | `prd` | LiteLLM (VM100) |

## Validation

Run before and after infrastructure changes:
```bash
./scripts/validate-cluster.sh    # Node, pod, storage, VIP checks
./scripts/health-check.sh        # Full Proxmox + K3s + ArgoCD health
```

## Working Conventions

- **SSH first, then edit.** Verify current state via SSH before writing configs.
- **Test on staging.** If possible, test changes in infra-staging namespace first.
- **Drain before maintenance.** Always `kubectl drain` before node work.
- **Document runbooks.** Every non-trivial operation gets a runbook in runbooks/.
- **Check VIPs after network changes.** Keepalived failover must be verified.
- **Never skip backups.** Snapshot VMs before destructive operations.
