from pydantic import BaseModel
from datetime import datetime


class TaskCreate(BaseModel):
    title: str
    description: str | None = None
    due_at: datetime | None = None


class TaskResponse(BaseModel):
    id: int
    title: str
    description: str | None
    due_at: datetime | None
    is_active: bool
