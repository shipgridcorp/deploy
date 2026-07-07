# Changelog

All notable changes to the ShipGrid on-prem Helm chart are documented here.
This chart follows [Semantic Versioning](https://semver.org/); the `appVersion`
tracks the ShipGrid platform release.

## 0.4.12 — 2026-07-07

### Changed
- **Prometheus metric namespace renamed `devflow_*` → `shipgrid_*`.** Bundled
  Grafana dashboards and baseline alert rules updated to match. Requires service
  images built from shared ≥ v0.86.0 (they emit `shipgrid_*`); align the image
  pins to that release set.

## 0.4.11 — 2026-07-07

### Added
- **Observability (bundle + BYO).** New opt-in `observability.monitoring.enabled`
  bundles Prometheus + Grafana (ShipGrid dashboards) + Jaeger all-in-one, with a
  lean baseline alert set (service-down, 5xx rate, p95 latency). Pods now carry
  `prometheus.io/scrape` annotations (`observability.monitoring.scrapeAnnotations`)
  so a bring-your-own Prometheus discovers every service's `/metrics`.
- **Client-configurable trace export.** `observability.tracing.*` values (rendered
  into the shared `shipgrid-config` ConfigMap as `OTEL_*` env) control the OTLP
  endpoint, protocol, auth headers, TLS, head-sampling ratio, error-only mode,
  per-service on/off, and PII body-redaction — mapping 1:1 to the admin console's
  Observability page. Applied on pod restart. Default trace target is the bundled
  Jaeger when the monitoring stack is on.

## 0.4.10 — 2026-07-06

### Changed
- **First-admin bootstrap requires a password from a secret — no log fallback.**
  The admin-auth image no longer generates a one-time password and prints it to
  the log. Seed the first admin via `adminBootstrap.email` + `adminBootstrap.password`
  (the seed Job upserts it deterministically; the password is never logged). With
  `adminBootstrap.password` empty, no admin is created. The redundant
  `BOOTSTRAP_ADMIN_EMAIL` env was removed from the admin-auth Deployment
  (K8s seeding is Job-only).

## 0.4.9 — 2026-07-06

### Changed
- **License trust root is now embedded in the images.** `license.publicKeyHex`
  is no longer required at install — the public key is baked into the service
  binaries. The value remains as a dev-only override (ignored when a key is
  embedded). Install with just `--set-file license.file=license.signed.json`.
- **Expiry no longer stops the platform.** A valid-but-expired license degrades
  to **restricted (read-only) mode** after its grace period: sign-in, viewing,
  export and installing a renewed license stay available; new AI/scan/automation/
  config operations are blocked. Only a missing/invalid license fails closed.
  billing `/readyz` stays *ready* on expiry (reports `restricted: true`) so the
  pod is not pulled from the Service endpoints.
- Bumped all pinned service image tags to the release carrying the above.

### Added
- **`adminBootstrap.password` seeds the first admin without logging it** (already
  present; documented). On Compose, `BOOTSTRAP_ADMIN_PASSWORD_FILE` does the same.

## 0.4.4 — 2026-07-04

### Added
- **A commented example `configs/<service>/config.yaml` for every service** (not
  just `gate`/`security`/split-workers), documenting the fields each accepts —
  uncomment only what you change and set `services.<name>.config=true`.

### Changed
- **Per-service `DATABASE_URL` is generated from `services.<name>.db`** +
  `infra.postgres.auth` instead of relying on the image's built-in DSN default.
  Override with `services.<name>.env.DATABASE_URL` for a managed database (an
  explicit `env:` entry still wins).
- Bundled-Postgres user and per-service database names are now `shipgrid` /
  `shipgrid_<service>`.

## 0.4.3 — 2026-07-04

### Changed
- Release pins: `auth v1.41.0`, `frontend onprem-v1.527.0`,
  `frontend-landing onprem-v1.51.0`. The sign-in page now lists the instance's
  configured identity providers as direct "Continue with <IdP>" buttons
  (public `GET /sso/providers`, active when `LICENSE_ENABLED=true` — already
  set by this chart, no values change needed). Optional `display_name` in
  `PUT /api/v1/auth/sso/config` sets the button label; failed IdP callbacks
  surface a visible sign-in banner.

## 0.4.2 — 2026-07-04

### Added
- **Deterministic first-admin seed.** Set `adminBootstrap.email` +
  `adminBootstrap.password` and a post-install/upgrade hook Job
  (`templates/admin-seed.yaml`) upserts the admin-console admin (bcrypt via
  pgcrypto) — no scraping the random temp password from the admin-auth log.
  `forcePasswordChange` toggles must-change-on-first-login;
  `adminBootstrap.db.*` targets a managed admin-auth DB.
- **Optional pentest helpers** (`pentest.*`):
  - `pentest.zap.enabled` → OWASP ZAP daemon (DAST). Self-contained; the
    security service auto-discovers it at `http://zap:8080`.
  - `pentest.oob.enabled` → self-hosted interactsh OOB/OAST server for
    blind-vuln detection. Requires `pentest.oob.domain` + `pentest.oob.publicIP`
    (public IP + NS/glue DNS delegation); not usable fully air-gapped — the
    rest of the pentest engine still runs.

## 0.4.1 — 2026-07-04

### Changed
- **Kafka image → `apache/kafka:4.3.1`** (official image, KRaft mode). The
  bundled Kafka StatefulSet is written for that contract: `KAFKA_`-prefixed
  config env, `KAFKA_LOG_DIRS=/var/lib/kafka/data`, `fsGroup: 1000`, a pinned
  `CLUSTER_ID`, and the data volume mounted via `subPath: kafka-data` so the
  ext4 `lost+found` at the PVC root doesn't trip Kafka's log-dir check (same
  class of fix as `PGDATA=<mount>/pgdata` for Postgres).
- **`security` resources** raised to 2Gi memory (from the 512Mi default): its
  bundled semgrep/checkov scanners OOM under 512Mi during real scans. Its
  `/readyz` runs a live scan per tool and the Python scanners can overrun the
  internal probe timeout on CPU-constrained nodes — gate k8s readiness on
  `/healthz` there (per-service `probes.readiness.path` in your overlay).

## 0.4.0 — 2026-07-03

Production-readiness pass: every backend service gets real health checks, sane
resource defaults, disruption protection, and rollouts that pick up config/secret
changes.

### Added
- **Liveness/readiness probes** on every backend Deployment (`/healthz` +
  `/readyz`; `gate` uses `/health` + `/readiness`), tunable via
  `defaults.probes` or per-service `services.<name>.probes`.
- **Resource requests/limits** by default (100m/192Mi requests, 500m/512Mi
  limits), replacing the previous empty `{}` (BestEffort QoS). Override per
  service via `services.<name>.resources`.
- **PodDisruptionBudget** per backend service (`maxUnavailable: 1`; a no-op at
  `replicas: 1`, real protection once scaled up). Disable stack-wide with
  `defaults.pdb.enabled=false`.
- **`checksum/secrets` / `checksum/site-config` / `checksum/config`** pod
  annotations so `helm upgrade` after rotating a secret or editing a
  `configs/<name>/config.yaml` actually restarts the affected pods.
- `defaults`/per-service `nodeSelector`, `tolerations`, `affinity` pass-through.
- Container `securityContext` (`allowPrivilegeEscalation: false`, drop `ALL`
  capabilities) and `automountServiceAccountToken: false` on every backend pod.
- `configs/security/config.yaml` wiring the six extracted security-platform
  microservice URLs (policy-engine, proof-engine, cloud-scanner, k8s-scanner,
  runtime-collector, findings-correlator) through `security`'s ConfigMap.

### Changed
- `secrets.redisURL` now derives from `secrets.redisPassword` when left empty,
  so rotating `redisPassword` alone no longer breaks `gate`'s Redis auth.

## 0.3.0 — 2026-07-02

First public release of the chart.

### Changed
- **Default image registry** is the vendor release registry
  `registry.shipgrid.app/shipgrid`. Pull with a per-client, pull-only robot
  credential; air-gapped installs mirror the images and override
  `global.registry`.

### Added
- `kubeVersion` (>= 1.27), `home`/`sources` and Artifact Hub annotations in
  `Chart.yaml`.
