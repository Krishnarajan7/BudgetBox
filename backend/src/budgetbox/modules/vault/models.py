from sqlalchemy import Text
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, StampedMixin, pk_id


class VaultItem(Base, StampedMixin):
    """Zero-knowledge: the server only ever holds opaque base64 blobs (AES-GCM on
    the device). No plaintext, no key material, and /v1/vault bodies are never
    logged. Titles exist only decrypted in the app's memory."""

    __tablename__ = "vault_items"

    id: Mapped[str] = pk_id()
    nonce: Mapped[str] = mapped_column(Text)
    cipher: Mapped[str] = mapped_column(Text)
