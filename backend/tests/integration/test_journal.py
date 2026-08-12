"""Journal: one entry per IST day, keyed by the day itself, so PUT is a natural
upsert — plus the month view's mood grid, streak, and mood-against-money whisper."""

import time_machine
from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id
from tests.integration.helpers import make_account, make_txn


def test_put_creates_then_updates_same_day(client: TestClient) -> None:
    resp = client.put("/v1/journal/2026-07-15", json={"body": "long day", "mood": 3})
    assert resp.status_code == 200, resp.text
    created = resp.json()
    assert created["date"] == "2026-07-15"
    assert created["body"] == "long day"
    assert created["mood"] == 3

    resp = client.put("/v1/journal/2026-07-15", json={"body": "better by evening", "mood": 5})
    assert resp.status_code == 200, resp.text
    updated = resp.json()
    assert updated["body"] == "better by evening"
    assert updated["mood"] == 5
    assert updated["created_at"] == created["created_at"]  # same row, not a second one
    assert updated["updated_at"] > created["updated_at"]

    assert (
        len(
            client.get(
                "/v1/journal", params={"from_day": "2026-07-01", "to_day": "2026-08-01"}
            ).json()
        )
        == 1
    )


def test_put_defaults_body_and_allows_null_mood(client: TestClient) -> None:
    entry = client.put("/v1/journal/2026-07-15", json={}).json()
    assert entry["body"] == ""
    assert entry["mood"] is None


def test_mood_out_of_range_rejected(client: TestClient) -> None:
    assert client.put("/v1/journal/2026-07-15", json={"mood": 0}).status_code == 422
    assert client.put("/v1/journal/2026-07-15", json={"mood": 6}).status_code == 422
    assert client.get("/v1/journal/2026-07-15").status_code == 404  # nothing was written


def test_get_missing_day_is_problem_json(client: TestClient) -> None:
    resp = client.get("/v1/journal/2026-07-15")
    assert resp.status_code == 404
    assert resp.json()["type"] == "urn:budgetbox:problem:not-found"


def test_range_is_newest_first_and_to_day_exclusive(client: TestClient) -> None:
    for day in ("2026-07-09", "2026-07-10", "2026-07-12", "2026-07-15"):
        assert client.put(f"/v1/journal/{day}", json={"body": day}).status_code == 200

    rows = client.get(
        "/v1/journal", params={"from_day": "2026-07-10", "to_day": "2026-07-15"}
    ).json()
    assert [r["date"] for r in rows] == ["2026-07-12", "2026-07-10"]


def test_range_requires_both_bounds(client: TestClient) -> None:
    assert client.get("/v1/journal", params={"from_day": "2026-07-10"}).status_code == 422
    assert client.get("/v1/journal", params={"to_day": "2026-07-15"}).status_code == 422


def test_delete_then_404(client: TestClient) -> None:
    client.put("/v1/journal/2026-07-15", json={"body": "gone soon"})
    assert client.delete("/v1/journal/2026-07-15").status_code == 204
    assert client.get("/v1/journal/2026-07-15").status_code == 404
    assert client.delete("/v1/journal/2026-07-15").status_code == 404


def test_entry_shows_up_in_changes(client: TestClient) -> None:
    client.put("/v1/journal/2026-07-15", json={"body": "hello", "mood": 4})
    changed = client.get("/v1/changes").json()["items"]
    assert [item["resource_id"] for item in changed if item["resource"] == "journal_entries"] == [
        "2026-07-15"
    ]


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_month_view_draws_the_mood_grid_and_the_streak(client: TestClient) -> None:
    for day, mood in (("2026-07-12", 2), ("2026-07-13", 4), ("2026-07-14", 5)):
        client.put(f"/v1/journal/{day}", json={"body": "wrote", "mood": mood})
    client.put("/v1/journal/2026-07-02", json={"body": "", "mood": None})  # a blank page

    got = client.get("/v1/journal/month").json()
    assert got["month"] == "2026-07"
    assert [e["date"] for e in got["entries"]][:3] == [
        "2026-07-14",
        "2026-07-13",
        "2026-07-12",
    ]
    assert len(got["mood_dots"]) == 31
    assert got["mood_dots"][11:14] == [2, 4, 5]
    assert got["mood_dots"][1] is None
    assert got["pages_written"] == 3  # the blank page isn't a day he showed up for
    assert got["streak_days"] == 3  # today isn't written yet; grace, not a break


@time_machine.travel("2026-07-20T10:00:00+05:30")
def test_month_view_weighs_mood_against_money(client: TestClient) -> None:
    account_id = make_account(client)
    rough = {"2026-07-02": 2, "2026-07-03": 1, "2026-07-04": 2}
    bright = {"2026-07-06": 5, "2026-07-07": 4, "2026-07-08": 4}
    for day, mood in (rough | bright).items():
        client.put(f"/v1/journal/{day}", json={"body": "a day", "mood": mood})
        amount = 600_00 if day in rough else 100_00
        make_txn(client, account_id, amount=amount, at=f"{day}T12:00:00+05:30")

    verdict = client.get("/v1/journal/month").json()["mood_money"]
    assert verdict["verdict"] == "rough_costs_more"
    assert (verdict["rough_days"], verdict["bright_days"]) == (3, 3)
    assert (verdict["rough_avg_paise"], verdict["bright_avg_paise"]) == (600_00, 100_00)


@time_machine.travel("2026-07-20T10:00:00+05:30")
def test_month_view_stays_quiet_without_enough_evidence(client: TestClient) -> None:
    for day, mood in (("2026-07-02", 1), ("2026-07-06", 5)):
        client.put(f"/v1/journal/{day}", json={"body": "a day", "mood": mood})
    assert client.get("/v1/journal/month").json()["mood_money"] is None


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_day_facts_answer_even_for_a_blank_page(client: TestClient) -> None:
    account_id = make_account(client)
    make_txn(client, account_id, amount=250_00, at="2026-07-15T09:00:00+05:30")
    make_txn(client, account_id, amount=150_00, at="2026-07-15T20:00:00+05:30")
    make_txn(client, account_id, amount=999_00, at="2026-07-14T09:00:00+05:30")
    client.put(
        f"/v1/focus/sessions/{new_id()}",
        json={
            "started_at": "2026-07-15T11:00:00+05:30",
            "minutes": 45,
            "kind": "work",
            "completed": True,
        },
    )
    client.put(
        f"/v1/focus/sessions/{new_id()}",
        json={
            "started_at": "2026-07-15T14:00:00+05:30",
            "minutes": 30,
            "kind": "work",
            "completed": False,  # walked away: no verdict, no minutes counted
        },
    )
    client.put(f"/v1/notes/{new_id()}", json={"title": "Idea", "body": "..."})

    facts = client.get("/v1/journal/2026-07-15/facts").json()
    assert facts == {
        "date": "2026-07-15",
        "spent_paise": 400_00,
        "txn_count": 2,
        "focus_minutes": 45,
        "notes_count": 1,
    }
    # Nothing was written on the 13th, and the day still answers.
    assert client.get("/v1/journal/2026-07-13/facts").json()["spent_paise"] == 0
