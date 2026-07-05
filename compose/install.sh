#!/usr/bin/env bash
# ShipGrid on-prem single-VM installer (Scenario A).
#
#   ./install.sh [--bundle images.tar[.gz]] [--yes] [--no-smoke]
#
# Steps: preflight → (load air-gap image bundle) → ensure .env → license check
#        → docker compose up -d → smoke test.
# Idempotent: safe to re-run (compose converges, .env is preserved).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BUNDLE=""
ASSUME_YES=0
RUN_SMOKE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --bundle) BUNDLE="${2:-}"; shift 2 ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --no-smoke) RUN_SMOKE=0; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

c_red()  { printf '\033[31m%s\033[0m\n' "$*"; }
c_grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
c_ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }
step()   { printf '\n\033[1m▶ %s\033[0m\n' "$*"; }
die()    { c_red "✗ $*"; exit 1; }

# ── 1. Preflight ─────────────────────────────────────────────────────────────
step "Preflight checks"
command -v docker >/dev/null 2>&1 || die "docker not found. Install Docker Engine 24+."
if docker compose version >/dev/null 2>&1; then
  DC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  DC=(docker-compose)
else
  die "docker compose (v2) not found."
fi
docker info >/dev/null 2>&1 || die "cannot talk to the Docker daemon (is it running? are you in the docker group?)."

# Resources (best-effort; warn, don't block).
total_ram_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
if [ "$total_ram_kb" -gt 0 ]; then
  ram_gb=$(( total_ram_kb / 1024 / 1024 ))
  if [ "$ram_gb" -lt 32 ]; then
    c_ylw "⚠ ${ram_gb} GB RAM detected. The full stack (25 services + Postgres/Redis/Kafka/ClickHouse/Neo4j/Qdrant) wants 64+ GB for production; 32 GB is the practical floor for a PoC."
  else
    c_grn "✓ RAM: ${ram_gb} GB"
  fi
fi
cpus=$(nproc 2>/dev/null || echo 0)
[ "$cpus" -gt 0 ] && c_grn "✓ CPU: ${cpus} cores"
avail_gb=$(df -BG "$SCRIPT_DIR" 2>/dev/null | awk 'NR==2{gsub("G","",$4); print $4}' || echo 0)
if [ "${avail_gb:-0}" -gt 0 ] && [ "$avail_gb" -lt 80 ]; then
  c_ylw "⚠ ${avail_gb} GB free disk. Recommend 100+ GB (images + volumes + scan data)."
else
  [ "${avail_gb:-0}" -gt 0 ] && c_grn "✓ Disk free: ${avail_gb} GB"
fi
c_grn "✓ Docker + compose present"

# ── 2. Load image bundle (air-gap) ───────────────────────────────────────────
if [ -n "$BUNDLE" ]; then
  step "Loading image bundle: $BUNDLE"
  [ -f "$BUNDLE" ] || die "bundle not found: $BUNDLE"
  if [ -f "$BUNDLE.sha256" ]; then
    ( cd "$(dirname "$BUNDLE")" && { sha256sum -c "$(basename "$BUNDLE").sha256" 2>/dev/null || shasum -a 256 -c "$(basename "$BUNDLE").sha256"; } ) \
      || die "checksum verification FAILED for $BUNDLE"
    c_grn "✓ Checksum verified"
  else
    c_ylw "⚠ No $BUNDLE.sha256 next to the bundle — skipping checksum verification."
  fi
  case "$BUNDLE" in
    *.gz) gunzip -c "$BUNDLE" | docker load ;;
    *)    docker load -i "$BUNDLE" ;;
  esac
  c_grn "✓ Images loaded"
fi

# ── 3. Ensure .env ───────────────────────────────────────────────────────────
step "Configuration (.env)"
if [ ! -f .env ]; then
  cp .env.example .env
  c_grn "✓ Created .env from template (.env.example)"
  c_ylw "  Edit .env: place your license.signed.json, LLM credentials, PUBLIC_APP_URL."
  if [ "$ASSUME_YES" -eq 0 ]; then
    read -r -p "  Edit .env now, then press Enter to continue (or Ctrl-C to abort)... " _ || true
  fi
else
  c_grn "✓ Using existing .env"
fi

set -a
# shellcheck source=/dev/null
. ./.env 2>/dev/null || true
set +a

# ── 4. License ───────────────────────────────────────────────────────────────
LIC_HOST="${LICENSE_FILE_HOST:-./license.json}"
if [ "${LICENSE_ENABLED:-true}" = "true" ]; then
  step "License"
  if [ ! -f "$LIC_HOST" ]; then
    c_red "✗ License file not found at $LIC_HOST."
    c_red "  Every backend service verifies the signed license at startup and will"
    c_red "  refuse to boot without it (the public key is embedded in the images)."
    c_red "  Place the license.signed.json you received as $LIC_HOST,"
    die   "  or set LICENSE_ENABLED=false in .env for an unlicensed trial."
  fi
  c_grn "✓ License file present"
fi

# ── 5. Start the stack ───────────────────────────────────────────────────────
step "Starting the stack (pulls and boots ~35 containers on first run)"
"${DC[@]}" up -d
c_grn "✓ Compose up issued"

# ── 6. Wait for health + smoke ───────────────────────────────────────────────
if [ "$RUN_SMOKE" -eq 1 ]; then
  step "Waiting for services to become healthy"
  bash "$SCRIPT_DIR/smoke.sh" || die "smoke test failed — check 'docker compose logs'."
fi

step "Done"
c_grn "ShipGrid on-prem is up."
echo "  App:   ${PUBLIC_APP_URL:-http://localhost:8080}"
echo "  Admin: ${ADMIN_APP_URL:-http://localhost:8081}"
echo "  Logs:  ${DC[*]} logs -f <service>"
echo "  Stop:  ${DC[*]} down          (data volumes are kept)"
