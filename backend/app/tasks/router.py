from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.tasks.schemas import TaskCreate, TaskResponse
from app.tasks.service import create_task, complete_task, task_insights
from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User


router = APIRouter(prefix="/tasks", tags=["tasks"])


@router.post("", response_model=TaskResponse, status_code=status.HTTP_201_CREATED)
async def create(
    data: TaskCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await create_task(db, user.id, data)


@router.post("/{task_id}/complete")
async def complete(
    task_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await complete_task(db, user.id, task_id)
    return {"status": "completed"}



@router.get("/insights")
async def insights(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await task_insights(db, user.id)