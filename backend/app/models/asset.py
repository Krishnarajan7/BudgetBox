import enum

from sqlalchemy import String, DateTime, Numeric, Enum, ForeignKey, func, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class AssetKind(enum.Enum):
    ASSET = "asset"
    LIABILITY = "liability"


class Asset(Base):
    __tablename__ = "assets"

    __table_args__ = (
        Index("ix_assets_user_id", "user_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    kind: Mapped[AssetKind] = mapped_column(Enum(AssetKind), nullable=False)
    category: Mapped[str] = mapped_column(String(50), nullable=False)
    value: Mapped[Numeric] = mapped_column(Numeric(14, 2), nullable=False)
    note: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    user = relationship("User")
