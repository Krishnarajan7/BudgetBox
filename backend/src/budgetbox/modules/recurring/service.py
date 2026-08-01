import datetime as dt

import structlog
from sqlalchemy import select
from sqlalchemy.orm import Session

from budgetbox.core.errors import Invalid, NotFound
from budgetbox.core.ids import new_id, require_uuid
from budgetbox.core.money import Paise
from budgetbox.core.time import ist_day_start, today_ist
from budgetbox.domain.pace import round_half_away_from_zero as round_like_dart
from budgetbox.domain.periods import clamp_day
from budgetbox.domain.recurrence import advance, occurrences_through
from budgetbox.modules.accounts.models import Account
from budgetbox.modules.categories.models import Category
from budgetbox.modules.recurring.models import Recurring, RecurringKind
from budgetbox.modules.recurring.schemas import DueItem, RecurringIn, RecurringOut, RecurringPatch
from budgetbox.modules.transactions import service as txn_service
from budgetbox.modules.transactions.models import Txn, TxnType
from budgetbox.modules.transactions.schemas import TxnIn

log = structlog.get_logger()


def _first_due(day_of_month: int, today: dt.date) -> dt.date:
    """The next matching day, today included."""
    candidate = clamp_day(today.year, today.month, day_of_month)
    if candidate >= today:
        return candidate
    return advance(candidate, 1, day_of_month)


def _validate_refs(session: Session, account_id: str, category_id: str | None) -> None:
    if session.get(Account, account_id) is None:
        raise Invalid(f"no account {account_id}")
    if category_id is not None and session.get(Category, category_id) is None:
        raise Invalid(f"no category {category_id}")


def get(session: Session, recurring_id: str) -> Recurring:
    row = session.get(Recurring, recurring_id)
    if row is None:
        raise NotFound(f"no recurring {recurring_id}")
    return row


def list_recurrings(session: Session, *, include_inactive: bool = False) -> list[Recurring]:
    stmt = select(Recurring).order_by(Recurring.next_due, Recurring.title)
    if not include_inactive:
        stmt = stmt.where(Recurring.active.is_(True))
    return list(session.scalars(stmt))


def upsert(session: Session, recurring_id: str, data: RecurringIn) -> Recurring:
    recurring_id = require_uuid(recurring_id)
    _validate_refs(session, data.account_id, data.category_id)
    row = session.get(Recurring, recurring_id)
    if row is None:
        row = Recurring(id=recurring_id, kind=data.kind)
        session.add(row)
    row.title = data.title
    row.amount_paise = data.amount_paise
    row.account_id = data.account_id
    row.category_id = data.category_id
    row.every_months = data.every_months
    row.day_of_month = data.day_of_month
    row.next_due = data.next_due or _first_due(data.day_of_month, today_ist())
    row.active = data.active
    session.commit()
    return row


def patch(session: Session, recurring_id: str, data: RecurringPatch) -> Recurring:
    row = get(session, recurring_id)
    changes = data.model_dump(exclude_unset=True)
    for field, value in changes.items():
        setattr(row, field, value)
    _validate_refs(session, row.account_id, row.category_id)
    if "day_of_month" in changes and "next_due" not in changes:
        row.next_due = _first_due(row.day_of_month, today_ist())
    session.commit()
    return row


def deactivate(session: Session, recurring_id: str) -> Recurring:
    row = get(session, recurring_id)
    row.active = False
    session.commit()
    return row


def upcoming(session: Session, *, until: dt.date) -> list[DueItem]:
    """Next due per active recurring, for every due date through `until`."""
    items: list[DueItem] = []
    for row in list_recurrings(session):
        for due in occurrences_through(row.next_due, row.every_months, row.day_of_month, until):
            items.append(
                DueItem(
                    recurring=RecurringOut.model_validate(row),
                    due=due,
                    is_bill=row.kind is RecurringKind.BILL,
                )
            )
    items.sort(key=lambda i: (i.due, i.recurring.title))
    return items


def committed_monthly_paise(session: Session) -> Paise:
    """Sum of active recurrings, each normalized to per-month (yearly at 1/12)."""
    total = 0
    for row in list_recurrings(session):
        total += round_like_dart(row.amount_paise / row.every_months)
    return total


def committed_due_between(
    session: Session,
    start: dt.date,
    end_exclusive: dt.date,
    *,
    category_id: str | None = None,
) -> Paise:
    """Unposted committed charges falling due inside [start, end): feeds budget
    pace `upcoming_paise`. category_id narrows to one category (None = all)."""
    total = 0
    for row in list_recurrings(session):
        if category_id is not None and row.category_id != category_id:
            continue
        for due in occurrences_through(
            row.next_due, row.every_months, row.day_of_month, end_exclusive - dt.timedelta(days=1)
        ):
            if due >= start:
                total += row.amount_paise
    return total


def materialize_due(session: Session, *, today: dt.date | None = None) -> int:
    """Post a txn for every due date up to today, per active recurring. Idempotent
    catch-up: a rerun (or a run after downtime) posts exactly the missing ones.
    Returns the number of txns created."""
    today = today or today_ist()
    created = 0
    for row in list_recurrings(session):
        dues = occurrences_through(row.next_due, row.every_months, row.day_of_month, today)
        for due in dues:
            at = ist_day_start(due)
            exists = session.scalar(select(Txn.id).where(Txn.recurring_id == row.id, Txn.at == at))
            if exists is None:
                txn_service.upsert(
                    session,
                    new_id(),
                    TxnIn(
                        amount_paise=row.amount_paise,
                        type=TxnType.EXPENSE,
                        account_id=row.account_id,
                        category_id=row.category_id,
                        title=row.title,
                        at=at,
                    ),
                    recurring_id=row.id,
                )
                created += 1
        if dues:
            row.next_due = advance(dues[-1], row.every_months, row.day_of_month)
            row.last_materialized_due = dues[-1]
            session.commit()
            log.info("materialized", recurring=row.title, count=len(dues))
    return created
