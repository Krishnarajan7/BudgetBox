import datetime as dt
import enum

from sqlalchemy import Boolean, CheckConstraint, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, DayKey, StampedMixin, pk_id, str_enum


class SpendingClass(enum.StrEnum):
    ESSENTIAL = "essential"
    DISCRETIONARY = "discretionary"
    AVOID = "avoid"


class InsightKind(enum.StrEnum):
    MERCHANT_SURGE = "merchant_surge"
    REPEATED_DISCRETIONARY = "repeated_discretionary"
    BUDGET_RISK = "budget_risk"


class InsightStatus(enum.StrEnum):
    ACTIVE = "active"
    DISMISSED = "dismissed"
    ACTED = "acted"


class MerchantRule(Base, StampedMixin):
    """A user-owned interpretation of a normalized transaction title."""

    __tablename__ = "merchant_rules"
    __table_args__ = (UniqueConstraint("match_text", name="match_text"),)

    id: Mapped[str] = pk_id()
    match_text: Mapped[str] = mapped_column(String(120))
    merchant_name: Mapped[str] = mapped_column(String(80))
    classification: Mapped[SpendingClass] = mapped_column(str_enum(SpendingClass, "spending_class"))
    active: Mapped[bool] = mapped_column(Boolean, default=True)


class CoachingInsight(Base, StampedMixin):
    __tablename__ = "coaching_insights"
    __table_args__ = (
        UniqueConstraint("fingerprint", name="fingerprint"),
        CheckConstraint("priority BETWEEN 0 AND 100", name="priority_range"),
    )

    id: Mapped[str] = pk_id()
    fingerprint: Mapped[str] = mapped_column(String(160))
    kind: Mapped[InsightKind] = mapped_column(str_enum(InsightKind, "insight_kind"))
    title: Mapped[str] = mapped_column(String(120))
    message: Mapped[str] = mapped_column(Text)
    evidence_json: Mapped[str] = mapped_column(Text)
    priority: Mapped[int]
    current_paise: Mapped[int | None] = mapped_column(default=None)
    baseline_paise: Mapped[int | None] = mapped_column(default=None)
    difference_paise: Mapped[int | None] = mapped_column(default=None)
    period_start: Mapped[dt.date] = mapped_column(DayKey())
    period_end: Mapped[dt.date] = mapped_column(DayKey())
    expires_on: Mapped[dt.date] = mapped_column(DayKey())
    status: Mapped[InsightStatus] = mapped_column(
        str_enum(InsightStatus, "insight_status"), default=InsightStatus.ACTIVE
    )
    snoozed_until: Mapped[dt.date | None] = mapped_column(DayKey(), default=None)
