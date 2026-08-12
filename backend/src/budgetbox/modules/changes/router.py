"""Deletion-aware, cursor-paginated synchronization feed."""

from datetime import datetime

from fastapi import APIRouter, Query
from sqlalchemy import select

from budgetbox.api.deps import SessionDep
from budgetbox.api.schemas import APIModel, Instant
from budgetbox.core.time import now_utc
from budgetbox.modules.changes.models import ChangeEvent, ChangeOperation

router = APIRouter(prefix="/changes", tags=["changes"])


class ChangeOut(APIModel):
    sequence: int
    resource: str
    resource_id: str
    operation: ChangeOperation


class ChangesOut(APIModel):
    server_time: datetime
    items: list[ChangeOut]
    next_cursor: int
    has_more: bool
    # Compatibility for app builds that still poll by timestamp. New clients
    # ignore these fields and use the durable cursor above.
    now: datetime
    changed: dict[str, list[str]]


@router.get("")
def changes(
    session: SessionDep,
    after: int = Query(default=0, ge=0),
    limit: int = Query(default=200, ge=1, le=500),
    since: Instant | None = None,
) -> ChangesOut:
    """Events strictly after ``after``, oldest first.

    A cursor advances only through rows returned in this page. Deletes remain
    visible as tombstones, and ``has_more`` prevents a large restore from
    silently skipping the tail of the ledger.
    """
    rows = list(
        session.scalars(
            select(ChangeEvent)
            .where(ChangeEvent.sequence > after)
            .order_by(ChangeEvent.sequence)
            .limit(limit + 1)
        )
    )
    has_more = len(rows) > limit
    page = rows[:limit]
    next_cursor = page[-1].sequence if page else after
    server_time = now_utc()

    legacy: dict[str, list[str]] = {}
    if since is not None:
        legacy_rows = session.execute(
            select(ChangeEvent.resource, ChangeEvent.resource_id)
            .where(
                ChangeEvent.changed_at > since,
                ChangeEvent.operation == ChangeOperation.UPSERT,
            )
            .order_by(ChangeEvent.sequence)
        )
        for resource, resource_id in legacy_rows:
            ids = legacy.setdefault(resource, [])
            if resource_id not in ids:
                ids.append(resource_id)

    return ChangesOut(
        server_time=server_time,
        items=[ChangeOut.model_validate(row) for row in page],
        next_cursor=next_cursor,
        has_more=has_more,
        now=server_time,
        changed=legacy,
    )
