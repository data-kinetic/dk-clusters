# Edge Route Inventory

## Last Verified
2026-03-23

## TLS Certificates

| Namespace | Certificate | Secret | Ready | Domain |
|-----------|------------|--------|-------|--------|
| agent-mesh-prod | agent-mesh-api-tls | agent-mesh-api-tls | True | agents.behaviorlabs.ai |
| argocd | argocd-tls | argocd-tls | True | argocd.behaviorlabs.ai |
| behaviorlabs-prod | wildcard-behaviorlabs-ai | wildcard-behaviorlabs-ai-tls | True | *.behaviorlabs.ai |
| behaviorlabs-staging | wildcard-preview-behaviorlabs-ai | wildcard-preview-behaviorlabs-ai-tls | True | *.preview.behaviorlabs.ai |
| behaviorlabs-staging | wildcard-staging-behaviorlabs-ai | wildcard-staging-behaviorlabs-ai-tls | True | *.staging.behaviorlabs.ai |
| dk-data-prod | data-behaviorlabs-ai-tls | data-behaviorlabs-ai-tls | True | data.behaviorlabs.ai |
| dk-data-staging | data-staging-behaviorlabs-ai-tls | data-staging-behaviorlabs-ai-tls | True | data.staging.behaviorlabs.ai |
| dkos-staging | wildcard-dev-datakinetic-com | wildcard-dev-datakinetic-com-tls | True | *.dev.datakinetic.com |

All certificates are Ready. Managed by cert-manager with Let's Encrypt DNS-01 (Route53).

## Ingress Routes (Traefik IngressRoute CRD)

| Namespace | Name | Host Match |
|-----------|------|------------|
| dk-mercury-staging | mercury-ingress | mercury.staging.datakinetic.com (PathPrefix /api) |
| dk-phantom-prod | phantom-dashboard | phantom.behaviorlabs.ai |
| dk-phantom-staging | phantom-dashboard | phantom.behaviorlabs.ai |

## Standard Ingresses

| Namespace | Name | Host | TLS | Ports |
|-----------|------|------|-----|-------|
| agent-mesh-prod | agent-mesh-api | agents.behaviorlabs.ai | Yes | 80, 443 |
| argocd | argocd-server-ingress | argocd.behaviorlabs.ai | Yes | 80, 443 |
| behaviorlabs-prod | admin | admin.behaviorlabs.ai | Yes | 80, 443 |
| behaviorlabs-prod | api | api.behaviorlabs.ai | Yes | 80, 443 |
| behaviorlabs-prod | app | app.behaviorlabs.ai | Yes | 80, 443 |
| behaviorlabs-prod | behavior-labs-web | www.behaviorlabs.ai | No | 80 |
| behaviorlabs-staging | admin | admin.staging.behaviorlabs.ai | Yes | 80, 443 |
| behaviorlabs-staging | api | api.staging.behaviorlabs.ai | Yes | 80, 443 |
| behaviorlabs-staging | app | app.staging.behaviorlabs.ai | Yes | 80, 443 |
| behaviorlabs-staging | behavior-labs-web | staging.behaviorlabs.ai, www.staging.behaviorlabs.ai | No | 80 |
| dk-data-prod | dk-data-api | data.behaviorlabs.ai | Yes | 80, 443 |
| dk-data-staging | dk-data-api | data.staging.behaviorlabs.ai | Yes | 80, 443 |
| dkos-staging | dkos-api | api.dev.datakinetic.com | Yes | 80, 443 |
| dkos-staging | dkos-app | app.dev.datakinetic.com | Yes | 80, 443 |
| dkos-staging | dkos-portal | portal.dev.datakinetic.com | Yes | 80, 443 |
| dkos-staging | dkos-web | dev.datakinetic.com | Yes | 80, 443 |
| infra-staging | grafana | grafana.preview.behaviorlabs.ai | Yes | 80, 443 |
| infra | grafana | grafana.behaviorlabs.ai | Yes | 80, 443 |

## Edge Network Topology

```
Internet
  ↓
UDM Pro (port forward 80/443 → VIP 192.168.1.100)
  ↓
phantom (10.0.0.2) ←VRRP→ venom (10.0.0.3)
  VIP: 192.168.1.100
  ↓
Traefik (K3s DaemonSet, ports 80/443)
  ↓
K3s cluster: k3s-master-1 (10.0.0.11), k3s-slave-1 (10.0.0.12)
```

## Domain Summary

| Domain Pattern | Environment | Backend |
|----------------|-------------|---------|
| *.behaviorlabs.ai | Production | K3s cluster |
| *.staging.behaviorlabs.ai | Staging | K3s cluster |
| *.preview.behaviorlabs.ai | Preview/Staging | K3s cluster |
| *.dev.datakinetic.com | DKOS Staging | K3s cluster |
| *.staging.datakinetic.com | Mercury Staging | K3s cluster |
