# Doppler Alignment for Cluster Infrastructure

## Cluster-Related Doppler Projects

| Project | Config | Used By | Secrets |
|---------|--------|---------|---------|
| `dk-cluster` | `prd` | ArgoCD | Admin password, server URL, repo PAT |
| `dk-infrastructure` | `prd` | All infra DopplerSecrets | GHCR creds, DB passwords, service tokens |
| `00-dk-tools` | `prd` | LiteLLM (VM100) | LITELLM_MASTER_KEY |

## DopplerSecret Token Distribution

The Doppler Operator uses a token secret in each namespace to authenticate with Doppler SaaS:

| Namespace | Token Secret | Doppler Project |
|-----------|-------------|----------------|
| `infra` | `doppler-token-secret` | `dk-infrastructure` |
| `argocd` | `doppler-token-secret` | `dk-cluster` |
| `behaviorlabs-prod` | `doppler-token-secret` | `behaviorlabs-applications` |
| `behaviorlabs-staging` | `doppler-token-secret` | `behaviorlabs-applications` |

## Validation

Run `scripts/validate-cluster.sh` to verify DopplerSecret CRDs are synced and secrets are propagated.
