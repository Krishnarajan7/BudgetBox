"""Opaque keyset cursors over (at, id) — stable under concurrent inserts, unlike
offset pagination."""

import base64
import binascii
from datetime import UTC, datetime

from budgetbox.core.errors import Invalid


def encode_cursor(at: datetime, row_id: str) -> str:
    raw = f"{at.astimezone(UTC).isoformat(timespec='microseconds')}|{row_id}"
    return base64.urlsafe_b64encode(raw.encode()).decode()


def decode_cursor(cursor: str) -> tuple[datetime, str]:
    try:
        raw = base64.urlsafe_b64decode(cursor.encode()).decode()
        at_str, row_id = raw.split("|", 1)
        return datetime.fromisoformat(at_str), row_id
    except (binascii.Error, UnicodeDecodeError, ValueError) as exc:
        raise Invalid("malformed cursor") from exc
