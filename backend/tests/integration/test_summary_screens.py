"""Screen-shaped read models: the Book's month, the calendar's money layer, and
the extra facts Today grew — quiet days, the closing streak, yesterday's figure."""

import time_machine
from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id
from tests.integration.helpers import expense_category, make_account, make_txn

FOOD = "019fb983-3f3c-7c0c-a3d1-5ca809294bdf"
TRAVEL = "019fb983-3f3d-7628-af74-c9b2c624f57b"
SALARY = "019fb983-3f44-7954-afad-51289be99bbc"


# --- the Book's month ---------------------------------------------------------


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_month_summary_reads_in_out_and_kept(client: TestClient) -> None:
    account = make_account(client)
    make_txn(client, account, amount=1_000_00, at="2026-07-03T10:00:00+05:30", category_id=FOOD)
    make_txn(client, account, amount=400_00, at="2026-07-03T18:00:00+05:30", category_id=TRAVEL)
    make_txn(
        client,
        account,
        amount=50_000_00,
        type_="income",
        at="2026-07-01T10:00:00+05:30",
        title="Salary",
        category_id=SALARY,
    )
    other = make_account(client, "Cash", kind="cash")
    make_txn(
        client,
        account,
        amount=5_000_00,
        type_="transfer",
        at="2026-07-04T10:00:00+05:30",
        title="To wallet",
        to_account_id=other,
    )

    got = client.get("/v1/summary/month").json()
    assert got["month"] == "2026-07"
    assert (got["start"], got["end"]) == ("2026-07-01", "2026-08-01")
    assert got["in_paise"] == 50_000_00
    assert got["out_paise"] == 1_400_00  # transfers are neither in nor out
    assert got["kept_paise"] == 48_600_00
    assert got["entry_count"] == 4  # but they are still entries
    assert got["total_days"] == 31
    assert got["elapsed_days"] == 15
    assert got["salary_day_of_month"] == 1


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_month_summary_draws_the_heat_grid_and_where_it_went(client: TestClient) -> None:
    account = make_account(client)
    make_txn(client, account, amount=1_000_00, at="2026-07-03T10:00:00+05:30", category_id=FOOD)
    make_txn(client, account, amount=300_00, at="2026-07-03T18:00:00+05:30", category_id=TRAVEL)
    make_txn(client, account, amount=200_00, at="2026-07-09T10:00:00+05:30", category_id=FOOD)

    got = client.get("/v1/summary/month").json()
    days = {d["date"]: d for d in got["day_totals"]}
    assert len(got["day_totals"]) == 31  # every day, blank ones included
    assert days["2026-07-03"]["spent_paise"] == 1_300_00
    assert days["2026-07-03"]["entry_count"] == 2
    assert days["2026-07-04"]["spent_paise"] == 0
    assert got["heaviest_day"] == "2026-07-03"
    assert got["heaviest_day_paise"] == 1_300_00
    # 15 days lived, two of them written on.
    assert got["quiet_days"] == 13
    assert got["categories"] == [
        {"category_id": FOOD, "spent_paise": 1_200_00},
        {"category_id": TRAVEL, "spent_paise": 300_00},
    ]


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_month_summary_names_the_entry_that_carried_the_month(client: TestClient) -> None:
    account = make_account(client)
    make_txn(client, account, amount=100_00, at="2026-07-02T10:00:00+05:30", title="Chai")
    make_txn(client, account, amount=900_00, at="2026-07-06T10:00:00+05:30", title="Flight")

    got = client.get("/v1/summary/month").json()
    assert got["biggest_expense"]["title"] == "Flight"
    assert got["biggest_expense_share"] == 0.9

    # A month with nothing in it makes no claims.
    empty = client.get("/v1/summary/month", params={"month": "2026-05"}).json()
    assert empty["biggest_expense"] is None
    assert empty["biggest_expense_share"] is None
    assert empty["heaviest_day"] is None


@time_machine.travel("2026-08-20T10:00:00+05:30")
def test_month_summary_of_a_finished_month_counts_every_day(client: TestClient) -> None:
    account = make_account(client)
    make_txn(client, account, amount=100_00, at="2026-07-02T10:00:00+05:30")
    got = client.get("/v1/summary/month", params={"month": "2026-07"}).json()
    assert got["elapsed_days"] == 31
    assert got["quiet_days"] == 30


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_month_summary_carries_the_seals(client: TestClient) -> None:
    client.put("/v1/seals/2026-07-12")
    client.put("/v1/seals/2026-06-30")  # another month's seal stays there
    got = client.get("/v1/summary/month").json()
    assert got["sealed_days"] == ["2026-07-12"]


