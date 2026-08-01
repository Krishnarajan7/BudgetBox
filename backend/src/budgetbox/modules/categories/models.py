import enum

from sqlalchemy import Boolean, String
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, StampedMixin, pk_id, str_enum


class CategoryKind(enum.StrEnum):
    EXPENSE = "expense"
    INCOME = "income"


class Category(Base, StampedMixin):
    __tablename__ = "categories"

    id: Mapped[str] = pk_id()
    name: Mapped[str] = mapped_column(String(40))
    # Key into the app's LedgerIcons catalogue, not an emoji.
    icon: Mapped[str] = mapped_column(String(24), default="circle")
    kind: Mapped[CategoryKind] = mapped_column(str_enum(CategoryKind, "category_kind"))
    sort_order: Mapped[int] = mapped_column(default=0)
    archived: Mapped[bool] = mapped_column(Boolean, default=False)
