"""The two books that used to live only on the phone. What matters here is the
restore story: everything written comes back, deletions leave tombstones the
other phone can act on, and nothing about a mark's meaning is enforced server-side."""

from typing import Any

from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id


def put_mark(client: TestClient, mark_id: str, **body: Any) -> Any:
    payload: dict[str, Any] = {
        "date": "2026-08-19",
        "kind": "bath",
        "at": "2026-08-19T02:30:00Z",
        **body,
    }
    return client.put(f"/v1/marks/{mark_id}", json=payload)


def put_alarm(client: TestClient, alarm_id: str, **body: Any) -> Any:
    payload: dict[str, Any] = {"minute_of_day": 330, "label": "gym", **body}
    return client.put(f"/v1/alarms/{alarm_id}", json=payload)


# ————— marks —————


def test_mark_round_trips_verbatim(client: TestClient) -> None:
    mark_id = new_id()
    resp = put_mark(client, mark_id, kind="meal", note="curd rice")
    assert resp.status_code == 200, resp.text
    created = resp.json()
    assert (created["id"], created["kind"], created["note"]) == (mark_id, "meal", "curd rice")

    listed = client.get("/v1/marks").json()
    assert listed == [created]


def test_same_day_and_kind_repeats_for_counted_habits(client: TestClient) -> None:
    """Eight glasses of water is eight rows, not one row that lost seven taps."""
    for _ in range(8):
        assert put_mark(client, new_id(), kind="water").status_code == 200
    assert len(client.get("/v1/marks").json()) == 8


def test_unknown_kinds_are_stored_not_judged(client: TestClient) -> None:
    """A habit the app invents tomorrow must not need a migration here."""
    resp = put_mark(client, new_id(), kind="cold-shower")
    assert resp.status_code == 200, resp.text
    assert resp.json()["kind"] == "cold-shower"


def test_marks_filter_by_day_range(client: TestClient) -> None:
    for day in ("2026-08-17", "2026-08-19", "2026-08-21"):
        put_mark(client, new_id(), date=day, at=f"{day}T02:30:00Z")
    rows = client.get("/v1/marks", params={"from_day": "2026-08-18", "to_day": "2026-08-20"}).json()
    assert [r["date"] for r in rows] == ["2026-08-19"]


def test_deleting_a_mark_leaves_a_tombstone(client: TestClient) -> None:
    """Un-ticking a habit on one phone must un-tick it on the other."""
    mark_id = new_id()
    put_mark(client, mark_id)
    assert client.delete(f"/v1/marks/{mark_id}").status_code == 204
    assert client.get("/v1/marks").json() == []

    events = client.get("/v1/changes").json()["items"]
    assert {"resource": "day_marks", "resource_id": mark_id, "operation": "delete"}.items() <= (
        next(e for e in events if e["operation"] == "delete").items()
    )


def test_deleting_a_missing_mark_is_404(client: TestClient) -> None:
    assert client.delete(f"/v1/marks/{new_id()}").status_code == 404


# ————— alarms —————


def test_alarm_round_trips_with_defaults(client: TestClient) -> None:
    alarm_id = new_id()
    created = put_alarm(client, alarm_id).json()
    assert created["minute_of_day"] == 330
    # A bare alarm rings once and switches itself off: days == 0.
    assert (created["days"], created["enabled"], created["snooze_minutes"]) == (0, True, 9)
    assert created["vibrate"] is True


def test_alarm_upsert_replaces_in_place(client: TestClient) -> None:
    alarm_id = new_id()
    first = put_alarm(client, alarm_id).json()
    after = put_alarm(client, alarm_id, minute_of_day=360, days=31, enabled=False).json()
    assert (after["minute_of_day"], after["days"], after["enabled"]) == (360, 31, False)
    assert after["created_at"] == first["created_at"]


def test_alarms_list_earliest_first(client: TestClient) -> None:
    for minute in (600, 330, 1380):
        put_alarm(client, new_id(), minute_of_day=minute)
    assert [a["minute_of_day"] for a in client.get("/v1/alarms").json()] == [330, 600, 1380]


def test_impossible_alarm_shapes_are_refused(client: TestClient) -> None:
    assert put_alarm(client, new_id(), minute_of_day=1440).status_code == 422
    assert put_alarm(client, new_id(), days=128).status_code == 422
    assert put_alarm(client, new_id(), snooze_minutes=0).status_code == 422


def test_deleting_an_alarm_leaves_a_tombstone(client: TestClient) -> None:
    alarm_id = new_id()
    put_alarm(client, alarm_id)
    assert client.delete(f"/v1/alarms/{alarm_id}").status_code == 204
    assert client.get("/v1/alarms").json() == []
    events = client.get("/v1/changes").json()["items"]
    assert any(
        e["resource"] == "alarms" and e["resource_id"] == alarm_id and e["operation"] == "delete"
        for e in events
    )


def test_habit_definitions_ride_the_settings_store(client: TestClient) -> None:
    """No table for habits: the app's 'habits' JSON is a setting, and settings
    already sync — which is the whole reason a restored phone knows what 'push' is."""
    body = '[{"kind":"push","name":"Push-ups","target":50,"unit":"reps"}]'
    assert client.put("/v1/settings/habits", json={"value": body}).status_code == 200
    assert client.get("/v1/settings").json()["habits"] == body


def test_a_malformed_id_is_the_clients_mistake(client: TestClient) -> None:
    assert put_mark(client, "not-a-uuid").status_code == 422
    assert put_alarm(client, "not-a-uuid").status_code == 422