def test_month_summary_rejects_a_malformed_month(client: TestClient) -> None:
    resp = client.get("/v1/summary/month", params={"month": "july"})
    assert resp.status_code == 422
    assert resp.json()["type"] == "urn:budgetbox:problem:invalid"


# --- the calendar's money layer ----------------------------------------------


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_calendar_window_lays_spend_charges_and_plans_over_a_month(client: TestClient) -> None:
    account = make_account(client)
    make_txn(client, account, amount=250_00, at="2026-07-04T10:00:00+05:30")
    make_txn(
        client,
        account,
        amount=1_000_00,
        type_="income",
        at="2026-07-04T18:00:00+05:30",
        title="Freelance",
    )

    client.put(
        f"/v1/recurring/{new_id()}",
        json={
            "title": "Rent",
            "amount_paise": 15_000_00,
            "account_id": account,
            "kind": "bill",
            "day_of_month": 5,
        },
    )
    client.put(
        f"/v1/events/{new_id()}",
        json={"title": "Amma's birthday", "date": "2026-07-20", "repeat": "yearly"},
    )

    got = client.get(
        "/v1/summary/calendar", params={"from_day": "2026-07-01", "to_day": "2026-08-01"}
    ).json()
    assert got["days"] == [{"date": "2026-07-04", "spent_paise": 250_00, "earned_paise": 1_000_00}]
    assert [(c["due"], c["recurring"]["title"], c["is_bill"]) for c in got["charges"]] == [
        ("2026-07-05", "Rent", True)
    ]
    assert got["charge_total_paise"] == 15_000_00
    assert [(o["date"], o["event"]["title"]) for o in got["events"]] == [
        ("2026-07-20", "Amma's birthday")
    ]


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_calendar_window_reaches_backwards_and_forwards(client: TestClient) -> None:
    account = make_account(client)
    client.put(
        f"/v1/recurring/{new_id()}",
        json={
            "title": "Netflix",
            "amount_paise": 499_00,
            "account_id": account,
            "kind": "subscription",
            "day_of_month": 8,
        },
    )
    # The schedule's next due is 2026-08-08, but May and June are still drawn.
    got = client.get(
        "/v1/summary/calendar", params={"from_day": "2026-05-01", "to_day": "2026-10-01"}
    ).json()
    assert [c["due"] for c in got["charges"]] == [
        "2026-05-08",
        "2026-06-08",
        "2026-07-08",
        "2026-08-08",
        "2026-09-08",
    ]


# --- Today's extra facts ------------------------------------------------------


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_today_carries_yesterday_the_streak_and_the_quiet_days(client: TestClient) -> None:
    account = make_account(client)
    make_txn(client, account, amount=200_00, at="2026-07-15T09:00:00+05:30")
    make_txn(client, account, amount=500_00, at="2026-07-14T09:00:00+05:30")
    make_txn(client, account, amount=100_00, at="2026-07-11T09:00:00+05:30")
    for day in ("2026-07-13", "2026-07-14"):
        client.put(f"/v1/seals/{day}")

    got = client.get("/v1/summary/today").json()
    assert got["spent_today_paise"] == 200_00
    assert got["spent_yesterday_paise"] == 500_00
    assert got["seal_streak_days"] == 2  # today isn't sealed yet; grace, not a break
    # The last seven days before today, minus the two that were written on.
    assert got["quiet_days"] == [
        "2026-07-13",
        "2026-07-12",
        "2026-07-10",
        "2026-07-09",
        "2026-07-08",
    ]


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_today_counts_what_the_month_still_owes(client: TestClient) -> None:
    account = make_account(client)
    cat = expense_category(client)
    client.put(
        f"/v1/recurring/{new_id()}",
        json={
            "title": "Broadband",
            "amount_paise": 800_00,
            "account_id": account,
            "category_id": cat,
            "kind": "bill",
            "day_of_month": 22,
        },
    )
    client.put(
        f"/v1/recurring/{new_id()}",
        json={
            "title": "Insurance",
            "amount_paise": 6_000_00,
            "account_id": account,
            "kind": "bill",
            "day_of_month": 3,  # already gone by: lands next month
        },
    )
    assert client.get("/v1/summary/today").json()["committed_paise"] == 800_00
