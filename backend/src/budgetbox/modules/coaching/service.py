import datetime as dt
import re
import statistics
import unicodedata

from sqlalchemy import select
from sqlalchemy.orm import Session

from budgetbox.core.errors import Conflict, Invalid, NotFound
from budgetbox.core.ids import new_id, require_uuid
from budgetbox.core.time import ist_day_start, today_ist
from budgetbox.domain.periods import add_months, clamp_day, month_end_exclusive, month_start
from budgetbox.modules.budgets import service as budget_service
from budgetbox.modules.coaching.models import (
    CoachingInsight,
    InsightKind,
    InsightStatus,
    MerchantRule,
    SpendingClass,
)
from budgetbox.modules.coaching.schemas import (
    CoachingInsightOut,
    CoachingPreferences,
    InsightEvidence,
    InsightFeedbackIn,
    MerchantRuleIn,
    MerchantRulePatch,
)
from budgetbox.modules.settings import service as settings_service
from budgetbox.modules.transactions.models import Txn, TxnType

_PREFERENCES_KEY = "coaching_preferences"
_NON_WORD = re.compile(r"[^\w]+", re.UNICODE)


def normalize_merchant(value: str) -> str:
    """Stable exact-match key: Unicode-normalized, case-folded, punctuation collapsed."""
    normalized = unicodedata.normalize("NFKC", value).casefold().strip()
    return " ".join(part for part in _NON_WORD.split(normalized) if part)[:120]


def list_rules(session: Session, *, include_inactive: bool = False) -> list[MerchantRule]:
    stmt = select(MerchantRule).order_by(MerchantRule.merchant_name, MerchantRule.match_text)
    if not include_inactive:
        stmt = stmt.where(MerchantRule.active.is_(True))
    return list(session.scalars(stmt))


def get_rule(session: Session, rule_id: str) -> MerchantRule:
    row = session.get(MerchantRule, rule_id)
    if row is None:
        raise NotFound(f"no merchant rule {rule_id}")
    return row


def upsert_rule(session: Session, rule_id: str, data: MerchantRuleIn) -> MerchantRule:
    rule_id = require_uuid(rule_id)
    match_text = normalize_merchant(data.match_text)
    if not match_text:
        raise Invalid("match_text must contain a letter or number")
    collision = session.scalar(
        select(MerchantRule).where(
            MerchantRule.match_text == match_text, MerchantRule.id != rule_id
        )
    )
    if collision is not None:
        raise Conflict(f"a rule already matches {match_text!r}")
    row = session.get(MerchantRule, rule_id)
    if row is None:
        row = MerchantRule(id=rule_id)
        session.add(row)
    row.match_text = match_text
    row.merchant_name = data.merchant_name.strip()
    row.classification = data.classification
    row.active = data.active
    session.commit()
    return row


def patch_rule(session: Session, rule_id: str, data: MerchantRulePatch) -> MerchantRule:
    row = get_rule(session, rule_id)
    changes = data.model_dump(exclude_unset=True)
    if "merchant_name" in changes:
        changes["merchant_name"] = changes["merchant_name"].strip()
    for field, value in changes.items():
        setattr(row, field, value)
    session.commit()
    return row


def preferences(session: Session) -> CoachingPreferences:
    raw = settings_service.get(session, _PREFERENCES_KEY)
    if raw is None:
        return CoachingPreferences()
    try:
        return CoachingPreferences.model_validate_json(raw)
    except ValueError:
        return CoachingPreferences()


def set_preferences(session: Session, data: CoachingPreferences) -> CoachingPreferences:
    settings_service.set_value(session, _PREFERENCES_KEY, data.model_dump_json())
    return data


def _money(paise: int) -> str:
    rupees = round(paise / 100)
    return f"₹{rupees:,}"


def _same_elapsed_window(month: dt.date, elapsed_days: int) -> tuple[dt.date, dt.date]:
    start = month_start(month)
    last = clamp_day(start.year, start.month, elapsed_days)
    return start, min(last + dt.timedelta(days=1), month_end_exclusive(start))


