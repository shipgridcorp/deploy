#!/usr/bin/env bash
# mirror-to-registry.sh — put the ShipGrid images into YOUR internal registry
# (Harbor/Nexus/Artifactory), for Kubernetes installs and air-gapped perimeters.
#
#   Online (host has access to registry.shipgrid.app; docker login done):
#     ./mirror-to-registry.sh harbor.internal.example.ru/shipgrid
#
#   Air-gapped (images come from the delivery bundle, no internet):
#     ./mirror-to-registry.sh --bundle shipgrid-onprem-images.tar.gz harbor.internal.example.ru/shipgrid
#
# What it does: resolve the full image list from ../compose/docker-compose.yml
# (the single source of truth for the tested release set) → pull or load →
# retag under the target registry → push. Then install the Helm chart with
#   --set global.registry=<target>
#
# ShipGrid service images keep their name and tag. With --all, third-party
# infrastructure images (postgres, redis, kafka…) are mirrored too, retagged
# by basename under the same target — override the chart's infra.*.image
# values to match if you use them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$SCRIPT_DIR/../compose"
VENDOR_PREFIX="${VENDOR_PREFIX:-registry.shipgrid.app/shipgrid}"

BUNDLE=""
MIRROR_ALL=0
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bundle) BUNDLE="${2:-}"; shift 2 ;;
    --all) MIRROR_ALL=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) TARGET="$1"; shift ;;
  esac
done
[ -n "$TARGET" ] || { echo "usage: $0 [--bundle images.tar.gz] [--all] <target-registry-prefix>" >&2; exit 2; }
TARGET="${TARGET%/}"

command -v docker >/dev/null || { echo "docker required" >&2; exit 1; }
if docker compose version >/dev/null 2>&1; then DC=(docker compose); else DC=(docker-compose); fi

echo "▶ Resolving the release image set from compose/docker-compose.yml ..."
IMAGES="$(cd "$COMPOSE_DIR" && "${DC[@]}" -f docker-compose.yml config --images 2>/dev/null | sort -u | grep -v '^$')"
[ -n "$IMAGES" ] || { echo "could not resolve images from $COMPOSE_DIR/docker-compose.yml" >&2; exit 1; }

# ── Load or pull ─────────────────────────────────────────────────────────────
if [ -n "$BUNDLE" ]; then
  echo "▶ Loading bundle: $BUNDLE"
  [ -f "$BUNDLE" ] || { echo "bundle not found: $BUNDLE" >&2; exit 1; }
  if [ -f "$BUNDLE.sha256" ]; then
    ( cd "$(dirname "$BUNDLE")" && { sha256sum -c "$(basename "$BUNDLE").sha256" 2>/dev/null || shasum -a 256 -c "$(basename "$BUNDLE").sha256"; } ) \
      || { echo "✗ checksum verification FAILED" >&2; exit 1; }
    echo "✓ Checksum verified"
  else
    echo "⚠ No $BUNDLE.sha256 next to the bundle — skipping checksum verification." >&2
  fi
  case "$BUNDLE" in
    *.gz) gunzip -c "$BUNDLE" | docker load ;;
    *)    docker load -i "$BUNDLE" ;;
  esac
else
  echo "▶ Pulling images (docker login to the source registries first) ..."
  while IFS= read -r img; do
    docker image inspect "$img" >/dev/null 2>&1 || docker pull "$img"
  done <<< "$IMAGES"
fi

# ── Retag + push ─────────────────────────────────────────────────────────────
echo "▶ Mirroring to $TARGET ..."
pushed=0 skipped=0
while IFS= read -r img; do
  case "$img" in
    "$VENDOR_PREFIX"/*)
      dst="$TARGET/${img#"$VENDOR_PREFIX"/}"
      ;;
    *)
      if [ "$MIRROR_ALL" -eq 1 ]; then
        base="${img##*/}"                       # strip any registry/namespace
        dst="$TARGET/$base"
      else
        skipped=$((skipped+1)); continue        # third-party infra: --all to include
      fi
      ;;
  esac
  echo "  $img → $dst"
  docker tag "$img" "$dst"
  docker push "$dst"
  pushed=$((pushed+1))
done <<< "$IMAGES"

echo "✓ Mirrored $pushed images to $TARGET ($skipped third-party images skipped$([ "$MIRROR_ALL" -eq 1 ] || printf ' — use --all to include'))"
echo "  Kubernetes install: helm install … --set global.registry=$TARGET"
echo "  Compose install:    REGISTRY=$TARGET in compose/.env"
