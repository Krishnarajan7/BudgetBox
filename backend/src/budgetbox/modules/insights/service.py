import datetime as dt

from sqlalchemy import select
from sqlalchemy.orm import Session

from budgetbox.core.time import day_key, ist_day_start
from budgetbox.domain.insights import MonthStory, TxnFact, month_story
from budgetbox.modules.categories.models import Category
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
