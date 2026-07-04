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


async def test_habit_insights_blocks_cross_user_access(client):
    user_a = await _register_and_login(client, "habit-owner@example.com")
    user_b = await _register_and_login(client, "habit-intruder@example.com")

    r = await client.post("/habits", headers=user_a, json={"name": "Meditate"})
    assert r.status_code == 201, r.text
    habit_id = r.json()["id"]

    # Owner can access their own habit insights
    r = await client.get(f"/habits/{habit_id}/insights", headers=user_a)
    assert r.status_code == 200, r.text

    # Another authenticated user must not be able to read the habit's insights
    r = await client.get(f"/habits/{habit_id}/insights", headers=user_b)
    assert r.status_code == 404, r.text


async def test_habit_impact_blocks_cross_user_access(client):
    user_a = await _register_and_login(client, "habit-owner2@example.com")
    user_b = await _register_and_login(client, "habit-intruder2@example.com")

    r = await client.post("/habits", headers=user_a, json={"name": "Run"})
    assert r.status_code == 201, r.text
    habit_id = r.json()["id"]

    # Owner can access their own habit financial impact
    r = await client.get(f"/habits/{habit_id}/impact", headers=user_a)
    assert r.status_code == 200, r.text

    # Another authenticated user must not be able to read the habit's financial impact
    r = await client.get(f"/habits/{habit_id}/impact", headers=user_b)
    assert r.status_code == 404, r.text


async def test_habit_insights_and_impact_404_for_unknown_habit(client):
    user_a = await _register_and_login(client, "habit-owner3@example.com")

    r = await client.get("/habits/999999/insights", headers=user_a)
    assert r.status_code == 404, r.text

    r = await client.get("/habits/999999/impact", headers=user_a)
    assert r.status_code == 404, r.text


async def test_habit_logs_today_reads_without_creating_row(client):
    user_a = await _register_and_login(client, "habit-owner4@example.com")

    r = await client.post("/habits", headers=user_a, json={"name": "Read"})
    assert r.status_code == 201, r.text
    habit_id = r.json()["id"]

    # No log row exists yet -> completed should be false
    r = await client.get(f"/habits/{habit_id}/logs/today", headers=user_a)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["habit_id"] == habit_id
    assert body["completed"] is False

    # Reading again must not create a row / must not flip state
    r = await client.get(f"/habits/{habit_id}/logs/today", headers=user_a)
    assert r.status_code == 200, r.text
    assert r.json()["completed"] is False

    # Now actually mark it complete via PATCH
    r = await client.patch(
        f"/habits/{habit_id}/logs/today",
        headers=user_a,
        json={"completed": True},
    )
    assert r.status_code == 200, r.text
    assert r.json()["completed"] is True

    # GET now reflects the completed state
    r = await client.get(f"/habits/{habit_id}/logs/today", headers=user_a)
    assert r.status_code == 200, r.text
    assert r.json()["completed"] is True


async def test_habit_logs_today_blocks_cross_user_access(client):
    user_a = await _register_and_login(client, "habit-owner5@example.com")
    user_b = await _register_and_login(client, "habit-intruder5@example.com")

    r = await client.post("/habits", headers=user_a, json={"name": "Stretch"})
    assert r.status_code == 201, r.text
    habit_id = r.json()["id"]

    r = await client.get(f"/habits/{habit_id}/logs/today", headers=user_b)
    assert r.status_code == 404, r.text

    r = await client.patch(
        f"/habits/{habit_id}/logs/today",
        headers=user_b,
        json={"completed": True},
    )
    assert r.status_code == 404, r.text


async def test_update_habit_renames(client):
    user_a = await _register_and_login(client, "habit-owner6@example.com")

    r = await client.post("/habits", headers=user_a, json={"name": "Old Name"})
    assert r.status_code == 201, r.text
    habit_id = r.json()["id"]

    r = await client.patch(
        f"/habits/{habit_id}",
        headers=user_a,
        json={"name": "New Name"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["id"] == habit_id
    assert body["name"] == "New Name"

    r = await client.get("/habits", headers=user_a)
    assert r.status_code == 200, r.text
    names = [h["name"] for h in r.json()]
    assert "New Name" in names


async def test_update_habit_blocks_cross_user_access(client):
    user_a = await _register_and_login(client, "habit-owner7@example.com")
    user_b = await _register_and_login(client, "habit-intruder7@example.com")

    r = await client.post("/habits", headers=user_a, json={"name": "Journal"})
    assert r.status_code == 201, r.text
    habit_id = r.json()["id"]

    r = await client.patch(
        f"/habits/{habit_id}",
        headers=user_b,
        json={"name": "Hijacked"},
    )
    assert r.status_code == 404, r.text
