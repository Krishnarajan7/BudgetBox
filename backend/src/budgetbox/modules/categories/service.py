from sqlalchemy import select
from sqlalchemy.orm import Session

from budgetbox.core.errors import Invalid, NotFound
from budgetbox.core.ids import require_uuid
from budgetbox.modules.categories.models import Category
from budgetbox.modules.categories.schemas import CategoryIn, CategoryPatch


def list_categories(session: Session, *, include_archived: bool = False) -> list[Category]:
    stmt = select(Category).order_by(Category.kind, Category.sort_order, Category.name)
    if not include_archived:
        stmt = stmt.where(Category.archived.is_(False))
    return list(session.scalars(stmt))


def get(session: Session, category_id: str) -> Category:
    row = session.get(Category, category_id)
    if row is None:
        raise NotFound(f"no category {category_id}")
    return row


def upsert(session: Session, category_id: str, data: CategoryIn) -> Category:
    """PUT semantics: create with the client's id, or replace in place. Kind is
    immutable once created — a category's txns would change meaning under it."""
    category_id = require_uuid(category_id)
    row = session.get(Category, category_id)
    if row is None:
        row = Category(id=category_id, kind=data.kind)
        session.add(row)
    elif row.kind is not data.kind:
        raise Invalid("a category's kind cannot change; archive it and create a new one")
    row.name = data.name
    row.icon = data.icon
    row.sort_order = data.sort_order
    session.commit()
    return row


def patch(session: Session, category_id: str, data: CategoryPatch) -> Category:
    row = get(session, category_id)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(row, field, value)
    session.commit()
    return row
