import datetime as dt
import enum

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, DayKey, StampedMixin, UTCInstant, pk_id, str_enum


class RecurringKind(enum.StrEnum):
    BILL = "bill"
    SUBSCRIPTION = "subscription"


class Recurring(Base, StampedMixin):
    """A committed charge on a rhythm. day_of_month is the *intended* day and is
    clamped per month at scheduling time (rent on the 31st bills Feb 28, Mar 31).
    Deactivation, not deletion: history keeps pointing at it."""

    __tablename__ = "recurrings"
    __table_args__ = (
        CheckConstraint("every_months >= 1", name="every_months_positive"),
        CheckConstraint("day_of_month BETWEEN 1 AND 31", name="day_of_month_range"),
        CheckConstraint("amount_paise > 0", name="amount_positive"),
    )

    id: Mapped[str] = pk_id()
    title: Mapped[str] = mapped_column(String(120))
    amount_paise: Mapped[int]
    category_id: Mapped[str | None] = mapped_column(ForeignKey("categories.id"), default=None)
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"))
    kind: Mapped[RecurringKind] = mapped_column(str_enum(RecurringKind, "recurring_kind"))
    every_months: Mapped[int] = mapped_column(default=1)
    day_of_month: Mapped[int]
    next_due: Mapped[dt.date] = mapped_column(DayKey())
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    # High-water mark so a rerun of materialization can never double-post.
    last_materialized_due: Mapped[dt.date | None] = mapped_column(DayKey(), default=None)


class JobRun(Base, StampedMixin):
    """One row per daily-job invocation; /healthz reports the latest."""

    __tablename__ = "job_runs"

    id: Mapped[str] = pk_id()
    name: Mapped[str] = mapped_column(String(40))
    started_at: Mapped[dt.datetime] = mapped_column(UTCInstant())
    finished_at: Mapped[dt.datetime | None] = mapped_column(UTCInstant(), default=None)
    ok: Mapped[bool] = mapped_column(Boolean, default=False)
    detail: Mapped[str | None] = mapped_column(String(500), default=None)
