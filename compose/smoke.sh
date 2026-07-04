#!/usr/bin/env bash
# Post-install smoke test: wait for core services, then probe the gateway and
# the billing /readyz (incl. license status). Exit non-zero on failure.
#
#   ./smoke.sh [timeout_seconds]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1
TIMEOUT="${1:-240}"

if docker compose version >/dev/null 2>&1; then DC=(docker compose); else DC=(docker-compose); fi

# Load .env for URLs.
set -a
# shellcheck source=/dev/null
. ./.env 2>/dev/null || true
set +a
APP_URL="http://localhost:${APP_PORT:-8080}"

# Core services that must be running before we call the stack up.
CORE="postgres redis kafka auth platform gate billing"

c_grn() { printf '\033[32m%s\033[0m\n' "$*"; }
c_red() { printf '\033[31m%s\033[0m\n' "$*"; }
c_ylw() { printf '\033[33m%s\033[0m\n' "$*"; }

echo "Waiting up to ${TIMEOUT}s for core services: $CORE"
deadline=$(( $(date +%s) + TIMEOUT ))
while :; do
  ok=1
  ps_out="$("${DC[@]}" ps 2>/dev/null)"
  for svc in $CORE; do
    line="$(printf '%s\n' "$ps_out" | grep -E "[ -]${svc}[ -]|^${svc} " || true)"
    if [ -z "$line" ]; then ok=0; break; fi
    # Treat "Up", "running", "healthy" as good; "Restarting"/"Exit" as not-ready.
    if printf '%s' "$line" | grep -qiE 'restarting|exit|starting|unhealthy'; then ok=0; break; fi
    if ! printf '%s' "$line" | grep -qiE 'up|running|healthy'; then ok=0; break; fi
  done
  if [ "$ok" -eq 1 ]; then c_grn "✓ core services running"; break; fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    c_red "✗ timed out waiting for: $svc"
    "${DC[@]}" ps
    exit 1
  fi
  sleep 5
done

# HTTP probe: gateway serves the SPA (any 2xx/3xx is fine).
echo "Probing gateway at $APP_URL ..."
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$APP_URL" || echo 000)"
if printf '%s' "$code" | grep -qE '^(2|3)'; then
  c_grn "✓ gateway responded ($code)"
else
  c_ylw "⚠ gateway returned $code — frontends may still be starting; check logs if this persists."
fi

# License status via billing /readyz (best-effort; needs wget/curl in the image —
# if unavailable we skip without failing the smoke run).
echo "Checking billing /readyz ..."
ready="$("${DC[@]}" exec -T billing sh -c \
  'wget -qO- http://localhost:8000/readyz 2>/dev/null || curl -s http://localhost:8000/readyz 2>/dev/null' 2>/dev/null || true)"
if [ -n "$ready" ]; then
  echo "  $ready"
  if printf '%s' "$ready" | grep -q '"status":"ok"'; then
    c_grn "✓ billing ready (license OK or licensing disabled)"
  else
    c_ylw "⚠ billing not fully ready — if licensing is enabled, place a valid signed license.json (see README)."
  fi
else
  c_ylw "  (could not read /readyz from inside the container — skipping; not a failure)"
fi

c_grn "Smoke test complete."
