"""Entity ids are UUIDv7 strings — time-ordered (append-friendly b-tree inserts,
free creation ordering) and client-generatable, so the phone can mint ids offline
and PUT them idempotently."""

import uuid

from uuid6 import uuid7

from budgetbox.core.errors import Invalid


def new_id() -> str:
    return str(uuid7())


def require_uuid(value: str) -> str:
    """Validate and canonicalize (lowercase) an id supplied by the client.

    Raises `Invalid` (422), never a bare ValueError: a malformed id is the
    client's mistake, and the phone must be able to tell "you sent rubbish"
    from "the server is unwell". A 500 here reads as the latter, so a queued
    write with a bad id would be retried forever instead of being parked.
    """
    try:
        return str(uuid.UUID(value))
    except ValueError as exc:
        raise Invalid(f"not a valid id: {value!r}") from exc
