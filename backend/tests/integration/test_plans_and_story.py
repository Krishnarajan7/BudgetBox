"""The plans page's evidence — a budget's trail, a goal's rhythm, the shelf's
yearly cost — and the story's conditional pages."""

import time_machine
from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id
from tests.integration.helpers import make_account, make_txn
from tests.integration.test_budgets_and_goals import make_budget

FOOD = "019fb983-3f3c-7c0c-a3d1-5ca809294bdf"
TRAVEL = "019fb983-3f3d-7628-af74-c9b2c624f57b"


# --- a budget's trail ---------------------------------------------------------


@time_machine.travel("2026-07-10T10:00:00+05:30")
def test_budget_trail_counts_the_months_the_line_held(client: TestClient) -> None:
    account = make_account(client)
    budget = make_budget(client, category_id=FOOD, limit_paise=5_000_00)
    # Apr and May held; Jun went over, which ends the run.
    for month, amount in (("04", 4_000_00), ("05", 4_500_00), ("06", 6_000_00)):
        make_txn(
            client,
            account,
            amount=amount,
            at=f"2026-{month}-10T10:00:00+05:30",
            category_id=FOOD,
        )
    trail = client.get(f"/v1/budgets/{budget}/trail").json()
    assert [m["month"] for m in trail["months"]] == [
        "2026-01",
        "2026-02",
        "2026-03",
        "2026-04",
        "2026-05",
        "2026-06",
        "2026-07",
    ]
    assert [m["held"] for m in trail["months"]] == [False, False, False, True, True, False, False]
    assert trail["held_months_running"] == 0

    # Bring June back inside the line and the run reads three.
    make_txn(
        client, account, amount=100_00, at="2026-07-01T10:00:00+05:30", category_id=FOOD
    )  # noise in the current month, which is still being lived
    over = client.get("/v1/txns", params={"from_day": "2026-06-01", "to_day": "2026-07-01"}).json()
    client.delete(f"/v1/txns/{over['items'][0]['id']}")
    make_txn(client, account, amount=1_000_00, at="2026-06-10T10:00:00+05:30", category_id=FOOD)
    assert client.get(f"/v1/budgets/{budget}/trail").json()["held_months_running"] == 3


@time_machine.travel("2026-07-10T10:00:00+05:30")
def test_a_month_with_no_spending_is_not_evidence_of_restraint(client: TestClient) -> None:
    account = make_account(client)
    budget = make_budget(client, category_id=FOOD, limit_paise=5_000_00)
    make_txn(client, account, amount=1_000_00, at="2026-04-10T10:00:00+05:30", category_id=FOOD)
    make_txn(client, account, amount=1_000_00, at="2026-06-10T10:00:00+05:30", category_id=FOOD)
    # June held, May was blank: the run stops at one.
    assert client.get(f"/v1/budgets/{budget}/trail").json()["held_months_running"] == 1


@time_machine.travel("2026-07-10T10:00:00+05:30")
def test_budget_trail_climbs_day_by_day_against_an_even_pace(client: TestClient) -> None:
    account = make_account(client)
    budget = make_budget(client, category_id=FOOD, limit_paise=3_100_00)
    make_txn(client, account, amount=200_00, at="2026-07-02T10:00:00+05:30", category_id=FOOD)
    make_txn(client, account, amount=300_00, at="2026-07-05T10:00:00+05:30", category_id=FOOD)
    make_txn(client, account, amount=50_00, at="2026-07-05T18:00:00+05:30", category_id=TRAVEL)

    trail = client.get(f"/v1/budgets/{budget}/trail").json()
    # Ten days lived; the line never dips, and the other category stays out of it.
    assert trail["daily_cumulative_paise"] == [
        0,
        200_00,
        200_00,
        200_00,
        500_00,
        500_00,
        500_00,
        500_00,
        500_00,
        500_00,
    ]
    # ₹3100 over 31 days is exactly ₹100 a day.
    assert trail["even_pace_paise"] == [100_00 * d for d in range(1, 11)]


def test_budget_trail_of_a_missing_budget_is_a_not_found_problem(client: TestClient) -> None:
    resp = client.get(f"/v1/budgets/{new_id()}/trail")
    assert resp.status_code == 404
    assert resp.json()["type"] == "urn:budgetbox:problem:not-found"


# --- a goal's rhythm ----------------------------------------------------------


@time_machine.travel("2026-07-10T10:00:00+05:30")
def test_goal_rhythm_marks_the_months_something_went_in(client: TestClient) -> None:
    account = make_account(client)
    goal_id = new_id()
    client.put(
        f"/v1/goals/{goal_id}",
        json={"name": "Laptop", "target_paise": 80_000_00, "kind": "save"},
    )
    for at in ("2026-03-04T10:00:00+05:30", "2026-06-04T10:00:00+05:30"):
        client.post(
            f"/v1/goals/{goal_id}/contribute",
            json={"amount_paise": 5_000_00, "account_id": account, "at": at},
        )
    view = client.get(f"/v1/goals/{goal_id}").json()
    # Feb, Mar, Apr, May, Jun, Jul — oldest first.
    assert view["rhythm"] == [False, True, False, False, True, False]


