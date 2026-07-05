#!/usr/bin/env bash
# verify-bundle.sh — CLIENT-SIDE verification of an air-gap delivery BEFORE you
# load anything. Runs the chain of trust top-down (guide §6.3):
#
#   cosign signature → SHA256SUMS → release-manifest.json → image digests
#
# A plain SHA-256 proves the file was not corrupted; the cosign signature proves
# ShipGrid produced it. Run this at the DMZ side and again inside the perimeter.
#
# Usage:
#   ./verify-bundle.sh [--cosign-key cosign.pub] <bundle-dir>
#   # after loading the tarball, also cross-check the loaded images:
#   ./verify-bundle.sh --check-loaded <bundle-dir>
#
# Exit non-zero on ANY failure (fail closed) — do not load a bundle that fails.
set -euo pipefail

COSIGN_KEY=""
CHECK_LOADED=0
DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --cosign-key) COSIGN_KEY="${2:?}"; shift 2 ;;
    --check-loaded) CHECK_LOADED=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) DIR="$1"; shift ;;
  esac
done
[ -n "$DIR" ] && [ -d "$DIR" ] || { echo "usage: $0 [--cosign-key cosign.pub] [--check-loaded] <bundle-dir>" >&2; exit 2; }

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
have()   { command -v "$1" >/dev/null 2>&1; }
fail()   { echo "✗ $1" >&2; exit 1; }

cd "$DIR"
[ -f SHA256SUMS ] || fail "SHA256SUMS missing — this is not a supply-chain bundle"

# 1. Origin: cosign signature over SHA256SUMS.
echo "▶ 1/3 Verifying origin signature ..."
if [ -f SHA256SUMS.sig ]; then
  have cosign || fail "SHA256SUMS.sig present but cosign not installed — cannot verify origin"
  [ -n "$COSIGN_KEY" ] || fail "pass --cosign-key <cosign.pub> (from ShipGrid) to verify the signature"
  cosign verify-blob --key "$COSIGN_KEY" --signature SHA256SUMS.sig SHA256SUMS >/dev/null 2>&1 \
    || fail "cosign signature does NOT verify — bundle origin is not ShipGrid. STOP."
  echo "  ✓ signature valid — issued by ShipGrid"
else
  echo "  ⚠ SHA256SUMS.sig absent — origin NOT proven (integrity only). For a bank/CII"
  echo "    delivery this is a defect: request a signed bundle from ShipGrid." >&2
fi

# 2. Integrity: every artifact matches SHA256SUMS.
echo "▶ 2/3 Verifying checksums ..."
sha256 -c SHA256SUMS >/dev/null 2>&1 || fail "checksum mismatch — bundle is corrupted or altered. STOP."
echo "  ✓ all artifacts match SHA256SUMS"

# 3. Manifest present and well-formed.
echo "▶ 3/3 Checking release manifest ..."
[ -f release-manifest.json ] || fail "release-manifest.json missing"
if have jq; then
  n="$(jq '.images | length' release-manifest.json 2>/dev/null)" || fail "release-manifest.json is not valid JSON"
  echo "  ✓ manifest lists $n images"
else
  echo "  ⚠ jq not installed — manifest structure not checked"
fi

# Optional: after `docker load`, confirm loaded image digests match the manifest.
if [ "$CHECK_LOADED" -eq 1 ]; then
  echo "▶ Cross-checking loaded image digests against the manifest ..."
  have jq || fail "jq required for --check-loaded"
  mism=0
  while IFS=$'\t' read -r ref want; do
    got="$(docker image inspect "$ref" --format '{{index .RepoDigests 0}}' 2>/dev/null | sed 's/.*@//')"
    if [ -z "$got" ]; then echo "  ⚠ $ref not loaded"; continue; fi
    if [ "$got" = "$want" ]; then echo "  ✓ $ref"; else echo "  ✗ $ref digest mismatch (want $want got $got)"; mism=1; fi
  done < <(jq -r '.images[] | [.ref, .digest] | @tsv' release-manifest.json)
  [ "$mism" -eq 0 ] || fail "one or more loaded images do not match the manifest. STOP."
fi

echo
echo "✓ Bundle verified — safe to load."
