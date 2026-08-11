import datetime as dt

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from budgetbox.core.errors import Invalid, NotFound
from budgetbox.core.ids import require_uuid
from budgetbox.core.money import Paise
from budgetbox.core.time import day_key, ist_day_start, today_ist
from budgetbox.domain.pace import BudgetPace, round_half_away_from_zero
from budgetbox.domain.periods import (
    add_months,
    fy_end_exclusive,
    fy_start,
    month_end_exclusive,
    month_start,
)
from budgetbox.modules.budgets.models import Budget, BudgetKind, BudgetPeriod, BudgetTxn
from budgetbox.modules.budgets.schemas import (
    BudgetIn,
    BudgetOut,
    BudgetPatch,
    BudgetSuggestion,
    BudgetTrail,
    BudgetView,
    MonthSpend,
    PaceOut,
)
from budgetbox.modules.categories.models import Category
from budgetbox.modules.categories.schemas import CategoryOut
from budgetbox.modules.recurring import service as recurring_service
from budgetbox.modules.transactions.models import Txn, TxnType


def get(session: Session, budget_id: str) -> Budget:
    row = session.get(Budget, budget_id)
    if row is None:
        raise NotFound(f"no budget {budget_id}")
    return row


def list_budgets(session: Session, *, include_archived: bool = False) -> list[Budget]:
    stmt = select(Budget).order_by(Budget.category_id.is_not(None), Budget.name)
    if not include_archived:
        stmt = stmt.where(Budget.archived.is_(False))
    return list(session.scalars(stmt))


def upsert(session: Session, budget_id: str, data: BudgetIn) -> Budget:
    budget_id = require_uuid(budget_id)
    if data.category_id is not None and session.get(Category, data.category_id) is None:
        raise Invalid(f"no category {data.category_id}")
    row = session.get(Budget, budget_id)
    if row is None:
        row = Budget(id=budget_id, period=data.period, kind=data.kind)
        session.add(row)
    elif row.period is not data.period or row.kind is not data.kind:
        raise Invalid("a budget's period/kind cannot change; archive it and create a new one")
    row.name = data.name
    row.category_id = data.category_id
    row.limit_paise = data.limit_paise
    row.rollover = data.rollover
    session.commit()
    return row


def patch(session: Session, budget_id: str, data: BudgetPatch) -> Budget:
    row = get(session, budget_id)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(row, field, value)
    session.commit()
    return row


def add_txn(session: Session, budget_id: str, txn_id: str) -> None:
    budget = get(session, budget_id)
    if budget.kind is not BudgetKind.ADDED:
        raise Invalid("only 'added' budgets take hand-picked txns")
    if session.get(Txn, txn_id) is None:
        raise NotFound(f"no txn {txn_id}")
    if session.get(BudgetTxn, (budget_id, txn_id)) is None:
        session.add(BudgetTxn(budget_id=budget_id, txn_id=txn_id))
        session.commit()


def remove_txn(session: Session, budget_id: str, txn_id: str) -> None:
    link = session.get(BudgetTxn, (budget_id, txn_id))
    if link is not None:
        session.delete(link)
        session.commit()


def rebalance(
    session: Session, budget_ids: list[str], *, month: dt.date | None = None
) -> list[Budget]:
    """Atomically redistribute the selected limits in proportion to actual spend.

    Limits are whole rupees and remain positive. The final budget receives the
    rounding remainder, so the total allocation never drifts.
    """
    if len(set(budget_ids)) != len(budget_ids):
        raise Invalid("budget_ids must be unique")
    selected = [get(session, budget_id) for budget_id in budget_ids]
    if any(b.period is not BudgetPeriod.MONTH or b.kind is not BudgetKind.ALL for b in selected):
        raise Invalid("rebalance only supports automatic monthly budgets")

    ref = month or today_ist()
    spends = [_spent(session, budget, _window(budget, ref)) for budget in selected]
    total_limit = sum(b.limit_paise for b in selected)
    total_spent = sum(spends)
    minimum = 100  # ₹1: the database intentionally forbids zero-value budgets.
    if total_spent <= 0:
        raise Invalid("cannot rebalance before any selected budget has spending")
    if total_limit < minimum * len(selected):
        raise Invalid("combined limit is too small to keep every budget positive")

    distributable = total_limit - minimum * len(selected)
    assigned = 0
    for index, (budget, spent) in enumerate(zip(selected, spends, strict=True)):
        if index == len(selected) - 1:
            share = total_limit - assigned
        else:
            weighted = minimum + distributable * spent / total_spent
            share = max(minimum, round_half_away_from_zero(weighted / 100) * 100)
            # Preserve at least the minimum for every row still to be assigned.
            remaining = len(selected) - index - 1
            share = min(share, total_limit - assigned - remaining * minimum)
        budget.limit_paise = share
        assigned += share
    session.commit()
    return selected


