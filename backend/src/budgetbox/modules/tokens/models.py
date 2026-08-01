from datetime import datetime

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, StampedMixin, UTCInstant, pk_id


class DeviceToken(Base, StampedMixin):
    """One row per provisioned device. Only the SHA-256 of the token is stored;
    the plaintext is printed once at issue time and never persisted."""

    __tablename__ = "device_tokens"

    id: Mapped[str] = pk_id()
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    label: Mapped[str] = mapped_column(String(60))
    last_used_at: Mapped[datetime | None] = mapped_column(UTCInstant(), default=None)
    revoked_at: Mapped[datetime | None] = mapped_column(UTCInstant(), default=None)
