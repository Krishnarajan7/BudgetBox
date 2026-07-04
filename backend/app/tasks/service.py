from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc, func
from datetime import datetime

from app.tasks.schemas import TaskCreate, TaskUpdate, TaskLogPatch, TaskResponse
from app.models.task import Task
from app.models.task_log import TaskLog
from app.tasks.intelligence import weekly_productivity, task_timeliness
from app.core.errors import AppError


def _to_response(
    task: Task,
    completed: bool = False,
    completed_at: datetime | None = None,
) -> TaskResponse:
    return TaskResponse(
        id=task.id,
        title=task.title,
        description=task.description,
        due_at=task.due_at,
        is_active=task.is_active,
        priority=task.priority,
        completed=completed,
        completed_at=completed_at,
    )


async def _latest_log(db: AsyncSession, task_id: int) -> TaskLog | None:
    result = await db.execute(
        select(TaskLog)
        .where(TaskLog.task_id == task_id)
        .order_by(desc(TaskLog.completed_at), desc(TaskLog.id))
        .limit(1)
    )
    return result.scalar_one_or_none()


async def create_task(
    db: AsyncSession,
    user_id: int,
    data: TaskCreate,
) -> TaskResponse:
    task = Task(
        user_id=user_id,
        title=data.title,
        description=data.description,
        due_at=data.due_at,
        priority=data.priority,
        is_active=True,
    )
    db.add(task)
    await db.commit()
    await db.refresh(task)
    return _to_response(task)


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
) -> list[TaskResponse]:
    # Single query: join each task to its most recent TaskLog (by completed_at,
    # tie-broken by id) using a row_number() window function, so completion
    # state is populated without any N+1 per-task lookups.
    latest_log = (
        select(
            TaskLog.task_id.label("task_id"),
            TaskLog.completed.label("completed"),
            TaskLog.completed_at.label("completed_at"),
            func.row_number()
            .over(
                partition_by=TaskLog.task_id,
                order_by=(desc(TaskLog.completed_at), desc(TaskLog.id)),
            )
            .label("rn"),
        )
    ).subquery()

    result = await db.execute(
        select(Task, latest_log.c.completed, latest_log.c.completed_at)
        .outerjoin(
            latest_log,
            (latest_log.c.task_id == Task.id) & (latest_log.c.rn == 1),
        )
        .where(
            Task.user_id == user_id,
            Task.is_active.is_(True),
        )
        .order_by(Task.id.desc())
    )

    return [
        _to_response(
            task,
            completed=bool(completed) if completed is not None else False,
            completed_at=completed_at,
        )
        for task, completed, completed_at in result.all()
    ]


async def update_task(
    db: AsyncSession,
    user_id: int,
    task_id: int,
    data: TaskUpdate,
) -> TaskResponse:
    result = await db.execute(
        select(Task).where(
            Task.id == task_id,
            Task.user_id == user_id,
            Task.is_active.is_(True),
        )
    )
    task = result.scalar_one_or_none()
    if not task:
        raise AppError("TASK_NOT_FOUND", "Task not found", 404)

    if data.title is not None:
        task.title = data.title
    if data.description is not None:
        task.description = data.description
    if data.due_at is not None:
        task.due_at = data.due_at
    if data.priority is not None:
        task.priority = data.priority

    await db.commit()
    await db.refresh(task)

    log = await _latest_log(db, task.id)
    return _to_response(
        task,
        completed=bool(log.completed) if log else False,
        completed_at=log.completed_at if log else None,
    )


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
