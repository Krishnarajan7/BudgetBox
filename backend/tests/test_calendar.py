from datetime import date, datetime, time

from app.main import app
from app.calendar_events.router import router as calendar_router

# The calendar_events module is intentionally self-contained (per the task
# spec we must not touch app/main.py), so this test file mounts its router
# onto the shared app instance directly. Guard against double-registration
# in case this module gets imported more than once in a session.
if not getattr(app, "_calendar_router_mounted", False):
    app.include_router(calendar_router)
    app._calendar_router_mounted = True


async def _register_and_login(client, email: str, password: str = "supersecret") -> dict:
    reg = await client.post(
        "/auth/register",
        json={"email": email, "password": password},
    )
    assert reg.status_code == 201, reg.text

    login = await client.post(
        "/auth/login",
        json={"email": email, "password": password},
    )
    assert login.status_code == 200, login.text

    token = login.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


async def test_create_list_update_delete_event(client, auth_headers):
    today = date.today()

    r = await client.post(
        "/events",
        headers=auth_headers,
        json={
            "title": "Dentist appointment",
            "date": today.isoformat(),
            "time": "09:30",
            "kind": "reminder",
            "note": "Bring insurance card",
        },
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["title"] == "Dentist appointment"
    assert body["time"] == "09:30"
    assert body["kind"] == "reminder"
    assert body["recur_yearly"] is False
    assert body["occurs_on"] == today.isoformat()
    assert body["years_since"] is None
    event_id = body["id"]

    # Default range (no start/end) should default to the current month and
    # include the event we just created for today.
    r = await client.get("/events", headers=auth_headers)
    assert r.status_code == 200, r.text
    events = r.json()
    assert any(e["id"] == event_id for e in events)

    r = await client.patch(
        f"/events/{event_id}",
        headers=auth_headers,
        json={"title": "Dentist appointment (rescheduled)", "time": "14:00"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["title"] == "Dentist appointment (rescheduled)"
    assert body["time"] == "14:00"

    r = await client.delete(f"/events/{event_id}", headers=auth_headers)
    assert r.status_code == 204, r.text

    r = await client.get(
        "/events",
        headers=auth_headers,
        params={
            "start_date": today.replace(day=1).isoformat(),
            "end_date": today.isoformat(),
        },
    )
    assert r.status_code == 200, r.text
    assert all(e["id"] != event_id for e in r.json())


async def test_patch_and_delete_nonexistent_event_returns_404(client, auth_headers):
    r = await client.patch(
        "/events/999999",
        headers=auth_headers,
        json={"title": "Nope"},
    )
    assert r.status_code == 404, r.text

    r = await client.delete("/events/999999", headers=auth_headers)
    assert r.status_code == 404, r.text


async def test_yearly_recurring_birthday_shows_with_years_since(client, auth_headers):
    r = await client.post(
        "/events",
        headers=auth_headers,
        json={
            "title": "Mom's birthday",
            "date": "1990-05-12",
            "kind": "birthday",
            "recur_yearly": True,
        },
    )
    assert r.status_code == 201, r.text

    r = await client.get(
        "/events",
        headers=auth_headers,
        params={"start_date": "2026-05-01", "end_date": "2026-05-31"},
    )
    assert r.status_code == 200, r.text
    events = r.json()
    assert len(events) == 1
    occurrence = events[0]
    assert occurrence["title"] == "Mom's birthday"
    assert occurrence["date"] == "1990-05-12"
    assert occurrence["occurs_on"] == "2026-05-12"
    assert occurrence["years_since"] == 36

    # Outside the recurring month/day window, it should not appear.
    r = await client.get(
        "/events",
        headers=auth_headers,
        params={"start_date": "2026-06-01", "end_date": "2026-06-30"},
    )
    assert r.status_code == 200, r.text
    assert r.json() == []


async def test_calendar_month_view_includes_event_and_task_due(client, auth_headers):
    today = date.today()
    month_str = today.strftime("%Y-%m")

    r = await client.post(
        "/events",
        headers=auth_headers,
        json={
            "title": "Anniversary dinner",
            "date": today.isoformat(),
            "kind": "event",
        },
    )
    assert r.status_code == 201, r.text

    due_at = datetime.combine(today, time(18, 0)).isoformat()
    r = await client.post(
        "/tasks",
        headers=auth_headers,
        json={"title": "Buy flowers", "due_at": due_at, "priority": "high"},
    )
    assert r.status_code == 201, r.text

    r = await client.get("/calendar", headers=auth_headers, params={"month": month_str})
    assert r.status_code == 200, r.text
    body = r.json()
    day_key = today.isoformat()
    assert day_key in body["days"]

    day = body["days"][day_key]
    assert any(e["title"] == "Anniversary dinner" for e in day["events"])
    task_entries = [t for t in day["tasks_due"] if t["title"] == "Buy flowers"]
    assert len(task_entries) == 1
    assert task_entries[0]["priority"] == "high"
    assert task_entries[0]["completed"] is False

    # Default (no month param) should behave the same as the current month.
    r = await client.get("/calendar", headers=auth_headers)
    assert r.status_code == 200, r.text
    assert day_key in r.json()["days"]


async def test_cross_user_isolation(client, auth_headers):
    other_headers = await _register_and_login(client, "calendar-intruder@example.com")

    today = date.today()
    r = await client.post(
        "/events",
        headers=auth_headers,
        json={"title": "Owner's event", "date": today.isoformat(), "kind": "event"},
    )
    assert r.status_code == 201, r.text
    event_id = r.json()["id"]

    # Other user can't see it in their listing.
    r = await client.get(
        "/events",
        headers=other_headers,
        params={
            "start_date": today.replace(day=1).isoformat(),
            "end_date": today.isoformat(),
        },
    )
    assert r.status_code == 200, r.text
    assert all(e["id"] != event_id for e in r.json())

    # Other user can't patch or delete it.
    r = await client.patch(
        f"/events/{event_id}",
        headers=other_headers,
        json={"title": "Hijacked"},
    )
    assert r.status_code == 404, r.text

    r = await client.delete(f"/events/{event_id}", headers=other_headers)
    assert r.status_code == 404, r.text

    # It's still intact for the owner.
    r = await client.patch(
        f"/events/{event_id}",
        headers=auth_headers,
        json={"title": "Still mine"},
    )
    assert r.status_code == 200, r.text
