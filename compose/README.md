# Scenario A · Single VM (Docker Compose)

The full ShipGrid stack on one virtual machine — the fastest path for a pilot
or PoC.

What runs: 25 backend services + SPA frontends (app / admin / landing) + an
edge nginx gateway, and single-node infrastructure — PostgreSQL (pgvector),
Redis, Kafka, ClickHouse, Neo4j, Qdrant, Kroki. Everything is defined in one
self-contained [`docker-compose.yml`](docker-compose.yml); everything
install-specific lives in `.env`.

| Profile | vCPU | RAM | Disk |
|---|---|---|---|
| Minimum (PoC) | 16 | 32 GB | 100 GB SSD |
| Recommended | 16–24 | 64 GB | 150 GB SSD |

For HA and scaling use [Scenario B (Kubernetes)](../kubernetes/).

## Pre-flight

- [ ] 1 Linux VM (Ubuntu 22.04+ / RHEL 8+), sized as above.
- [ ] Docker Engine 24+ and docker compose v2 (`docker compose version`).
- [ ] Network access to `registry.shipgrid.app` **or** the air-gap bundle.
- [ ] (optional) internal domain + TLS certificate for external access.
- [ ] Ports 8080 / 8081 reachable for users (behind a TLS reverse-proxy).
- [ ] RF-LLM credentials (Yandex / GigaChat) — unless AI is self-hosted or mock.

ShipGrid delivery includes: pull access to the registry (or the image bundle)
and the signed license + public key.

## Install

```bash
cp .env.example .env
# edit .env: LLM credentials, PUBLIC_APP_URL
# place license.signed.json → ./license.json  (the public key is embedded in the images)

docker login registry.shipgrid.app   # credentials issued with the delivery
./install.sh                         # preflight → pull → up → smoke
```

Air-gapped (no internet on the VM):

```bash
sha256sum -c shipgrid-onprem-images.tar.gz.sha256
./install.sh --bundle shipgrid-onprem-images.tar.gz
```

`install.sh` is idempotent — it checks OS/Docker/resources, loads the bundle if
given, creates `.env` from the template, verifies the license file is in place
(every backend service verifies the signed license at startup and refuses to
boot without it when `LICENSE_ENABLED=true`), starts the stack and runs the
smoke test.

## LLM modes

The recommended way to connect a real LLM is the admin console (`:8081` →
AI Config → Providers): pick a template (YandexGPT / GigaChat / self-hosted
OpenAI-compatible), the key is stored encrypted in the DB, Test connection
hits the real endpoint, and routing picks the provider up live — no restart.
The `.env` variables below pre-provision a provider for automated / air-gap
installs where everything must be file-driven:

| Mode | `.env` settings |
|---|---|
| Mock (default) | `MOCK_PROVIDER_ENABLED=true` — stub answers, no real LLM |
| YandexGPT | `YANDEX_API_KEY`, `YANDEX_FOLDER_ID`, `MOCK_PROVIDER_ENABLED=false` |
| GigaChat | `GIGACHAT_AUTH_KEY`, `GIGACHAT_SCOPE`, `GIGACHAT_CA_FILE` (CA Минцифры) |
| Self-hosted | `LOCAL_LLM_BASE_URL=http://<vllm-host>:<port>/v1` + route your model names via `model_aliases` in `config/gate/config.yaml` |

Foreign providers (OpenAI/Anthropic) are honoured only with
`BLOCK_FOREIGN_LLM=false` — for installs outside the RF regulatory scope.

### Which model does each feature use?

Services request models by *role* — `auto:chat` (analysis, reviews,
assistants), `auto:chat-light` (bulk indexing, summaries), `auto:embeddings`
(vector search) — and the gate substitutes the active model per request.

Roles are assigned **only in the admin console**: AI Settings → Providers →
tag a model with the role. The assignment applies to every service live and
survives upgrades. There is no file or env fallback by design — until a role
is assigned, AI requests for it fail with a clear error naming the console
page, so a misconfiguration is always visible, never silent.

Embedding vector dimensions are discovered from the model automatically — no
dimension setting. Switching the embeddings model rebuilds vector collections;
re-index repositories afterwards (the console warns before the switch).

## Service configs

Every service boots from built-in defaults + the shared environment in
`docker-compose.yml`. To override a specific field, use the per-service example
config in [`config/<service>/config.yaml`](config/) (precedence: file → env →
default): uncomment only the keys you change, then mount the directory and set
`CONFIG_PATH` on that service — the `gate`, `security` and split-worker
services in `docker-compose.yml` show the pattern.

## External access

- App — port **:8080**, Admin — **:8081**, Landing — **:8082** (override via
  `APP_PORT` / `ADMIN_PORT` / `LANDING_PORT`).
- For production put a reverse-proxy (nginx / Traefik) with TLS in front of
  those ports and set `PUBLIC_APP_URL` / `ADMIN_APP_URL` in `.env` to the
  public origins.

## Acceptance

```bash
./smoke.sh
docker compose ps                                                    # all Up
docker compose exec -T billing sh -c 'wget -qO- localhost:8000/readyz'  # license status
```

The license itself is enforced by every backend service at startup; billing
`/readyz` is where its status is exposed for checks like the one above.

## Runbook

```bash
docker compose logs -f gate billing     # logs
docker compose restart billing          # e.g. after replacing the license file
docker compose down                     # stop (data volumes are KEPT)
docker compose down -v                  # ⚠ deletes the data too
./smoke.sh                              # re-check health
```

- **Update:** new tags arrive with a release → `docker compose pull && docker
  compose up -d` (or `./install.sh --bundle <new bundle>` in air-gap).
- **License renewal:** replace `./license.json` → restart (picked up
  automatically within ~6h otherwise).
- **Backup:** docker volumes `pg_data`, `clickhouse_data`, `neo4j_data`,
  `qdrant_data`, `kafka_data`, `redis_data` — regularly, and they stay inside
  your perimeter.
- **Managed Postgres:** override each service's `DATABASE_URL` (or the
  split-workers' `config/<name>/config.yaml` DSN) via a compose override file.

## Hardening before production

- [ ] Rotate the shared dev secrets: `../scripts/rotate-secrets.sh`, paste the
      printed block into `.env`, then `docker compose up -d`. Do this **before
      go-live**: `ENCRYPTION_KEY` cannot be swapped once real data is encrypted.
- [ ] TLS reverse-proxy in front of the gateway (it serves plain HTTP).
- [ ] Egress firewall: allow only the RF-LLM endpoint / registry; air-gap — nothing.
- [ ] Set a real `BOOTSTRAP_ADMIN_EMAIL` before first boot (one-time password is
      printed once in the `admin-auth` log).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `install.sh` fails preflight | no docker / compose v2, low RAM or disk — see the message |
| services crash-loop at startup | license missing/invalid while `LICENSE_ENABLED=true` (every service enforces it) — check `./license.json`. An *expired* license does **not** crash-loop; it runs in restricted (read-only) mode |
| gateway returns non-2xx | frontends still starting — `docker compose logs -f frontend` |
| billing `/readyz` degraded | license missing/invalid (bad signature/format). An expired license stays ready in restricted mode — install a renewed `license.signed.json` |
| new AI/scan/config blocked, but sign-in works | license expired beyond grace → restricted mode. Install a renewed `license.signed.json` to restore full operation |
| AI answers empty / error | LLM credentials unset/invalid in `.env` — see **LLM modes** |
| `ImagePull` errors | not logged in to the registry, or `REGISTRY` in `.env` doesn't match your mirror |
