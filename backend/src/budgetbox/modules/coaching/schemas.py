from datetime import date, datetime
from typing import Literal

from pydantic import Field

from budgetbox.api.schemas import APIModel, StrictPaise
from budgetbox.modules.coaching.models import InsightKind, InsightStatus, SpendingClass


class MerchantRuleIn(APIModel):
    match_text: str = Field(min_length=1, max_length=120)
    merchant_name: str = Field(min_length=1, max_length=80)
    classification: SpendingClass
    active: bool = True


class MerchantRulePatch(APIModel):
    merchant_name: str | None = Field(default=None, min_length=1, max_length=80)
    classification: SpendingClass | None = None
    active: bool | None = None


class MerchantRuleOut(APIModel):
    id: str
    match_text: str
    merchant_name: str
    classification: SpendingClass
    active: bool
    created_at: datetime
    updated_at: datetime


class CoachingPreferences(APIModel):
    enabled: bool = True
    max_cards: int = Field(default=3, ge=1, le=10)
    minimum_increase_paise: int = Field(default=30_000, ge=0)
    surge_ratio: float = Field(default=1.5, ge=1.1, le=10)
    repeat_count: int = Field(default=3, ge=2, le=30)


class InsightEvidence(APIModel):
    reason: str
    merchant_rule_id: str | None = None
    merchant_name: str | None = None
    classification: SpendingClass | None = None
    transaction_ids: list[str] = Field(default_factory=list)
    comparison_months: list[str] = Field(default_factory=list)
    count: int | None = None
    budget_id: str | None = None
    budget_name: str | None = None
    projected_paise: StrictPaise | None = None
    limit_paise: StrictPaise | None = None


class CoachingInsightOut(APIModel):
    id: str
    kind: InsightKind
    title: str
    message: str
    evidence: InsightEvidence
    priority: int
    current_paise: StrictPaise | None
    baseline_paise: StrictPaise | None
    difference_paise: StrictPaise | None
    period_start: date
    period_end: date
    expires_on: date
    status: InsightStatus
    snoozed_until: date | None
    created_at: datetime
    updated_at: datetime


class InsightFeedbackIn(APIModel):
    action: Literal["dismiss", "acted", "snooze"]
    snoozed_until: date | None = None
