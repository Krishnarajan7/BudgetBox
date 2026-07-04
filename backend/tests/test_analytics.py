from datetime import datetime, timezone


async def _seed_wallet_and_category(client, headers):
    wallets = await client.get("/wallets", headers=headers)
    assert wallets.status_code == 200
    wallet_id = wallets.json()[0]["id"]

    cats = await client.get("/categories", headers=headers, params={"type": "expense"})
    assert cats.status_code == 200
    category_id = cats.json()[0]["id"]

    return wallet_id, category_id


async def test_expense_logged_today_appears_in_weekly_and_monthly_summary(
    client, auth_headers
):
    wallet_id, category_id = await _seed_wallet_and_category(client, auth_headers)

    # Mid-day "now" - the date-boundary bug excluded anything after 00:00 today
    # from the upper bound of the range (occurred_at <= today at midnight).
    now = datetime.now(timezone.utc).replace(hour=15, minute=0, second=0, microsecond=0)

    r = await client.post(
        "/expenses",
        headers=auth_headers,
        json={
            "wallet_id": wallet_id,
            "category_id": category_id,
            "amount": 42.0,
            "occurred_at": now.isoformat(),
            "note": "afternoon coffee",
        },
    )
    assert r.status_code == 201, r.text

    weekly = await client.get("/analytics/weekly", headers=auth_headers)
    assert weekly.status_code == 200, weekly.text
    assert weekly.json()["expense"] == 42.0

    monthly = await client.get("/analytics/monthly", headers=auth_headers)
    assert monthly.status_code == 200, monthly.text
    assert monthly.json()["expense"] == 42.0


async def test_dashboard_summary_includes_todays_expense(client, auth_headers):
    wallet_id, category_id = await _seed_wallet_and_category(client, auth_headers)

    now = datetime.now(timezone.utc).replace(hour=20, minute=30, second=0, microsecond=0)

    r = await client.post(
        "/expenses",
        headers=auth_headers,
        json={
            "wallet_id": wallet_id,
            "category_id": category_id,
            "amount": 10.0,
            "occurred_at": now.isoformat(),
        },
    )
    assert r.status_code == 201, r.text

    dashboard = await client.get("/analytics/dashboard", headers=auth_headers)
    assert dashboard.status_code == 200, dashboard.text
    body = dashboard.json()
    assert body["weekly"]["expense"] == 10.0
    assert body["monthly"]["expense"] == 10.0


async def test_income_create_rejects_expense_category(client, auth_headers):
    wallet_id, category_id = await _seed_wallet_and_category(client, auth_headers)

    now = datetime.now(timezone.utc)

    r = await client.post(
        "/income",
        headers=auth_headers,
        json={
            "wallet_id": wallet_id,
            "category_id": category_id,  # this is an EXPENSE category
            "amount": 100.0,
            "occurred_at": now.isoformat(),
        },
    )
    assert r.status_code == 400, r.text


async def test_income_create_rejects_unknown_category(client, auth_headers):
    wallets = await client.get("/wallets", headers=auth_headers)
    wallet_id = wallets.json()[0]["id"]

    now = datetime.now(timezone.utc)

    r = await client.post(
        "/income",
        headers=auth_headers,
        json={
            "wallet_id": wallet_id,
            "category_id": 999999,
            "amount": 100.0,
            "occurred_at": now.isoformat(),
        },
    )
    assert r.status_code == 404, r.text
