from fastapi import APIRouter
from pydantic import Field

from budgetbox.api.deps import SessionDep
from budgetbox.api.schemas import APIModel
from budgetbox.modules.settings import service

router = APIRouter(prefix="/settings", tags=["settings"])


class SettingIn(APIModel):
    value: str = Field(max_length=10_000)


@router.get("")
def all_settings(session: SessionDep) -> dict[str, str]:
    return service.all_settings(session)


@router.put("/{key}")
def set_setting(session: SessionDep, key: str, data: SettingIn) -> dict[str, str]:
    row = service.set_value(session, key, data.value)
    return {row.key: row.value}
