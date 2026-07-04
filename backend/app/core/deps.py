from dataclasses import dataclass
from fastapi import Query


@dataclass
class PaginationParams:
    limit: int
    offset: int


def pagination(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
) -> PaginationParams:
    return PaginationParams(limit=limit, offset=offset)
