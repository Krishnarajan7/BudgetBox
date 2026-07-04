from datetime import date, datetime, time, timedelta, timezone

from app.main import app as _app
from app.focus.router import router as _focus_router

# The focus router is a brand-new module; the app owner mounts it into
# app/main.py separately. To exercise the real HTTP surface in tests without
# touching app/main.py, mount it here if it isn't already registered
# (idempotent so this is a no-op once app/main.py includes it directly).
if not any(getattr(r, "path", "").startswith("/focus") for r in _app.routes):
    _app.include_router(_focus_router)


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


def _at(day: date, hour: int = 10) -> str:
    return datetime.combine(day, time(hour, 0), tzinfo=timezone.utc).isoformat()


async def _log_session(
    client,
    headers,
    *,
    started_at: str,
    duration_min: int,
    kind: str = "work",
    label: str | None = None,
    completed: bool = True,
):
    r = await client.post(
        "/focus/sessions",
        headers=headers,
        json={
            "started_at": started_at,
            "duration_min": duration_min,
            "kind": kind,
            "label": label,
            "completed": completed,
        },
    )
    assert r.status_code == 201, r.text
    return r.json()


async def test_create_focus_session(client, auth_headers):
    today = date.today()
    body = await _log_session(
        client,
        auth_headers,
        started_at=_at(today),
        duration_min=25,
        kind="work",
        label="Write report",
        completed=True,
    )
    assert body["duration_min"] == 25
    assert body["kind"] == "work"
    assert body["label"] == "Write report"
    assert body["completed"] is True
    assert "id" in body and "created_at" in body


async def test_list_focus_sessions_date_range(client, auth_headers):
    today = date.today()

    in_range = await _log_session(
        client, auth_headers, started_at=_at(today), duration_min=25
    )
    also_in_range = await _log_session(
        client, auth_headers, started_at=_at(today - timedelta(days=1)), duration_min=25
    )
    out_of_range = await _log_session(
        client, auth_headers, started_at=_at(today - timedelta(days=10)), duration_min=25
    )

    r = await client.get(
        "/focus/sessions",
        headers=auth_headers,
        params={
            "start_date": (today - timedelta(days=1)).isoformat(),
            "end_date": today.isoformat(),
        },
    )
    assert r.status_code == 200, r.text
    ids = [s["id"] for s in r.json()]

    assert in_range["id"] in ids
    assert also_in_range["id"] in ids
    assert out_of_range["id"] not in ids

    # started_at desc
    started_ats = [s["started_at"] for s in r.json()]
    assert started_ats == sorted(started_ats, reverse=True)


async def test_focus_stats_math(client, auth_headers):
    today = date.today()

    # Today: one completed 25-min work session, one abandoned 10-min work
    # session (still counts toward minutes logged), and a 5-min break
    # (breaks never count toward focus minutes/sessions).
    await _log_session(client, auth_headers, started_at=_at(today), duration_min=25, completed=True)
    await _log_session(client, auth_headers, started_at=_at(today), duration_min=10, completed=False)
    await _log_session(
        client, auth_headers, started_at=_at(today), duration_min=5, kind="break", completed=True
    )

    # A consecutive completed-work-session streak: today, yesterday, day-2, day-3.
    for offset in (1, 2, 3):
        await _log_session(
            client,
            auth_headers,
            started_at=_at(today - timedelta(days=offset)),
            duration_min=25,
            completed=True,
        )

    r = await client.get("/focus/stats", headers=auth_headers)
    assert r.status_code == 200, r.text
    stats = r.json()

    assert stats["today_minutes"] == 35
    assert stats["today_sessions"] == 2
    assert stats["week_minutes"] == 110
    assert stats["week_sessions"] == 5
    assert stats["current_streak_days"] == 4


async def test_focus_stats_streak_zero_when_no_recent_completed_session(client, auth_headers):
    today = date.today()

    # Only a completed session from 5 days ago -> doesn't touch today/yesterday.
    await _log_session(
        client,
        auth_headers,
        started_at=_at(today - timedelta(days=5)),
        duration_min=25,
        completed=True,
    )

    r = await client.get("/focus/stats", headers=auth_headers)
    assert r.status_code == 200, r.text
    assert r.json()["current_streak_days"] == 0


async def test_delete_focus_session(client, auth_headers):
    today = date.today()
    session = await _log_session(client, auth_headers, started_at=_at(today), duration_min=25)

    r = await client.delete(f"/focus/sessions/{session['id']}", headers=auth_headers)
    assert r.status_code == 204, r.text

    r = await client.get("/focus/sessions", headers=auth_headers)
    assert r.status_code == 200, r.text
    assert session["id"] not in [s["id"] for s in r.json()]


async def test_delete_focus_session_404_for_unknown(client, auth_headers):
    r = await client.delete("/focus/sessions/999999", headers=auth_headers)
    assert r.status_code == 404, r.text


async def test_focus_sessions_block_cross_user_access(client):
    user_a = await _register_and_login(client, "focus-owner@example.com")
    user_b = await _register_and_login(client, "focus-intruder@example.com")

    today = date.today()
    session = await _log_session(client, user_a, started_at=_at(today), duration_min=25)

    # User B cannot see user A's sessions.
    r = await client.get("/focus/sessions", headers=user_b)
    assert r.status_code == 200, r.text
    assert session["id"] not in [s["id"] for s in r.json()]

    # User B's stats are unaffected by user A's sessions.
    r = await client.get("/focus/stats", headers=user_b)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["today_minutes"] == 0
    assert body["today_sessions"] == 0
    assert body["week_minutes"] == 0
    assert body["week_sessions"] == 0
    assert body["current_streak_days"] == 0

    # User B cannot delete user A's session.
    r = await client.delete(f"/focus/sessions/{session['id']}", headers=user_b)
    assert r.status_code == 404, r.text

    # It's still there for user A.
    r = await client.get("/focus/sessions", headers=user_a)
    assert r.status_code == 200, r.text
    assert session["id"] in [s["id"] for s in r.json()]
