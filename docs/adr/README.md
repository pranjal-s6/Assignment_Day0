# Architecture Decision Records

Short records of the non-obvious choices, in the order they were made. Each one states
the context, the decision, and what it costs.

| # | Decision |
|---|---|
| [0001](0001-run-agents-natively-in-wsl2.md) | Run Nomad and Consul natively in WSL2, not inside Docker |
| [0002](0002-read-through-cache-with-invalidation-and-fail-open.md) | Read-through cache with explicit invalidation and fail-open reads |
| [0003](0003-mesh-only-data-tier-and-deny-by-default.md) | Data tier is mesh-only; intentions are deny-by-default |
| [0004](0004-edge-ingress-through-the-mesh.md) | A small `edge` job is the ingress; the API has no host port |
| [0005](0005-config-from-consul-kv-via-template.md) | Config and secrets from Consul KV via `template {}` |
| [0006](0006-fastapi-async.md) | FastAPI with asyncpg and redis.asyncio |
