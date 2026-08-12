from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.modules.coaching import service
from budgetbox.modules.coaching.schemas import (
    CoachingInsightOut,
    CoachingPreferences,
    InsightFeedbackIn,
    MerchantRuleIn,
    MerchantRuleOut,
    MerchantRulePatch,
)

router = APIRouter(prefix="/coaching", tags=["coaching"])


@router.get("/feed")
def feed(session: SessionDep) -> list[CoachingInsightOut]:
    return service.feed(session)


@router.get("/preferences")
def preferences(session: SessionDep) -> CoachingPreferences:
    return service.preferences(session)


@router.put("/preferences")
def set_preferences(session: SessionDep, data: CoachingPreferences) -> CoachingPreferences:
    return service.set_preferences(session, data)


@router.get("/merchant-rules")
def merchant_rules(session: SessionDep, include_inactive: bool = False) -> list[MerchantRuleOut]:
    return [
        MerchantRuleOut.model_validate(row)
        for row in service.list_rules(session, include_inactive=include_inactive)
    ]


@router.put("/merchant-rules/{rule_id}")
def upsert_rule(session: SessionDep, rule_id: str, data: MerchantRuleIn) -> MerchantRuleOut:
    return MerchantRuleOut.model_validate(service.upsert_rule(session, rule_id, data))


@router.patch("/merchant-rules/{rule_id}")
def patch_rule(session: SessionDep, rule_id: str, data: MerchantRulePatch) -> MerchantRuleOut:
    return MerchantRuleOut.model_validate(service.patch_rule(session, rule_id, data))


@router.post("/insights/{insight_id}/feedback")
def feedback(session: SessionDep, insight_id: str, data: InsightFeedbackIn) -> CoachingInsightOut:
    return service.feedback(session, insight_id, data)
