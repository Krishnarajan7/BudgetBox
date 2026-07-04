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


async def test_create_task_and_list_shows_not_completed(client, auth_headers):
    r = await client.post(
        "/tasks",
        headers=auth_headers,
        json={"title": "Write report", "priority": "high"},
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["title"] == "Write report"
    assert body["priority"] == "high"
    assert body["completed"] is False
    assert body["completed_at"] is None
    task_id = body["id"]

    r = await client.get("/tasks", headers=auth_headers)
    assert r.status_code == 200, r.text
    tasks = r.json()
    assert len(tasks) == 1
    assert tasks[0]["id"] == task_id
    assert tasks[0]["completed"] is False
    assert tasks[0]["completed_at"] is None
    assert tasks[0]["priority"] == "high"


async def test_create_task_defaults_priority_to_medium(client, auth_headers):
    r = await client.post(
        "/tasks",
        headers=auth_headers,
        json={"title": "Default priority task"},
    )
    assert r.status_code == 201, r.text
    assert r.json()["priority"] == "medium"


async def test_complete_task_then_list_shows_completed(client, auth_headers):
    r = await client.post(
        "/tasks",
        headers=auth_headers,
        json={"title": "Pay bills"},
    )
    assert r.status_code == 201, r.text
    task_id = r.json()["id"]

    r = await client.post(f"/tasks/{task_id}/complete", headers=auth_headers)
    assert r.status_code == 200, r.text
    assert r.json()["completed"] is True
    assert r.json()["completed_at"] is not None

    r = await client.get("/tasks", headers=auth_headers)
    assert r.status_code == 200, r.text
    tasks = r.json()
    assert len(tasks) == 1
    assert tasks[0]["completed"] is True
    assert tasks[0]["completed_at"] is not None


async def test_patch_task_updates_title_and_priority(client, auth_headers):
    r = await client.post(
        "/tasks",
        headers=auth_headers,
        json={"title": "Old title", "priority": "low"},
    )
    assert r.status_code == 201, r.text
    task_id = r.json()["id"]

    r = await client.patch(
        f"/tasks/{task_id}",
        headers=auth_headers,
        json={"title": "New title", "priority": "high"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["title"] == "New title"
    assert body["priority"] == "high"

    r = await client.get("/tasks", headers=auth_headers)
    assert r.status_code == 200, r.text
    tasks = r.json()
    assert tasks[0]["title"] == "New title"
    assert tasks[0]["priority"] == "high"


async def test_patch_task_preserves_completion_state(client, auth_headers):
    r = await client.post(
        "/tasks",
        headers=auth_headers,
        json={"title": "Task to complete"},
    )
    task_id = r.json()["id"]

    await client.post(f"/tasks/{task_id}/complete", headers=auth_headers)

    r = await client.patch(
        f"/tasks/{task_id}",
        headers=auth_headers,
        json={"description": "updated description"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["description"] == "updated description"
    assert body["completed"] is True
    assert body["completed_at"] is not None


async def test_patch_nonexistent_task_returns_404(client, auth_headers):
    r = await client.patch(
        "/tasks/999999",
        headers=auth_headers,
        json={"title": "Nope"},
    )
    assert r.status_code == 404, r.text


async def test_patch_other_users_task_returns_404(client, auth_headers):
    other_headers = await _register_and_login(client, "task-intruder@example.com")

    r = await client.post(
        "/tasks",
        headers=auth_headers,
        json={"title": "Owner's task"},
    )
    assert r.status_code == 201, r.text
    task_id = r.json()["id"]

    r = await client.patch(
        f"/tasks/{task_id}",
        headers=other_headers,
        json={"title": "Hijacked"},
    )
    assert r.status_code == 404, r.text
