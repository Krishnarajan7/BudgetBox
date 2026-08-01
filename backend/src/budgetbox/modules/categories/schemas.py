from datetime import datetime

from pydantic import Field

from budgetbox.api.schemas import APIModel
from budgetbox.modules.categories.models import CategoryKind


class CategoryIn(APIModel):
    name: str = Field(min_length=1, max_length=40)
    icon: str = Field(default="circle", min_length=1, max_length=24)
    kind: CategoryKind
    sort_order: int = 0


class CategoryPatch(APIModel):
    name: str | None = Field(default=None, min_length=1, max_length=40)
    icon: str | None = Field(default=None, min_length=1, max_length=24)
    sort_order: int | None = None
    archived: bool | None = None


class CategoryOut(APIModel):
    id: str
    name: str
    icon: str
    kind: CategoryKind
    sort_order: int
    archived: bool
    created_at: datetime
    updated_at: datetime
