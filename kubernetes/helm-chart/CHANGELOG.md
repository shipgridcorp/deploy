# Changelog

All notable changes to the ShipGrid on-prem Helm chart are documented here.
This chart follows [Semantic Versioning](https://semver.org/); the `appVersion`
tracks the ShipGrid platform release.

## 0.4.2 — 2026-07-04

Env-driven first admin + optional pentest infrastructure (parity with the SaaS).

### Added
- **Deterministic first-admin seed.** Set `adminBootstrap.email` + a new
  `adminBootstrap.password` and a post-install/upgrade **hook Job**
  (`templates/admin-seed.yaml`) upserts the admin-console admin directly
  (bcrypt via pgcrypto) — the client owns the first admin from values/env, no
  scraping the random temp password from the admin-auth log. `forcePasswordChange`
  toggles must-change-on-first-login. `adminBootstrap.db.*` targets a managed
  admin-auth DB when `infra.postgres.enabled=false`.
- **`scripts/reset-admin.sh`** — standalone reset/seed of a system admin
  (email+password) for both K8s and Compose installs.
- **Optional pentest helpers** (`pentest.*`), matching the SaaS deployment:
  - `pentest.zap.enabled` → OWASP ZAP daemon (DAST). Self-contained; the
    security service auto-discovers it at `http://zap:8080`. Safe in an isolated
    contour.
  - `pentest.oob.enabled` → self-hosted interactsh OOB/OAST server for
    blind-vuln detection; wires `PENTEST_OOB_SERVER_URL`/`PENTEST_OOB_DOMAIN`
    onto the security pod. Requires `pentest.oob.domain` + `pentest.oob.publicIP`
    (public IP + NS/glue DNS delegation) — a template guard fails fast otherwise.
    Not usable fully air-gapped; the rest of the pentest engine still runs.

## 0.4.1 — 2026-07-04

Bundled-infra and image-pin fixes found during an on-prem reinstall on a small
(4 vCPU / 8 GB, no-GPU) cluster.

### Changed
- **Kafka image → `apache/kafka:4.3.1`** (was the deprecated, unmaintained
  `bitnamilegacy/kafka:3.7`). The bundled Kafka StatefulSet is rewritten for the
  official image: `KAFKA_`-prefixed config env (not Bitnami's `KAFKA_CFG_*`),
  `KAFKA_LOG_DIRS=/var/lib/kafka/data`, `fsGroup: 1000`, a pinned `CLUSTER_ID`,
  and — critically — the data volume is mounted via `subPath: kafka-data` so the
  ext4 `lost+found` at the PVC root doesn't trip Kafka's "not a topic-partition"
  log-dir check (same class of fix as `PGDATA=<mount>/pgdata` for Postgres).
- **`indexing` tag pinned to `v1.61.0`** — the previous `v1.64.0` default is
  referenced in docs but not published to `registry.shipgrid.app`.
- **`security` resources** raised to 2Gi memory (from the 512Mi default): its
  bundled semgrep/checkov scanners OOM under 512Mi during real scans. Note its
  `/readyz` runs a live scan per tool and the Python scanners can overrun the
  service's internal probe timeout on CPU-constrained nodes — gate k8s readiness
  on `/healthz` there (per-service `probes.readiness.path` in your overlay).

### Notes
- The dedicated `local` LLM provider needs `gate ≥ v1.24.0` /
  `ai-analysis ≥ v1.249.0` (see `docs/local-models.md`). Until those images are
  published, route a self-hosted OpenAI-compatible endpoint (vLLM/Ollama) through
  the built-in `openai` provider with a `base_url` override and
  `blockForeignProviders: false` — inference still stays in-cluster.

## 0.4.0 — 2026-07-03

Production-readiness pass: every backend service now gets real health checks,
sane resource defaults, disruption protection, and rollouts that actually pick
up config/secret changes.

### Added
- **Liveness/readiness probes** on every backend Deployment (`/healthz` +
  `/readyz`; `gate` uses `/health` + `/readiness`), tunable via
  `defaults.probes` or per-service `services.<name>.probes`.
- **Resource requests/limits** by default (100m/192Mi requests, 500m/512Mi
  limits — sized off the vendor sizing guide for the 26-service footprint),
  replacing the previous empty `{}` (BestEffort QoS). Override per service via
  `services.<name>.resources`.
- **PodDisruptionBudget** per backend service (`maxUnavailable: 1`; a no-op at
  `replicas: 1`, real protection once scaled up). Disable stack-wide with
  `defaults.pdb.enabled=false`.
- **`checksum/secrets` / `checksum/site-config` / `checksum/config`** pod
  annotations so `helm upgrade` after rotating a secret or editing a
  `configs/<name>/config.yaml` actually restarts the affected pods (Kubernetes
  doesn't roll pods on `envFrom`/mounted-ConfigMap content changes by itself).
- `defaults`/per-service `nodeSelector`, `tolerations`, `affinity` pass-through.
- Container `securityContext` (`allowPrivilegeEscalation: false`, drop `ALL`
  capabilities) on every backend pod.
- `automountServiceAccountToken: false` on every backend pod (none call the
  Kubernetes API).
- `configs/security/config.yaml` wiring the six extracted security-platform
  microservice URLs (policy-engine, proof-engine, cloud-scanner, k8s-scanner,
  runtime-collector, findings-correlator) through `security`'s ConfigMap.

### Changed
- `secrets.redisURL` now derives from `secrets.redisPassword`
  (`redis://:<redisPassword>@redis:6379/0`) when left empty, instead of being
  a separately hardcoded string that had to be kept in sync by hand — rotating
  `redisPassword` alone no longer breaks `gate`'s Redis auth.
- Removed raw per-service `env:` overrides for peer-service URLs on
  `platform` (redundant with its own code default) and `security` (moved to
  `configs/security/config.yaml`, matching the chart's own documented
  override convention). `indexing`'s `PLATFORM_URL` override was removed too
  — fixed upstream (indexing v1.64.0 now defaults `services.platform_url` to
  `http://platform:8000` like every other service).
- `values-onprem.yaml` now includes `secrets.*` rotation placeholders (it
  previously only rotated `internalAuthSecret`, silently leaving the other
  shared secrets on dev defaults).

## 0.3.0 — 2026-07-02

First public release of the chart as a standalone repository.

### Changed
- **Default image registry** is now the vendor release registry
  `registry.shipgrid.app/shipgrid` (Harbor). Pull with a per-client, pull-only
  robot credential; air-gapped installs mirror the images and override
  `global.registry`.
- Documented the full **distribution model** in the README: install the chart by
  OCI reference (`helm install shipgrid oci://registry.shipgrid.app/charts/shipgrid`)
  — no source-repository clone required.

### Added
- `kubeVersion` (>= 1.27), `home`/`sources` and Artifact Hub annotations in `Chart.yaml`.

### Removed
- Customer-specific values overlay (kept out of the public chart — supply your own
  values file at install time; see `values-onprem.yaml` for a template).
