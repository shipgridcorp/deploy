#!/usr/bin/env bash
# rotate-secrets.sh — generate a fresh set of the SHARED platform secrets and
# print them ready to paste, both for the single-VM .env (compose/) and for a
# Helm values override (kubernetes/). Run ONCE before a production install.
#
#   ./scripts/rotate-secrets.sh            # print + write secrets-summary.txt
#   ./scripts/rotate-secrets.sh --stdout   # print only, write nothing
#
# The secrets are used by EVERY service — inter-service auth breaks if they
# diverge — so both deployment paths take them from ONE place:
#   • Compose: .env (the compose file threads them into every container)
#   • Helm:    global.internalAuthSecret + secrets.* values
#
# secrets-summary.txt is gitignored. Store the values in your secrets vault;
# they cannot be recovered from a running install.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$SCRIPT_DIR/../secrets-summary.txt"
WRITE=1
[ "${1:-}" = "--stdout" ] && WRITE=0

command -v openssl >/dev/null || { echo "openssl required" >&2; exit 1; }

INTERNAL="$(openssl rand -hex 32)"                                   # 64 hex chars
JWT="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 48)"   # 48 alnum
ENC="$(openssl rand -base64 32)"                                     # AES-256 key (base64)
REDIS="$(openssl rand -hex 16)"
NEO4J="$(openssl rand -hex 16)"
CLICKHOUSE="$(openssl rand -hex 16)"

SUMMARY="$(cat <<EOF
# ShipGrid shared platform secrets — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Keep this file OUT of git (it is gitignored). Store in your secrets vault.

## Single-VM (compose): paste into compose/.env
INTERNAL_AUTH_SECRET=$INTERNAL
JWT_SECRET=$JWT
ENCRYPTION_KEY=$ENC
REDIS_PASSWORD=$REDIS
NEO4J_PASSWORD=$NEO4J
CLICKHOUSE_PASSWORD=$CLICKHOUSE

## Kubernetes (helm): pass as a gitignored values file or --set
# values-secrets.yaml:
global:
  internalAuthSecret: "$INTERNAL"
secrets:
  jwtSecret: "$JWT"
  encryptionKey: "$ENC"
  redisPassword: "$REDIS"
  neo4jPassword: "$NEO4J"
infra:
  clickhouse:
    password: "$CLICKHOUSE"
EOF
)"

printf '%s\n' "$SUMMARY"

if [ "$WRITE" -eq 1 ]; then
  umask 077
  printf '%s\n' "$SUMMARY" > "$OUT"
  printf '\n\033[32m✓ Written to %s (chmod 600, gitignored)\033[0m\n' "$OUT"
fi

cat >&2 <<'EON'

Notes:
 • Apply BEFORE first boot if possible. Rotating on an existing install also
   requires restarting the whole stack so every service picks up the new values
   (compose: docker compose up -d; helm: helm upgrade — the chart's checksum
   annotations restart affected pods automatically).
 • ENCRYPTION_KEY protects data encrypted at rest (integration credentials,
   tokens). Changing it on an existing install makes previously encrypted
   values unreadable — plan rotation before go-live, not after.
 • The bundled Postgres keeps its fixed internal credentials: it is not
   reachable from outside the deployment network and the per-service DSNs
   reference it explicitly. Point services at a managed database (per-service
   DATABASE_URL / config DSN) if your policy requires rotated DB credentials.
EON
