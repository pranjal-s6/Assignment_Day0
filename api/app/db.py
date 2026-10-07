"""Postgres access through a small asyncpg pool.

The DSN points at 127.0.0.1:5432, which inside the Nomad allocation is the Envoy
sidecar's upstream listener for the `postgres` service, not Postgres itself.
"""

import asyncio
import logging

import asyncpg

log = logging.getLogger("api.db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS items (
    id   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text    NOT NULL
)
"""


class Database:
    def __init__(self, pool: asyncpg.Pool) -> None:
        self._pool = pool

    @classmethod
    async def connect(cls, dsn: str, attempts: int = 15, delay: float = 2.0) -> "Database":
        # Postgres (or its sidecar) may come up after us; retry instead of crash-looping the task.
        for attempt in range(1, attempts + 1):
            try:
                pool = await asyncpg.create_pool(dsn, min_size=1, max_size=5, timeout=5)
                return cls(pool)
            except (OSError, asyncpg.PostgresError, asyncio.TimeoutError) as exc:
                log.warning("postgres not ready (attempt %d/%d): %s", attempt, attempts, exc)
                await asyncio.sleep(delay)
        raise RuntimeError("could not connect to postgres")

    async def migrate(self) -> None:
        await self._pool.execute(SCHEMA)

    async def ping(self) -> bool:
        try:
            return await self._pool.fetchval("SELECT 1") == 1
        except (OSError, asyncpg.PostgresError, asyncio.TimeoutError):
            return False

    async def insert(self, name: str) -> dict:
        row = await self._pool.fetchrow("INSERT INTO items (name) VALUES ($1) RETURNING id, name", name)
        return dict(row)

    async def get(self, item_id: int) -> dict | None:
        row = await self._pool.fetchrow("SELECT id, name FROM items WHERE id = $1", item_id)
        return dict(row) if row else None

    async def update(self, item_id: int, name: str) -> dict | None:
        row = await self._pool.fetchrow(
            "UPDATE items SET name = $2 WHERE id = $1 RETURNING id, name", item_id, name
        )
        return dict(row) if row else None

    async def delete(self, item_id: int) -> bool:
        return await self._pool.execute("DELETE FROM items WHERE id = $1", item_id) == "DELETE 1"

    async def close(self) -> None:
        await self._pool.close()
