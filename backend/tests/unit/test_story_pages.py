"""The story's conditional pages, the journal's mood whisper, and streaks — the
selection rules that decide whether the book says anything at all."""

from datetime import date

from budgetbox.domain.insights import (
    BudgetHoldCandidate,
    GoalMoveCandidate,
    held_budget,
    mood_money,
    moved_goal,
    quietest_week,
    streak_days,
)

# --- quietest week ------------------------------------------------------------


def test_quietest_week_ignores_the_week_still_being_lived() -> None:
    # Days 1-7 cost 700, days 8-14 cost 100. On the 20th both are complete.
    totals = {d: 100_00 for d in range(1, 8)} | {d: 10_00 for d in range(8, 15)}
    week = quietest_week(totals, days_in_month=31, today_day=20)
    assert week is not None
    assert (week.start_day, week.end_day, week.spent_paise) == (8, 14, 70_00)
    # 31/7 rounds to 4 weeks.
    assert week.projected_paise == 70_00 * 4

    # On the 10th only the first week has finished. One week is not a stretch
    # to single out — it is simply the only week there is — so there is no page.
    assert quietest_week(totals, days_in_month=31, today_day=10) is None


def test_quietest_week_needs_a_finished_week_with_spending() -> None:
    assert quietest_week({1: 100_00}, days_in_month=31, today_day=3) is None  # none complete
    assert quietest_week({}, days_in_month=31, today_day=31) is None  # a blank week says nothing


def test_quietest_week_breaks_ties_to_the_earlier_week() -> None:
    totals = {d: 10_00 for d in range(1, 29)}  # four complete weeks, all equal
    week = quietest_week(totals, days_in_month=31, today_day=31)
    assert week is not None
    assert week.start_day == 1


def test_a_blank_complete_week_is_not_a_quiet_week() -> None:
    # Nothing written is silence, not restraint: the page doesn't appear.
    totals = {d: 10_00 for d in range(1, 8)}
    assert quietest_week(totals, days_in_month=31, today_day=31) is None


# --- the budget that held -----------------------------------------------------


def test_held_budget_wants_the_tightest_real_hold() -> None:
    candidates = [
        BudgetHoldCandidate("a", "Food", limit_paise=5_000_00, spent_paise=4_800_00),  # 96%
        BudgetHoldCandidate("b", "Travel", limit_paise=5_000_00, spent_paise=3_000_00),  # 60%
    ]
    held = held_budget(candidates)
    assert held is not None
    assert held.budget_id == "a"
    assert held.spare_paise == 200_00
    assert held.spare_year_paise == 200_00 * 12


def test_held_budget_rejects_overspent_untouched_and_barely_used() -> None:
    assert held_budget([BudgetHoldCandidate("a", "Food", 1_000_00, 1_000_01)]) is None  # over
    assert held_budget([BudgetHoldCandidate("a", "Food", 1_000_00, 0)]) is None  # untouched
    # 40% used isn't restraint, it's a line that was never tested.
    assert held_budget([BudgetHoldCandidate("a", "Food", 1_000_00, 400_00)]) is None
    # Exactly on the line still counts as held.
    assert held_budget([BudgetHoldCandidate("a", "Food", 1_000_00, 1_000_00)]) is not None


# --- the goal that moved ------------------------------------------------------


def test_moved_goal_picks_the_biggest_mover() -> None:
    moved = moved_goal(
        [
            GoalMoveCandidate(
                "a", "Laptop", moved_paise=5_000_00, done_paise=5_000_00, target_paise=60_000_00
            ),
            GoalMoveCandidate(
                "b", "Trip", moved_paise=9_000_00, done_paise=9_000_00, target_paise=40_000_00
            ),
        ]
    )
    assert moved is not None
    assert moved.goal_id == "b"
    assert moved.reached is False
    assert moved.remaining_paise == 31_000_00
    assert moved.months_left == 4  # ceil(31000/9000)


def test_moved_goal_ignores_a_token_contribution_but_never_a_finish() -> None:
    # 1% of the target isn't a month that moved.
    assert moved_goal([GoalMoveCandidate("a", "Car", 1_000_00, 1_000_00, 100_000_00)]) is None
    # A goal that closed always earns the page, however small the last stroke.
    done = moved_goal([GoalMoveCandidate("a", "Car", 100_00, 100_000_00, 100_000_00)])
    assert done is not None
    assert done.reached is True
    assert done.months_left is None
    assert done.remaining_paise == 0


# --- mood against money -------------------------------------------------------


def test_mood_money_speaks_only_with_evidence_on_both_sides() -> None:
    rough = [(1, 500_00), (2, 600_00), (1, 700_00)]
    bright = [(5, 100_00), (4, 100_00), (4, 100_00)]
    verdict = mood_money(rough + bright)
    assert verdict is not None
    assert verdict.verdict == "rough_costs_more"
    assert verdict.rough_days == 3
    assert verdict.rough_avg_paise == 600_00
    assert verdict.bright_avg_paise == 100_00

    # Two rough days is not a pattern.
    assert mood_money(rough[:2] + bright) is None
    # Middling moods belong to neither bucket.
    assert mood_money([(3, 500_00)] * 10) is None


def test_mood_money_stays_quiet_when_the_difference_is_small() -> None:
    pairs = [(1, 100_00), (2, 105_00), (1, 110_00), (5, 100_00), (4, 95_00), (4, 100_00)]
    assert mood_money(pairs) is None


# --- streaks ------------------------------------------------------------------


def test_streak_forgives_today_but_not_a_gap() -> None:
    days = {date(2026, 7, 12), date(2026, 7, 13), date(2026, 7, 14)}
    # Today isn't written yet: the streak still stands at three.
    assert streak_days(days, date(2026, 7, 15)) == 3
    assert streak_days(days | {date(2026, 7, 15)}, date(2026, 7, 15)) == 4
    # A missed day ends it, however much came before.
    assert streak_days(days, date(2026, 7, 16)) == 0
    assert streak_days(set(), date(2026, 7, 15)) == 0


def test_quietest_week_needs_two_finished_weeks_to_compare() -> None:
    """Matches the app: a lone finished week is the only week there is, and
    calling it the quietest says nothing worth a page."""
    totals = {d: 10_00 for d in range(1, 15)}
    assert quietest_week(totals, days_in_month=31, today_day=9) is None
    assert quietest_week(totals, days_in_month=31, today_day=16) is not None
