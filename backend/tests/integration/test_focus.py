"""The focus ledger: idempotent session writes, IST month windows, and the
completed-work-only monthly tally."""

from typing import Any

import time_machine
from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id


def tally(stats: dict[str, Any]) -> dict[str, Any]:
    """Just the month's headline figures; the grids and the all-time record have
    their own tests."""
    return {k: stats[k] for k in ("total_minutes", "sessions", "best_day", "best_day_minutes")}


def make_session(
    client: TestClient,
    *,
    started_at: str = "2026-07-15T10:00:00+05:30",
    minutes: int = 25,
    kind: str = "work",
    completed: bool = True,
    label: str | None = None,
    session_id: str | None = None,
) -> str:
    session_id = session_id or new_id()
    body: dict[str, Any] = {
        "started_at": started_at,
        "minutes": minutes,
        "kind": kind,
        "completed": completed,
    }
    if label is not None:
        body["label"] = label
    resp = client.put(f"/v1/focus/sessions/{session_id}", json=body)
    assert resp.status_code == 200, resp.text
    return session_id


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_upsert_is_idempotent_and_patch_is_partial(client: TestClient) -> None:
    session_id = make_session(client, minutes=12, completed=False, label="Deep work")
    body = {
        "started_at": "2026-07-15T10:00:00+05:30",
        "minutes": 25,
        "kind": "work",
        "completed": True,
        "label": "Deep work",
    }
    # Same id, new body: one row, overwritten — not a second line.
    again = client.put(f"/v1/focus/sessions/{session_id}", json=body)
    assert again.status_code == 200, again.text
    assert again.json()["minutes"] == 25
    rows = client.get("/v1/focus/sessions").json()
    assert len(rows) == 1
    assert rows[0]["id"] == session_id
    assert rows[0]["label"] == "Deep work"

    patched = client.patch(f"/v1/focus/sessions/{session_id}", json={"minutes": 40})
    assert patched.status_code == 200, patched.text
    assert patched.json()["minutes"] == 40
    assert patched.json()["completed"] is True  # untouched fields survive
    assert patched.json()["label"] == "Deep work"


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_patch_missing_session_is_a_not_found_problem(client: TestClient) -> None:
    resp = client.patch(f"/v1/focus/sessions/{new_id()}", json={"completed": True})
    assert resp.status_code == 404
    assert resp.json()["type"] == "urn:budgetbox:problem:not-found"


