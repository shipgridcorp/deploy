# Self-hosted / custom LLM models

Every LLM call in the stack goes through the `gate` service (an OpenAI-compatible
proxy), so pointing the platform at a model you host yourself — vLLM, Ollama,
TGI, or any other server that speaks the OpenAI chat-completions API — is a
config-only change. No image rebuilds.

Minimum versions: `gate` ≥ v1.24.0, `ai-analysis` ≥ v1.249.0.

## Option A — one local model for everything

The gate routes any model name it does not recognise to the `openai` provider,
and that provider accepts a `base_url` override. So for a single self-hosted
endpoint you only need two env vars on the gate container:

```env
OPENAI_BASE_URL=http://vllm.internal:8000/v1
OPENAI_API_KEY=anything-your-server-accepts   # blank is fine if the server needs no auth
```

Then set the model name your server expects (e.g. `qwen3-32b-instruct`) as the
global default — or per feature — in the admin console under **AI Settings**.
Done: every feature now talks to your endpoint.

## Option B — hybrid: cloud vendor + local model side by side

When some features should stay on a cloud vendor and others move to your GPU,
give the local endpoint its own provider entry and alias its model names to it
in `config/gate/config.yaml`:

```yaml
providers:
  local:
    base_url: http://vllm.internal:8000/v1
    api_key: ""            # omit auth entirely, or set a token
    timeout_seconds: 300   # local models are often slower; default is 120

# model name → provider. Without an alias an unknown model name would fall
# back to the "openai" provider (i.e. the cloud vendor in a hybrid setup).
model_aliases:
  qwen3-32b-instruct: local
  deepseek-r1-distill-32b: local
```

If the install runs with `BLOCK_FOREIGN_LLM=true` (RU perimeter), also allow the
custom provider name:

```yaml
llm_policy:
  allowed_providers: ["local"]
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
