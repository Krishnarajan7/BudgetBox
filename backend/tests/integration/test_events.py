"""Calendar events: idempotent upsert/patch, window expansion of yearly repeats,
all-day ordering, and archived events dropping out of the calendar."""

from typing import Any

from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id


def make_event(
    client: TestClient,
    *,
    title: str = "Dentist",
    date: str = "2026-08-14",
    time_minutes: int | None = None,
    repeat: str = "none",
    note: str | None = None,
    event_id: str | None = None,
) -> str:
    event_id = event_id or new_id()
    body: dict[str, Any] = {"title": title, "date": date, "repeat": repeat}
    if time_minutes is not None:
        body["time_minutes"] = time_minutes
    if note is not None:
        body["note"] = note
    resp = client.put(f"/v1/events/{event_id}", json=body)
    assert resp.status_code == 200, resp.text
    return event_id


def occurrences(client: TestClient, from_day: str, to_day: str) -> list[dict[str, Any]]:
    resp = client.get("/v1/events", params={"from_day": from_day, "to_day": to_day})
    assert resp.status_code == 200, resp.text
    return resp.json()


def test_upsert_is_idempotent_and_patch_is_partial(client: TestClient) -> None:
    event_id = make_event(client, time_minutes=10 * 60 + 30, note="upper left")
    # Same id again: one row, updated in place.
    make_event(client, event_id=event_id, title="Dentist (moved)", date="2026-08-20")
    rows = client.get("/v1/events/all").json()
    assert len(rows) == 1
    assert rows[0]["title"] == "Dentist (moved)"
    assert rows[0]["date"] == "2026-08-20"
    assert rows[0]["time_minutes"] is None  # omitted on the PUT -> all-day
    assert rows[0]["note"] is None

    got = client.patch(f"/v1/events/{event_id}", json={"time_minutes": 9 * 60})
    assert got.status_code == 200, got.text
    assert got.json()["time_minutes"] == 9 * 60
    assert got.json()["title"] == "Dentist (moved)"  # untouched fields survive

    missing = client.patch(f"/v1/events/{new_id()}", json={"title": "Nope"})
    assert missing.status_code == 404


def test_yearly_event_appears_in_consecutive_year_windows(client: TestClient) -> None:
    make_event(client, title="Amma's birthday", date="2026-09-03", repeat="yearly")
    make_event(client, title="One-off", date="2026-09-10")

    this_year = occurrences(client, "2026-09-01", "2026-10-01")
    assert [(o["event"]["title"], o["date"]) for o in this_year] == [
        ("Amma's birthday", "2026-09-03"),
        ("One-off", "2026-09-10"),
    ]

    next_year = occurrences(client, "2027-09-01", "2027-10-01")
    assert [(o["event"]["title"], o["date"]) for o in next_year] == [
        ("Amma's birthday", "2027-09-03")
    ]

    # A multi-year window expands one occurrence per year.
    span = occurrences(client, "2026-01-01", "2029-01-01")
    assert [o["date"] for o in span if o["event"]["title"] == "Amma's birthday"] == [
        "2026-09-03",
        "2027-09-03",
        "2028-09-03",
    ]


def test_all_day_sorts_before_timed_on_the_same_date(client: TestClient) -> None:
    make_event(client, title="Standup", date="2026-08-14", time_minutes=9 * 60 + 30)
    make_event(client, title="Deadline", date="2026-08-14")  # all-day
    make_event(client, title="Gym", date="2026-08-14", time_minutes=7 * 60)
    make_event(client, title="Anniversary", date="2026-08-14")  # all-day

    got = occurrences(client, "2026-08-14", "2026-08-15")
    assert [(o["event"]["title"], o["time_minutes"]) for o in got] == [
        ("Anniversary", None),
        ("Deadline", None),  # all-day first, then by title
        ("Gym", 7 * 60),
        ("Standup", 9 * 60 + 30),
    ]


def test_archived_events_drop_out_of_expansion_but_stay_listable(client: TestClient) -> None:
    event_id = make_event(client, title="Old ritual", date="2026-08-14", repeat="yearly")
    make_event(client, title="Kept", date="2026-08-14")

    assert client.patch(f"/v1/events/{event_id}", json={"archived": True}).status_code == 200

    got = occurrences(client, "2026-08-01", "2027-09-01")
    assert [o["event"]["title"] for o in got] == ["Kept"]

    assert [r["title"] for r in client.get("/v1/events/all").json()] == ["Kept"]
    with_archived = client.get("/v1/events/all", params={"include_archived": True}).json()
    assert sorted(r["title"] for r in with_archived) == ["Kept", "Old ritual"]


def test_validation_rejects_out_of_range_time_and_empty_title(client: TestClient) -> None:
    bad_time = client.put(
        f"/v1/events/{new_id()}",
        json={"title": "Midnight+1", "date": "2026-08-14", "time_minutes": 1440},
    )
    assert bad_time.status_code == 422, bad_time.text

    bad_title = client.put(f"/v1/events/{new_id()}", json={"title": "", "date": "2026-08-14"})
    assert bad_title.status_code == 422

    # The window params are required, not optional.
    assert client.get("/v1/events", params={"from_day": "2026-08-01"}).status_code == 422


def test_events_are_reported_by_the_changes_feed(client: TestClient) -> None:
    make_event(client, title="Tracked", date="2026-08-14")
    changed = client.get("/v1/changes").json()
    assert len([item for item in changed["items"] if item["resource"] == "events"]) == 1


def test_remind_minutes_round_trips_and_clears(client: TestClient) -> None:
    """The asked-for reminder time survives the wire, and a full upsert
    without one clears it — the phone owns the truth, the row records it."""
    event_id = new_id()
    resp = client.put(
        f"/v1/events/{event_id}",
        json={
            "title": "client meeting at Karaikal",
            "date": "2026-08-19",
            "time_minutes": 10 * 60,
            "remind_minutes": 8 * 60 + 30,
        },
    )
    assert resp.status_code == 200, resp.text
    row = client.get("/v1/events/all").json()[0]
    assert row["remind_minutes"] == 8 * 60 + 30

    # PATCH moves only the reminder.
    resp = client.patch(f"/v1/events/{event_id}", json={"remind_minutes": 9 * 60})
    assert resp.status_code == 200, resp.text
    assert client.get("/v1/events/all").json()[0]["remind_minutes"] == 9 * 60

    # A full upsert without the field returns it to silence.
    resp = client.put(
        f"/v1/events/{event_id}",
        json={"title": "client meeting at Karaikal", "date": "2026-08-19"},
    )
    assert resp.status_code == 200, resp.text
    assert client.get("/v1/events/all").json()[0]["remind_minutes"] is None

    # Out-of-range reminders are refused at the door.
    resp = client.put(
        f"/v1/events/{new_id()}",
        json={"title": "x", "date": "2026-08-19", "remind_minutes": 2000},
    )
    assert resp.status_code == 422
