from datetime import date, timedelta


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
# Notes
# ---------------------------------------------------------------------------


async def test_note_crud(client):
    user_a = await _register_and_login(client, "note-owner@example.com")

    r = await client.post(
        "/notes",
        headers=user_a,
        json={"title": "Groceries", "body": "Buy milk and eggs"},
    )
    assert r.status_code == 201, r.text
    note = r.json()
    note_id = note["id"]
    assert note["title"] == "Groceries"
    assert note["body"] == "Buy milk and eggs"
    assert note["pinned"] is False

    r = await client.get("/notes", headers=user_a)
    assert r.status_code == 200, r.text
    assert any(n["id"] == note_id for n in r.json())

    r = await client.patch(
        f"/notes/{note_id}",
        headers=user_a,
        json={"body": "Buy milk, eggs, and bread"},
    )
    assert r.status_code == 200, r.text
    assert r.json()["body"] == "Buy milk, eggs, and bread"
    assert r.json()["title"] == "Groceries"

    r = await client.delete(f"/notes/{note_id}", headers=user_a)
    assert r.status_code == 204, r.text

    r = await client.get("/notes", headers=user_a)
    assert r.status_code == 200, r.text
    assert all(n["id"] != note_id for n in r.json())

    r = await client.delete(f"/notes/{note_id}", headers=user_a)
    assert r.status_code == 404, r.text

    r = await client.patch(f"/notes/{note_id}", headers=user_a, json={"title": "x"})
    assert r.status_code == 404, r.text


async def test_note_search(client):
    user_a = await _register_and_login(client, "note-search@example.com")

    await client.post(
        "/notes", headers=user_a, json={"title": "Trip plan", "body": "Visit Paris"}
    )
    await client.post(
        "/notes", headers=user_a, json={"title": "Recipe", "body": "Bake a cake"}
    )
    await client.post(
        "/notes",
        headers=user_a,
        json={"title": "Reminder", "body": "paris souvenirs to buy"},
    )

    r = await client.get("/notes", headers=user_a, params={"q": "paris"})
    assert r.status_code == 200, r.text
    titles = {n["title"] for n in r.json()}
    assert titles == {"Trip plan", "Reminder"}

    r = await client.get("/notes", headers=user_a, params={"q": "cake"})
    assert r.status_code == 200, r.text
    titles = {n["title"] for n in r.json()}
    assert titles == {"Recipe"}


async def test_note_pinned_ordering(client):
    user_a = await _register_and_login(client, "note-pin@example.com")

    r1 = await client.post(
        "/notes", headers=user_a, json={"title": "First", "body": "one"}
    )
    r2 = await client.post(
        "/notes", headers=user_a, json={"title": "Second", "body": "two"}
    )
    r3 = await client.post(
        "/notes", headers=user_a, json={"title": "Third", "body": "three"}
    )
    assert r1.status_code == 201 and r2.status_code == 201 and r3.status_code == 201

    third_id = r3.json()["id"]

    # Pin the last-created note; it should now sort first despite being the
    # oldest by update time among the set once we touch the others.
    r = await client.patch(
        f"/notes/{third_id}", headers=user_a, json={"pinned": True}
    )
    assert r.status_code == 200, r.text

    r = await client.get("/notes", headers=user_a, params={"pinned": True})
    assert r.status_code == 200, r.text
    pinned_ids = [n["id"] for n in r.json()]
    assert pinned_ids == [third_id]

    r = await client.get("/notes", headers=user_a)
    assert r.status_code == 200, r.text
    ids = [n["id"] for n in r.json()]
    assert ids[0] == third_id  # pinned-first


async def test_note_cross_user_isolation(client):
    user_a = await _register_and_login(client, "note-owner2@example.com")
    user_b = await _register_and_login(client, "note-intruder2@example.com")

    r = await client.post(
        "/notes", headers=user_a, json={"title": "Secret", "body": "hidden"}
    )
    assert r.status_code == 201, r.text
    note_id = r.json()["id"]

    r = await client.get("/notes", headers=user_b)
    assert r.status_code == 200, r.text
    assert all(n["id"] != note_id for n in r.json())

    r = await client.patch(
        f"/notes/{note_id}", headers=user_b, json={"title": "Hijacked"}
    )
    assert r.status_code == 404, r.text

    r = await client.delete(f"/notes/{note_id}", headers=user_b)
    assert r.status_code == 404, r.text


# ---------------------------------------------------------------------------
# Journal entries
# ---------------------------------------------------------------------------


