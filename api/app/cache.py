"""Fail-open Redis cache.

A cache outage (or a mesh intention denying api -> redis) must degrade reads to the
database, never fail them. Every call therefore reports a status instead of raising:

    HIT     value came from Redis
    MISS    Redis answered, key absent
    BYPASS  Redis unreachable; caller should go to the database and skip the write-back
"""

import json
import logging
from typing import Literal

import redis.asyncio as redis
from redis.asyncio.retry import Retry
from redis.backoff import ExponentialBackoff
from redis.exceptions import ConnectionError as RedisConnectionError
from redis.exceptions import RedisError
from redis.exceptions import TimeoutError as RedisTimeoutError

log = logging.getLogger("api.cache")

Status = Literal["HIT", "MISS", "BYPASS"]


class Cache:
    def __init__(self, url: str, ttl: int) -> None:
        self.ttl = ttl
        self._r = redis.from_url(
            url,
            decode_responses=True,
            # The sidecar is on localhost; anything slower than this is an outage, not latency.
            socket_connect_timeout=0.5,
            socket_timeout=0.5,
            # Redis closes idle connections (--timeout 10). Two defences, because a pooled
            # connection the server already closed otherwise costs the first request after a
            # quiet spell a spurious BYPASS (seen 2026-10-07 after ~1h idle):
            #   - health_check_interval: PING any connection idle > 5s before reusing it, and
            #     reconnect if the PING fails (5 < 10, so stale sockets are caught first);
            #   - retry: one transparent re-run on a connection error.
            # A real outage exhausts both fast and surfaces as BYPASS, which is the point.
            health_check_interval=5,
            retry=Retry(ExponentialBackoff(cap=0.1, base=0.01), retries=2),
            retry_on_error=[RedisConnectionError, RedisTimeoutError],
        )

    async def get(self, key: str) -> tuple[dict | None, Status]:
        try:
            raw = await self._r.get(key)
        except RedisError as exc:
            log.warning("cache unavailable, bypassing: key=%s err=%s", key, exc)
            return None, "BYPASS"
        if raw is None:
            return None, "MISS"
        return json.loads(raw), "HIT"

    async def set(self, key: str, value: dict) -> bool:
        try:
            await self._r.set(key, json.dumps(value), ex=self.ttl)
            return True
        except RedisError as exc:
            log.warning("cache write skipped: key=%s err=%s", key, exc)
            return False

    async def delete(self, key: str) -> bool:
        try:
            await self._r.delete(key)
            return True
        except RedisError as exc:
            # Stale-on-outage: the key expires by TTL anyway, so this is bounded staleness, not corruption.
            log.warning("cache invalidation skipped: key=%s err=%s", key, exc)
            return False

    async def ping(self) -> bool:
        try:
            return bool(await self._r.ping())
        except RedisError:
            return False

    async def close(self) -> None:
        await self._r.aclose()
