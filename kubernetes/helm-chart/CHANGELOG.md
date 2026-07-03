# Changelog

All notable changes to the ShipGrid on-prem Helm chart are documented here.
This chart follows [Semantic Versioning](https://semver.org/); the `appVersion`
tracks the ShipGrid platform release.

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
