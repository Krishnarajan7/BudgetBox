from datetime import date, timedelta

from app.analytics.service import summary_by_period
from app.habits.intelligence import habit_streak
from app.analytics.alerts import expense_alerts


async def weekly_insight(db, user_id: int):
    today = date.today()
    this_week_start = today - timedelta(days=7)
    last_week_start = today - timedelta(days=14)
    last_week_end = this_week_start - timedelta(days=1)

    this_week = await summary_by_period(db, user_id, this_week_start, today)
    last_week = await summary_by_period(db, user_id, last_week_start, last_week_end)

    messages = []

    if this_week["expense"] < last_week["expense"]:
        messages.append("You spent less than last week. Good control.")
    elif this_week["expense"] > last_week["expense"]:
        messages.append("Your spending increased compared to last week.")

    if this_week["profit"] > last_week["profit"]:
        messages.append("Your savings improved this week.")
    else:
        messages.append("Your savings dipped this week.")

    alerts = await expense_alerts(db, user_id)
    for alert in alerts:
        messages.append(alert["message"])

    if not messages:
        messages.append("Keep going. Consistency matters more than perfection.")

    return {
        "period": "weekly",
        "summary": messages,
        "numbers": {
            "this_week": this_week,
            "last_week": last_week,
        },
    }
