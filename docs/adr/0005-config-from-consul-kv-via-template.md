# ADR 0005: Connection details and secrets come from Consul KV via `template {}`

Date: 2026-10-07 · Status: accepted

## Context

The sample jobs hard-code `POSTGRES_PASSWORD = "app"` and `DATABASE_URL = "postgresql://app:app@..."`
in `env {}`. Stretch goal four asks to pull `DATABASE_URL` from Consul KV instead.

## Decision

Both the producer and the consumer of the credential read the same keys:

| Key | Used by |
|---|---|
| `app/db/user`, `app/db/password`, `app/db/name` | `postgres` task (env for initdb) and `api` task (`DATABASE_URL`) |
| `app/cache/ttl` | `api` task (`CACHE_TTL_SECONDS`), with `keyOrDefault` so it is optional |

Rendered into `secrets/*.env` with `env = true`, and `change_mode = "restart"` on the
API so a KV change rolls the instances (one at a time, thanks to the `update {}` block).

## Consequences

- No credential appears in a job file or in `git`.
- `scripts/seed-kv.sh` must run before `make deploy`: a template that references a
  missing key blocks the task in `pending` until the key exists. That is a feature
  (the task never starts with a wrong config) but it is the first thing to check when an
  allocation seems stuck.
- Changing the TTL is `consul kv put app/cache/ttl 5` followed by a rolling restart you
  can watch in the Nomad UI.
- In a real deployment the password would live in Vault and the template would use
  `{{ with secret "..." }}`; the stanza shape is identical, which is the point of
  learning it this way.
