from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User

from app.tasks.schemas import (
    TaskCreate,
    TaskUpdate,
    TaskResponse,
    TaskLogPatch,
    TaskLogResponse,
)
from app.tasks.service import (
    create_task,
    complete_task_for_today,
    task_insights,
    patch_task_log,
    list_tasks,
    update_task,
    delete_task,
)


router = APIRouter(prefix="/tasks", tags=["tasks"])


@router.post(
    "",
    response_model=TaskResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_task_endpoint(
    data: TaskCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await create_task(db, user.id, data)


@router.post("/{task_id}/complete", response_model=TaskLogResponse)
async def complete_task_today(
    task_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    log = await complete_task_for_today(db, user.id, task_id)
    return {
        "task_id": task_id,
        "completed": log.completed,
        "completed_at": log.completed_at,
    }


@router.get("/insights")
async def task_insights_endpoint(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await task_insights(db, user.id)


@router.patch("/{task_id}/logs/today", response_model=TaskLogResponse)
async def patch_today_task_log(
    task_id: int,
    data: TaskLogPatch,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    log = await patch_task_log(db, user.id, task_id, data)
    return {
        "task_id": task_id,
        "completed": log.completed,
        "completed_at": log.completed_at,
    }


@router.get("", response_model=list[TaskResponse])
async def list_user_tasks(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await list_tasks(db, user.id)


@router.patch("/{task_id}", response_model=TaskResponse)
async def update_task_endpoint(
    task_id: int,
    data: TaskUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await update_task(db, user.id, task_id, data)


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_task_endpoint(
    task_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await delete_task(db, user.id, task_id)
