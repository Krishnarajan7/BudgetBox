from pydantic import BaseModel
from typing import Optional

from app.models.category import CategoryType


class CategoryCreate(BaseModel):
    name: str
    type: CategoryType


class CategoryUpdate(BaseModel):
    name: Optional[str] = None
    type: Optional[CategoryType] = None


class CategoryResponse(BaseModel):
    id: int
    name: str
    type: CategoryType

    class Config:
        from_attributes = True
