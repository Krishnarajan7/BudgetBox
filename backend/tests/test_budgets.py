from datetime import date, datetime, timezone

from app.main import app as _app
from app.budgets.router import router as _budgets_router

# The budgets router is a brand-new module; the app owner mounts it into
# app/main.py separately. To exercise the real HTTP surface in tests without
# touching app/main.py, mount it here if it isn't already registered
# (idempotent so this is a no-op once app/main.py includes it directly).
if not any(getattr(r, "path", "").startswith("/budgets") for r in _app.routes):
    _app.include_router(_budgets_router)


def _current_month() -> str:
    return date.today().strftime("%Y-%m")


async def _register_user(client, email: str) -> dict:
    password = "supersecret"
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


async def _seed_wallet_and_category(client, headers):
    wallets = await client.get("/wallets", headers=headers)
    assert wallets.status_code == 200
    wallet_id = wallets.json()[0]["id"]

    cats = await client.get("/categories", headers=headers, params={"type": "expense"})
    assert cats.status_code == 200
    category_id = cats.json()[0]["id"]

    return wallet_id, category_id


async def test_create_budget(client, auth_headers):
    _, category_id = await _seed_wallet_and_category(client, auth_headers)
    month = _current_month()

    r = await client.post(
        "/budgets",
        headers=auth_headers,
        json={"category_id": category_id, "month": month, "limit": 500.0},
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["category_id"] == category_id
    assert body["month"] == month
    assert float(body["limit"]) == 500.0


async def test_get_budgets_reflects_spent_and_remaining(client, auth_headers):
    wallet_id, category_id = await _seed_wallet_and_category(client, auth_headers)
    month = _current_month()

    r = await client.post(
        "/budgets",
        headers=auth_headers,
        json={"category_id": category_id, "month": month, "limit": 200.0},
    )
    assert r.status_code == 201, r.text

    now = datetime.now(timezone.utc)
    r = await client.post(
        "/expenses",
        headers=auth_headers,
        json={
            "wallet_id": wallet_id,
            "category_id": category_id,
            "amount": 50.0,
            "occurred_at": now.isoformat(),
        },
    )
    assert r.status_code == 201, r.text

    r = await client.get("/budgets", headers=auth_headers, params={"month": month})
    assert r.status_code == 200, r.text
    items = r.json()
    assert len(items) == 1
    item = items[0]
    assert item["category_id"] == category_id
    assert item["month"] == month
    assert float(item["limit"]) == 200.0
    assert float(item["spent"]) == 50.0
    assert float(item["remaining"]) == 150.0
    assert float(item["percent_used"]) == 25.0


async def test_get_budgets_defaults_to_current_month(client, auth_headers):
    _, category_id = await _seed_wallet_and_category(client, auth_headers)
    month = _current_month()

    r = await client.post(
        "/budgets",
        headers=auth_headers,
        json={"category_id": category_id, "month": month, "limit": 100.0},
    )
    assert r.status_code == 201, r.text

    r = await client.get("/budgets", headers=auth_headers)
    assert r.status_code == 200, r.text
    items = r.json()
    assert len(items) == 1
    assert items[0]["month"] == month


async def test_duplicate_budget_rejected(client, auth_headers):
    _, category_id = await _seed_wallet_and_category(client, auth_headers)
    month = _current_month()

    r = await client.post(
        "/budgets",
        headers=auth_headers,
        json={"category_id": category_id, "month": month, "limit": 300.0},
    )
    assert r.status_code == 201, r.text

    r = await client.post(
        "/budgets",
        headers=auth_headers,
        json={"category_id": category_id, "month": month, "limit": 400.0},
    )
    assert r.status_code == 409, r.text


async def test_other_users_budget_invisible_and_patch_404(client, auth_headers):
    _, category_id = await _seed_wallet_and_category(client, auth_headers)
    month = _current_month()

    r = await client.post(
        "/budgets",
        headers=auth_headers,
        json={"category_id": category_id, "month": month, "limit": 250.0},
    )
    assert r.status_code == 201, r.text
    budget_id = r.json()["id"]

    other_headers = await _register_user(client, "other-budget-user@example.com")

    # The other user's GET must not show it.
    r = await client.get("/budgets", headers=other_headers, params={"month": month})
    assert r.status_code == 200, r.text
    assert r.json() == []

    # PATCH/DELETE against the owner's budget id, as the other user, is a 404.
    r = await client.patch(
        f"/budgets/{budget_id}", headers=other_headers, json={"limit": 999.0}
    )
    assert r.status_code == 404, r.text

    r = await client.delete(f"/budgets/{budget_id}", headers=other_headers)
    assert r.status_code == 404, r.text

    # Owner can still patch their own budget.
    r = await client.patch(
        f"/budgets/{budget_id}", headers=auth_headers, json={"limit": 350.0}
    )
    assert r.status_code == 200, r.text
    assert float(r.json()["limit"]) == 350.0


async def test_budget_rejects_another_users_category(client, auth_headers):
    await _seed_wallet_and_category(client, auth_headers)
    month = _current_month()

    other_headers = await _register_user(client, "owner-of-budget-category@example.com")
    other_cats = await client.get(
        "/categories", headers=other_headers, params={"type": "expense"}
    )
    assert other_cats.status_code == 200
    other_category_id = other_cats.json()[0]["id"]

    r = await client.post(
        "/budgets",
        headers=auth_headers,
        json={"category_id": other_category_id, "month": month, "limit": 100.0},
    )
    assert r.status_code in (400, 404), r.text


async def test_budget_alert_appears_when_over_limit(client, auth_headers):
    wallet_id, category_id = await _seed_wallet_and_category(client, auth_headers)
    month = _current_month()

    r = await client.post(
        "/budgets",
        headers=auth_headers,
        json={"category_id": category_id, "month": month, "limit": 100.0},
    )
    assert r.status_code == 201, r.text

    now = datetime.now(timezone.utc)
    r = await client.post(
        "/expenses",
        headers=auth_headers,
        json={
            "wallet_id": wallet_id,
            "category_id": category_id,
            "amount": 150.0,
            "occurred_at": now.isoformat(),
        },
    )
    assert r.status_code == 201, r.text

    r = await client.get("/analytics/dashboard", headers=auth_headers)
    assert r.status_code == 200, r.text
    alerts = r.json()["alerts"]
    assert any(a["type"] == "danger" for a in alerts)
