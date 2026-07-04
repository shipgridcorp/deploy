#!/usr/bin/env bash
# reset-admin.sh — set (or reset) the ShipGrid admin-console first admin.
#
# Seeds/updates a row in devflow_admin_auth.system_admin_users with a bcrypt hash
# (pgcrypto), so you can log into the admin console immediately — no scraping the
# random temp password from the admin-auth pod log. Idempotent (upsert by email).
#
# Works against either deployment scenario:
#
#   Kubernetes (Scenario B):
#     ./reset-admin.sh --k8s -n <namespace> -e admin@corp.ru [-p 'PASSWORD']
#
#   Docker Compose (Scenario A):
#     ./reset-admin.sh --compose -e admin@corp.ru [-p 'PASSWORD']
#
# Options:
#   --k8s | --compose   target (default: autodetect — k8s if $KUBECONFIG/kubectl works)
#   -n, --namespace     k8s namespace (default: current context namespace or 'shipgrid')
#   -e, --email         admin email (required)
#   -p, --password      admin password (default: generated and printed)
#   --force-change      require the admin to change the password on first login
#   --db-name           admin-auth database (default: devflow_admin_auth)
#   --pg-user           postgres user (default: devflow)
#   -h, --help
#
# Requires: kubectl (k8s) or docker (compose); a reachable bundled/managed Postgres.
set -euo pipefail

TARGET=""; NS=""; EMAIL=""; PASSWORD=""; FORCE=false
DB_NAME="devflow_admin_auth"; PG_USER="devflow"
PG_SERVICE="postgres"           # bundled postgres service/container name

while [ $# -gt 0 ]; do
  case "$1" in
    --k8s) TARGET="k8s"; shift ;;
    --compose) TARGET="compose"; shift ;;
    -n|--namespace) NS="${2:-}"; shift 2 ;;
    -e|--email) EMAIL="${2:-}"; shift 2 ;;
    -p|--password) PASSWORD="${2:-}"; shift 2 ;;
    --force-change) FORCE=true; shift ;;
    --db-name) DB_NAME="${2:-}"; shift 2 ;;
    --pg-user) PG_USER="${2:-}"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$EMAIL" ] || { echo "✗ --email is required" >&2; exit 2; }
if [ -z "$PASSWORD" ]; then
  PASSWORD="Sg-$(head -c 9 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 12)!"
  GENERATED=1
fi

# Autodetect target if not given.
if [ -z "$TARGET" ]; then
  if command -v kubectl >/dev/null 2>&1 && kubectl version >/dev/null 2>&1; then TARGET="k8s"; else TARGET="compose"; fi
fi

# The upsert SQL. psql -v quoting parameterizes the values (injection-safe).
read -r -d '' SQL <<'EOSQL' || true
CREATE EXTENSION IF NOT EXISTS pgcrypto;
INSERT INTO system_admin_users (email, password_hash, is_active, must_change_password)
VALUES (:'email', crypt(:'pw', gen_salt('bf')), TRUE, :'force'::boolean)
ON CONFLICT (email) DO UPDATE
  SET password_hash        = crypt(:'pw', gen_salt('bf')),
      is_active            = TRUE,
      must_change_password = :'force'::boolean;
SELECT email, is_active, must_change_password FROM system_admin_users WHERE lower(email)=lower(:'email');
EOSQL

run_psql() {   # reads SQL on stdin, runs it inside the postgres container
  local vars=(-v ON_ERROR_STOP=1 -v email="$EMAIL" -v pw="$PASSWORD" -v force="$FORCE")
  if [ "$TARGET" = "k8s" ]; then
    local nsflag=(); [ -n "$NS" ] && nsflag=(-n "$NS")
    local pod
    pod="$(kubectl "${nsflag[@]}" get pod -l app.kubernetes.io/name=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
    [ -n "$pod" ] || { echo "✗ no postgres pod found (is infra.postgres bundled? for managed DB, run psql against it directly)" >&2; exit 1; }
    kubectl "${nsflag[@]}" exec -i "$pod" -- psql -U "$PG_USER" -d "$DB_NAME" "${vars[@]}"
  else
    docker compose exec -T "$PG_SERVICE" psql -U "$PG_USER" -d "$DB_NAME" "${vars[@]}"
  fi
}

echo "▶ Target: $TARGET   DB: $DB_NAME   admin: $EMAIL"
printf '%s\n' "$SQL" | run_psql

echo
echo "✓ Admin ready."
echo "  email:    $EMAIL"
if [ "${GENERATED:-0}" = "1" ]; then
  echo "  password: $PASSWORD   (generated — store it now, then rotate after login)"
else
  echo "  password: (the one you passed)"
fi
[ "$FORCE" = "true" ] && echo "  note: must change password on first login."
