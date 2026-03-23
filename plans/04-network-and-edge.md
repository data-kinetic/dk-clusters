# Network & Edge

## Context
Edge networking is mostly functional (phantom + venom with Traefik + Keepalived) but has several issues: TLS cert not mirrored to staging (#294), venom edge LB may need restoration (#235), UDM IPS category persistence issue (#251), and some hairpin NAT edge cases. A production outage (2026-02-09) was caused by switch port misconfiguration.

## Scope
- TLS certificate lifecycle and mirroring
- Venom edge LB operational status
- VRRP hardening and monitoring
- Hairpin NAT validation
- UDM configuration management
- Edge route documentation

## Dependencies
- Plan 01 (reflector fix) — reflector handles cert mirroring

## Existing Work
- dk-alchemy spec-009 (infra-evolution) — 98% complete, edge networking done
- dk-alchemy: k8s/edge/ (traefik, keepalived, routes)
- dk-alchemy: docs/networking-deep-dive.md
- dk-planning docs: [infrastructure.md](https://github.com/data-kinetic/dk-planning/blob/main/docs/infrastructure.md) (edge LB section)

## Implementation Steps

### Phase 1: TLS Certificate Lifecycle
1. Fix cert mirroring to infra-staging (#294):
   - Requires reflector fix from [Plan 01](https://github.com/data-kinetic/dk-planning/blob/main/plans/dk-alchemy/01-critical-fixes.md)
   - Verify reflector annotation on cert secret: `reflector.v1.k8s.emberstack.com/reflection-allowed: "true"`
   - Verify target namespace: `reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces: "infra-staging"`
2. Document cert renewal process:
   - Let's Encrypt via cert-manager DNS-01 challenge (Route53)
   - Current wildcard: *.behaviorlabs.ai (expires 2026-05-11)
   - Auto-renewal at 30 days before expiry
3. Add Grafana alert for cert expiry < 14 days
4. Add cert-expiry check to sentinel probe (TLS validation)

### Phase 2: Venom Edge LB
5. Verify venom (VM 211, krang, 10.0.0.3) operational status
6. If down: restore Traefik + Keepalived configuration
7. Test failover: stop phantom's Keepalived → VIP should migrate to venom
8. Verify external access continues via venom
9. Restore phantom, verify VIP returns

### Phase 3: VRRP Monitoring
10. Add Keepalived metrics to Alloy scraping (if not already)
11. Create VRRP dashboard in Grafana:
    - VIP ownership per node
    - Failover events
    - Health check status
12. Add alerts:
    - Both nodes claim MASTER (split-brain)
    - No node claims MASTER (total failure)
    - Frequent failover oscillation

### Phase 4: Hairpin NAT Validation
13. Test all access paths from Core LAN (192.168.1.0/24):
    - User device → 192.168.1.100 (VIP) → Traefik → K3s services
    - User device → llm.behaviorlabs.ai → resolves to VIP → works?
14. Document any remaining hairpin issues
15. Add hairpin NAT test to probe-service targets

### Phase 5: UDM Configuration Management
16. Document UDM firewall rules, NAT rules, VLAN config
17. Address IPS category persistence (#251) — DSHIELD/WEB_SERVER changes revert
18. Consider UDM config backup/version control

### Phase 6: Edge Route Documentation
19. Create complete edge route inventory:
    - k3s-production: *.behaviorlabs.ai → 10.0.0.11:443
    - k3s-staging: *.staging.behaviorlabs.ai → 10.0.0.11:443
    - litellm: llm.behaviorlabs.ai → 192.168.10.50:4000
    - preview-stack: *.preview.behaviorlabs.ai → 10.0.0.51:80
    - datakinetic-preview: *.preview.datakinetic.com → 10.0.0.51:80
    - enercore: *.enercore.ai → 10.0.0.51:80
    - dkos-dev: *.dev.datakinetic.com → 192.168.10.88:80
20. Add route inventory to dk-alchemy docs

## dk-alchemy Changes
- MODIFY: k8s/infrastructure/reflector/ (cert mirroring annotations)
- CREATE: grafana/dashboards/infrastructure/edge-networking.json (VRRP dashboard)
- CREATE: grafana/alerts/edge.yaml (VRRP alerts, cert expiry)
- CREATE: docs/edge-route-inventory.md
- CREATE: docs/udm-configuration.md

## Verification
- TLS cert present in infra-staging namespace
- Cert expiry alert fires at < 14 days
- Failover test: phantom down → VIP migrates to venom → external access works
- Hairpin NAT: Core LAN devices can access *.behaviorlabs.ai
- Edge route inventory is complete and accurate
