# ADR 0002: Read-through cache with explicit invalidation and fail-open reads

Date: 2026-10-07 · Status: accepted

## Context

The exercise asks for read-through on `GET /items/{id}`: Redis first, Postgres on a miss,
write back with a TTL. Two questions it leaves open: what do writes do, and what happens
when Redis is unreachable? The second one is not hypothetical here, the "break it on
purpose" step denies `api -> redis` in the mesh.

## Decision

1. **Read-through with TTL** (`CACHE_TTL_SECONDS`, default 60s, sourced from Consul KV).
2. **Write-then-invalidate.** `POST`, `PUT` and `DELETE` write Postgres, then `DEL` the
   key. The next read repopulates from the source of truth. We do not write-through,
   because a write-through that races a concurrent read-through can leave a stale value
   that lives for a full TTL; invalidation cannot.
3. **Fail-open.** Every cache call returns a status instead of raising. If Redis is
   unreachable the read goes to Postgres, skips the write-back, and reports
   `X-Cache: BYPASS`. A cache outage degrades latency, never availability.
4. **Short timeouts** (500ms connect/read) because the sidecar is on localhost: anything
   slower is an outage, and we would rather hit the DB than hang.
5. **Versioned keys** (`item:v1:{id}`) so a change in the cached shape can be shipped
   without a flush.
6. **Visible behaviour.** `X-Cache: HIT | MISS | BYPASS | INVALIDATED` on every response
   and `source` in the body, so the behaviour is observable from `curl -i`.

## Consequences

- Bounded staleness: at most one TTL after an invalidation that failed because Redis was
  down (logged as a warning).
- `/ready` reports Postgres as required and Redis as optional, matching the policy.
- Under a cache outage, Postgres absorbs full read load. For this exercise that is the
  point; in production it is where a circuit breaker or request coalescing would go
  (considered and deliberately left out, see README "what I would do next").
