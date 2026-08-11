"""Recurring lifecycle: scheduling, upcoming/committed heroes, and the
materialization job's idempotent catch-up."""

import time_machine
from fastapi import FastAPI
from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id
from budgetbox.jobs.daily import run_daily
from tests.integration.helpers import balance, make_account, make_txn


def make_recurring(
    client: TestClient,
    account_id: str,
    *,
    title: str = "Rent",
    amount: int = 15_000_00,
    kind: str = "bill",
    day_of_month: int = 1,
    every_months: int = 1,
    next_due: str | None = None,
) -> str:
    recurring_id = new_id()
    body: dict[str, object] = {
        "title": title,
        "amount_paise": amount,
        "account_id": account_id,
        "kind": kind,
        "day_of_month": day_of_month,
        "every_months": every_months,
    }
    if next_due is not None:
        body["next_due"] = next_due
    resp = client.put(f"/v1/recurring/{recurring_id}", json=body)
    assert resp.status_code == 200, resp.text
    return recurring_id


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_first_due_defaults_to_next_matching_day(client: TestClient) -> None:
    account_id = make_account(client)
    make_recurring(client, account_id, day_of_month=20)  # later this month
    make_recurring(
        client, account_id, title="Netflix", kind="subscription", amount=649_00, day_of_month=10
    )  # already passed -> next month
    rows = {r["title"]: r for r in client.get("/v1/recurring").json()}
    assert rows["Rent"]["next_due"] == "2026-07-20"
    assert rows["Netflix"]["next_due"] == "2026-08-10"


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_upcoming_and_committed_hero(client: TestClient) -> None:
    account_id = make_account(client)
    make_recurring(client, account_id, day_of_month=20)  # 15000/mo
    make_recurring(
        client,
        account_id,
        title="iCloud",
        kind="subscription",
        amount=1200_00,
        every_months=12,
        day_of_month=5,
    )  # yearly
    got = client.get("/v1/recurring/upcoming", params={"until": "2026-08-31"}).json()
    assert [(i["recurring"]["title"], i["due"]) for i in got["items"]] == [
        ("Rent", "2026-07-20"),
        ("iCloud", "2026-08-05"),  # yearly: next occurrence lands in the horizon
        ("Rent", "2026-08-20"),
    ]
    # 15000 + round(1200/12) = 15000 + 100 per month.
    assert got["committed_monthly_paise"] == 15_000_00 + 100_00


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_materialization_posts_catch_up_and_is_idempotent(app: FastAPI, client: TestClient) -> None:
    account_id = make_account(client)
    from tests.integration.helpers import anchor

    anchor(client, account_id, 100_000_00, at="2026-03-01T09:00:00+05:30")
    # Server "was down" since April: next_due still 2026-04-05.
    make_recurring(
        client,
        account_id,
        title="Netflix",
        kind="subscription",
        amount=649_00,
        day_of_month=5,
        next_due="2026-04-05",
    )

    assert run_daily(app.state.session_factory) is True
    txns = client.get("/v1/txns").json()["items"]
    assert [t["at"][:10] for t in txns] == ["2026-07-04", "2026-06-04", "2026-05-04", "2026-04-04"]
    # (IST days 05th; stored instants are UTC, hence the prior calendar date at :30.)
    assert all(t["title"] == "Netflix" and t["recurring_id"] for t in txns)
    assert balance(client, account_id) == 100_000_00 - 4 * 649_00

    # Rerun: nothing new, next_due advanced past today.
    assert run_daily(app.state.session_factory) is True
    assert len(client.get("/v1/txns").json()["items"]) == 4
    (row,) = client.get("/v1/recurring").json()
    assert row["next_due"] == "2026-08-05"
    assert row["last_materialized_due"] == "2026-07-05"

    health = client.get("/healthz").json()
    assert health["daily_job_ok"] is True


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_deactivated_recurring_is_not_materialized(app: FastAPI, client: TestClient) -> None:
    account_id = make_account(client)
    recurring_id = make_recurring(client, account_id, next_due="2026-07-01")
    client.delete(f"/v1/recurring/{recurring_id}")
    run_daily(app.state.session_factory)
    assert client.get("/v1/txns").json()["items"] == []


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_manual_payment_is_idempotent_and_advances_once(app: FastAPI, client: TestClient) -> None:
    account_id = make_account(client)
    recurring_id = make_recurring(client, account_id, day_of_month=20)
    txn_id = new_id()
    body = {
        "amount_paise": 14_500_00,
        "at": "2026-07-18T09:30:00+05:30",
        "note": "Paid early after discount",
    }

    first = client.put(f"/v1/recurring/{recurring_id}/payments/{txn_id}", json=body)
    assert first.status_code == 200, first.text
    assert first.json()["id"] == txn_id
    assert first.json()["recurring_id"] == recurring_id
    assert first.json()["amount_paise"] == 14_500_00

    recurring = client.get("/v1/recurring").json()[0]
    assert recurring["last_materialized_due"] == "2026-07-20"
    assert recurring["next_due"] == "2026-08-20"

    retry = client.put(f"/v1/recurring/{recurring_id}/payments/{txn_id}", json=body)
    assert retry.status_code == 200
    assert len(client.get("/v1/txns").json()["items"]) == 1
    assert client.get("/v1/recurring").json()[0]["next_due"] == "2026-08-20"

    corrected = {**body, "amount_paise": 14_000_00}
    assert (
        client.put(f"/v1/recurring/{recurring_id}/payments/{txn_id}", json=corrected).json()[
            "amount_paise"
        ]
        == 14_000_00
    )
    assert client.get(f"/v1/txns/{txn_id}").json()["amount_paise"] == 14_000_00
    assert client.get("/v1/recurring").json()[0]["next_due"] == "2026-08-20"

    # The daily catch-up cannot duplicate the manually paid July occurrence.
    assert run_daily(app.state.session_factory) is True
    assert len(client.get("/v1/txns").json()["items"]) == 1


def test_manual_payment_rejects_inactive_recurring(client: TestClient) -> None:
    account_id = make_account(client)
    recurring_id = make_recurring(client, account_id)
    client.delete(f"/v1/recurring/{recurring_id}")
    resp = client.put(f"/v1/recurring/{recurring_id}/payments/{new_id()}", json={})
    assert resp.status_code == 422


def test_manual_payment_rejects_transaction_id_collision(client: TestClient) -> None:
    account_id = make_account(client)
    recurring_id = make_recurring(client, account_id)
    next_due = client.get("/v1/recurring").json()[0]["next_due"]
    txn_id = make_txn(client, account_id)
    resp = client.put(
        f"/v1/recurring/{recurring_id}/payments/{txn_id}",
        json={"at": "2026-07-15T10:00:00+05:30"},
    )
    assert resp.status_code == 409
    assert client.get("/v1/recurring").json()[0]["next_due"] == next_due


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_today_summary_lists_upcoming_week(client: TestClient) -> None:
    account_id = make_account(client)
    make_recurring(client, account_id, day_of_month=20)  # within 7 days
    make_recurring(
        client, account_id, title="Far away", amount=100_00, kind="bill", day_of_month=28
    )  # beyond 7 days
    got = client.get("/v1/summary/today").json()
    assert [(i["recurring"]["title"], i["due"]) for i in got["upcoming"]] == [
        ("Rent", "2026-07-20")
    ]