def _expense_rows(session: Session, start: dt.date, end: dt.date) -> list[Txn]:
    return list(
        session.scalars(
            select(Txn).where(
                Txn.type == TxnType.EXPENSE,
                Txn.at >= ist_day_start(start),
                Txn.at < ist_day_start(end),
            )
        )
    )


def _write_insight(
    session: Session,
    *,
    fingerprint: str,
    kind: InsightKind,
    title: str,
    message: str,
    evidence: InsightEvidence,
    priority: int,
    period_start: dt.date,
    period_end: dt.date,
    expires_on: dt.date,
    current_paise: int | None = None,
    baseline_paise: int | None = None,
    difference_paise: int | None = None,
) -> bool:
    row = session.scalar(select(CoachingInsight).where(CoachingInsight.fingerprint == fingerprint))
    created = row is None
    if row is None:
        row = CoachingInsight(id=new_id(), fingerprint=fingerprint, status=InsightStatus.ACTIVE)
        session.add(row)
    # Feedback is durable for this evidence window. Regeneration refreshes the
    # arithmetic but never resurrects a dismissed or acted-on card.
    row.kind = kind
    row.title = title
    row.message = message
    row.evidence_json = evidence.model_dump_json()
    row.priority = priority
    row.current_paise = current_paise
    row.baseline_paise = baseline_paise
    row.difference_paise = difference_paise
    row.period_start = period_start
    row.period_end = period_end
    row.expires_on = expires_on
    return created


def generate(session: Session, *, today: dt.date | None = None) -> int:
    today = today or today_ist()
    prefs = preferences(session)
    if not prefs.enabled:
        return 0

    start = month_start(today)
    end = today + dt.timedelta(days=1)
    expires = month_end_exclusive(today)
    elapsed = (today - start).days + 1
    current_rows = _expense_rows(session, start, end)
    created = 0

    historical: list[tuple[str, list[Txn]]] = []
    for back in range(1, 4):
        year, month = add_months(start.year, start.month, -back)
        old_start, old_end = _same_elapsed_window(dt.date(year, month, 1), elapsed)
        historical.append((f"{year:04d}-{month:02d}", _expense_rows(session, old_start, old_end)))

    for rule in list_rules(session):
        if rule.classification is SpendingClass.ESSENTIAL:
            continue
        current = [t for t in current_rows if normalize_merchant(t.title) == rule.match_text]
        if not current:
            continue
        current_total = sum(t.amount_paise for t in current)
        baselines = [
            sum(t.amount_paise for t in rows if normalize_merchant(t.title) == rule.match_text)
            for _month, rows in historical
        ]
        baseline = round(statistics.median(baselines))
        difference = current_total - baseline

        surged = (
            current_total >= 50_000
            and difference >= prefs.minimum_increase_paise
            and current_total >= max(round(baseline * prefs.surge_ratio), 1)
        )
        if surged:
            created += int(
                _write_insight(
                    session,
                    fingerprint=f"merchant_surge:{start.isoformat()}:{rule.id}",
                    kind=InsightKind.MERCHANT_SURGE,
                    title=f"{rule.merchant_name} is above your usual pace",
                    message=(
                        f"You have spent {_money(current_total)} at {rule.merchant_name} "
                        f"so far—{_money(difference)} above the median for the same point "
                        "in the previous three months."
                    ),
                    evidence=InsightEvidence(
                        reason="same_elapsed_days_median",
                        merchant_rule_id=rule.id,
                        merchant_name=rule.merchant_name,
                        classification=rule.classification,
                        transaction_ids=[t.id for t in current],
                        comparison_months=[month for month, _rows in historical],
                        count=len(current),
                    ),
                    priority=90 if rule.classification is SpendingClass.AVOID else 75,
                    current_paise=current_total,
                    baseline_paise=baseline,
                    difference_paise=difference,
                    period_start=start,
                    period_end=end,
                    expires_on=expires,
                )
            )

        # One merchant gets one useful card per window. A surge already says
        # more than a raw repeat count, so do not stack both on Today's page.
        if (
            not surged
            and len(current) >= prefs.repeat_count
            and current_total >= prefs.minimum_increase_paise
        ):
            created += int(
                _write_insight(
                    session,
                    fingerprint=f"repeated_discretionary:{start.isoformat()}:{rule.id}",
                    kind=InsightKind.REPEATED_DISCRETIONARY,
                    title=f"{len(current)} entries at {rule.merchant_name}",
                    message=(
                        f"{rule.merchant_name} has appeared {len(current)} times this month "
                        f"for {_money(current_total)} in total. You marked this spending "
                        f"as {rule.classification.value}."
                    ),
                    evidence=InsightEvidence(
                        reason="user_classified_repeat",
                        merchant_rule_id=rule.id,
                        merchant_name=rule.merchant_name,
                        classification=rule.classification,
                        transaction_ids=[t.id for t in current],
                        count=len(current),
                    ),
                    priority=80 if rule.classification is SpendingClass.AVOID else 60,
                    current_paise=current_total,
                    period_start=start,
                    period_end=end,
                    expires_on=expires,
                )
            )

    for view in budget_service.pace_views(session, month=today):
        overspend = view.pace.projected_overspend_paise
        if overspend < prefs.minimum_increase_paise:
            continue
        budget = view.budget
        created += int(
            _write_insight(
                session,
                fingerprint=f"budget_risk:{start.isoformat()}:{budget.id}",
                kind=InsightKind.BUDGET_RISK,
                title=f"{budget.name} may cross its line",
                message=(
                    f"{budget.name}'s line is {_money(view.pace.limit_paise)}. "
                    f"At the current pace, spending may reach "
                    f"{_money(view.pace.projected_paise)}—{_money(overspend)} over."
                ),
                evidence=InsightEvidence(
                    reason="even_pace_projection",
                    budget_id=budget.id,
                    budget_name=budget.name,
                    projected_paise=view.pace.projected_paise,
                    limit_paise=view.pace.limit_paise,
                ),
                priority=85,
                current_paise=view.pace.spent_paise,
                baseline_paise=view.pace.limit_paise,
                difference_paise=overspend,
                period_start=start,
                period_end=end,
                expires_on=expires,
            )
        )

    session.commit()
    return created


