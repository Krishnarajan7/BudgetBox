from sqlalchemy import String, Integer, DateTime, ForeignKey, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class VaultConfig(Base):
    """Public KDF material for a user's client-side-encrypted vault.

    This table never stores a passphrase or plaintext. `canary_ct`/`canary_iv`
    hold a client-encrypted known value the client uses to verify a supplied
    passphrase locally, purely opaque to the server.
    """

    __tablename__ = "vault_configs"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
    )

    kdf_salt: Mapped[str] = mapped_column(String(512), nullable=False)
    kdf_iterations: Mapped[int] = mapped_column(Integer, nullable=False)

    canary_ct: Mapped[str] = mapped_column(String(2048), nullable=False)
    canary_iv: Mapped[str] = mapped_column(String(512), nullable=False)

    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
