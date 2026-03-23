# VM Inventory

Complete inventory of all virtual machines across the Data Kinetic Proxmox cluster.

Last updated: 2026-03-23

## penguin VMs

| VMID | Name | vCPU | RAM | Disk | Storage | HA | Role |
|------|------|------|-----|------|---------|-----|------|
| 100 | litellm-server | 16 | 64G | 500G | bulk-images | Yes | LLM proxy |
| 101 | preview-stack | 32 | 128G | 500G | bulk-images | No | Preview envs |
| 102 | dk-shared-services | 24 | 96G | 500G | bulk-images | No | Shared services |
| 200 | k3s-master-1 | 32 | 128G | 1T | nvfast | No | K3s control plane |
| 210 | phantom | 2 | 2G | 10G | local-lvm | No | Edge LB (Traefik + Keepalived) |
| 9000 | ubuntu-22.04-template | 2 | 2G | 2.2G | bulk-images | No | VM template |

## krang VMs

| VMID | Name | vCPU | RAM | Disk | Storage | HA | Role |
|------|------|------|-----|------|---------|-----|------|
| 201 | k3s-slave-1 | 12 | 64G | 250G | local-lvm | No | K3s worker (vmbr1 + vmbr2) |
| 211 | venom | 2 | 2G | 10G | local-lvm | No | Edge LB — Traefik + Keepalived (vmbr1 + vmbr2 + vmbr3) |
| 220 | vllm-minimax | 64 | 256G | 500G + 2TB models | local-lvm + models zvol | No | vLLM inference — 8× A100 GPU passthrough (vmbr0) |

## Recommendations

### 1. HA Policy — k3s-master-1 (VM 200) should have HA enabled

VM 200 runs the production K3s control plane. It currently has HA disabled, meaning it will not auto-restart on node failure. This is the highest-priority change.

**Action:** Enable HA for VM 200 in Proxmox:
```bash
ha-manager add vm:200 --state started --group proxmox-ha
```

### 2. preview-stack (VM 101) is overprovisioned

32 vCPU and 128G RAM for a docker-compose preview environment is excessive. Unless running many concurrent preview stacks, this could be halved (16 vCPU / 64G) to free resources for other workloads.

**Action:** Monitor actual usage via `htop` or Proxmox metrics, then right-size.

### 3. dk-shared-services (VM 102) role needs clarification

VM 102 has significant resources (24 vCPU / 96G) but its role is unclear. The services running on it need to be audited to determine whether they should migrate to K3s or remain standalone.

**Action:** SSH into 192.168.10.52 and audit:
```bash
docker ps
systemctl list-units --type=service --state=running
```

### 4. VM template should be updated to Ubuntu 24.04

VM 9000 (ubuntu-22.04-template) uses Ubuntu 22.04 LTS. Ubuntu 24.04 LTS is available with a newer kernel and support through 2029.

**Recommended approach:**
- Create a new template (VM 9001) with Ubuntu 24.04 LTS
- Pre-install: qemu-guest-agent, docker, cloud-init
- Harden: SSH key-only auth, no password, unattended-upgrades
- Keep VM 9000 until all existing VMs are migrated or decommissioned

### 5. litellm-server (VM 100) may be overprovisioned

16 vCPU and 64G RAM for an LLM proxy (which forwards requests, not runs models) seems high. Worth monitoring actual resource usage.

### 6. Naming convention

Current names are generally clear. The plan recommends a `dk-<role>-<host>` format, but renaming carries risk of breaking DNS, configs, and hostnames. Recommendation: keep existing names unless a rename is part of a larger migration.

## Resource Summary

| Host | Total vCPU Allocated | Total RAM Allocated | VM Count |
|------|---------------------|--------------------|----|
| penguin | 108 | 420G | 6 (incl. template) |
| krang | 78 | 322G | 3 |
| **Total** | **186** | **742G** | **9** |
