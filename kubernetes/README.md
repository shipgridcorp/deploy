# Scenario B · Kubernetes (Helm)

ShipGrid in your production cluster via the umbrella Helm chart — for
enterprise installs with HA and scaling.

The chart lives in [`helm-chart/`](helm-chart/) (self-contained, with its own
[full reference README](helm-chart/README.md)) and is also published as an OCI
artifact — both install paths are equivalent:

```bash
cd helm-chart && helm install shipgrid . -n shipgrid --create-namespace …   # from this kit
helm install shipgrid oci://registry.shipgrid.app/charts/shipgrid --version 0.4.4 …   # from the registry
```

## Pre-flight

Your team prepares:

- [ ] Kubernetes 1.27+, `kubectl` access, a dedicated namespace
      (one release per namespace — the chart uses bare resource names).
- [ ] Rights to create Deployment / Service / Secret / ConfigMap /
      NetworkPolicy / StatefulSet.
- [ ] **Data dependencies** (managed or operator-run): PostgreSQL (pgvector),
      Redis, Kafka, ClickHouse, Neo4j, Qdrant — as bare-named Services in the
      namespace. For a PoC the chart bundles single-node versions
      (`infra.*.enabled=true`).
- [ ] Internal **registry** (Harbor/Nexus) for the image mirror + pull access.
- [ ] Ingress controller + TLS certificate + DNS records.
- [ ] StorageClass for PVCs (if using bundled infra).

## Install

**1 · Mirror the images into your registry** (skip to use the vendor registry
directly with a pull secret):

```bash
docker login registry.shipgrid.app          # pull credentials from the delivery
../airgap/mirror-to-registry.sh harbor.company.ru/shipgrid
```

**2 · Namespace + pull secret:**

```bash
kubectl create namespace shipgrid
kubectl -n shipgrid create secret docker-registry regcred \
  --docker-server=harbor.company.ru --docker-username=<u> --docker-password=<t>
```

**3 · Data dependencies** — bare names in the namespace (`postgres`, `redis`,
`kafka`, `clickhouse`, `neo4j`, `qdrant`). PoC shortcut: `--set
infra.postgres.enabled=true --set infra.redis.enabled=true …`

**4 · Install the chart:**

```bash
cd helm-chart
helm install shipgrid . -n shipgrid \
  -f values-onprem.yaml \
  --set global.registry=harbor.company.ru/shipgrid \
  --set global.imagePullSecrets[0].name=regcred \
  --set-file license.file=license.signed.json \
  --set llm.yandex.apiKey=<key> --set llm.yandex.folderId=<folder> \
  --set networkPolicy.enabled=true
# the license public key is embedded in the images — no publicKeyHex needed
```

**5 · External access** — gateway + Ingress + TLS + SPA frontends:

```bash
helm upgrade shipgrid . -n shipgrid --reuse-values \
  --set gateway.resolver=$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}') \
  --set frontends.enabled=true \
  --set ingress.enabled=true \
  --set ingress.app.host=shipgrid.company.ru \
  --set ingress.admin.host=admin.shipgrid.company.ru \
  --set ingress.tls.enabled=true --set ingress.tls.secretName=shipgrid-tls
```

`gateway.resolver` (CoreDNS ClusterIP) is **required** — without it the edge
nginx cannot resolve backends.

## Before production

- Rotate the shared secrets: `../scripts/rotate-secrets.sh` prints a ready
  `values-secrets.yaml` block — keep it out of git, pass with `-f`.
- Use managed databases; point services at them via
  `services.<name>.env.DATABASE_URL` (or the split-workers'
  `configs/<name>/config.yaml` DSN), keep `infra.*.enabled=false`.
- `networkPolicy.enabled=true` with `allowedEgressCIDRs` restricted to your
  LLM endpoint / registry / databases.

The complete values reference and hardening checklist are in
[`helm-chart/README.md`](helm-chart/README.md).

## Acceptance

```bash
kubectl -n shipgrid get pods -l app.kubernetes.io/part-of=shipgrid
kubectl -n shipgrid exec deploy/billing -- wget -qO- localhost:8000/readyz   # license status
helm -n shipgrid status shipgrid
```

The license is enforced by **every** backend service at startup — the public key
is embedded in the images. A missing/invalid license fails closed; a valid-but-
expired one degrades to restricted (read-only) mode after grace rather than
stopping. billing `/readyz` is where its status is exposed.

## Operate

- **Update:** mirror the new tags → `helm upgrade shipgrid . -n shipgrid …`
- **Rollback:** `helm rollback shipgrid <revision> -n shipgrid`
- **Backup:** managed DBs by their own tooling; bundled PVCs — snapshots.
- **Monitoring:** every service exposes `/healthz` + `/readyz` — wire up your
  Prometheus / Grafana.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `ImagePullBackOff` | image not mirrored / wrong `regcred` / wrong `global.registry` |
| service can't find a peer | a data dependency isn't bare-named in the namespace |
| billing `/readyz` degraded | license missing/invalid (bad signature/format). An expired license stays ready in restricted mode — install a renewed `license.signed.json` |
| service `CrashLoop` | config points at an unreachable DB — check the DSN |
| two releases conflict | bare names → strictly one release per namespace |
