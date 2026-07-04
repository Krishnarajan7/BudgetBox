from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, extract
from datetime import date

from app.models.transaction import Transaction, TransactionType
from app.budgets.service import list_budgets_with_usage


async def _budget_alerts(db: AsyncSession, user_id: int) -> list[dict]:
    """Alerts derived from the user's Budget limits for the current month.

    Any category with a budget that has hit >=80% usage gets a warning,
    and >=100% usage gets an over-budget alert. These are more actionable
    than the average-based alerts below, so they are returned first.
    """
    current_month = date.today().strftime("%Y-%m")
    usage = await list_budgets_with_usage(db, user_id, current_month)

    alerts = []
    for item in usage:
        percent = item["percent_used"]
        if percent >= 100:
            alerts.append(
                {
                    "type": "danger",
                    "message": (
                        f"You have exceeded your {item['category_name']} budget "
                        f"for {item['month']} "
                        f"({item['spent']:.2f} of {item['limit']:.2f})"
                    ),
                }
            )
        elif percent >= 80:
            alerts.append(
                {
                    "type": "warning",
                    "message": (
                        f"You have used {percent:.0f}% of your "
                        f"{item['category_name']} budget for {item['month']}"
                    ),
                }
            )
    return alerts


async def expense_alerts(
    db: AsyncSession,
    user_id: int,
):
    budget_based_alerts = await _budget_alerts(db, user_id)

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

    return budget_based_alerts + alerts
