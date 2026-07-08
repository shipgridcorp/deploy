# Observability — Grafana dashboards

Every ShipGrid service exposes Prometheus metrics (prefixed `shipgrid_`) on
`/metrics`. The Grafana dashboards that visualize them live in
[`dashboards/`](dashboards/) — import them into your own Grafana, or let the
bundled monitoring stack provision them for you.

## Option 1 — bundled stack (auto-provisioned)

You don't need to import anything; the dashboards land in Grafana automatically.

- **Docker Compose** (`compose/`): start the monitoring profile
  ```bash
  docker compose --profile monitoring up -d
  ```
  Prometheus + Grafana come up and the dashboards appear in Grafana under the
  **ShipGrid** folder. Open `http://<host>:3000` (`admin` / `GRAFANA_ADMIN_PASSWORD`).

- **Kubernetes / Helm** (`kubernetes/helm-chart/`): enable the stack in your values
  ```yaml
  observability:
    monitoring:
      enabled: true
  ```
  The chart provisions the same Prometheus datasource + dashboards into the
  bundled Grafana.

## Option 2 — bring your own Grafana

If you already run Grafana and Prometheus:

1. Point Prometheus at each ShipGrid service's `/metrics`. The scrape config the
   bundle uses is in [`compose/config/prometheus/prometheus.yml`](../compose/config/prometheus/prometheus.yml)
   (job `shipgrid`) — copy the relabeling from there.
2. In Grafana: **Dashboards → New → Import**, then upload each file from
   [`dashboards/`](dashboards/).
3. When prompted, pick your Prometheus datasource. The panels reference a
   datasource with **uid `prometheus`** — either give your Prometheus datasource
   that uid, or remap it in the import dialog.

## Dashboards

| File | Shows |
|---|---|
| [`dashboards/shipgrid-service-overview.json`](dashboards/shipgrid-service-overview.json) | RPS, latency and error rate per service |
| [`dashboards/shipgrid-http-runtime.json`](dashboards/shipgrid-http-runtime.json) | HTTP request rate and status codes by service |
| [`dashboards/shipgrid-ai-llm.json`](dashboards/shipgrid-ai-llm.json) | LLM calls, tokens, latency and cost |
| [`dashboards/shipgrid-service-health.json`](dashboards/shipgrid-service-health.json) | Which services are up/down, 5xx error rate and P95 latency per service |

All four dashboards read the standard `/metrics` scrape (job `shipgrid` in
Compose, `shipgrid-pods` in Kubernetes) — no blackbox-exporter or extra probes
required.

## Keeping copies in sync

These JSON files are the source of truth. They are mirrored, byte-for-byte, into
each self-contained deployment scenario so an air-gapped bundle carries its own
copy:

- `compose/config/grafana/dashboards/`
- `kubernetes/helm-chart/files/dashboards/`

CI (`dashboard-drift`) fails if the three copies diverge. After editing a
dashboard here, run `scripts/sync-dashboards.sh` to refresh both mirrors in the
same commit.
