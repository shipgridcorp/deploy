# ShipGrid — On-Prem Helm Chart

Umbrella Helm chart that deploys **ShipGrid** (SDLC + DevSecOps platform) into a
customer-operated Kubernetes cluster, including fully air-gapped environments.

It renders all backend services, an edge gateway (single origin for the SPA +
`/api`), the SPA frontends, an internal-auth Secret, an Ed25519 license Secret,
an optional egress NetworkPolicy, and — for a quick PoC — bundled single-node
infrastructure (PostgreSQL, Redis, Kafka, Neo4j, Qdrant, ClickHouse, Kroki).

- **App / Admin:** one origin behind the gateway, exposed via your Ingress + TLS.
- **LLM:** RU providers (YandexGPT / GigaChat), a self-hosted OpenAI-compatible
  model, or `mock` — foreign providers are blocked by default (152-ФЗ).
- **Licensing:** every backend enforces a signed Ed25519 license at startup.

---

## Distribution model

Two things are distributed to you — **images** and **the chart itself**. Neither
requires access to any private source-code repository.

### 1. Images — pulled from the vendor release registry

Service images are served from the vendor registry
**`registry.shipgrid.app/shipgrid`** (the chart's default `global.registry`).
Only release-ready tags are published there. The registry is authenticated: you
pull with a **per-client, pull-only, revocable robot credential** issued with
your delivery.

```bash
# create the pull secret from the robot credential you were issued
kubectl -n shipgrid create secret docker-registry regcred \
  --docker-server=registry.shipgrid.app \
  --docker-username='robot$<client>' --docker-password='<token>'
```

Then reference it at install with `--set global.imagePullSecrets[0].name=regcred`.

**Air-gapped or registry-policy environments:** mirror the images into your own
registry (Harbor, Nexus, Artifactory…) and override the default:

```bash
--set global.registry=harbor.internal.example.ru/shipgrid
```

The bundled infra images (PostgreSQL, Redis, …) come from their public upstream
registries; mirror those too for a closed network.

### 2. The chart — installed straight from Harbor (OCI), no git clone

The chart is published as an OCI artifact in the same Harbor, so you install it
by reference — you do **not** clone any private repository:

```bash
helm install shipgrid oci://registry.shipgrid.app/charts/shipgrid --version 0.4.4 \
  -n shipgrid --create-namespace \
  -f values-onprem.yaml \
  --set global.imagePullSecrets[0].name=regcred \
  --set-file license.file=license.signed.json \
  --set license.publicKeyHex=<ed25519-pub-hex>
```

Inspect defaults without installing:

```bash
helm show values oci://registry.shipgrid.app/charts/shipgrid --version 0.4.4
```

> Alternatively, install from this kit's local path
> (`helm install shipgrid . -n shipgrid …`). The chart is self-contained; the
> example overrides live in [`values-onprem.yaml`](values-onprem.yaml).

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Kubernetes | 1.27+ |
| Helm | 3.8+ (OCI support) |
| Namespace | one release per namespace (resources use bare names) |
| Registry pull secret | robot credential for `registry.shipgrid.app` (or your mirror) |
| Signed license | `license.signed.json` + Ed25519 public key (hex) |
| Data dependencies | managed/operator PostgreSQL·Redis·Kafka·ClickHouse·Neo4j·Qdrant for production (bundled single-node for PoC) |
| Ingress + TLS | your ingress controller + certificate + DNS record |
| LLM | YandexGPT / GigaChat credentials, a self-hosted model, or `mock` |

Sizing guidance is in the on-prem installation guides at
**https://docs.shipgrid.app**.

---

## Quick start (PoC, bundled infra)

```bash
helm install shipgrid oci://registry.shipgrid.app/charts/shipgrid --version 0.4.4 \
  -n shipgrid --create-namespace \
  --set global.imagePullSecrets[0].name=regcred \
  --set infra.postgres.enabled=true --set infra.redis.enabled=true \
  --set infra.kafka.enabled=true --set infra.neo4j.enabled=true \
  --set infra.qdrant.enabled=true --set infra.clickhouse.enabled=true \
  --set gateway.resolver=$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}') \
  --set-file license.file=license.signed.json --set license.publicKeyHex=<hex>
```

This boots the whole stack with single-node bundled dependencies and `mock` LLM
— enough to validate the install. Harden before production (see below).

---

## Data dependencies

Heavy stateful dependencies are **not** bundled for production. Deploy them (via
your operators/managed services) as Services named **bare** in the namespace —
`postgres`, `redis`, `kafka`, `clickhouse`, `neo4j`, `qdrant` — so the in-cluster
config defaults (`postgres:5432`, `kafka:9092`, `bolt://neo4j:7687`, …) resolve.

For a PoC, the chart can bring single-node versions of each:

```bash
--set infra.postgres.enabled=true    # creates the per-service databases
--set infra.redis.enabled=true
--set infra.kafka.enabled=true       # KRaft single-node
--set infra.neo4j.enabled=true
--set infra.qdrant.enabled=true
--set infra.clickhouse.enabled=true  # LLM usage analytics (admin tab)
--set infra.kroki.enabled=true       # server-side C4 diagram rendering
```

For production, point each service's `DATABASE_URL` at your managed endpoint
via `services.<name>.env.DATABASE_URL` (an explicit `env:` entry always wins
over the URL the chart generates from `services.<name>.db`) and keep
`infra.*.enabled=false`. Peer-*service* URLs (e.g. wiring the security
split-workers) are set via `configs/<name>/config.yaml` + `config: true`
instead — see `configs/security/config.yaml` for a worked example; a commented
example config ships for **every** service under `configs/`.

---

## LLM configuration

| Mode | How |
|---|---|
| **Mock** (default) | `llm.mockEnabled=true` — no real LLM; stub answers, for validating the install |
| **YandexGPT** | `--set llm.yandex.apiKey=… --set llm.yandex.folderId=… --set llm.mockEnabled=false` |
| **GigaChat** | `--set llm.gigachat.authKey=…` `--set llm.gigachat.scope=…`, mount the Russian Trusted Root CA in `llm.gigachat.caFile` |
| **Self-hosted** | run a vLLM/Ollama/TGI OpenAI-compatible endpoint in the namespace, `--set llm.local.baseURL=…` (+ `llm.local.apiKey` if it needs auth), and route your model names via `model_aliases` in [`configs/gate/config.yaml`](configs/gate/config.yaml) |
| **Foreign (non-RU only)** | `--set llm.blockForeignProviders=false --set llm.openai.apiKey=…` (or `llm.anthropic.*`) |

`llm.blockForeignProviders=true` (default) blocks OpenAI/Anthropic stack-wide. A
gate image built with `-tags ru` is the binary-level guarantee for a security
review — it contains no calls to foreign LLMs at all.

---

## Licensing

Every backend enforces a signed Ed25519 license at startup (`shared/license.Gate`,
fail-closed). Provide it at install:

```bash
--set license.enabled=true \
--set-file license.file=license.signed.json \
--set license.publicKeyHex=<ed25519-public-key-hex>
```

The license caps seats and gates modules (`module.*`). Status is exposed on
`billing /readyz` and `GET /internal/license`. Renew by replacing the license
Secret/file — no online activation (works air-gapped); picked up within ~6h or on
restart. The public key is **not** secret; the private signing key stays with the
vendor.

---

## External access

The chart ships an edge `gateway` (nginx) that serves the SPA and proxies `/api`
to the backend Services on one origin, plus Ingress + TLS templates.

```bash
helm upgrade shipgrid oci://registry.shipgrid.app/charts/shipgrid --version 0.4.4 -n shipgrid \
  --set gateway.resolver=$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}') \
  --set frontends.enabled=true \
  --set ingress.enabled=true \
  --set ingress.app.host=shipgrid.example.ru \
  --set ingress.admin.host=admin.shipgrid.example.ru \
  --set ingress.tls.enabled=true --set ingress.tls.secretName=shipgrid-tls
# + a DNS record to the ingress controller, and a TLS secret (cert-manager or manual)
```

- `gateway.resolver` is **required** — set it to your cluster's CoreDNS ClusterIP,
  or the gateway cannot resolve backends.
- `frontends.enabled=true` deploys the SPA images (`:onprem-*`, same-origin API,
  host-agnostic behind the gateway). Without frontends, `/api` works but the SPA
  returns 502.

---

## Production hardening

The chart ships working **development** defaults so it boots out of the box.
Before production:

- **Override the shared secrets** baked into the defaults — `internalAuthSecret`,
  `secrets.jwtSecret`, `secrets.encryptionKey`, and the bundled-DB passwords.
  Supply your own values from a gitignored values file, `--set`, or a secret
  manager (SealedSecrets / External Secrets Operator). Generate fresh values with
  e.g. `openssl rand -hex 32` (internal auth), `openssl rand -base64 32`
  (encryption key). Keep the same value everywhere a secret is referenced.
- **Use managed databases** and point the services at them (`infra.*.enabled=false`).
- **Lock egress:** `--set networkPolicy.enabled=true` with `allowedEgressCIDRs`
  restricted to your LLM endpoint / registry / DB (default-deny otherwise). In a
  full air-gap, allow nothing outbound.
- **TLS** in front of the gateway (Ingress `ingress.tls.enabled=true`).
- **Size for your workload.** `defaults.resources` (100m/192Mi requests,
  500m/512Mi limits per service) is derived from the vendor sizing guide for
  the standard 26-service footprint — see the sizing guide at
  **https://docs.shipgrid.app** and override heavier services individually via
  `services.<name>.resources` if profiling shows they need more (e.g.
  `indexing`, which also runs `replicas: 2`).
- **Scale past one replica where it matters** (`services.<name>.replicas`).
  Every service ships a PodDisruptionBudget (`maxUnavailable: 1`, harmless
  no-op at `replicas: 1`) so node drains don't take out a scaled service
  entirely; disable stack-wide with `defaults.pdb.enabled=false` if your
  policies forbid PDBs.
- **Spread pods across nodes/zones** via `defaults.nodeSelector` /
  `defaults.tolerations` / `defaults.affinity` (or the same three keys per
  service under `services.<name>`) if you run dedicated node pools or want
  anti-affinity across AZs.

> ⚠ Never commit secrets: signed licenses, private keys, LLM credentials, your
> real `internalAuthSecret`, or Russian Trusted Root CA bundles. Keep them in a
> gitignored values file, `--set`, or a SealedSecret/External Secrets.

Every backend Deployment carries `checksum/secrets`, `checksum/site-config`,
and (for `config: true` services) `checksum/config` pod annotations, so
`helm upgrade` after rotating a secret or editing a `configs/<name>/config.yaml`
actually restarts the affected pods — Kubernetes doesn't do this on its own
for `envFrom`/mounted-ConfigMap changes.

Liveness (`/healthz`) and readiness (`/readyz`) probes are wired for every
service out of the box (gate uses `/health` + `/readiness` — see its
`services.gate.probes` override); tune timing via `defaults.probes` or
per-service `services.<name>.probes`.

---

## Configuration reference

| Value | Default | Meaning |
|---|---|---|
| `global.registry` | `registry.shipgrid.app/shipgrid` | image registry (override for an air-gap mirror) |
| `global.imagePullSecrets` | `[]` | pull secret(s) for the registry |
| `secrets.*` | dev defaults | shared JWT / encryption / Redis / Neo4j secrets — **rotate** |
| `site.publicAppURL` / `adminAppURL` | `""` | public origins (deep links / SAML ACS) |
| `adminBootstrap.email` | `""` | first admin-console user (temp password printed once) |
| `llm.blockForeignProviders` | `true` | block OpenAI/Anthropic (152-ФЗ) |
| `llm.yandex.*` / `llm.gigachat.*` | `""` | RU LLM credentials |
| `llm.mockEnabled` | `true` | run with no real LLM (PoC) |
| `license.enabled` / `publicKeyHex` / `file` | `true` / `""` / `""` | Ed25519 license |
| `networkPolicy.enabled` | `false` | default-deny egress except DNS + allowlist |
| `gateway.enabled` / `gateway.resolver` | `true` / CoreDNS IP | edge nginx (set resolver!) |
| `ingress.enabled` / `ingress.app.host` / `ingress.tls.*` | `false` | external access + TLS |
| `frontends.enabled` | `false` | deploy SPA images |
| `infra.<dep>.enabled` | `false` | bundle a single-node PoC dependency |
| `defaults.resources` / `defaults.probes` / `defaults.pdb.enabled` | see values.yaml | per-service overridable resource/probe/PDB baseline |
| `services.<name>.{image,tag,config,db,replicas,resources,probes}` | — | per-service overrides. `db` = the service's logical database (drives the generated `DATABASE_URL`). Peer-service URLs/feature-switches go through `configs/<name>/config.yaml` + `config: true`, not `env:` — see that directory. `env:` is reserved for genuinely install-specific values like a managed-DB `DATABASE_URL` |

See [`values.yaml`](values.yaml) for the complete, commented set and
[`values-onprem.yaml`](values-onprem.yaml) for an example production overlay.

---

## Upgrade / rollback / uninstall

```bash
helm upgrade shipgrid oci://registry.shipgrid.app/charts/shipgrid --version <new> -n shipgrid -f values-onprem.yaml
helm rollback shipgrid <revision> -n shipgrid
helm uninstall shipgrid -n shipgrid          # PVCs of bundled infra are retained; delete manually if desired
```

Validate the chart locally:

```bash
helm lint .
helm template shipgrid . -f values-onprem.yaml >/dev/null
```

---

## Support

Documentation: **https://docs.shipgrid.app** · Product: **https://shipgrid.app**

Licensed, supported on-prem deployment — contact your ShipGrid representative for
registry robot credentials, a signed license, and release tags.

---

## License

This chart is released under the [MIT License](LICENSE). It packages and
configures the deployment of ShipGrid; the ShipGrid service images it references
are proprietary and distributed under a separate commercial license.
