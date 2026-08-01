"""Full-ledger CSV: every txn with names resolved — the 'my data leaves whenever
I want' guarantee behind Settings → The data."""

import csv
import io

from sqlalchemy import select
from sqlalchemy.orm import Session

from budgetbox.core.time import IST
from budgetbox.modules.accounts.models import Account
from budgetbox.modules.categories.models import Category
from budgetbox.modules.goals.models import Goal
from budgetbox.modules.transactions.models import Txn

HEADER = [
    "date_ist",
    "time_ist",
    "type",
    "amount_inr",
    "amount_paise",
    "title",
    "category",
    "account",
    "to_account",
    "goal",
    "note",
    "id",
]


def txns_csv(session: Session) -> str:
    accounts = {a.id: a.name for a in session.scalars(select(Account))}
    categories = {c.id: c.name for c in session.scalars(select(Category))}
    goals = {g.id: g.name for g in session.scalars(select(Goal))}

    buf = io.StringIO()
    writer = csv.writer(buf, lineterminator="\n")
    writer.writerow(HEADER)
    for t in session.scalars(select(Txn).order_by(Txn.at, Txn.id)):
        local = t.at.astimezone(IST)
        writer.writerow(
            [
                local.strftime("%Y-%m-%d"),
                local.strftime("%H:%M:%S"),
                t.type.value,
                f"{t.amount_paise / 100:.2f}",
                t.amount_paise,
                t.title,
                categories.get(t.category_id, "") if t.category_id else "",
                accounts.get(t.account_id, t.account_id),
                accounts.get(t.to_account_id, "") if t.to_account_id else "",
                goals.get(t.goal_id, "") if t.goal_id else "",
                t.note or "",
                t.id,
            ]
        )
    return buf.getvalue()