# --- the shelf ----------------------------------------------------------------


@time_machine.travel("2026-07-10T10:00:00+05:30")
def test_upcoming_reports_the_shelfs_yearly_cost_and_what_the_month_owes(
    client: TestClient,
) -> None:
    account = make_account(client)
    client.put(
        f"/v1/recurring/{new_id()}",
        json={
            "title": "Rent",
            "amount_paise": 15_000_00,
            "account_id": account,
            "kind": "bill",
            "day_of_month": 20,
        },
    )
    client.put(
        f"/v1/recurring/{new_id()}",
        json={
            "title": "Domain",
            "amount_paise": 1_200_00,
            "account_id": account,
            "kind": "subscription",
            "every_months": 12,
            "day_of_month": 14,
        },
    )
    got = client.get("/v1/recurring/upcoming").json()
    assert got["yearly_bill_paise"] == 15_000_00 * 12
    assert got["yearly_subscription_paise"] == 1_200_00  # a yearly plan counts once
    assert got["yearly_paise"] == 15_000_00 * 12 + 1_200_00
    # Both still land before July turns.
    assert got["committed_unpaid_paise"] == 16_200_00


# --- the story's conditional pages -------------------------------------------


@time_machine.travel("2026-08-01T10:00:00+05:30")
def test_story_names_the_budget_that_held_its_line(client: TestClient) -> None:
    account = make_account(client)
    make_budget(client, name="Food", category_id=FOOD, limit_paise=5_000_00)
    make_budget(client, name="Travel", category_id=TRAVEL, limit_paise=5_000_00)
    make_txn(client, account, amount=4_800_00, at="2026-07-10T10:00:00+05:30", category_id=FOOD)
    make_txn(client, account, amount=3_000_00, at="2026-07-11T10:00:00+05:30", category_id=TRAVEL)

    held = client.get("/v1/insights/month-story", params={"month": "2026-07"}).json()["budget_held"]
    assert held["name"] == "Food"  # the tighter hold, not the bigger gap
    assert held["spare_paise"] == 200_00
    assert held["spare_year_paise"] == 2_400_00


@time_machine.travel("2026-08-01T10:00:00+05:30")
def test_story_names_the_goal_that_moved(client: TestClient) -> None:
    account = make_account(client)
    goal_id = new_id()
    client.put(
        f"/v1/goals/{goal_id}",
        json={"name": "Trip", "target_paise": 40_000_00, "kind": "save"},
    )
    client.post(
        f"/v1/goals/{goal_id}/contribute",
        json={
            "amount_paise": 9_000_00,
            "account_id": account,
            "at": "2026-07-12T10:00:00+05:30",
        },
    )
    moved = client.get("/v1/insights/month-story", params={"month": "2026-07"}).json()["goal_moved"]
    assert moved["name"] == "Trip"
    assert moved["moved_paise"] == 9_000_00
    assert moved["months_left"] == 4
    assert moved["reached"] is False


@time_machine.travel("2026-08-01T10:00:00+05:30")
def test_story_finds_the_quietest_week_only_when_it_would_have_helped(
    client: TestClient,
) -> None:
    account = make_account(client)
    # A heavy first week, then a light one, then two ordinary ones.
    make_txn(client, account, amount=20_000_00, at="2026-07-03T10:00:00+05:30")
    make_txn(client, account, amount=500_00, at="2026-07-10T10:00:00+05:30")
    make_txn(client, account, amount=1_000_00, at="2026-07-17T10:00:00+05:30")
    make_txn(client, account, amount=1_000_00, at="2026-07-24T10:00:00+05:30")

    week = client.get("/v1/insights/month-story", params={"month": "2026-07"}).json()[
        "quietest_week"
    ]
    assert (week["start_day"], week["end_day"]) == (8, 14)
    assert week["spent_paise"] == 500_00
    assert week["projected_paise"] == 2_000_00  # 31 days rounds to four weeks

    # A week whose rate would have cost as much as the month says nothing.
    even = make_account(client, "Cash", kind="cash")
    for day in (3, 10, 17, 24):
        make_txn(client, even, amount=1_00, at=f"2026-06-{day:02d}T10:00:00+05:30")
    assert (
        client.get("/v1/insights/month-story", params={"month": "2026-06"}).json()["quietest_week"]
        is None
    )


@time_machine.travel("2026-08-01T10:00:00+05:30")
def test_story_pages_stay_absent_when_the_month_did_not_earn_them(client: TestClient) -> None:
    got = client.get("/v1/insights/month-story", params={"month": "2026-07"}).json()
    assert got["budget_held"] is None
    assert got["goal_moved"] is None
    assert got["quietest_week"] is None
