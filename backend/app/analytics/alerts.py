from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, extract
from datetime import date

from app.models.transaction import Transaction, TransactionType


async def expense_alerts(
    db: AsyncSession,
    user_id: int,
):
    today = date.today()
    current_month = today.month
    current_year = today.year

    result = await db.execute(
        select(
            extract("month", Transaction.occurred_at).label("month"),
            func.sum(Transaction.amount),
        )
        .where(
            Transaction.user_id == user_id,
            Transaction.type == TransactionType.EXPENSE,
            extract("year", Transaction.occurred_at) == current_year,
        )
        .group_by("month")
    )

    month_data = {
        int(month): float(total or 0)
        for month, total in result.all()
    }

    current_expense = month_data.get(current_month, 0.0)

    previous_months = {
        m: v for m, v in month_data.items() if m != current_month
    }

    avg_expense = (
        sum(previous_months.values()) / len(previous_months)
        if previous_months
        else 0.0
    )

    alerts = []

    if avg_expense > 0 and current_expense > avg_expense:
        alerts.append(
            {
                "type": "warning",
                "message": "You are spending more than your monthly average",
            }
        )

    if month_data and current_expense == max(month_data.values()):
        alerts.append(
            {
                "type": "info",
                "message": "This is your highest spending month this year",
            }
        )

    if avg_expense > 0 and current_expense < avg_expense:
        alerts.append(
            {
                "type": "success",
                "message": "You are controlling expenses better this month",
            }
        )

    return alerts
