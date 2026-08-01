import hashlib
import secrets
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from budgetbox.core.errors import NotFound
from budgetbox.core.ids import new_id
from budgetbox.core.time import now_utc
from budgetbox.modules.tokens.models import DeviceToken

TOKEN_PREFIX = "bbx_"
_LAST_USED_GRANULARITY = timedelta(minutes=15)  # avoid a DB write on every request

# Transaction convention (all services): SQLAlchemy autobegins on first use, so a
# service does its reads and writes, then session.commit() — one atomic unit.


def _hash(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


def issue(session: Session, label: str) -> tuple[DeviceToken, str]:
    """Mint a token. Returns (row, plaintext); plaintext exists only in this return value."""
    raw = TOKEN_PREFIX + secrets.token_urlsafe(32)
    row = DeviceToken(id=new_id(), token_hash=_hash(raw), label=label)
    session.add(row)
    session.commit()
    return row, raw


def authenticate(session: Session, raw: str) -> DeviceToken | None:
    row = session.scalar(
        select(DeviceToken).where(
            DeviceToken.token_hash == _hash(raw),
            DeviceToken.revoked_at.is_(None),
        )
    )
    if row is None:
        return None
    now = now_utc()
    if row.last_used_at is None or now - row.last_used_at > _LAST_USED_GRANULARITY:
        row.last_used_at = now
        session.commit()
    return row


def revoke(session: Session, token_id: str) -> DeviceToken:
    row = session.get(DeviceToken, token_id)
    if row is None:
        raise NotFound(f"no token with id {token_id}")
    row.revoked_at = now_utc()
    session.commit()
    return row


def list_tokens(session: Session) -> list[DeviceToken]:
    return list(session.scalars(select(DeviceToken).order_by(DeviceToken.created_at)))