@time_machine.travel("2026-08-05T10:00:00+05:30")
def test_month_window_follows_ist_not_utc(client: TestClient) -> None:
    # 18:30Z on Jul 31 is 00:00 IST on Aug 1: an August sitting.
    august = make_session(client, started_at="2026-07-31T18:30:00+00:00", minutes=30)
    # 18:29Z is 23:59 IST on Jul 31: still July.
    july = make_session(client, started_at="2026-07-31T18:29:00+00:00", minutes=45)
    later_august = make_session(client, started_at="2026-08-04T09:00:00+05:30", minutes=15)

    default_month = client.get("/v1/focus/sessions").json()  # travels to August
    assert [r["id"] for r in default_month] == [later_august, august]  # started_at desc
    assert [r["id"] for r in client.get("/v1/focus/sessions?month=2026-07").json()] == [july]
    assert client.get("/v1/focus/stats?month=2026-07").json()["total_minutes"] == 45
    assert client.get("/v1/focus/stats").json()["total_minutes"] == 45  # 30 + 15


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_stats_count_only_completed_work_sessions(client: TestClient) -> None:
    make_session(client, started_at="2026-07-02T09:00:00+05:30", minutes=50)
    make_session(client, started_at="2026-07-03T09:00:00+05:30", minutes=10, kind="rest")
    make_session(client, started_at="2026-07-04T09:00:00+05:30", minutes=90, completed=False)
    make_session(client, started_at="2026-06-30T09:00:00+05:30", minutes=200)  # other month

    stats = client.get("/v1/focus/stats").json()
    assert tally(stats) == {
        "total_minutes": 50,
        "sessions": 1,
        "best_day": "2026-07-02",
        "best_day_minutes": 50,
    }
    # The ledger still lists every line, rest and abandoned included.
    assert len(client.get("/v1/focus/sessions").json()) == 3


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_best_day_sums_the_day_and_breaks_ties_to_the_earlier_one(client: TestClient) -> None:
    make_session(client, started_at="2026-07-05T09:00:00+05:30", minutes=25)
    make_session(client, started_at="2026-07-05T14:00:00+05:30", minutes=35)  # 60 that day
    make_session(client, started_at="2026-07-09T09:00:00+05:30", minutes=60)  # tie, later day
    make_session(client, started_at="2026-07-11T09:00:00+05:30", minutes=30)

    assert tally(client.get("/v1/focus/stats").json()) == {
        "total_minutes": 150,
        "sessions": 4,
        "best_day": "2026-07-05",
        "best_day_minutes": 60,
    }


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_empty_month_and_input_guards(client: TestClient) -> None:
    assert tally(client.get("/v1/focus/stats?month=2026-01").json()) == {
        "total_minutes": 0,
        "sessions": 0,
        "best_day": None,
        "best_day_minutes": 0,
    }
    naive = client.put(
        f"/v1/focus/sessions/{new_id()}",
        json={"started_at": "2026-07-15T10:00:00", "minutes": 25, "kind": "work"},
    )
    assert naive.status_code == 422
    too_long = client.put(
        f"/v1/focus/sessions/{new_id()}",
        json={"started_at": "2026-07-15T10:00:00+05:30", "minutes": 601, "kind": "work"},
    )
    assert too_long.status_code == 422


@time_machine.travel("2026-07-15T10:00:00+05:30")  # a Wednesday
def test_stats_carry_the_day_grid_and_the_week_bars(client: TestClient) -> None:
    make_session(client, started_at="2026-07-13T09:00:00+05:30", minutes=40)  # Monday
    make_session(client, started_at="2026-07-15T09:00:00+05:30", minutes=25)  # Wednesday
    make_session(client, started_at="2026-07-15T11:00:00+05:30", minutes=20, completed=False)
    make_session(client, started_at="2026-07-06T09:00:00+05:30", minutes=90)  # last week

    stats = client.get("/v1/focus/stats").json()
    assert stats["day_minutes"] == [
        {"date": "2026-07-06", "minutes": 90},
        {"date": "2026-07-13", "minutes": 40},
        {"date": "2026-07-15", "minutes": 25},
    ]
    assert stats["week_minutes"] == [40, 0, 25, 0, 0, 0, 0]  # Mon…Sun
    # Today's tally counts the sitting he walked away from: the minutes were sat.
    assert stats["today_work_minutes"] == 45


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_record_is_all_time_and_counts_only_finished_work(client: TestClient) -> None:
    make_session(client, started_at="2025-02-10T09:00:00+05:30", minutes=90)
    make_session(client, started_at="2026-07-13T09:00:00+05:30", minutes=50)
    make_session(client, started_at="2026-07-13T14:00:00+05:30", minutes=55)
    make_session(client, started_at="2026-07-14T09:00:00+05:30", minutes=30)
    make_session(client, started_at="2026-07-14T14:00:00+05:30", minutes=200, completed=False)
    make_session(client, started_at="2026-07-14T18:00:00+05:30", minutes=200, kind="rest")

    record = client.get("/v1/focus/stats").json()["record"]
    assert record["total_minutes"] == 225
    assert record["sessions"] == 4
    assert record["longest_minutes"] == 90
    assert record["longest_at"].startswith("2025-02-10")
    assert record["best_day"] == "2026-07-13"
    assert record["best_day_minutes"] == 105
    # The 13th and 14th run up to yesterday; today is grace, not a break.
    assert record["streak_days"] == 2
    # A past month's stats still report the same all-time record.
    assert client.get("/v1/focus/stats?month=2026-01").json()["record"] == record
