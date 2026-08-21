"""/v1/alarms — the set of alarms, so a reinstalled phone keeps its mornings."""

from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.modules.alarms import service
from budgetbox.modules.alarms.schemas import AlarmIn, AlarmOut

router = APIRouter(prefix="/alarms", tags=["alarms"])


@router.get("")
def list_alarms(session: SessionDep) -> list[AlarmOut]:
    return [AlarmOut.model_validate(r) for r in service.list_alarms(session)]


@router.put("/{alarm_id}")
def upsert_alarm(session: SessionDep, alarm_id: str, data: AlarmIn) -> AlarmOut:
    return AlarmOut.model_validate(service.upsert(session, alarm_id, data))


@router.delete("/{alarm_id}", status_code=204)
def delete_alarm(session: SessionDep, alarm_id: str) -> None:
    service.delete(session, alarm_id)