def suggestions(session: Session, *, months: int) -> list[BudgetSuggestion]:
    """Average expense spend by category over the previous complete months."""
    current = month_start(today_ist())
    start_year, start_month = add_months(current.year, current.month, -months)
    start = dt.date(start_year, start_month, 1)
    rows = session.execute(
        select(Txn.category_id, func.coalesce(func.sum(Txn.amount_paise), 0))
        .where(
            Txn.type == TxnType.EXPENSE,
            Txn.category_id.is_not(None),
            Txn.at >= ist_day_start(start),
            Txn.at < ist_day_start(current),
        )
        .group_by(Txn.category_id)
    )
    out: list[BudgetSuggestion] = []
    for category_id, total in rows:
        average = round_half_away_from_zero(total / months)
        suggested = round_half_away_from_zero(average / 10_000) * 10_000  # nearest ₹100
        if suggested <= 0:
            continue
        out.append(
            BudgetSuggestion(
                category_id=category_id,
                suggested_limit_paise=suggested,
                average_spent_paise=average,
                months=months,
            )
        )
    return sorted(out, key=lambda item: (-item.suggested_limit_paise, item.category_id))


# --- pace ---------------------------------------------------------------------


def _window(budget: Budget, ref: dt.date) -> tuple[dt.date, dt.date] | None:
    match budget.period:
        case BudgetPeriod.MONTH:
            return month_start(ref), month_end_exclusive(ref)
        case BudgetPeriod.FY:
            return fy_start(ref), fy_end_exclusive(ref)
        case BudgetPeriod.CUSTOM:
            return None


def _spent(
    session: Session,
    budget: Budget,
    window: tuple[dt.date, dt.date] | None,
) -> Paise:
    if budget.kind is BudgetKind.ADDED:
        stmt = (
            select(func.coalesce(func.sum(Txn.amount_paise), 0))
            .join(BudgetTxn, BudgetTxn.txn_id == Txn.id)
            .where(BudgetTxn.budget_id == budget.id, Txn.type == TxnType.EXPENSE)
        )
    else:
        stmt = select(func.coalesce(func.sum(Txn.amount_paise), 0)).where(
            Txn.type == TxnType.EXPENSE
        )
        if budget.category_id is not None:
            stmt = stmt.where(Txn.category_id == budget.category_id)
    if window is not None:
        stmt = stmt.where(Txn.at >= ist_day_start(window[0]), Txn.at < ist_day_start(window[1]))
    return session.scalar(stmt) or 0


def _elapsed_total(window: tuple[dt.date, dt.date] | None, today: dt.date) -> tuple[int, int]:
    if window is None:
        return 0, 0
    start, end = window
    total = (end - start).days
    if today < start:
        return 0, total
    elapsed = min((today - start).days + 1, total)
    return elapsed, total


def _effective_limit(
    session: Session, budget: Budget, window: tuple[dt.date, dt.date] | None
) -> Paise:
    """Rollover (month budgets only): last month's leftover carries into this one —
    both directions, so overspending eats next month's line."""
    if not budget.rollover or budget.period is not BudgetPeriod.MONTH or window is None:
        return budget.limit_paise
    year, month = add_months(window[0].year, window[0].month, -1)
    prev_start = dt.date(year, month, 1)
    prev_window = (prev_start, window[0])
    prev_spent = _spent(session, budget, prev_window)
    return budget.limit_paise + (budget.limit_paise - prev_spent)


