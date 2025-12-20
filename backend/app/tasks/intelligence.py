from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from datetime import date, timedelta

from app.models.task import Task
from app.models.task_log import TaskLog


async def weekly_productivity(db: AsyncSession, user_id: int):
    today = date.today()
    start = today - timedelta(days=6)

    completed_result = await db.execute(
        select(func.count(TaskLog.id))
        .join(Task, Task.id == TaskLog.task_id)
        .where(
            Task.user_id == user_id,
            TaskLog.completed == True,
            TaskLog.completed_at >= start,
        )
    )
    completed = completed_result.scalar() or 0

    created_result = await db.execute(
        select(func.count(Task.id))
        .where(
            Task.user_id == user_id,
            Task.created_at >= start,
        )
    )
    created = created_result.scalar() or 0

    score = round((completed / max(created, 1)) * 100, 2)

    momentum = "improving" if score >= 70 else "needs_focus"

    return {
        "completed_tasks": completed,
        "created_tasks": created,
        "productivity_score": score,
        "momentum": momentum,
    }


async def task_timeliness(db: AsyncSession, user_id: int):
    result = await db.execute(
        select(Task, TaskLog.completed_at)
        .join(TaskLog, TaskLog.task_id == Task.id)
        .where(
            Task.user_id == user_id,
            TaskLog.completed == True,
            Task.due_at.isnot(None),
        )
    )

    on_time = 0
    late = 0

    for task, completed_at in result.all():
        if completed_at <= task.due_at:
            on_time += 1
        else:
            late += 1

    total = on_time + late

    return {
        "on_time": on_time,
        "late": late,
        "on_time_rate": round((on_time / max(total, 1)) * 100, 2),
    }
