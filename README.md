<div align="center">

# ShipGrid · Deploy

**Deployment kit for running [ShipGrid](https://shipgrid.app) in your own perimeter** —
Docker Compose on a single VM, a production Kubernetes cluster, or a fully air-gapped environment.

[![License: MIT](https://img.shields.io/badge/license-MIT-8a5cff)](LICENSE)
[![Docker Compose v2](https://img.shields.io/badge/docker%20compose-v2-2496ed?logo=docker&logoColor=white)](compose/)
[![Kubernetes 1.27+](https://img.shields.io/badge/kubernetes-1.27%2B-326ce5?logo=kubernetes&logoColor=white)](kubernetes/)
[![Helm 3.8+](https://img.shields.io/badge/helm-3.8%2B-0f1689?logo=helm&logoColor=white)](kubernetes/helm-chart/)
[![Air-gapped ready](https://img.shields.io/badge/air--gapped-ready-047857)](airgap/)

[Documentation](https://docs.shipgrid.app) · [Product](https://shipgrid.app)

</div>

---

The on-prem delivery runs the whole ShipGrid stack inside **your** perimeter:
your data never leaves it, AI works through an RF-resident LLM (YandexGPT /
GigaChat) or a model self-hosted on your GPUs, and foreign LLM providers are
blocked by default.

Pick a scenario, open its folder, follow its README.

## Pick your scenario

| Scenario | Folder | Best for | Where data lives |
|---|---|---|---|
| **A · Single VM** — Docker Compose | [`compose/`](compose/) | PoC, pilots, small/medium teams | your VM |
| **B · Kubernetes** — Helm chart | [`kubernetes/`](kubernetes/) | enterprise, HA, your own cluster | your cluster |
| **C · Air-gapped** — Compose *or* K8s | [`airgap/`](airgap/) | isolated perimeters, no internet | your isolated segment |

```
deploy/
├── compose/            Scenario A — the full stack on one VM (installer, smoke test, configs)
├── kubernetes/         Scenario B — umbrella Helm chart + production values
│   └── helm-chart/     the chart itself (also published as an OCI artifact)
├── airgap/             Scenario C — bundle verification & registry mirroring
└── scripts/            shared tooling (secret rotation)
```

## Quick starts

**Single VM (Scenario A):**

```bash
cd compose
cp .env.example .env          # license, LLM credentials, public URLs
./install.sh                  # preflight → pull → up → smoke test
# App → http://localhost:8080   Admin → http://localhost:8081
```

**Kubernetes (Scenario B)** — from this kit or straight from the OCI registry:

```bash
cd kubernetes/helm-chart
helm install shipgrid . -n shipgrid --create-namespace \
  -f values-onprem.yaml \
  --set global.imagePullSecrets[0].name=regcred \
  --set-file license.file=license.signed.json
# the license public key is embedded in the images — no publicKeyHex needed
```

**Air-gapped (Scenario C)** — verify the delivered bundle, then install with no
internet at all:

```bash
sha256sum -c shipgrid-onprem-images.tar.gz.sha256
cd compose && ./install.sh --bundle ../shipgrid-onprem-images.tar.gz      # C1: single VM
# or mirror into your internal registry for Kubernetes (C2):
./airgap/mirror-to-registry.sh --bundle shipgrid-onprem-images.tar.gz harbor.internal/shipgrid
```

## What you receive with the delivery

| Artifact | Purpose |
|---|---|
| Pull credentials for `registry.shipgrid.app` | authenticated vendor registry with release-ready images (or an image bundle for air-gap) |
| `license.signed.json` | offline-verified license — **every** backend service verifies it at startup against the public key embedded in the images; no activation servers. Missing/invalid fails closed; expired degrades to restricted (read-only) mode |
| Release tag set | the tested image versions, pinned as defaults in this kit |
| *ShipGrid On-Prem Installation Guide* | scenarios, hardware sizing, LLM options |

## Hardware at a glance

| Profile | vCPU | RAM | Disk |
|---|---|---|---|
| Minimum (PoC, single VM) | 16 | 32 GB | 100 GB SSD |
| Single VM, recommended | 16–24 | 64 GB | 150 GB SSD |
| Kubernetes, production (total) | 32 | 64 GB | 250 GB |
| Kubernetes, with headroom | 48+ | 128 GB | 500 GB+ |

GPU is needed **only** for a self-hosted LLM (full air-gap without a cloud RF
LLM): 1× A100/H100-class 80 GB for a 14–32B model.

## LLM options

| Mode | What it takes |
|---|---|
| **Mock** (default) | nothing — the stack runs with stub AI answers, for validating the install |
| **YandexGPT** | API key + folder id; egress to Yandex Cloud |
| **GigaChat** | auth key + scope + Russian Trusted Root CA; egress to Sber Cloud |
| **Self-hosted** | vLLM/Ollama/TGI on your GPU node — OpenAI-compatible endpoint inside the perimeter, zero egress |
| Foreign (non-RU installs only) | OpenAI/Anthropic keys with `BLOCK_FOREIGN_LLM=false` |

Self-hosted wiring: set the endpoint (`LOCAL_LLM_BASE_URL` in Compose /
`llm.local.baseURL` in Helm) and route your model names to it via
`model_aliases` in the gate config — see `config/gate/config.yaml` (Compose) or
`configs/gate/config.yaml` (Helm).

Which model each feature uses is controlled by **roles**: services request
`auto:chat`, `auto:chat-light` or `auto:embeddings` and the gate substitutes
the active model. Roles are assigned **only in the admin console** (AI
Settings → Providers → tag a model with the role) — applied to all services
live; there is no file or env fallback, and an unassigned role fails with a
clear error pointing at the console. Embedding vector dimensions are
discovered automatically; switching the embeddings model rebuilds vector
collections — re-index afterwards.

## Configuration model

Every service boots from built-in defaults + the shared environment (secrets,
site URLs, license). A per-service config file overrides specific fields
(precedence: **file → env → default**). The kit ships a commented example
config for **every** service — `compose/config/<service>/config.yaml` and
`kubernetes/helm-chart/configs/<service>/config.yaml`; keep only the keys you
change.

## Before production

Dev defaults boot out of the box; production needs four things (details in each
scenario README):

1. **Rotate the shared secrets** — `./scripts/rotate-secrets.sh`, apply via
   `.env` (Compose) or a gitignored values file (Helm).
2. **TLS** in front of the entrypoints (reverse-proxy / Ingress).
3. **Egress lockdown** — allow only your LLM endpoint and registry; in air-gap,
   nothing.
4. **Backups** of the data volumes / databases — and they stay in your perimeter.

> ⚠️ Never commit secrets to this repository: licenses, LLM credentials, rotated
> secret values, CA bundles. `.gitignore` already covers the usual suspects.

## Support

Contact your ShipGrid representative for registry credentials, a signed license
and release tags. Documentation: **[docs.shipgrid.app](https://docs.shipgrid.app)**.

## License

The deployment kit (this repository) is [MIT](LICENSE). The ShipGrid service
images it deploys are proprietary and distributed under a separate commercial
license.
