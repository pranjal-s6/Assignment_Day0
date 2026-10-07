"""Items API: read-through cache (Redis) in front of Postgres.

Both dependencies are reached via localhost ports owned by this allocation's Envoy
sidecar (see jobs/api.nomad.hcl `upstreams`). The app has no idea where they live.
"""

import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query, Request, Response

from .cache import Cache
from .db import Database
from .models import ItemIn, ItemOut, Readiness

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("api")

# Nomad injects NOMAD_ALLOC_ID; surfacing it lets you see which of the count=2 instances answered.
INSTANCE = os.getenv("NOMAD_ALLOC_ID", "local")[:8]
TTL = int(os.getenv("CACHE_TTL_SECONDS", "60"))


def cache_key(item_id: int) -> str:
    # Versioned so a future change to the cached shape can't be poisoned by old entries.
    return f"item:v1:{item_id}"


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.db = await Database.connect(os.environ["DATABASE_URL"])
    app.state.cache = Cache(os.environ["REDIS_URL"], ttl=TTL)
    await app.state.db.migrate()
    log.info("ready instance=%s cache_ttl=%ss", INSTANCE, TTL)
    try:
        yield
    finally:
        await app.state.cache.close()
        await app.state.db.close()


app = FastAPI(title="items-api", lifespan=lifespan)


@app.middleware("http")
async def tag_instance(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Instance"] = INSTANCE
    return response


@app.get("/health")
async def health() -> dict:
    # Liveness only: "the process is up". Consul/Nomad poll this.
    return {"ok": True}


@app.get("/ready", response_model=Readiness)
async def ready(request: Request, response: Response) -> Readiness:
    # Readiness: can this instance actually serve? Postgres is required, Redis is optional (fail-open).
    pg = await request.app.state.db.ping()
    rd = await request.app.state.cache.ping()
    if not pg:
        response.status_code = 503
    return Readiness(ok=pg, postgres=pg, redis=rd, instance=INSTANCE)


@app.post("/items", response_model=ItemOut, status_code=201)
async def create_item(
    request: Request,
    response: Response,
    name: str | None = Query(default=None, min_length=1, max_length=200),
    body: ItemIn | None = None,
) -> ItemOut:
    # Accept both `POST /items?name=x` (as in the exercise) and a JSON body.
    item_name = body.name if body else name
    if not item_name:
        raise HTTPException(422, "name is required: ?name=... or JSON {\"name\": ...}")
    row = await request.app.state.db.insert(item_name)
    # Ids are never reused (IDENTITY), so this is a no-op by construction; kept so every
    # write path invalidates uniformly and the behaviour is explicit in the headers.
    await request.app.state.cache.delete(cache_key(row["id"]))
    response.headers["X-Cache"] = "INVALIDATED"
    return ItemOut(**row, source="db")


@app.get("/items/{item_id}", response_model=ItemOut)
async def read_item(item_id: int, request: Request, response: Response) -> ItemOut:
    # Read-through: cache -> on miss, db -> write back with TTL.
    key = cache_key(item_id)
    cached, status = await request.app.state.cache.get(key)
    response.headers["X-Cache"] = status
    if cached is not None:
        return ItemOut(**cached, source="cache")

    row = await request.app.state.db.get(item_id)
    if row is None:
        raise HTTPException(404, "item not found")
    if status != "BYPASS":
        await request.app.state.cache.set(key, row)
    return ItemOut(**row, source="db")


@app.put("/items/{item_id}", response_model=ItemOut)
async def update_item(
    item_id: int,
    request: Request,
    response: Response,
    name: str | None = Query(default=None, min_length=1, max_length=200),
    body: ItemIn | None = None,
) -> ItemOut:
    item_name = body.name if body else name
    if not item_name:
        raise HTTPException(422, "name is required: ?name=... or JSON {\"name\": ...}")
    row = await request.app.state.db.update(item_id, item_name)
    if row is None:
        raise HTTPException(404, "item not found")
    # Write-then-invalidate: the next read repopulates from the source of truth.
    await request.app.state.cache.delete(cache_key(item_id))
    response.headers["X-Cache"] = "INVALIDATED"
    return ItemOut(**row, source="db")


@app.delete("/items/{item_id}", status_code=204)
async def delete_item(item_id: int, request: Request, response: Response) -> Response:
    if not await request.app.state.db.delete(item_id):
        raise HTTPException(404, "item not found")
    await request.app.state.cache.delete(cache_key(item_id))
    return Response(status_code=204, headers={"X-Cache": "INVALIDATED"})
