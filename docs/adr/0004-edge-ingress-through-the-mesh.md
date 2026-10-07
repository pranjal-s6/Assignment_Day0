# ADR 0004: A small `edge` job is the ingress; the API has no host port

Date: 2026-10-07 · Status: accepted

## Context

The sample `api` job uses `port "http" { static = 8000 }`. The stretch goal asks for
`count = 2`. On a single dev node those are mutually exclusive: the second allocation
can never be placed because port 8000 is taken, and Nomad reports a placement failure.

Options considered:

1. Dynamic port and a lookup script that asks the Consul catalog where the API is.
   Works, but `localhost:8000` from the exercise stops working and nothing balances load.
2. Keep `static = 8000`, document that `count = 2` needs two nodes.
3. A fourth job, `edge`, holding the static port and reaching the API **through the
   mesh** as a Connect upstream.

## Decision

Option 3. `edge` is nginx with a single `proxy_pass http://127.0.0.1:8080`, where 8080 is
its sidecar's upstream listener for `api`. The API has **no host port at all**: its
`service.port` is the numeric `8000` the app listens on inside the netns, exactly like
redis and postgres, and `count = 2` with a rolling `update {}` block.

The health check still works without a host port through `check { expose = true }`:
Nomad allocates a dynamic port and configures Envoy to forward it to `/health` on
`127.0.0.1:8000` inside the namespace, so Consul checks the app via the sidecar.

**What went wrong first (2026-10-07):** the first version used `port "http" { to = 8000 }`
plus `service.port = "http"`, "a dynamic port for the health check". That registers the
sidecar's local service port as the *host* port of the label (e.g. `21478`), so the API's
Envoy forwarded mesh traffic to `127.0.0.1:21478` inside the netns, where nothing listens.
The symptom was confusing: the health check passed (Consul hits the host port, which
port-maps to 8000), TLS and intentions were fine, `edge` got a clean `503 upstream connect
error` from the API's own sidecar. Envoy's `local_app` cluster stats
(`cx_connect_fail`) pointed at it. Rule: for a Connect service, `service.port` is the port
*inside the namespace*; use a numeric value, not a label.

## Consequences

- `curl localhost:8000` works exactly as the exercise describes.
- Load-balancing across API instances is done by Envoy from Consul's catalog, with no
  nginx `upstream {}` block to keep in sync. `X-Instance` in responses shows it happening.
- One extra job (~50 lines) and one extra intention (`edge -> api`).
- The API is mesh-only: the only way to reach it is through an identity Consul
  recognises. The single published host port in the whole system is the edge's `8000`
  (the `expose` ports only serve `/health` and only to Consul).
