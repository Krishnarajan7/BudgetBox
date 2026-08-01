import math

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from budgetbox.core.errors import NotFound
from budgetbox.core.ids import new_id, require_uuid
from budgetbox.core.time import now_utc, today_ist
from budgetbox.domain.periods import add_months, clamp_day
from budgetbox.modules.goals.models import Goal
from budgetbox.modules.goals.schemas import ContributeIn, GoalIn, GoalOut, GoalPatch, GoalView
from budgetbox.modules.transactions import service as txn_service
from budgetbox.modules.transactions.models import Txn, TxnType
from budgetbox.modules.transactions.schemas import TxnIn


def get(session: Session, goal_id: str) -> Goal:
    row = session.get(Goal, goal_id)
    if row is None:
        raise NotFound(f"no goal {goal_id}")
    return row


def upsert(session: Session, goal_id: str, data: GoalIn) -> Goal:
    goal_id = require_uuid(goal_id)
    row = session.get(Goal, goal_id)
    if row is None:
        row = Goal(id=goal_id, kind=data.kind)
        session.add(row)
    row.name = data.name
    row.target_paise = data.target_paise
    row.target_date = data.target_date
    row.monthly_paise = data.monthly_paise
    session.commit()
    return row


def patch(session: Session, goal_id: str, data: GoalPatch) -> Goal:
    row = get(session, goal_id)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(row, field, value)
    session.commit()
    return row


def _view(session: Session, goal: Goal) -> GoalView:
    done, count = session.execute(
        select(func.coalesce(func.sum(Txn.amount_paise), 0), func.count(Txn.id)).where(
            Txn.goal_id == goal.id
        )
    ).one()
    remaining = max(goal.target_paise - done, 0)
    reached = done >= goal.target_paise
    eta = None
    if not reached and goal.monthly_paise and goal.monthly_paise > 0:
        months = math.ceil(remaining / goal.monthly_paise)
        today = today_ist()
        year, month = add_months(today.year, today.month, months)
        eta = clamp_day(year, month, today.day)
    return GoalView(
        goal=GoalOut.model_validate(goal),
        done_paise=done,
        entry_count=count,
        remaining_paise=remaining,
        fraction=min(done / goal.target_paise, 1.0),
        reached=reached,
        eta=eta,
    )


def views(session: Session, *, include_archived: bool = False) -> list[GoalView]:
    stmt = select(Goal).order_by(Goal.created_at)
    if not include_archived:
        stmt = stmt.where(Goal.archived.is_(False))
    return [_view(session, g) for g in session.scalars(stmt)]


def view(session: Session, goal_id: str) -> GoalView:
    return _view(session, get(session, goal_id))


def contribute(session: Session, goal_id: str, data: ContributeIn) -> Txn:
    """Set money aside: an expense txn tagged with the goal (goals never keep
    their own ledger)."""
    goal = get(session, goal_id)
    txn, _ = txn_service.upsert(
        session,
        new_id(),
        TxnIn(
            amount_paise=data.amount_paise,
            type=TxnType.EXPENSE,
            account_id=data.account_id,
            title=goal.name,
            note=data.note,
            at=data.at or now_utc(),
            goal_id=goal.id,
        ),
    )
    return txn
