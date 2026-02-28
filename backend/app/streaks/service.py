from datetime import date, timedelta
from sqlalchemy import select, func


async def calculate_streak(
    db,
    *,
    date_column,
    user_filter,
):
    result = await db.execute(
        select(func.date(date_column))
        .where(user_filter)
        .group_by(func.date(date_column))
        .order_by(func.date(date_column).desc())
    )

    dates = [row[0] for row in result.all()]

    if not dates:
        return {
            "current_streak": 0,
            "longest_streak": 0,
            "active_days": 0,
        }

    longest = 1
    streak = 1

    for i in range(1, len(dates)):
        if dates[i - 1] - dates[i] == timedelta(days=1):
            streak += 1
            longest = max(longest, streak)
        else:
            streak = 1

    current = 0
    if dates[0] == date.today():
        current = 1
        for i in range(1, len(dates)):
            if dates[i - 1] - dates[i] == timedelta(days=1):
                current += 1
            else:
                break

    return {
        "current_streak": current,
        "longest_streak": longest,
        "active_days": len(dates),
    }
