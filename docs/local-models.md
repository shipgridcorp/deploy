# Self-hosted / custom LLM models

Every LLM call in the stack goes through the `gate` service (an OpenAI-compatible
proxy), so pointing the platform at a model you host yourself — vLLM, Ollama,
TGI, or any other server that speaks the OpenAI chat-completions API — is a
config-only change. No image rebuilds.

Minimum versions: `gate` ≥ v1.24.0, `ai-analysis` ≥ v1.249.0.

## The `local` provider — set once, works for one model or several

Every deploy target (Compose, Kubernetes, air-gap) already ships a `local`
provider entry in `config/gate/config.yaml`, driven by env vars — no need to
write YAML from scratch:

```yaml
providers:
  local:
    base_url: ${LOCAL_LLM_BASE_URL:-}
    api_key: ${LOCAL_LLM_API_KEY:-}
    timeout_seconds: 300   # local models are often slower; default is 120
```

It is named `local`, not `openai`, on purpose: the built-in `openai` provider is
gated by `llm_policy.allowed_providers` like any foreign vendor, so on the
default RU/on-prem policy (`BLOCK_FOREIGN_LLM=true`) it never instantiates
regardless of `base_url` — pointing a self-hosted model at `OPENAI_BASE_URL`
silently does nothing there. `local` avoids that trap, but still needs one
manual opt-in (a custom provider name isn't domestic-by-default even though it
never leaves your perimeter — the policy has no way to know that from
`base_url` alone):

```yaml
llm_policy:
  allowed_providers: ["local"]
```

## Option A — one local model for everything

```env
LOCAL_LLM_BASE_URL=http://vllm.internal:8000/v1
LOCAL_LLM_API_KEY=anything-your-server-accepts   # blank is fine if the server needs no auth
```

(Compose: set these in `.env`. Kubernetes: `--set llm.local.baseURL=… --set llm.local.apiKey=…`.)

Then set the model name your server expects (e.g. `qwen3-32b-instruct`) as the
global default — or per feature — in the admin console under **AI Settings**.
Done: every feature now talks to your endpoint.

> Non-RU installs only (`BLOCK_FOREIGN_LLM=false`): you can use the `openai`
> provider instead of `local` — `OPENAI_BASE_URL`/`OPENAI_API_KEY` — since it's
> unblocked there and needs no `allowed_providers` entry. On the RU/on-prem
> default, use `local` as above.

## Option B — hybrid: cloud vendor + local model side by side

When some features should stay on a cloud vendor and others move to your GPU,
alias the specific model names to `local` in `config/gate/config.yaml` (set
`LOCAL_LLM_BASE_URL`/`LOCAL_LLM_API_KEY` as above, then add):

```yaml
# model name → provider. Without an alias an unknown model name falls back to
# the "openai" provider (i.e. the cloud vendor in a hybrid setup) — blocked by
# default under the RU policy, same as above.
model_aliases:
  qwen3-32b-instruct: local
  deepseek-r1-distill-32b: local
```

Restart the gate, then assign the aliased model names to the features you want
moved in **AI Settings**.

## Things to know

- **Pricing rows.** If strict DB pricing is enabled
  (`billing.disable_hardcoded_price_fallback: true`), every provider+model pair
  must have a `token_prices` row or requests are rejected with
  "pricing not configured". A provider-wide wildcard row works:
  `INSERT INTO token_prices (provider, model, input_cost_per_1k, output_cost_per_1k) VALUES ('local', '*', 0, 0);`
  With the default (non-strict) pricing this step is unnecessary.
- **Background-job throughput.** Multi-request background jobs (indexing,
  ingestion, scaffold, test generation) run against the gate with bounded
  parallelism — `WORKFLOW_SYNC_MULTICHAT_CONCURRENCY` on the `ai-analysis`
  container, default 4. Raise it if your GPU server has capacity, lower it to 1
  if it must be protected.
- **Leave the OpenAI Batch flags off.** All `prefer_openai_batch_*` /
  `openai_batch_for_*` toggles must stay at their default `false` on-prem: the
  OpenAI Batch API is proprietary to api.openai.com and no self-hosted stack
  implements it. The platform detects gate-issued keys and fails Batch attempts
  fast, falling back to the realtime path — but there is nothing to gain from
  enabling them.
- **Timeouts.** Reasoning-heavy generations on a 14–32B model can run minutes.
  `timeout_seconds` on the provider entry covers a single completion; keep it
  ≥ 300 for large local models.
