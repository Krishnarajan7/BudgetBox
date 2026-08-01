from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.modules.goals import service
from budgetbox.modules.goals.schemas import ContributeIn, GoalIn, GoalPatch, GoalView
from budgetbox.modules.transactions.schemas import TxnOut

router = APIRouter(prefix="/goals", tags=["goals"])


@router.get("")
def list_goals(session: SessionDep, include_archived: bool = False) -> list[GoalView]:
    return service.views(session, include_archived=include_archived)


@router.get("/{goal_id}")
def get_goal(session: SessionDep, goal_id: str) -> GoalView:
    return service.view(session, goal_id)


@router.put("/{goal_id}")
def upsert_goal(session: SessionDep, goal_id: str, data: GoalIn) -> GoalView:
    service.upsert(session, goal_id, data)
    return service.view(session, goal_id)


@router.patch("/{goal_id}")
def patch_goal(session: SessionDep, goal_id: str, data: GoalPatch) -> GoalView:
    service.patch(session, goal_id, data)
    return service.view(session, goal_id)


@router.post("/{goal_id}/contribute", status_code=201)
def contribute(session: SessionDep, goal_id: str, data: ContributeIn) -> TxnOut:
    return TxnOut.model_validate(service.contribute(session, goal_id, data))
