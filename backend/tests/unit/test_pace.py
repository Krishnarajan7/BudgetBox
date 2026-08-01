"""Parity cases with lib/data/repos/budget_math.dart — same inputs, same numbers."""

from budgetbox.domain.pace import BudgetPace, BudgetStatus


def test_remaining_and_fractions() -> None:
    pace = BudgetPace(spent_paise=30_000, limit_paise=100_000, elapsed_days=10, total_days=30)
    assert pace.remaining_paise == 70_000
    assert pace.fraction_spent == 0.3
    assert pace.fraction_elapsed == 10 / 30


def test_zero_or_negative_limit_means_fully_spent() -> None:
    assert BudgetPace(1, 0, 1, 30).fraction_spent == 1.0
    assert BudgetPace(1, -5, 1, 30).fraction_spent == 1.0


def test_zero_total_days_means_fully_elapsed() -> None:
    assert BudgetPace(0, 100, 0, 0).fraction_elapsed == 1.0


def test_projection_before_any_day_elapsed() -> None:
    pace = BudgetPace(
        spent_paise=500, limit_paise=1000, elapsed_days=0, total_days=30, upcoming_paise=200
    )
    assert pace.projected_paise == 700


def test_projection_straight_line_plus_upcoming() -> None:
    # 30_000 in 10 of 30 days -> 90_000 projected, plus 5_000 committed.
    pace = BudgetPace(30_000, 100_000, 10, 30, upcoming_paise=5_000)
    assert pace.projected_paise == 95_000


def test_projection_rounds_half_away_from_zero_like_dart() -> None:
    # run_rate = 5/2 = 2.5; 2.5 * 1 = 2.5 → Dart .round() = 3 (banker's would give 2).
    assert BudgetPace(5, 1000, 2, 1).projected_paise == 3


def test_status_over_beats_everything() -> None:
    pace = BudgetPace(1500, 1000, 1, 30, upcoming_paise=100)
    assert pace.status is BudgetStatus.OVER


def test_status_pending_when_nothing_spent_but_bill_committed() -> None:
    # Even when the committed amount alone projects over, pending wins (outlined bar).
    pace = BudgetPace(0, 1000, 10, 30, upcoming_paise=5000)
    assert pace.status is BudgetStatus.PENDING


def test_status_projected_over() -> None:
    pace = BudgetPace(600, 1000, 10, 30)  # projects to 1800
    assert pace.status is BudgetStatus.PROJECTED_OVER
    assert pace.projected_overspend_paise == 800


def test_status_on_pace() -> None:
    pace = BudgetPace(300, 1000, 10, 30)  # projects to 900
    assert pace.status is BudgetStatus.ON_PACE
    assert pace.projected_overspend_paise == 0
