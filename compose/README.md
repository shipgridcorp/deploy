# Scenario A · Single VM (Docker Compose)

The full ShipGrid stack on one virtual machine — the fastest path for a pilot
or PoC: **about one working day** on a prepared VM. Follows Part 4 of the
*ShipGrid On-Prem Installation Guide*.

What runs: 25 backend services + SPA frontends (app / admin / landing) + an
edge nginx gateway, and single-node infrastructure — PostgreSQL (pgvector),
Redis, Kafka, ClickHouse, Neo4j, Qdrant, Kroki. Everything is defined in one
self-contained [`docker-compose.yml`](docker-compose.yml); everything
install-specific lives in `.env`.

## When to choose it

- Pilot / PoC, small or medium scale.
- You need it running fast, without Kubernetes overhead.
- Data must stay with you, HA is not required. For HA and scaling use
  [Scenario B](../kubernetes/).

| Profile | vCPU | RAM | Disk |
|---|---|---|---|
| Minimum (PoC) | 16 | 32 GB | 100 GB SSD |
| Recommended | 16–24 | 64 GB | 150 GB SSD |

## Pre-flight

Your team prepares:

- [ ] 1 Linux VM (Ubuntu 22.04+ / RHEL 8+), sized as above.
- [ ] Docker Engine 24+ and docker compose v2 (`docker compose version`).
- [ ] Network access to `registry.shipgrid.app` **or** the air-gap bundle.
- [ ] (optional) internal domain + TLS certificate for external access.
- [ ] Ports 8080 / 8081 reachable for users (behind a TLS reverse-proxy).
- [ ] RF-LLM credentials (Yandex / GigaChat) — unless AI is self-hosted or mock.

ShipGrid delivery includes: this kit, pull access to the registry (or the image
bundle), the signed license + public key.

## Install

```bash
cp .env.example .env
# edit .env: LICENSE_PUBLIC_KEY, LLM credentials, PUBLIC_APP_URL
# place license.signed.json → ./license.json

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
(every backend refuses to boot without a valid license when
`LICENSE_ENABLED=true`), starts the stack and runs the smoke test.

## LLM modes

| Mode | `.env` settings |
|---|---|
| Mock (default) | `MOCK_PROVIDER_ENABLED=true` — stub answers, no real LLM |
| YandexGPT | `YANDEX_API_KEY`, `YANDEX_FOLDER_ID`, `MOCK_PROVIDER_ENABLED=false` |
| GigaChat | `GIGACHAT_AUTH_KEY`, `GIGACHAT_SCOPE`, `GIGACHAT_CA_FILE` (CA Минцифры) |
| Self-hosted | `YANDEX_LLM_BASE_URL=http://<vllm-host>:<port>/v1` — model selection in Part 7 of the guide |

Foreign providers (OpenAI/Anthropic) are honoured only with
`BLOCK_FOREIGN_LLM=false` — for installs outside the RF regulatory scope.

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
docker compose exec -T billing sh -c 'wget -qO- localhost:8000/readyz'  # license=ok
```

Green smoke, license `active`, a test business-analysis run and a security scan
pass, dashboards open — accepted.

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
- **License renewal:** replace `./license.json` → `docker compose restart
  billing` (picked up automatically within ~6h otherwise).
- **Backup:** docker volumes `pg_data`, `clickhouse_data`, `neo4j_data`,
  `qdrant_data`, `kafka_data`, `redis_data` — regularly, and they stay inside
  your perimeter.

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
| services crash-loop at startup | license missing/invalid while `LICENSE_ENABLED=true` — check `./license.json` + `LICENSE_PUBLIC_KEY` |
| gateway returns non-2xx | frontends still starting — `docker compose logs -f frontend` |
| billing `/readyz` degraded | license missing or invalid — same check as above |
| AI answers empty / error | LLM credentials unset/invalid in `.env` — see **LLM modes** |
| `ImagePull` errors | not logged in to the registry, or `REGISTRY` in `.env` doesn't match your mirror |
