"""Entity ids are UUIDv7 strings — time-ordered (append-friendly b-tree inserts,
free creation ordering) and client-generatable, so the phone can mint ids offline
and PUT them idempotently."""

import uuid

from uuid6 import uuid7


def new_id() -> str:
    return str(uuid7())


def require_uuid(value: str) -> str:
    """Validate and canonicalize (lowercase) an id supplied by the client."""
    try:
        return str(uuid.UUID(value))
    except ValueError as exc:
        raise ValueError(f"not a valid uuid: {value!r}") from exc
