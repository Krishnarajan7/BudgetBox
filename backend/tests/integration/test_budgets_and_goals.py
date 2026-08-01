"""Budget pace views (windows, upcoming, rollover, trip books) and goal views."""

import time_machine
from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id
from tests.integration.helpers import expense_category, make_account, make_txn


def make_budget(client: TestClient, **overrides: object) -> str:
    budget_id = new_id()
    body: dict[str, object] = {
        "name": "Food",
        "limit_paise": 10_000_00,
        "period": "month",
        "kind": "all",
        **overrides,
    }
    resp = client.put(f"/v1/budgets/{budget_id}", json=body)
    assert resp.status_code == 200, resp.text
    return budget_id


def the_view(client: TestClient, budget_id: str, month: str | None = None) -> dict:
    params = {"month": month} if month else {}
    views = client.get("/v1/budgets/pace", params=params).json()
    return next(v for v in views if v["budget"]["id"] == budget_id)


@time_machine.travel("2026-07-10T10:00:00+05:30")
def test_category_budget_pace(client: TestClient) -> None:
    account_id = make_account(client)
    cat = expense_category(client)
    budget_id = make_budget(client, category_id=cat)
    make_txn(client, account_id, amount=3_000_00, at="2026-07-05T10:00:00+05:30", category_id=cat)
    make_txn(client, account_id, amount=500_00, at="2026-07-06T10:00:00+05:30")  # other cat

    view = the_view(client, budget_id)
    pace = view["pace"]
    assert (view["window_start"], view["window_end"]) == ("2026-07-01", "2026-08-01")
    assert pace["spent_paise"] == 3_000_00
    assert (pace["elapsed_days"], pace["total_days"]) == (10, 31)
    # 3000/10 * 31 = 9300 -> under 10000.
    assert pace["projected_paise"] == 9_300_00
    assert pace["status"] == "on_pace"


@time_machine.travel("2026-07-10T10:00:00+05:30")
def test_overall_budget_counts_everything_and_upcoming_bills(client: TestClient) -> None:
    account_id = make_account(client)
    budget_id = make_budget(client, name="Everything", limit_paise=40_000_00, category_id=None)
    make_txn(client, account_id, amount=2_000_00, at="2026-07-03T10:00:00+05:30")
    recurring_id = new_id()
    client.put(
        f"/v1/recurring/{recurring_id}",
        json={
            "title": "Rent",
            "amount_paise": 15_000_00,
            "account_id": account_id,
            "kind": "bill",
            "day_of_month": 20,
        },
    )
    pace = the_view(client, budget_id)["pace"]
    assert pace["spent_paise"] == 2_000_00
    assert pace["upcoming_paise"] == 15_000_00  # due the 20th, inside this window
    # 2000/10*31 = 6200 + 15000 = 21200: still on pace against 40000.
    assert pace["projected_paise"] == 21_200_00
    assert pace["status"] == "on_pace"


@time_machine.travel("2026-07-10T10:00:00+05:30")
def test_pending_status_before_first_spend(client: TestClient) -> None:
    account_id = make_account(client)
    cat = expense_category(client)
    budget_id = make_budget(client, category_id=cat, limit_paise=16_000_00)
    recurring_id = new_id()
    client.put(
        f"/v1/recurring/{recurring_id}",
        json={
            "title": "Rent",
            "amount_paise": 15_000_00,
            "account_id": account_id,
            "kind": "bill",
            "day_of_month": 20,
            "category_id": cat,
        },
    )
    assert the_view(client, budget_id)["pace"]["status"] == "pending"


@time_machine.travel("2026-08-10T10:00:00+05:30")
def test_rollover_carries_last_months_leftover(client: TestClient) -> None:
    account_id = make_account(client)
    cat = expense_category(client)
    budget_id = make_budget(client, category_id=cat, limit_paise=10_000_00, rollover=True)
    make_txn(
        client, account_id, amount=4_000_00, at="2026-07-15T10:00:00+05:30", category_id=cat
    )  # July: 6000 left over
    make_txn(client, account_id, amount=1_000_00, at="2026-08-05T10:00:00+05:30", category_id=cat)
    pace = the_view(client, budget_id)["pace"]
    assert pace["limit_paise"] == 16_000_00  # 10000 + 6000 carried
    assert pace["spent_paise"] == 1_000_00


@time_machine.travel("2026-07-10T10:00:00+05:30")
def test_trip_book_counts_only_added_txns(client: TestClient) -> None:
    account_id = make_account(client)
    budget_id = make_budget(
        client, name="Goa trip", period="custom", kind="added", limit_paise=20_000_00
    )
    trip_txn = make_txn(
        client, account_id, amount=5_000_00, title="Flights", at="2026-06-20T10:00:00+05:30"
    )
    make_txn(client, account_id, amount=999_00, title="Unrelated")

    assert client.put(f"/v1/budgets/{budget_id}/txns/{trip_txn}").status_code == 204
    view = the_view(client, budget_id)
    assert view["window_start"] is None
    assert view["pace"]["spent_paise"] == 5_000_00
    assert view["pace"]["fraction_elapsed"] == 1.0  # no clock on a trip book

    client.delete(f"/v1/budgets/{budget_id}/txns/{trip_txn}")
    assert the_view(client, budget_id)["pace"]["spent_paise"] == 0


def test_added_links_only_for_added_budgets(client: TestClient) -> None:
    account_id = make_account(client)
    budget_id = make_budget(client)  # kind=all
    txn_id = make_txn(client, account_id)
    resp = client.put(f"/v1/budgets/{budget_id}/txns/{txn_id}")
    assert resp.status_code == 422


@time_machine.travel("2026-07-10T10:00:00+05:30")
def test_goal_view_contribution_and_eta(client: TestClient) -> None:
    account_id = make_account(client)
    goal_id = new_id()
    resp = client.put(
        f"/v1/goals/{goal_id}",
        json={
            "name": "Emergency fund",
            "target_paise": 100_000_00,
            "kind": "save",
            "monthly_paise": 10_000_00,
        },
    )
    assert resp.status_code == 200
    view = resp.json()
    assert (view["done_paise"], view["remaining_paise"]) == (0, 100_000_00)
    assert view["eta"] == "2027-05-10"  # ceil(100000/10000) = 10 months out

    contributed = client.post(
        f"/v1/goals/{goal_id}/contribute",
        json={
            "amount_paise": 40_000_00,
            "account_id": account_id,
            "at": "2026-07-10T09:00:00+05:30",
        },
    )
    assert contributed.status_code == 201
    assert contributed.json()["goal_id"] == goal_id

    view = client.get(f"/v1/goals/{goal_id}").json()
    assert (view["done_paise"], view["entry_count"]) == (40_000_00, 1)
    assert view["fraction"] == 0.4
    assert view["eta"] == "2027-01-10"  # 6 more months

    # Tagging an existing txn counts too — goals are views over the ledger.
    txn_id = make_txn(client, account_id, amount=60_000_00, title="Bonus set aside")
    client.patch(f"/v1/txns/{txn_id}", json={"goal_id": goal_id})
    view = client.get(f"/v1/goals/{goal_id}").json()
    assert view["reached"] is True
    assert view["eta"] is None


def test_txn_with_unknown_goal_rejected(client: TestClient) -> None:
    account_id = make_account(client)
    resp = client.put(
        f"/v1/txns/{new_id()}",
        json={
            "amount_paise": 100,
            "type": "expense",
            "account_id": account_id,
            "title": "x",
            "at": "2026-07-02T10:00:00+05:30",
            "goal_id": new_id(),
        },
    )
    assert resp.status_code == 422
