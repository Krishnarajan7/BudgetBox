from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from datetime import datetime

from app.tasks.schemas import TaskCreate, TaskLogPatch
from app.models.task import Task
from app.models.task_log import TaskLog
from app.tasks.intelligence import weekly_productivity, task_timeliness


async def create_task(
    db: AsyncSession,
    user_id: int,
    data: TaskCreate,
) -> Task:
    task = Task(
        user_id=user_id,
        title=data.title,
        description=data.description,
        due_at=data.due_at,
        is_active=True,
    )
    db.add(task)
    await db.commit()
    await db.refresh(task)
    return task


async def complete_task_for_today(
    db: AsyncSession,
    user_id: int,
    task_id: int,
) -> TaskLog:
    result = await db.execute(
        select(Task).where(
            Task.id == task_id,
            Task.user_id == user_id,
            Task.is_active.is_(True),
        )
    )
    task = result.scalar_one()

    result = await db.execute(
        select(TaskLog)
        .where(TaskLog.task_id == task.id)
        .order_by(desc(TaskLog.completed_at))
        .limit(1)
    )
    log = result.scalar_one_or_none()

    if log and log.completed:
        return log

    log = TaskLog(
        task_id=task.id,
        completed=True,
        completed_at=datetime.utcnow(),
    )
    db.add(log)
    await db.commit()
    await db.refresh(log)
    return log


async def task_insights(
    db: AsyncSession,
    user_id: int,
):
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


async def patch_task_log(
    db: AsyncSession,
    user_id: int,
    task_id: int,
    data: TaskLogPatch,
) -> TaskLog:
    result = await db.execute(
        select(Task).where(
            Task.id == task_id,
            Task.user_id == user_id,
            Task.is_active.is_(True),
        )
    )
    task = result.scalar_one()

    result = await db.execute(
        select(TaskLog)
        .where(TaskLog.task_id == task.id)
        .order_by(desc(TaskLog.completed_at))
        .limit(1)
    )
    log = result.scalar_one_or_none()

    if log:
        if data.completed is not None:
            log.completed = data.completed
            log.completed_at = datetime.utcnow()
    else:
        log = TaskLog(
            task_id=task.id,
            completed=data.completed if data.completed is not None else False,
            completed_at=datetime.utcnow(),
        )
        db.add(log)

    await db.commit()
    await db.refresh(log)
    return log


async def list_tasks(
    db: AsyncSession,
    user_id: int,
):
    result = await db.execute(
        select(Task)
        .where(
            Task.user_id == user_id,
            Task.is_active.is_(True),
        )
        .order_by(Task.id.desc())
    )
    return result.scalars().all()


async def delete_task(
    db: AsyncSession,
    user_id: int,
    task_id: int,
):
    result = await db.execute(
        select(Task).where(
            Task.id == task_id,
            Task.user_id == user_id,
            Task.is_active.is_(True),
        )
    )
    task = result.scalar_one()

    task.is_active = False
    await db.commit()
