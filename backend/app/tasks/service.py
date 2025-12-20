from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime
from app.tasks.schemas import TaskCreate
from app.models.task import Task
from app.models.task_log import TaskLog
from app.tasks.intelligence import weekly_productivity, task_timeliness

async def create_task(db: AsyncSession, user_id: int, data: TaskCreate) -> Task:
    task = Task(
        user_id=user_id,
        title=data.title,
        description=data.description,
        due_at=data.due_at,
    )
    db.add(task)
    await db.commit()
    await db.refresh(task)
    return task


async def complete_task(db: AsyncSession, user_id: int, task_id: int):
    result = await db.execute(
        select(Task).where(
            Task.id == task_id,
            Task.user_id == user_id,
            Task.is_active == True,
        )
    )
    task = result.scalar_one()

    log = TaskLog(
        task_id=task.id,
        completed=True,
        completed_at=datetime.utcnow(),
    )
    db.add(log)
    await db.commit()

    return log


async def task_insights(db, user_id: int):
    weekly = await weekly_productivity(db, user_id)
    timing = await task_timeliness(db, user_id)

    insight = (
        "You are maintaining good task discipline"
        if weekly["productivity_score"] >= 70
        else "Try reducing task overload"
    )

    return {
        "weekly": weekly,
        "timeliness": timing,
        "insight": insight,
    }