def _out(row: CoachingInsight) -> CoachingInsightOut:
    return CoachingInsightOut(
        id=row.id,
        kind=row.kind,
        title=row.title,
        message=row.message,
        evidence=InsightEvidence.model_validate_json(row.evidence_json),
        priority=row.priority,
        current_paise=row.current_paise,
        baseline_paise=row.baseline_paise,
        difference_paise=row.difference_paise,
        period_start=row.period_start,
        period_end=row.period_end,
        expires_on=row.expires_on,
        status=row.status,
        snoozed_until=row.snoozed_until,
        created_at=row.created_at,
        updated_at=row.updated_at,
    )


def feed(session: Session, *, today: dt.date | None = None) -> list[CoachingInsightOut]:
    today = today or today_ist()
    prefs = preferences(session)
    if not prefs.enabled:
        return []
    generate(session, today=today)
    rows = session.scalars(
        select(CoachingInsight)
        .where(
            CoachingInsight.status == InsightStatus.ACTIVE,
            CoachingInsight.expires_on >= today,
            (CoachingInsight.snoozed_until.is_(None)) | (CoachingInsight.snoozed_until <= today),
        )
        .order_by(CoachingInsight.priority.desc(), CoachingInsight.created_at)
        .limit(prefs.max_cards)
    )
    return [_out(row) for row in rows]


def feedback(session: Session, insight_id: str, data: InsightFeedbackIn) -> CoachingInsightOut:
    row = session.get(CoachingInsight, insight_id)
    if row is None:
        raise NotFound(f"no coaching insight {insight_id}")
    if data.action == "dismiss":
        row.status = InsightStatus.DISMISSED
        row.snoozed_until = None
    elif data.action == "acted":
        row.status = InsightStatus.ACTED
        row.snoozed_until = None
    else:
        if data.snoozed_until is None or data.snoozed_until <= today_ist():
            raise Invalid("snoozed_until must be a future day")
        row.status = InsightStatus.ACTIVE
        row.snoozed_until = data.snoozed_until
    session.commit()
    return _out(row)
