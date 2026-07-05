#!/usr/bin/env bash
# build-bundle.sh — VENDOR-SIDE release tooling. Produces the air-gap delivery
# bundle AND its supply-chain artifacts, so an air-gapped client can verify the
# ORIGIN of what they load, not just its integrity.
#
# Standard for every air-gap delivery (guide §6.3):
#   shipgrid-onprem-images.tar.gz   docker-save of the full tested image set
#   release-manifest.json           image list with tags + sha256 digests + versions
#   SBOM/                           per-image SBOM (SPDX json) — requires syft
#   SHA256SUMS                      checksums of every artifact above
#   SHA256SUMS.sig                  cosign signature over SHA256SUMS (origin proof)
#   cosign image signatures         each image signed — requires cosign + key
#
# Usage:
#   ./build-bundle.sh [--out DIR] [--sign-key cosign.key] [--no-sbom]
#
# The release environment must have: docker, sha256sum (or shasum), jq.
# Origin proof additionally needs cosign (+ a signing key); SBOM needs syft.
# Missing optional tools are reported and skipped — the bundle is still built,
# but a bank/CII delivery MUST have the signature + SBOM, so run this where they
# are installed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$SCRIPT_DIR/../compose"
VENDOR_PREFIX="${VENDOR_PREFIX:-registry.shipgrid.app/shipgrid}"

OUT="./shipgrid-bundle"
SIGN_KEY=""
WANT_SBOM=1
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="${2:?}"; shift 2 ;;
    --sign-key) SIGN_KEY="${2:?}"; shift 2 ;;
    --no-sbom) WANT_SBOM=0; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
have()   { command -v "$1" >/dev/null 2>&1; }

command -v docker >/dev/null || { echo "docker required" >&2; exit 1; }
have jq || { echo "jq required (release manifest is JSON)" >&2; exit 1; }
if docker compose version >/dev/null 2>&1; then DC=(docker compose); else DC=(docker-compose); fi

mkdir -p "$OUT" "$OUT/SBOM"
TARBALL="$OUT/shipgrid-onprem-images.tar.gz"
MANIFEST="$OUT/release-manifest.json"

echo "▶ Resolving the release image set from compose/docker-compose.yml ..."
IMAGES="$(cd "$COMPOSE_DIR" && "${DC[@]}" -f docker-compose.yml config --images 2>/dev/null | sort -u | grep -v '^$' | grep "^$VENDOR_PREFIX/")"
[ -n "$IMAGES" ] || { echo "could not resolve ShipGrid images from compose" >&2; exit 1; }

echo "▶ Pulling images (docker login to registry.shipgrid.app first) ..."
while IFS= read -r img; do docker image inspect "$img" >/dev/null 2>&1 || docker pull "$img"; done <<< "$IMAGES"

echo "▶ Saving image tarball ..."
# shellcheck disable=SC2086
docker save $IMAGES | gzip > "$TARBALL"

echo "▶ Writing release manifest (images + digests + versions) ..."
{
  echo '{'
  echo '  "product": "shipgrid-onprem",'
  echo "  \"built_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"tarball\": \"$(basename "$TARBALL")\","
  echo '  "images": ['
  first=1
  while IFS= read -r img; do
    digest="$(docker image inspect "$img" --format '{{index .RepoDigests 0}}' 2>/dev/null | sed 's/.*@//')"
    [ -n "$digest" ] || digest="sha256:$(docker image inspect "$img" --format '{{.Id}}' | sed 's/sha256://')"
    tag="${img##*:}"; [ "$tag" = "$img" ] && tag="latest"
    [ $first -eq 1 ] || echo '    ,'
    first=0
    printf '    {"ref": "%s", "tag": "%s", "digest": "%s"}\n' "$img" "$tag" "$digest"
    # SBOM per image
    if [ "$WANT_SBOM" -eq 1 ] && have syft; then
      name="$(echo "$img" | sed 's#[/:]#_#g')"
      syft "$img" -o spdx-json > "$OUT/SBOM/${name}.spdx.json" 2>/dev/null && echo "  · SBOM $name" >&2
    fi
  done <<< "$IMAGES"
  echo '  ]'
  echo '}'
} | jq . > "$MANIFEST"

if [ "$WANT_SBOM" -eq 1 ] && ! have syft; then
  echo "⚠ syft not found — SBOM/ is empty. Install syft for a bank/CII delivery." >&2
fi

echo "▶ Computing checksums ..."
( cd "$OUT" && sha256 shipgrid-onprem-images.tar.gz release-manifest.json SBOM/* 2>/dev/null > SHA256SUMS ) || \
  ( cd "$OUT" && sha256 shipgrid-onprem-images.tar.gz release-manifest.json > SHA256SUMS )
# keep the classic per-tarball checksum too (mirror-to-registry.sh reads it)
( cd "$OUT" && sha256 shipgrid-onprem-images.tar.gz > shipgrid-onprem-images.tar.gz.sha256 )

echo "▶ Signing (origin proof) ..."
if have cosign && [ -n "$SIGN_KEY" ]; then
  cosign sign-blob --yes --key "$SIGN_KEY" "$OUT/SHA256SUMS" > "$OUT/SHA256SUMS.sig"
  echo "  ✓ SHA256SUMS.sig written"
  while IFS= read -r img; do
    cosign sign --yes --key "$SIGN_KEY" "$img" >/dev/null 2>&1 && echo "  ✓ signed image $img" || echo "  ⚠ could not sign $img (push it first)" >&2
  done <<< "$IMAGES"
else
  echo "⚠ cosign/--sign-key not provided — SHA256SUMS is NOT signed." >&2
  echo "  A bank/CII delivery MUST be signed. Re-run with cosign installed and" >&2
  echo "  --sign-key <cosign.key>. Verification: airgap/verify-bundle.sh." >&2
fi

echo
echo "✓ Bundle in: $OUT"
( cd "$OUT" && ls -1 )
echo "  Ship this whole directory. Client verifies with: airgap/verify-bundle.sh $OUT"
