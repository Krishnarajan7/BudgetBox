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


# ---------------------------------------------------------------------------
# Mood
# ---------------------------------------------------------------------------


async def test_mood_upsert_creates_then_updates_same_date(client):
    user_a = await _register_and_login(client, "mood-owner@example.com")

    r = await client.put(
        "/mood/2026-07-01",
        headers=user_a,
        json={"mood": 3, "note": "okay day"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["date"] == "2026-07-01"
    assert body["mood"] == 3
    assert body["note"] == "okay day"
    entry_id = body["id"]

    r = await client.put(
        "/mood/2026-07-01",
        headers=user_a,
        json={"mood": 5, "note": "great day"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["id"] == entry_id
    assert body["mood"] == 5
    assert body["note"] == "great day"

    r = await client.get("/mood", headers=user_a)
    assert r.status_code == 200, r.text
    assert len(r.json()) == 1


async def test_mood_list_filters_by_date_range(client):
    user_a = await _register_and_login(client, "mood-range@example.com")

    for d, m in [("2026-06-01", 2), ("2026-06-15", 4), ("2026-07-01", 5)]:
        r = await client.put(f"/mood/{d}", headers=user_a, json={"mood": m})
        assert r.status_code == 200, r.text

    r = await client.get(
        "/mood",
        headers=user_a,
        params={"start_date": "2026-06-10", "end_date": "2026-06-30"},
    )
    assert r.status_code == 200, r.text
    dates = [e["date"] for e in r.json()]
    assert dates == ["2026-06-15"]

    r = await client.get("/mood", headers=user_a)
    assert r.status_code == 200, r.text
    dates = [e["date"] for e in r.json()]
    # ordered by date desc
    assert dates == ["2026-07-01", "2026-06-15", "2026-06-01"]


async def test_mood_cross_user_isolation(client):
    user_a = await _register_and_login(client, "mood-a@example.com")
    user_b = await _register_and_login(client, "mood-b@example.com")

    r = await client.put("/mood/2026-07-01", headers=user_a, json={"mood": 4})
    assert r.status_code == 200, r.text

    r = await client.get("/mood", headers=user_b)
    assert r.status_code == 200, r.text
    assert r.json() == []

    r = await client.delete("/mood/2026-07-01", headers=user_b)
    assert r.status_code == 404, r.text

    # owner can still see and delete their own entry
    r = await client.get("/mood", headers=user_a)
    assert len(r.json()) == 1

    r = await client.delete("/mood/2026-07-01", headers=user_a)
    assert r.status_code == 204, r.text

    r = await client.delete("/mood/2026-07-01", headers=user_a)
    assert r.status_code == 404, r.text


async def test_mood_invalid_value_rejected(client):
    user_a = await _register_and_login(client, "mood-invalid@example.com")

    r = await client.put("/mood/2026-07-01", headers=user_a, json={"mood": 7})
    assert r.status_code == 422, r.text


# ---------------------------------------------------------------------------
# Water
# ---------------------------------------------------------------------------


async def test_water_upsert_creates_then_updates_same_date(client):
    user_a = await _register_and_login(client, "water-owner@example.com")

    r = await client.put(
        "/water/2026-07-01", headers=user_a, json={"glasses": 4}
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["glasses"] == 4
    assert body["goal"] == 8
    entry_id = body["id"]

    r = await client.put(
        "/water/2026-07-01", headers=user_a, json={"glasses": 6, "goal": 10}
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["id"] == entry_id
    assert body["glasses"] == 6
    assert body["goal"] == 10

    r = await client.get("/water", headers=user_a)
    assert r.status_code == 200, r.text
    assert len(r.json()) == 1


async def test_water_list_filters_by_date_range(client):
    user_a = await _register_and_login(client, "water-range@example.com")

    for d, g in [("2026-06-01", 3), ("2026-06-15", 5), ("2026-07-01", 8)]:
        r = await client.put(f"/water/{d}", headers=user_a, json={"glasses": g})
        assert r.status_code == 200, r.text

    r = await client.get(
        "/water",
        headers=user_a,
        params={"start_date": "2026-06-10", "end_date": "2026-06-30"},
    )
    assert r.status_code == 200, r.text
    dates = [e["date"] for e in r.json()]
    assert dates == ["2026-06-15"]


async def test_water_cross_user_isolation(client):
    user_a = await _register_and_login(client, "water-a@example.com")
    user_b = await _register_and_login(client, "water-b@example.com")

    r = await client.put("/water/2026-07-01", headers=user_a, json={"glasses": 5})
    assert r.status_code == 200, r.text

    r = await client.get("/water", headers=user_b)
    assert r.status_code == 200, r.text
    assert r.json() == []

    r = await client.delete("/water/2026-07-01", headers=user_b)
    assert r.status_code == 404, r.text

    r = await client.delete("/water/2026-07-01", headers=user_a)
    assert r.status_code == 204, r.text


async def test_water_invalid_value_rejected(client):
    user_a = await _register_and_login(client, "water-invalid@example.com")

    r = await client.put("/water/2026-07-01", headers=user_a, json={"glasses": -1})
    assert r.status_code == 422, r.text


# ---------------------------------------------------------------------------
# Sleep
# ---------------------------------------------------------------------------


async def test_sleep_upsert_creates_then_updates_same_date(client):
    user_a = await _register_and_login(client, "sleep-owner@example.com")

    r = await client.put(
        "/sleep/2026-07-01",
        headers=user_a,
        json={"hours": 7.5, "quality": 4, "bedtime": "23:00", "wake_time": "06:30"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["hours"] == "7.50"
    assert body["quality"] == 4
    entry_id = body["id"]

    r = await client.put(
        "/sleep/2026-07-01",
        headers=user_a,
        json={"hours": 6.0, "quality": 2, "bedtime": "01:00", "wake_time": "07:00"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["id"] == entry_id
    assert body["hours"] == "6.00"
    assert body["quality"] == 2

    r = await client.get("/sleep", headers=user_a)
    assert r.status_code == 200, r.text
    assert len(r.json()) == 1


async def test_sleep_list_filters_by_date_range(client):
    user_a = await _register_and_login(client, "sleep-range@example.com")

    for d, h in [("2026-06-01", 6), ("2026-06-15", 7), ("2026-07-01", 8)]:
        r = await client.put(f"/sleep/{d}", headers=user_a, json={"hours": h})
        assert r.status_code == 200, r.text

    r = await client.get(
        "/sleep",
        headers=user_a,
        params={"start_date": "2026-06-10", "end_date": "2026-06-30"},
    )
    assert r.status_code == 200, r.text
    dates = [e["date"] for e in r.json()]
    assert dates == ["2026-06-15"]


async def test_sleep_cross_user_isolation(client):
    user_a = await _register_and_login(client, "sleep-a@example.com")
    user_b = await _register_and_login(client, "sleep-b@example.com")

    r = await client.put("/sleep/2026-07-01", headers=user_a, json={"hours": 8})
    assert r.status_code == 200, r.text

    r = await client.get("/sleep", headers=user_b)
    assert r.status_code == 200, r.text
    assert r.json() == []

    r = await client.delete("/sleep/2026-07-01", headers=user_b)
    assert r.status_code == 404, r.text

    r = await client.delete("/sleep/2026-07-01", headers=user_a)
    assert r.status_code == 204, r.text


async def test_sleep_invalid_value_rejected(client):
    user_a = await _register_and_login(client, "sleep-invalid@example.com")

    r = await client.put(
        "/sleep/2026-07-01", headers=user_a, json={"hours": 8, "quality": 7}
    )
    assert r.status_code == 422, r.text
