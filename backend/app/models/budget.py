from decimal import Decimal
from sqlalchemy import ForeignKey, Numeric, String, DateTime, func, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database import Base


class Budget(Base):
    __tablename__ = "budgets"

    __table_args__ = (
        Index(
            "ix_budgets_user_category_month",
            "user_id",
            "category_id",
            "month",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    category_id: Mapped[int] = mapped_column(ForeignKey("categories.id"), nullable=False)
    month: Mapped[str] = mapped_column(String(7), nullable=False)
    limit: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="budgets")
