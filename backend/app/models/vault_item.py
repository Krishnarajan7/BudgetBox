from sqlalchemy import (
    String,
    Text,
    Integer,
    LargeBinary,
    DateTime,
    ForeignKey,
    CheckConstraint,
    Index,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

VAULT_ITEM_TYPES = ("note", "date", "credential", "file")


class VaultItem(Base):
    """A single opaque, client-encrypted vault entry.

    The server never sees plaintext: `title_ct`/`payload_ct`/`file_data` are
    ciphertext blobs produced client-side. `iv`/`file_iv` are the client's
    nonces for those ciphertexts. All fields here are opaque to the backend
    and are only validated for presence/size.
    """

    __tablename__ = "vault_items"

    __table_args__ = (
        CheckConstraint(
            "item_type IN ('note', 'date', 'credential', 'file')",
            name="ck_vault_items_item_type",
        ),
        Index("ix_vault_items_user_id", "user_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    item_type: Mapped[str] = mapped_column(String(20), nullable=False)

    title_ct: Mapped[str] = mapped_column(String(2048), nullable=False)
    payload_ct: Mapped[str] = mapped_column(Text, nullable=False)
    iv: Mapped[str] = mapped_column(String(512), nullable=False)

    file_data: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    file_iv: Mapped[str | None] = mapped_column(String(512), nullable=True)
    file_size: Mapped[int | None] = mapped_column(Integer, nullable=True)

    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )
