from sqlalchemy import select, func
from datetime import date, timedelta

from app.models.task_log import TaskLog
from app.models.task import Task
from app.models.habit_log import HabitLog
from app.models.habit import Habit


async def activity_heatmap(db, user_id: int):
    result = await db.execute(
        select(
            func.date(TaskLog.completed_at).label("date"),
            func.count().label("count"),
        )
        .join(Task, Task.id == TaskLog.task_id)
        .where(Task.user_id == user_id)
        .group_by(func.date(TaskLog.completed_at))
        .order_by(func.date(TaskLog.completed_at))
    )

    return {row.date.isoformat(): row.count for row in result.all()}