import enum

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, StampedMixin, pk_id, str_enum


class BudgetPeriod(enum.StrEnum):
    MONTH = "month"
    FY = "fy"
    CUSTOM = "custom"  # a one-off "trip book": no time window, hand-added txns


class BudgetKind(enum.StrEnum):
    ALL = "all"  # auto-includes every matching txn
    ADDED = "added"  # counts only hand-picked txns


class Budget(Base, StampedMixin):
    __tablename__ = "budgets"
    __table_args__ = (CheckConstraint("limit_paise > 0", name="limit_positive"),)

    id: Mapped[str] = pk_id()
    # Null category = the overall budget across all spending.
    category_id: Mapped[str | None] = mapped_column(ForeignKey("categories.id"), default=None)
    name: Mapped[str] = mapped_column(String(60))
    limit_paise: Mapped[int]
    period: Mapped[BudgetPeriod] = mapped_column(str_enum(BudgetPeriod, "budget_period"))
    kind: Mapped[BudgetKind] = mapped_column(str_enum(BudgetKind, "budget_kind"))
    rollover: Mapped[bool] = mapped_column(Boolean, default=False)
    archived: Mapped[bool] = mapped_column(Boolean, default=False)


class BudgetTxn(Base, StampedMixin):
    """Hand-picked membership for `added`-kind budgets."""

    __tablename__ = "budget_txns"

    budget_id: Mapped[str] = mapped_column(ForeignKey("budgets.id"), primary_key=True)
    txn_id: Mapped[str] = mapped_column(ForeignKey("txns.id", ondelete="CASCADE"), primary_key=True)
