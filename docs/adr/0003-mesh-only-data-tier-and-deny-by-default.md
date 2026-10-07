# ADR 0003: Data tier is reachable only through the mesh; intentions are deny-by-default

Date: 2026-10-07 · Status: accepted

## Context

The sample jobs in the exercise declare `port "db" { to = 5432 }` and
`port "redis" { to = 6379 }`. In bridge mode that publishes a dynamic host port for each,
which means Redis and Postgres are reachable from the host without going through a
sidecar at all. The mesh would be optional, not enforced.

Consul in `-dev` mode also defaults to allow-all intentions.

## Decision

- **No host ports for redis and postgres.** The `service.port` is the numeric port inside
  the allocation's network namespace; only the sidecar can reach it. The only published
  host port in the whole system is the edge's `8000`.
- **Deny-by-default.** A wildcard `service-intentions` entry (`*` -> `*`: deny) plus three
  explicit allows: `edge -> api`, `api -> redis`, `api -> postgres`. Applied as versioned
  config-entry files, in an order that writes the allows before the deny.
- **Explicit protocols** via `service-defaults` (`http` for edge/api, `tcp` for the data
  tier) so Envoy builds the right filter chains and the Consul UI topology view is accurate.

## Consequences

- `redis-cli -h localhost` and `psql -h localhost` fail by construction. Debugging goes
  through `nomad alloc exec`, which is the right habit.
- Health checks for redis/postgres must be `script` checks (run inside the container),
  not TCP checks from the host.
- Adding a new consumer of Redis is a one-file change under `consul/config-entries/`,
  reviewed like code.
- Intentions are enforced on **new** connections. Pooled connections survive a policy
  change until they are closed, which is why redis runs with `--timeout 10` and the
  chaos script waits 12 seconds. (See [`scripts/chaos.sh`](../../scripts/chaos.sh).)
