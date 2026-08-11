import datetime as dt

from sqlalchemy import select
from sqlalchemy.orm import Session

from budgetbox.core.time import day_key, ist_day_start
from budgetbox.domain.insights import (
    BudgetHeld,
    BudgetHoldCandidate,
    GoalMoveCandidate,
    GoalMoved,
    MonthStory,
    TxnFact,
    held_budget,
    month_story,
    moved_goal,
)
from budgetbox.modules.budgets.models import Budget, BudgetKind, BudgetPeriod
from budgetbox.modules.categories.models import Category
from budgetbox.modules.goals.models import Goal
from budgetbox.modules.transactions.models import Txn, TxnType


def story_for(
    session: Session, start: dt.date, end_exclusive: dt.date, today: dt.date
) -> MonthStory:
    names: dict[str, str] = {
        cid: name for cid, name in session.execute(select(Category.id, Category.name))
    }
    rows = session.scalars(
        select(Txn).where(
            Txn.at >= ist_day_start(start),
            Txn.at < ist_day_start(end_exclusive),
            Txn.type != TxnType.TRANSFER,
        )
    )
    facts = [
        TxnFact(
            amount_paise=t.amount_paise,
            kind=t.type.value,
            category_name=names.get(t.category_id) if t.category_id else None,
            day=day_key(t.at),
        )
        for t in rows
    ]
    return month_story(facts, window_start=start, window_end=end_exclusive, today=today)


def _spent_by_category(
    session: Session, start: dt.date, end_exclusive: dt.date
) -> dict[str | None, int]:
    out: dict[str | None, int] = {}
    rows = session.execute(
        select(Txn.category_id, Txn.amount_paise).where(
            Txn.type == TxnType.EXPENSE,
            Txn.at >= ist_day_start(start),
            Txn.at < ist_day_start(end_exclusive),
        )
    )
    for category_id, amount in rows:
        out[category_id] = out.get(category_id, 0) + amount
    return out


def budget_that_held(session: Session, start: dt.date, end_exclusive: dt.date) -> BudgetHeld | None:
    """The month's quiet win: a category budget that carried real spending and still
    stayed inside its line. Only automatic monthly budgets can hold a month."""
    spent = _spent_by_category(session, start, end_exclusive)
    candidates = [
        BudgetHoldCandidate(
            budget_id=b.id,
            name=b.name,
            limit_paise=b.limit_paise,
            spent_paise=spent.get(b.category_id, 0),
        )
        for b in session.scalars(
            select(Budget)
            .where(
                Budget.archived.is_(False),
                Budget.category_id.is_not(None),
                Budget.period == BudgetPeriod.MONTH,
                Budget.kind == BudgetKind.ALL,
            )
            .order_by(Budget.name)
        )
    ]
    return held_budget(candidates)


def goal_that_moved(session: Session, start: dt.date, end_exclusive: dt.date) -> GoalMoved | None:
    """A goal that actually moved this month — reached, or moved enough to matter."""
    moved: dict[str, int] = {}
    rows = session.execute(
        select(Txn.goal_id, Txn.amount_paise).where(
            Txn.goal_id.is_not(None),
            Txn.at >= ist_day_start(start),
            Txn.at < ist_day_start(end_exclusive),
        )
    )
    for goal_id, amount in rows:
        if goal_id is not None:
            moved[goal_id] = moved.get(goal_id, 0) + amount
    if not moved:
        return None

    done: dict[str, int] = {}
    for goal_id, amount in session.execute(
        select(Txn.goal_id, Txn.amount_paise).where(Txn.goal_id.in_(moved))
    ):
        if goal_id is not None:
            done[goal_id] = done.get(goal_id, 0) + amount

    candidates = [
        GoalMoveCandidate(
            goal_id=g.id,
            name=g.name,
            moved_paise=moved.get(g.id, 0),
            done_paise=done.get(g.id, 0),
            target_paise=g.target_paise,
        )
        for g in session.scalars(select(Goal).where(Goal.id.in_(moved)).order_by(Goal.created_at))
    ]
    return moved_goal(candidates)