def trail(
    session: Session, budget_id: str, *, month: dt.date | None = None, months: int = 6
) -> BudgetTrail:
    """One budget's history and this period's climb. `months` prior months plus the
    current one feed the sparkline; the streak counts only complete months."""
    budget = get(session, budget_id)
    today = today_ist()
    ref = month or today
    current = month_start(ref)

    history: list[MonthSpend] = []
    for back in range(months, -1, -1):
        year, mon = add_months(current.year, current.month, -back)
        first = dt.date(year, mon, 1)
        window = (first, month_end_exclusive(first))
        spent = _spent(session, budget, window)
        history.append(
            MonthSpend(
                month=f"{year:04d}-{mon:02d}",
                spent_paise=spent,
                # Zero spend is not evidence of restraint: it breaks the streak.
                held=0 < spent <= budget.limit_paise,
            )
        )

    running = 0
    for entry in reversed(history[:-1]):  # the current month is still being lived
        if not entry.held:
            break
        running += 1

    window = _window(budget, ref)
    elapsed, _total = _elapsed_total(window, today)
    cumulative: list[int] = []
    even: list[int] = []
    if window is not None and elapsed > 0:
        start, end = window
        rows = session.execute(
            select(Txn.at, Txn.amount_paise).where(
                Txn.type == TxnType.EXPENSE,
                Txn.at >= ist_day_start(start),
                Txn.at < ist_day_start(end),
                *(
                    [Txn.category_id == budget.category_id]
                    if budget.category_id is not None
                    else []
                ),
            )
        )
        per_day = [0] * elapsed
        for at, amount in rows:
            index = (day_key(at) - start).days
            if 0 <= index < elapsed:
                per_day[index] += amount
        total_days = (end - start).days
        running_total = 0
        for index, amount in enumerate(per_day, start=1):
            running_total += amount
            cumulative.append(running_total)
            even.append(round_half_away_from_zero(budget.limit_paise * index / total_days))

    return BudgetTrail(
        budget_id=budget.id,
        limit_paise=budget.limit_paise,
        months=history,
        held_months_running=running,
        daily_cumulative_paise=cumulative,
        even_pace_paise=even,
    )


def pace_views(session: Session, *, month: dt.date | None = None) -> list[BudgetView]:
    today = today_ist()
    ref = month or today
    views: list[BudgetView] = []
    for budget in list_budgets(session):
        window = _window(budget, ref)
        spent = _spent(session, budget, window)
        upcoming = 0
        if window is not None and today < window[1]:
            upcoming = recurring_service.committed_due_between(
                session,
                max(today, window[0]),
                window[1],
                category_id=budget.category_id,
            )
        elapsed, total = _elapsed_total(window, today)
        pace = BudgetPace(
            spent_paise=spent,
            limit_paise=_effective_limit(session, budget, window),
            elapsed_days=elapsed,
            total_days=total,
            upcoming_paise=upcoming,
        )
        category = (
            session.get(Category, budget.category_id) if budget.category_id is not None else None
        )
        views.append(
            BudgetView(
                budget=BudgetOut.model_validate(budget),
                category=CategoryOut.model_validate(category) if category else None,
                window_start=window[0] if window else None,
                window_end=window[1] if window else None,
                pace=PaceOut(
                    spent_paise=pace.spent_paise,
                    limit_paise=pace.limit_paise,
                    elapsed_days=pace.elapsed_days,
                    total_days=pace.total_days,
                    upcoming_paise=pace.upcoming_paise,
                    remaining_paise=pace.remaining_paise,
                    fraction_spent=pace.fraction_spent,
                    fraction_elapsed=pace.fraction_elapsed,
                    projected_paise=pace.projected_paise,
                    status=pace.status,
                    projected_overspend_paise=pace.projected_overspend_paise,
                ),
            )
        )
    return views
