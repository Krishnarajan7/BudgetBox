"""Reopening a sealed day, the pinned manager's evidence, the add sheet's memory,
and the activity log's readable lines."""

import time_machine
from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id
from tests.integration.helpers import make_account, make_txn

FOOD = "019fb983-3f3c-7c0c-a3d1-5ca809294bdf"
TRAVEL = "019fb983-3f3d-7628-af74-c9b2c624f57b"


# --- reopening a page ---------------------------------------------------------


def test_a_sealed_day_can_be_reopened(client: TestClient) -> None:
    assert client.put("/v1/seals/2026-07-12").status_code == 200
    assert client.delete("/v1/seals/2026-07-12").status_code == 204
    seals = client.get(
        "/v1/seals", params={"from_day": "2026-07-01", "to_day": "2026-08-01"}
    ).json()
    assert seals == []
    # Blind retries are safe both ways: the phone may be replaying a queue.
    assert client.delete("/v1/seals/2026-07-12").status_code == 204
    assert client.put("/v1/seals/2026-07-12").status_code == 200


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_reopening_a_day_breaks_the_streak(client: TestClient) -> None:
    for day in ("2026-07-12", "2026-07-13", "2026-07-14"):
        client.put(f"/v1/seals/{day}")
    assert client.get("/v1/summary/today").json()["seal_streak_days"] == 3
    client.delete("/v1/seals/2026-07-13")
    assert client.get("/v1/summary/today").json()["seal_streak_days"] == 1


# --- the pinned manager -------------------------------------------------------


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_pinned_board_counts_how_often_a_pin_was_stamped(client: TestClient) -> None:
    account = make_account(client)
    pinned_id = new_id()
    client.put(
        f"/v1/pinned/{pinned_id}",
        json={
            "title": "Morning chai",
            "amount_paise": 20_00,
            "category_id": FOOD,
            "account_id": account,
        },
    )
    for day in ("2026-07-10", "2026-07-11"):
        client.post(f"/v1/pinned/{pinned_id}/stamp", json={"at": f"{day}T08:00:00+05:30"})
    # A hand-typed entry with the same words and figure is the same stroke.
    make_txn(
        client,
        account,
        amount=20_00,
        at="2026-07-12T08:00:00+05:30",
        title="  morning CHAI ",
        category_id=FOOD,
    )
    # A different figure is not.
    make_txn(client, account, amount=30_00, at="2026-07-13T08:00:00+05:30", title="Morning chai")

    board = client.get("/v1/pinned/board").json()
    assert len(board["items"]) == 1
    assert board["items"][0]["pinned"]["id"] == pinned_id
    assert board["items"][0]["use_count"] == 3
    assert board["items"][0]["last_used_at"].startswith("2026-07-12")


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_pinned_board_suggests_repeats_that_earned_a_pin(client: TestClient) -> None:
    account = make_account(client)
    for day in (2, 5, 9):
        make_txn(
            client,
            account,
            amount=60_00,
            at=f"2026-07-{day:02d}T09:00:00+05:30",
            title="Auto to office",
            category_id=TRAVEL,
        )
    # Twice isn't a habit yet.
    for day in (3, 6):
        make_txn(
            client,
            account,
            amount=15_00,
            at=f"2026-07-{day:02d}T09:00:00+05:30",
            title="Bus",
            category_id=TRAVEL,
        )
    # An old habit is outside the ninety-day window.
    for day in (1, 2, 3):
        make_txn(
            client,
            account,
            amount=99_00,
            at=f"2025-01-{day:02d}T09:00:00+05:30",
            title="Old lunch",
            category_id=FOOD,
        )

    board = client.get("/v1/pinned/board").json()
    assert board["suggestions"] == [
        {
            "title": "Auto to office",
            "amount_paise": 60_00,
            "category_id": TRAVEL,
            "account_id": account,
            "count": 3,
        }
    ]

    # Pin it and it stops being a suggestion.
    client.put(
        f"/v1/pinned/{new_id()}",
        json={
            "title": "auto to office",
            "amount_paise": 60_00,
            "category_id": TRAVEL,
            "account_id": account,
        },
    )
    assert client.get("/v1/pinned/board").json()["suggestions"] == []