async def test_journal_upsert_create_then_update(client):
    user_a = await _register_and_login(client, "journal-owner@example.com")
    day = date(2026, 7, 1)

    r = await client.put(
        f"/journal/{day.isoformat()}",
        headers=user_a,
        json={"body": "Had a good day", "mood_note": "happy"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["date"] == day.isoformat()
    assert body["body"] == "Had a good day"
    assert body["mood_note"] == "happy"
    entry_id = body["id"]

    r = await client.put(
        f"/journal/{day.isoformat()}",
        headers=user_a,
        json={"body": "Updated reflection"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["id"] == entry_id  # same row, upserted not duplicated
    assert body["body"] == "Updated reflection"
    assert body["mood_note"] is None

    r = await client.get(
        "/journal",
        headers=user_a,
        params={"start_date": "2026-06-25", "end_date": "2026-07-05"},
    )
    assert r.status_code == 200, r.text
    entries = r.json()
    assert len(entries) == 1
    assert entries[0]["id"] == entry_id


async def test_journal_list_ordered_date_desc(client):
    user_a = await _register_and_login(client, "journal-owner2@example.com")

    for d in [date(2026, 7, 1), date(2026, 7, 3), date(2026, 7, 2)]:
        r = await client.put(
            f"/journal/{d.isoformat()}", headers=user_a, json={"body": f"entry {d}"}
        )
        assert r.status_code == 200, r.text

    r = await client.get(
        "/journal",
        headers=user_a,
        params={"start_date": "2026-07-01", "end_date": "2026-07-03"},
    )
    assert r.status_code == 200, r.text
    dates = [e["date"] for e in r.json()]
    assert dates == ["2026-07-03", "2026-07-02", "2026-07-01"]


async def test_journal_delete(client):
    user_a = await _register_and_login(client, "journal-owner3@example.com")
    day = date(2026, 7, 4)

    r = await client.put(
        f"/journal/{day.isoformat()}", headers=user_a, json={"body": "note"}
    )
    assert r.status_code == 200, r.text

    r = await client.delete(f"/journal/{day.isoformat()}", headers=user_a)
    assert r.status_code == 204, r.text

    r = await client.delete(f"/journal/{day.isoformat()}", headers=user_a)
    assert r.status_code == 404, r.text


async def test_journal_cross_user_isolation(client):
    user_a = await _register_and_login(client, "journal-owner4@example.com")
    user_b = await _register_and_login(client, "journal-intruder4@example.com")
    day = date(2026, 7, 4)

    r = await client.put(
        f"/journal/{day.isoformat()}", headers=user_a, json={"body": "private"}
    )
    assert r.status_code == 200, r.text

    r = await client.get(
        "/journal",
        headers=user_b,
        params={"start_date": "2026-07-01", "end_date": "2026-07-10"},
    )
    assert r.status_code == 200, r.text
    assert r.json() == []

    r = await client.delete(f"/journal/{day.isoformat()}", headers=user_b)
    assert r.status_code == 404, r.text


# ---------------------------------------------------------------------------
# Day summary
# ---------------------------------------------------------------------------


async def test_day_summary_connects_modules(client):
    user_a = await _register_and_login(client, "day-summary@example.com")

    # Tasks/habits are always completed "today" per their own conventions,
    # so the day under test must be today for those two pieces to line up.
    today = date.today()
    other_day = today + timedelta(days=1)

    # Journal entry for today
    r = await client.put(
        f"/journal/{today.isoformat()}",
        headers=user_a,
        json={"body": "Productive day", "mood_note": "content"},
    )
    assert r.status_code == 200, r.text

    # A wallet + category are required to create a transaction
    r = await client.post(
        "/wallets", headers=user_a, json={"name": "Cash", "balance": 100}
    )
    assert r.status_code == 201, r.text
    wallet_id = r.json()["id"]

    r = await client.post(
        "/categories", headers=user_a, json={"name": "Food", "type": "expense"}
    )
    assert r.status_code == 201, r.text
    category_id = r.json()["id"]

    occurred_at = f"{today.isoformat()}T12:30:00Z"
    r = await client.post(
        "/expenses",
        headers=user_a,
        json={
            "wallet_id": wallet_id,
            "category_id": category_id,
            "amount": 42.5,
            "note": "Lunch",
            "occurred_at": occurred_at,
        },
    )
    assert r.status_code == 201, r.text
    expense_id = r.json()["id"]

    # A task completed today
    r = await client.post("/tasks", headers=user_a, json={"title": "Write report"})
    assert r.status_code == 201, r.text
    task_id = r.json()["id"]
    r = await client.post(f"/tasks/{task_id}/complete", headers=user_a)
    assert r.status_code == 200, r.text

    # A habit completed today
    r = await client.post("/habits", headers=user_a, json={"name": "Read"})
    assert r.status_code == 201, r.text
    habit_id = r.json()["id"]
    r = await client.patch(
        f"/habits/{habit_id}/logs/today", headers=user_a, json={"completed": True}
    )
    assert r.status_code == 200, r.text

    r = await client.get(f"/journal/{today.isoformat()}/day", headers=user_a)
    assert r.status_code == 200, r.text
    summary = r.json()
    assert summary["date"] == today.isoformat()
    assert summary["entry"]["body"] == "Productive day"
    assert summary["entry"]["mood_note"] == "content"
    assert any(tx["id"] == expense_id and tx["note"] == "Lunch" for tx in summary["transactions"])
    assert any(
        t["id"] == task_id and t["title"] == "Write report"
        for t in summary["tasks_completed"]
    )
    assert any(
        h["id"] == habit_id and h["name"] == "Read"
        for h in summary["habits_completed"]
    )

    # Day with no activity is empty but well-formed
    r = await client.get(f"/journal/{other_day.isoformat()}/day", headers=user_a)
    assert r.status_code == 200, r.text
    empty_summary = r.json()
    assert empty_summary["entry"] is None
    assert empty_summary["transactions"] == []
    assert empty_summary["tasks_completed"] == []
    assert empty_summary["habits_completed"] == []
