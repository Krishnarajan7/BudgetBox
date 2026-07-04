from pydantic import BaseModel
from datetime import datetime
from typing import Literal

Priority = Literal["low", "medium", "high"]


class TaskCreate(BaseModel):
    title: str
    description: str | None = None
    due_at: datetime | None = None
    priority: Priority = "medium"


class TaskUpdate(BaseModel):
    title: str | None = None
    description: str | None = None
    due_at: datetime | None = None
    priority: Priority | None = None


class TaskResponse(BaseModel):
    id: int
    title: str
    description: str | None
    due_at: datetime | None
    is_active: bool
    priority: str
    completed: bool
    completed_at: datetime | None

    model_config = {"from_attributes": True}


class TaskLogPatch(BaseModel):
    completed: bool


class TaskLogResponse(BaseModel):
    task_id: int
    completed: bool
    completed_at: datetime | None
