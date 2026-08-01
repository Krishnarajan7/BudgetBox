"""Book filters + pagination, pinned one-tap repeats, day seals, /summary/today."""

import time_machine
from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id
from tests.integration.helpers import expense_category, make_account, make_txn


def test_filters_by_day_category_type_and_search(client: TestClient) -> None:
    account_id = make_account(client)
    cat = expense_category(client)
    make_txn(client, account_id, at="2026-07-05T10:00:00+05:30", title="Auto to office")
    make_txn(client, account_id, at="2026-07-20T10:00:00+05:30", title="Groceries", category_id=cat)
    make_txn(client, account_id, at="2026-08-02T10:00:00+05:30", title="August chai")

    july = client.get("/v1/txns", params={"from_day": "2026-07-01", "to_day": "2026-08-01"}).json()
    assert [t["title"] for t in july["items"]] == ["Groceries", "Auto to office"]

    by_cat = client.get("/v1/txns", params={"category_id": cat}).json()
    assert [t["title"] for t in by_cat["items"]] == ["Groceries"]

    search = client.get("/v1/txns", params={"q": "auto"}).json()
    assert [t["title"] for t in search["items"]] == ["Auto to office"]


def test_ist_day_boundary_in_book(client: TestClient) -> None:
    account_id = make_account(client)
    # 2026-07-31T23:30 IST == 18:00 UTC: belongs to July 31, not August 1.
    make_txn(client, account_id, at="2026-07-31T18:00:00+00:00", title="Late chai")
    july = client.get("/v1/txns", params={"from_day": "2026-07-31", "to_day": "2026-08-01"}).json()
    assert [t["title"] for t in july["items"]] == ["Late chai"]


def test_cursor_pagination_is_stable(client: TestClient) -> None:
    account_id = make_account(client)
    for hour in range(9, 19):
        make_txn(client, account_id, at=f"2026-07-10T{hour:02d}:00:00+05:30", title=f"txn-{hour}")
    page1 = client.get("/v1/txns", params={"limit": 4}).json()
    assert len(page1["items"]) == 4
    # An insert between pages must not shift the window.
    make_txn(client, account_id, at="2026-07-10T20:00:00+05:30", title="newest")
    page2 = client.get("/v1/txns", params={"limit": 4, "cursor": page1["next_cursor"]}).json()
    page3 = client.get("/v1/txns", params={"limit": 4, "cursor": page2["next_cursor"]}).json()
    titles = [t["title"] for t in page1["items"] + page2["items"] + page3["items"]]
    assert titles == [f"txn-{h}" for h in range(18, 8, -1)]
    assert page3["next_cursor"] is None


def test_malformed_cursor_is_422(client: TestClient) -> None:
    resp = client.get("/v1/txns", params={"cursor": "garbage"})
    assert resp.status_code == 422
    assert resp.json()["type"] == "urn:budgetbox:problem:invalid"


def test_title_suggestions_carry_memory(client: TestClient) -> None:
    account_id = make_account(client)
    cat = expense_category(client)
    make_txn(
        client, account_id, at="2026-07-05T10:00:00+05:30", title="Auto to office", category_id=cat
    )
    make_txn(
        client, account_id, at="2026-07-06T10:00:00+05:30", title="Auto to office", category_id=cat
    )
    got = client.get("/v1/txns/suggest", params={"q": "au"}).json()
    assert got == [{"title": "Auto to office", "category_id": cat, "account_id": account_id}]


def test_pinned_stamp_creates_txn(client: TestClient) -> None:
    account_id = make_account(client)
    cat = expense_category(client)
    pinned_id = new_id()
    resp = client.put(
        f"/v1/pinned/{pinned_id}",
        json={
            "title": "Morning chai",
            "amount_paise": 20_00,
            "category_id": cat,
            "account_id": account_id,
        },
    )
    assert resp.status_code == 200
    stamped = client.post(f"/v1/pinned/{pinned_id}/stamp", json={"at": "2026-07-10T08:00:00+05:30"})
    assert stamped.status_code == 201
    txn = stamped.json()
    assert (txn["title"], txn["amount_paise"], txn["type"]) == ("Morning chai", 20_00, "expense")


def test_seal_day_is_idempotent(client: TestClient) -> None:
    first = client.put("/v1/seals/2026-07-10")
    again = client.put("/v1/seals/2026-07-10")
    assert first.status_code == again.status_code == 200
    assert first.json()["sealed_at"] == again.json()["sealed_at"]
    listed = client.get(
        "/v1/seals", params={"from_day": "2026-07-01", "to_day": "2026-08-01"}
    ).json()
    assert [s["date"] for s in listed] == ["2026-07-10"]


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_today_summary(client: TestClient) -> None:
    account_id = make_account(client)
    client.put("/v1/settings/salary_day", json={"value": "1"})
    make_txn(client, account_id, amount=50_00, at="2026-07-15T08:00:00+05:30", title="Chai")
    make_txn(client, account_id, amount=200_00, at="2026-07-02T08:00:00+05:30", title="Earlier")
    make_txn(
        client,
        account_id,
        amount=75_00,
        type_="income",
        at="2026-07-15T09:00:00+05:30",
        title="Ignored income",
    )

    got = client.get("/v1/summary/today").json()
    assert got["day"] == "2026-07-15"
    assert got["sealed"] is False
    assert got["spent_today_paise"] == 50_00
    assert got["window_start"] == "2026-07-01"
    assert got["window_end"] == "2026-08-01"
    assert got["window_spent_paise"] == 250_00
    assert got["window_elapsed_days"] == 15
    assert got["window_total_days"] == 31
    assert [t["title"] for t in got["today_txns"]] == ["Ignored income", "Chai"]

    client.put("/v1/seals/2026-07-15")
    assert client.get("/v1/summary/today").json()["sealed"] is True
