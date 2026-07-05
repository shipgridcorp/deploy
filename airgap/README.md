# Scenario C · Air-gapped

Deployment into a fully isolated perimeter: no internet, artifacts enter only
through your approved transfer channel.

Air-gap is not a third deployment technology — it is Scenario
[A (Compose)](../compose/) or [B (Kubernetes)](../kubernetes/) fed from a
**delivery bundle** instead of the internet. This folder holds the tooling for
that feed.

## What the air-gap delivery contains

Standard for **every** air-gap delivery — a plain SHA-256 proves integrity but
not origin, so the bundle is also signed and carries an SBOM:

| Artifact | Purpose |
|---|---|
| `shipgrid-onprem-images.tar.gz` + `.sha256` | all platform service images (docker-save) |
| `release-manifest.json` | image list with tags + **sha256 digests** + versions |
| `SBOM/*.spdx.json` | per-image SBOM for security audit |
| `SHA256SUMS` + `SHA256SUMS.sig` | checksums of every artifact + **cosign signature (origin proof)** |
| Release notes + compatibility matrix | versions of every component, what changed |
| Inference-server image (vLLM) + open-model weights | self-hosted LLM on your GPU node |
| Scanner feeds: `trivy-db`, `nuclei-templates` | security scans work offline |
| `license.signed.json` | offline license validation — the public key is embedded in the images |
| Russian Trusted Root CA | only if GigaChat is used inside the perimeter |

For banks / CII, additionally: cosign per-image signatures, an extended CVE
report + VEX, image scan results, and a crypto format agreed in advance.

**Verify the chain, twice** — at the DMZ side and after transfer into the
perimeter, before loading anything. `verify-bundle.sh` runs origin →
checksums → manifest top-down and fails closed:

```bash
./verify-bundle.sh --cosign-key shipgrid-cosign.pub <bundle-dir>
# after `docker load`, cross-check the loaded image digests:
./verify-bundle.sh --check-loaded <bundle-dir>
```

The vendor builds this bundle with `build-bundle.sh` (see its header).

## C1 — single server (Compose)

The bundle goes straight into the local Docker daemon; no registry needed:

```bash
cd ../compose
./install.sh --bundle /path/to/shipgrid-onprem-images.tar.gz
# .env: LOCAL_LLM_BASE_URL=http://<vllm-host>:<port>/v1
#       license.signed.json → ./license.json   (public key is embedded in the images)
# + route your model names via model_aliases in config/gate/config.yaml
# After first login: assign the chat / chat-light / embeddings roles to your
# models in the admin console (AI Settings → Providers) — AI features stay
# inactive until the roles are assigned; the assignment is the only source.
```

## C2 — Kubernetes

Load the bundle and push it into your internal registry, then install the
chart exactly as in [Scenario B](../kubernetes/) with three air-gap overrides:

```bash
./mirror-to-registry.sh --bundle shipgrid-onprem-images.tar.gz harbor.internal/shipgrid
```

- `--set global.registry=harbor.internal/shipgrid` — images only from inside;
- LLM = a Service in the namespace: `--set llm.local.baseURL=http://vllm:8000/v1`
  + route your model names via `model_aliases` in `configs/gate/config.yaml`;
  after first login assign the chat / chat-light / embeddings roles to your
  models in the admin console (AI Settings → Providers) — the assignment is
  the only source, AI features stay inactive until it is made;
- `--set networkPolicy.enabled=true` with **default-deny egress** — no outbound
  traffic at all.

Third-party infra images (postgres, redis, …) are skipped by default; add
`--all` to mirror them too (retagged by basename — set the chart's
`infra.*.image` values to match).

## Self-hosted LLM + scanner feeds

- vLLM / Ollama / TGI on the GPU node → OpenAI-compatible endpoint; connected
  through the built-in OpenAI-compatible connector, no code changes. Model
  choice and GPU sizing: Part 7 of the guide.
- Load `trivy-db` / `nuclei-templates` from the bundle into the security
  service (volume mount) — **without the feeds, security scans return empty
  results**; that is the most common first-launch mistake.

## License offline

Same as everywhere (guide §3.2): renewal = transfer a new signed file and swap
it (Compose: replace `license.json`; K8s: update the Secret). Picked up within
~6h or on restart. No online activation.

## Acceptance

- [ ] All services healthy (`smoke.sh` / `kubectl get pods`).
- [ ] billing `/readyz` = ok, license `active`.
- [ ] Zero egress (verify firewall / NetworkPolicy).
- [ ] Security scan passes on local feeds.
- [ ] AI responds through the self-hosted LLM.

## Updating in air-gap

New bundle → transfer → verify checksums → load into the registry →
`helm upgrade` (C2) or `install.sh --bundle` (C1). Scanner feeds ship as a
separate package on their own cadence.