# --- the add sheet's memory ---------------------------------------------------


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_recent_amounts_rank_by_habit_then_recency(client: TestClient) -> None:
    account = make_account(client)
    for day, amount in ((2, 20_00), (3, 20_00), (4, 45_00), (5, 45_00), (6, 30_00)):
        make_txn(
            client,
            account,
            amount=amount,
            at=f"2026-07-{day:02d}T09:00:00+05:30",
            category_id=FOOD,
        )
    got = client.get("/v1/txns/recent-amounts", params={"category_id": FOOD}).json()
    # 45 and 20 both appear twice; 45 is the more recent of the two.
    assert got == [
        {"amount_paise": 45_00, "count": 2},
        {"amount_paise": 20_00, "count": 2},
        {"amount_paise": 30_00, "count": 1},
    ]
    assert client.get("/v1/txns/recent-amounts", params={"category_id": TRAVEL}).json() == []


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_top_categories_follow_the_recent_window(client: TestClient) -> None:
    account = make_account(client)
    for day in (2, 3, 4):
        make_txn(client, account, at=f"2026-07-{day:02d}T09:00:00+05:30", category_id=TRAVEL)
    make_txn(client, account, at="2026-07-05T09:00:00+05:30", category_id=FOOD)
    # Last year's habit doesn't crowd the chips.
    for day in (1, 2, 3, 4, 5):
        make_txn(client, account, at=f"2025-01-{day:02d}T09:00:00+05:30", category_id=FOOD)

    got = client.get("/v1/categories/top").json()
    assert got == [{"category_id": TRAVEL, "count": 3}, {"category_id": FOOD, "count": 1}]
    assert client.get("/v1/categories/top", params={"limit": 1}).json() == [
        {"category_id": TRAVEL, "count": 3}
    ]


def test_title_suggestions_match_anywhere_in_the_name(client: TestClient) -> None:
    account = make_account(client)
    make_txn(client, account, at="2026-07-05T10:00:00+05:30", title="Hotel Saravana Bhavan")
    # Typing the middle of a name has to find it — the app never anchors at the start.
    got = client.get("/v1/txns/suggest", params={"q": "sarav"}).json()
    assert [s["title"] for s in got] == ["Hotel Saravana Bhavan"]


# --- the activity log ---------------------------------------------------------


def test_activity_lines_read_as_entries_not_ids(client: TestClient) -> None:
    account = make_account(client)
    txn_id = make_txn(client, account, amount=250_00, title="Groceries")
    client.delete(f"/v1/txns/{txn_id}")

    log = client.get("/v1/activities").json()
    assert [(a["action"], a["title"], a["amount_paise"], a["txn_type"]) for a in log] == [
        ("deleted", "Groceries", 250_00, "expense"),
        ("created", "Groceries", 250_00, "expense"),
    ]
    # Only the delete can be replayed: the create's txn is already gone.
    assert [a["undoable"] for a in log] == [True, False]


def test_activities_narrow_to_one_entrys_rewrites(client: TestClient) -> None:
    account = make_account(client)
    first = make_txn(client, account, title="Chai")
    second = make_txn(client, account, title="Auto")
    client.patch(f"/v1/txns/{first}", json={"amount_paise": 300_00})
    client.patch(f"/v1/txns/{first}", json={"amount_paise": 400_00})

    mine = client.get("/v1/activities", params={"txn_id": first}).json()
    assert [a["action"] for a in mine] == ["edited", "edited", "created"]
    assert all(a["txn_id"] == first for a in mine)
    assert len(client.get("/v1/activities", params={"txn_id": second}).json()) == 1
