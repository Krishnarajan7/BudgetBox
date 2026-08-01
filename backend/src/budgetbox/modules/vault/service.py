"""Vault storage. Deliberately dumb: put a blob at an id, hand blobs back, drop
one. Nothing here inspects, indexes, or logs a payload — the server cannot read
these bytes and must not be able to leak them either."""

from sqlalchemy import select
from sqlalchemy.orm import Session

from budgetbox.core.errors import Conflict, NotFound
from budgetbox.core.ids import require_uuid
from budgetbox.modules.vault.models import VaultItem
from budgetbox.modules.vault.schemas import VaultItemIn


def list_items(session: Session) -> list[VaultItem]:
    """Single user, small set: return the whole vault and let the device decrypt."""
    return list(session.scalars(select(VaultItem).order_by(VaultItem.id)))


def upsert(session: Session, item_id: str, data: VaultItemIn) -> VaultItem:
    """PUT semantics with an optional precondition. Two devices editing the same
    secret would otherwise silently clobber each other, and a lost password has
    no undo — so a stale expected_updated_at is a 409, not a merge."""
    item_id = require_uuid(item_id)
    row = session.get(VaultItem, item_id)
    if row is None:
        row = VaultItem(id=item_id)
        session.add(row)
    elif data.expected_updated_at is not None and data.expected_updated_at != row.updated_at:
        raise Conflict("vault item changed since you loaded it")
    row.nonce = data.nonce
    row.cipher = data.cipher
    session.commit()
    return row


def delete(session: Session, item_id: str) -> None:
    """Hard delete: a deleted secret leaves no tombstone to attack."""
    row = session.get(VaultItem, item_id)
    if row is None:
        raise NotFound(f"no vault item {item_id}")
    session.delete(row)
    session.commit()
