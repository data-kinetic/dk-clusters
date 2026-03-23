# VM Lifecycle Management

## Context
VMs have generic names (k3s-master-1, dk-shared-services), no consistent naming convention, inconsistent HA policies, and the ubuntu template (VM 9000) may be outdated. dk-alchemy spec-013 recommends renaming and standardizing.

## Scope
- VM naming convention
- HA policy review
- Template VM updates
- dk-shared-services (VM 102) role clarification
- VM resource right-sizing

## Dependencies
- None (independent, low priority)

## Existing Work
- dk-alchemy spec-013 (DC Consolidation) — naming conventions
- dk-alchemy: proxmox-cluster/dk-cluster-overview.md (current VM inventory)

## Implementation Steps

### Phase 1: Naming Convention
1. Define naming standard:
   - Format: `dk-<role>-<host>[-<instance>]`
   - Examples:
     - VM 200: `k3s-master-1` → `dk-k3s-penguin` (or keep as-is if renaming is disruptive)
     - VM 201: `k3s-slave-1` → `dk-k3s-krang`
     - VM 210: `phantom` → keep (edge LB identity)
     - VM 211: `venom` → keep (edge LB identity)
     - VM 100: `litellm-server` → keep (clear purpose)
     - VM 101: `preview-stack` → keep (clear purpose)
     - VM 102: `dk-shared-services` → clarify role below
2. **Recommendation:** Only rename if renaming doesn't break references (hostnames in configs, DNS, etc.). Edge LBs and service VMs should keep current names.

### Phase 2: HA Policy Review
3. Current HA status:
   - VM 100 (litellm): HA = yes, started ✓
   - VM 101 (preview-stack): HA = no ← should this be HA?
   - VM 102 (dk-shared-services): HA = no ← should this be HA?
   - VM 200 (k3s-master-1): HA = no ← SHOULD be HA (production K3s)
   - VM 210 (phantom): HA = no ← acceptable (edge LB can failover via VRRP)
4. **Recommendations:**
   - VM 200 (k3s-master-1): **Enable HA** — this is the production cluster, auto-restart on node failure
   - VM 100 (litellm): Keep HA ✓
   - VM 101 (preview-stack): Keep no-HA — previews are non-critical
   - VM 102 (dk-shared-services): Evaluate — what services does it run?
   - VM 210 (phantom): Keep no-HA — Keepalived handles failover

### Phase 3: dk-shared-services (VM 102) Role
5. Identify what runs on VM 102 (192.168.10.52):
   - SSH: `ssh ubuntu@192.168.10.52` (via proxmox jump)
   - Check running services: `docker ps`, `systemctl list-units --type=service`
6. Document its role and services
7. Determine if services should migrate to K3s or stay standalone
8. If mostly unused: consider decommissioning to free resources

### Phase 4: Template VM Update
9. Check current template (VM 9000, ubuntu-22.04-template):
   - Ubuntu 22.04 LTS — still supported but 24.04 LTS is available
   - cloud-init configured? qemu-guest-agent installed?
10. Create updated template:
    - Base: Ubuntu 24.04 LTS
    - Pre-installed: qemu-guest-agent, docker, cloud-init
    - Hardened: SSH key only, no password auth, auto-updates
11. Keep old template until all VMs migrated

### Phase 5: Resource Right-Sizing
12. Review VM resource allocation vs actual usage:
    | VM | Allocated | Question |
    |----|-----------|----------|
    | litellm (100) | 16 vCPU, 64GB | Is this needed for a proxy? Monitor actual usage |
    | preview-stack (101) | 32 vCPU, 128GB | Heavily overprovisioned for docker-compose? |
    | dk-shared-services (102) | 24 vCPU, 96GB | What does it even do? |
    | k3s-master-1 (200) | 32 vCPU, 128GB | Runs all K3s — likely appropriate |
    | phantom (210) | 2 vCPU, 2GB | Minimal for Traefik + Keepalived ✓ |
13. Right-size based on actual metrics (if Proxmox exporter or node_exporter data available)
14. Freed resources can be allocated to new VMs or k3s worker nodes

## dk-alchemy Changes
- MODIFY: proxmox-cluster/dk-cluster-overview.md (naming, HA policies, resource notes)
- Potentially MODIFY: Proxmox VM configs (HA settings)

## Verification
- All VMs documented with role, resources, HA status
- k3s-master-1 HA enabled (auto-restart on node failure)
- dk-shared-services role documented and decision made (keep/decommission)
- VM template updated to Ubuntu 24.04 LTS
- Resource utilization reviewed and right-sized where appropriate

## Options/Recommendations
**VM template OS:**
- **Option A (Recommended): Ubuntu 24.04 LTS** — latest LTS, supported until 2029, better kernel for modern hardware
- **Option B: Stay on 22.04** — known working, avoids upgrade risk
**Recommendation:** Create 24.04 template alongside existing 22.04. Use for new VMs, migrate existing VMs during maintenance windows.
