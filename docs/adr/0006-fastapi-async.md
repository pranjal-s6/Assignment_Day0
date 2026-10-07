# ADR 0006: FastAPI with asyncpg and redis.asyncio

Date: 2026-10-07 · Status: accepted

## Context

The exercise allows FastAPI or Django. The API does three things, all I/O bound: talk to
Redis, talk to Postgres, serialise JSON.

## Decision

FastAPI on uvicorn, fully async:

- `asyncpg` pool (1-5 connections) instead of psycopg: native async, no thread pool.
- `redis.asyncio` with a retry policy tuned for a localhost sidecar.
- `lifespan` context manager (the `@app.on_event("startup")` in the sample is deprecated)
  with a bounded connect-retry loop so the task does not crash-loop while Postgres and
  the sidecars come up.
- Pydantic models for the request/response shapes; typed `source` field.
- Separate `/health` (liveness) and `/ready` (readiness with dependency state).

## Consequences

- No ORM and no migrations framework: one `CREATE TABLE IF NOT EXISTS` at startup. For
  one table that is honest; the moment there is a second table, this becomes an Alembic
  `prestart` task in the job.
- Django would have given the ORM for free but required a migration task and a sync
  cache client; the async story is simpler to reason about for a cache-in-front-of-DB
  service and makes the fail-open timeouts precise.
- Python 3.13 image rather than 3.14 because uvicorn's 3.14 support was still marked
  experimental when this was pinned (2026-10-07).
