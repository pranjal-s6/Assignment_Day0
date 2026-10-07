from typing import Literal

from pydantic import BaseModel, Field


class ItemIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)


class ItemOut(BaseModel):
    id: int
    name: str
    # Where this response was served from. Mirrors the X-Cache header for clients that only read the body.
    source: Literal["cache", "db"]


class Readiness(BaseModel):
    ok: bool
    postgres: bool
    redis: bool
    instance: str
