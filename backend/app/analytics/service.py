from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, extract
from datetime import date
from sqlalchemy import func
from datetime import date, timedelta
from dateutil.relativedelta import relativedelta

from app.analytics.alerts import expense_alerts

from app.models.transaction import Transaction, TransactionType
from app.models.category import Category


async def summary_by_period(
    db: AsyncSession,
    user_id: int,
    start_date: date,
    end_date: date,
):
    result = await db.execute(
        select(
            Transaction.type,
            func.sum(Transaction.amount),
        )
        .where(
            Transaction.user_id == user_id,
            Transaction.occurred_at >= start_date,
            Transaction.occurred_at < end_date + timedelta(days=1),
        )
        .group_by(Transaction.type)
    )

    income = 0.0
    expense = 0.0

    for t_type, total in result.all():
        total = float(total or 0)
        if t_type == TransactionType.INCOME:
            income = total
        else:
            expense = total

    return {
        "income": income,
        "expense": expense,
        "profit": income - expense,
    }


async def yearly_breakdown(
    db: AsyncSession,
    user_id: int,
    year: int,
):
    result = await db.execute(
        select(
            extract("month", Transaction.occurred_at).label("month"),
            Transaction.type,
            func.sum(Transaction.amount),
        )
        .where(
            Transaction.user_id == user_id,
            extract("year", Transaction.occurred_at) == year,
        )
        .group_by("month", Transaction.type)
        .order_by("month")
    )

    data: dict[int, dict[str, float]] = {}

    for month, t_type, total in result.all():
        month = int(month)
        total = float(total or 0)

        if month not in data:
            data[month] = {"income": 0.0, "expense": 0.0}

        if t_type == TransactionType.INCOME:
            data[month]["income"] += total
        else:
            data[month]["expense"] += total

    response = []
    for month in sorted(data.keys()):
        values = data[month]
        response.append(
            {
                "month": f"{year}-{month:02}",
                "income": values["income"],
                "expense": values["expense"],
                "profit": values["income"] - values["expense"],
            }
        )

    return response
  
async def top_expense_categories(
    db: AsyncSession,
    user_id: int,
    limit: int = 5,
):
    result = await db.execute(
        select(
            Category.name,
            func.sum(Transaction.amount).label("total")
        )
        .join(Category, Category.id == Transaction.category_id)
        .where(
            Transaction.user_id == user_id,
            Transaction.type == TransactionType.EXPENSE
        )
        .group_by(Category.name)
        .order_by(func.sum(Transaction.amount).desc())
        .limit(limit)
    )

    return [
        {"category": name, "amount": float(total)}
        for name, total in result.all()
    ]
    
async def dashboard_summary(db: AsyncSession, user_id: int):
    today = date.today()
    month_start = today.replace(day=1)
    week_start = today - timedelta(days=7)

    weekly = await summary_by_period(db, user_id, week_start, today)
    monthly = await summary_by_period(db, user_id, month_start, today)
    categories = await top_expense_categories(db, user_id)
    alerts = await expense_alerts(db, user_id)

    return {
        "weekly": weekly,
        "monthly": monthly,
        "top_categories": categories,
        "alerts": alerts,
    }
    
async def month_comparison(db: AsyncSession, user_id: int):
    today = date.today()

    current_start = today.replace(day=1)
    last_month_date = current_start - relativedelta(months=1)
    last_start = last_month_date.replace(day=1)
    last_end = current_start - relativedelta(days=1)

    current = await summary_by_period(db, user_id, current_start, today)
    previous = await summary_by_period(db, user_id, last_start, last_end)

    expense_diff = current["expense"] - previous["expense"]
    income_diff = current["income"] - previous["income"]

    return {
        "current_month": current,
        "previous_month": previous,
        "difference": {
            "expense": expense_diff,
            "income": income_diff,
            "profit": current["profit"] - previous["profit"],
        },
        "insight": (
            "You spent more this month"
            if expense_diff > 0
            else "You controlled your expenses better"
        ),
    }
