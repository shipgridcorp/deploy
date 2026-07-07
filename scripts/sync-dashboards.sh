#!/usr/bin/env bash
# Mirror the canonical Grafana dashboards into each self-contained deployment
# scenario. Source of truth: observability/dashboards/. Run after editing a
# dashboard; CI (`dashboard-drift`) enforces that these stay identical.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/observability/dashboards"
mirrors=(
  "$root/compose/config/grafana/dashboards"
  "$root/kubernetes/helm-chart/files/dashboards"
)

for dst in "${mirrors[@]}"; do
  mkdir -p "$dst"
  # Remove stale JSON so renamed/deleted dashboards don't linger in a mirror.
  find "$dst" -maxdepth 1 -name '*.json' -delete
  cp "$src"/*.json "$dst"/
  echo "synced -> ${dst#"$root/"}"
done

echo "OK: dashboards mirrored from observability/dashboards/"
