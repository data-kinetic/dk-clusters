# dk-clusters — Proxmox Cluster Management Plans

## Overview

[`dk-clusters`](https://github.com/data-kinetic/dk-clusters) manages the Proxmox cluster infrastructure: host configuration, VM lifecycle, storage, networking, K3s cluster operations, and disaster recovery for both **penguin** and **krang**.

This directory contains prioritized plans to align the current state with dk-planning documentation and resolve critical infrastructure gaps. The `dk-clusters` repo will be the operational home for cluster configs, scripts, and runbooks.

## Cluster Inventory

### penguin (Node 1 — Primary)
- **IP:** 192.168.10.8
- **CPU:** AMD EPYC 7773X (64C/128T)
- **RAM:** 995 GiB
- **Role:** K3s master, shared services, edge LB (phantom)
- **VMs:** k3s-master-1 (200), litellm (100), preview-stack (101), dk-shared-services (102), phantom (210)
- **Storage:** vmfast NVMe (92.3% CRITICAL), local-lvm (7.6%), bulk-images 24TB (0.5%)

### krang (Node 2 — GPU/Compute)
- **IP:** 192.168.10.100
- **CPU:** AMD EPYC 7763 × 2 (128C/256T)
- **RAM:** 1 TiB
- **GPUs:** 8× NVIDIA A100
- **Role:** K3s worker (pending join #292), edge LB (venom), GPU inference
- **VMs:** k3s-slave-1 (201, NOT JOINED), venom (211), vllm-minimax (220, 8× A100)
- **Storage:** local-lvm, bulk-images, nvfast (NVMe), models (2TB ZFS zvol)

### Quorum
- **QDevice:** 192.168.1.5:5403 (TLS, ffsplit algorithm)
- **Votes:** penguin (1) + krang (1) + QDevice (1) = 3 total, 2 required

## Priority Matrix

| # | Plan | Priority | Impact | Urgency | Issues |
|---|------|----------|--------|---------|--------|
| 01 | [Critical Fixes](01-critical-fixes.md) | P0 | Critical | This week | #290, #292, #295, vmfast |
| 02 | [HA & Resilience](02-ha-and-resilience.md) | P1 | Critical | This sprint | #292, spec-013 |
| 03 | [Backup & DR](03-backup-and-dr.md) | P1 | High | This month | #239, #243, spec-014 |
| 04 | [Network & Edge](04-network-and-edge.md) | P2 | Medium | Next sprint | #294, #251, spec-009 |
| 05 | [Storage Optimization](05-storage-optimization.md) | P1 | High | This sprint | vmfast 92.3%, spec-007 |
| 06 | [VM Lifecycle](06-vm-lifecycle.md) | P3 | Low | Backlog | spec-013 |

## Dependency Graph

```
01-Critical Fixes (P0, immediate)
  ├── 02-HA & Resilience (requires reflector + metrics fixed, krang join)
  │     └── 03-Backup & DR (requires multi-node for restore testing)
  └── 05-Storage Optimization (vmfast fix enables further work)

04-Network & Edge (independent)
06-VM Lifecycle (independent, low priority)
```

## Key Decision

**K3s cluster expansion:** Fix krang join first (#292) to get 2-node HA across physical hosts. Scarecrow added later as third node. No new K3s nodes on same host (same-host HA provides no hardware redundancy).

## dk-clusters Repository Structure

The [`dk-clusters`](https://github.com/data-kinetic/dk-clusters) repo will contain:

```
dk-clusters/
├── README.md                           # Cluster overview, host inventory
├── penguin/
│   ├── network/                        # Bridge configs, routes, iptables rules
│   ├── storage/                        # ZFS pool configs, storage class definitions
│   └── vms/                            # VM configs, cloud-init templates
├── krang/
│   ├── network/
│   ├── storage/
│   ├── vms/
│   └── gpu/                            # GPU passthrough config, vLLM setup
├── shared/
│   ├── corosync/                       # Cluster quorum config
│   ├── keepalived/                     # VRRP templates (source of truth for edge LBs)
│   └── templates/                      # VM templates (Ubuntu 24.04 cloud-init)
├── scripts/
│   ├── backup/                         # Proxmox backup scripts
│   ├── health/                         # Cluster health checks
│   ├── provision/                      # VM provisioning automation
│   └── storage/                        # Storage management utilities
├── runbooks/
│   ├── disaster-recovery.md            # Full DR procedure
│   ├── node-maintenance.md             # Drain, update, reboot procedures
│   ├── storage-expansion.md            # Adding storage to pools
│   ├── vm-migration.md                 # Moving VMs between hosts
│   └── edge-failover.md               # VRRP failover testing
└── monitoring/
    ├── dashboards/                     # Proxmox-specific Grafana dashboards
    └── alerts/                         # Storage, node, VRRP alerts
```

## Alignment with dk-planning Docs

| dk-planning Doc | Gap | Plan |
|----------------|-----|------|
| infrastructure.md | Single-node cluster, no HA | 02 |
| infrastructure.md | vmfast at 92.3% | 01, 05 |
| observability.md | Alloy namespace gap | 01 |
| disaster-recovery.md | No backup testing | 03 |
| disaster-recovery.md | No off-site replication | 03 |
| disaster-recovery.md | No sentinel probe | 03 |
| infrastructure.md | Edge LB venom status | 04 |
| platform-overview.md | VM naming inconsistent | 06 |

## Alignment with dk-alchemy Specs

| Spec | Status | Plan |
|------|--------|------|
| 007-storage-consolidation | Draft | 05 |
| 009-infra-evolution | 98% complete | 04 |
| 012-k3s-cluster-reconciliation | Superseded by 013 | 02 |
| 013-dc-consolidation-ha | In progress | 02, 06 |
| 014-sentinel-probe-deployment | SSH blocker | 03 |

## Related Plans

- [dk-alchemy plans](https://github.com/data-kinetic/dk-planning/blob/main/plans/dk-alchemy/) — platform-level implementation plans
- [dk-template plans](https://github.com/data-kinetic/dk-planning/blob/main/plans/dk-template/) — repo scaffolding
