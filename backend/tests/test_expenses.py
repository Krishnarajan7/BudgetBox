from datetime import datetime, timezone, date, timedelta


async def _seed_wallet_and_category(client, headers):
    wallets = await client.get("/wallets", headers=headers)
    assert wallets.status_code == 200
    wallet_id = wallets.json()[0]["id"]

    cats = await client.get("/categories", headers=headers, params={"type": "expense"})
    assert cats.status_code == 200
    category_id = cats.json()[0]["id"]

    return wallet_id, category_id


async def _register_user(client, email):
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


async def test_expense_crud_updates_wallet_balance(client, auth_headers):
    wallet_id, category_id = await _seed_wallet_and_category(client, auth_headers)

    # Wallet starts at 0
    w = await client.get("/wallets", headers=auth_headers)
    assert float(w.json()[0]["balance"]) == 0.0

    # Create expense
    r = await client.post(
        "/expenses",
        headers=auth_headers,
        json={
            "wallet_id": wallet_id,
            "category_id": category_id,
            "amount": 100.0,
            "occurred_at": datetime.now(timezone.utc).isoformat(),
            "note": "lunch",
        },
    )
    assert r.status_code == 201, r.text
    expense_id = r.json()["id"]

    w = await client.get("/wallets", headers=auth_headers)
    assert float(w.json()[0]["balance"]) == -100.0

    # List
    r = await client.get("/expenses", headers=auth_headers)
    assert r.status_code == 200
    assert len(r.json()) == 1

    # Update amount → 150 (wallet should reflect delta of -50)
    r = await client.patch(
        f"/expenses/{expense_id}",
        headers=auth_headers,
        json={"amount": 150.0},
    )
    assert r.status_code == 200

    w = await client.get("/wallets", headers=auth_headers)
    assert float(w.json()[0]["balance"]) == -150.0

    # Delete restores balance
    r = await client.delete(f"/expenses/{expense_id}", headers=auth_headers)
    assert r.status_code == 204

    w = await client.get("/wallets", headers=auth_headers)
    assert float(w.json()[0]["balance"]) == 0.0


async def test_unified_transactions_endpoint(client, auth_headers):
    wallet_id, category_id = await _seed_wallet_and_category(client, auth_headers)

    income_cats = await client.get(
        "/categories", headers=auth_headers, params={"type": "income"}
    )
    assert income_cats.status_code == 200
    income_category_id = income_cats.json()[0]["id"]

    now = datetime.now(timezone.utc).isoformat()

    # Create one income + one expense
    await client.post(
        "/income",
        headers=auth_headers,
        json={
            "wallet_id": wallet_id,
            "category_id": income_category_id,
            "amount": 500.0,
            "occurred_at": now,
        },
    )
    await client.post(
        "/expenses",
        headers=auth_headers,
        json={
            "wallet_id": wallet_id,
            "category_id": category_id,
            "amount": 200.0,
            "occurred_at": now,
        },
    )

    r = await client.get("/transactions", headers=auth_headers)
    assert r.status_code == 200
    body = r.json()
    assert body["total"] == 2
    assert len(body["items"]) == 2

    r = await client.get(
        "/transactions", headers=auth_headers, params={"type": "income"}
    )
    assert r.status_code == 200
    assert r.json()["total"] == 1


async def test_expense_filters_actually_filter(client, auth_headers):
    wallet_id, category_id = await _seed_wallet_and_category(client, auth_headers)

    # A second wallet and a second expense category, to filter against.
    w2 = await client.post(
        "/wallets", headers=auth_headers, json={"name": "Second Wallet"}
    )
    assert w2.status_code == 201, w2.text
    wallet_id_2 = w2.json()["id"]

    cats = await client.get(
        "/categories", headers=auth_headers, params={"type": "expense"}
    )
    expense_categories = cats.json()
    category_id_2 = (
        expense_categories[1]["id"]
        if len(expense_categories) > 1
        else category_id
    )

    today = date.today()
    in_range_dt = datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc) + timedelta(hours=23, minutes=59)
    out_of_range_dt = datetime.combine(
        today + timedelta(days=5), datetime.min.time(), tzinfo=timezone.utc
    )

    # Expense inside the filtered window, on wallet 1 / category 1.
    r = await client.post(
        "/expenses",
        headers=auth_headers,
        json={
            "wallet_id": wallet_id,
            "category_id": category_id,
            "amount": 10.0,
            "occurred_at": in_range_dt.isoformat(),
            "note": "in-range",
        },
    )
    assert r.status_code == 201, r.text
    in_range_id = r.json()["id"]

    # Expense outside the date window entirely.
    r = await client.post(
        "/expenses",
        headers=auth_headers,
        json={
            "wallet_id": wallet_id,
            "category_id": category_id,
            "amount": 20.0,
            "occurred_at": out_of_range_dt.isoformat(),
            "note": "out-of-range",
        },
    )
    assert r.status_code == 201, r.text

    # Expense in-range but on the second wallet.
    r = await client.post(
        "/expenses",
        headers=auth_headers,
        json={
            "wallet_id": wallet_id_2,
            "category_id": category_id,
            "amount": 30.0,
            "occurred_at": in_range_dt.isoformat(),
            "note": "other-wallet",
        },
    )
    assert r.status_code == 201, r.text

    # Date filter: end_date == today must include the 23:59 expense (exclusive
    # upper bound bug would previously drop everything after 00:00).
    r = await client.get(
        "/expenses",
        headers=auth_headers,
        params={"start_date": today.isoformat(), "end_date": today.isoformat()},
    )
    assert r.status_code == 200
    ids = {e["id"] for e in r.json()}
    assert in_range_id in ids
    assert all(e["note"] != "out-of-range" for e in r.json())

    # Wallet filter.
    r = await client.get(
        "/expenses", headers=auth_headers, params={"wallet_id": wallet_id}
    )
    assert r.status_code == 200
    assert all(e["wallet_id"] == wallet_id for e in r.json())
    assert any(e["note"] == "out-of-range" for e in r.json())
    assert all(e["note"] != "other-wallet" for e in r.json())

    r = await client.get(
        "/expenses", headers=auth_headers, params={"wallet_id": wallet_id_2}
    )
    assert r.status_code == 200
    notes = [e["note"] for e in r.json()]
    assert notes == ["other-wallet"]

    # Category filter (only meaningful if a distinct second category exists).
    if category_id_2 != category_id:
        r = await client.get(
            "/expenses", headers=auth_headers, params={"category_id": category_id}
        )
        assert r.status_code == 200
        assert all(e["category_id"] == category_id for e in r.json())


async def test_patch_nonexistent_expense_returns_404(client, auth_headers):
    r = await client.patch(
        "/expenses/999999",
        headers=auth_headers,
        json={"amount": 10.0},
    )
    assert r.status_code == 404, r.text


async def test_delete_nonexistent_expense_returns_404(client, auth_headers):
    r = await client.delete("/expenses/999999", headers=auth_headers)
    assert r.status_code == 404, r.text


async def test_patch_other_users_expense_returns_404(client, auth_headers):
    wallet_id, category_id = await _seed_wallet_and_category(client, auth_headers)

    r = await client.post(
        "/expenses",
        headers=auth_headers,
        json={
            "wallet_id": wallet_id,
            "category_id": category_id,
            "amount": 10.0,
            "occurred_at": datetime.now(timezone.utc).isoformat(),
        },
    )
    assert r.status_code == 201, r.text
    expense_id = r.json()["id"]

    other_headers = await _register_user(client, "other-user@example.com")

    r = await client.patch(
        f"/expenses/{expense_id}",
        headers=other_headers,
        json={"amount": 999.0},
    )
    assert r.status_code == 404, r.text

    r = await client.delete(f"/expenses/{expense_id}", headers=other_headers)
    assert r.status_code == 404, r.text


async def test_expense_rejects_another_users_category(client, auth_headers):
    wallet_id, _ = await _seed_wallet_and_category(client, auth_headers)

    other_headers = await _register_user(client, "owner-of-category@example.com")
    other_cats = await client.get(
        "/categories", headers=other_headers, params={"type": "expense"}
    )
    assert other_cats.status_code == 200
    other_category_id = other_cats.json()[0]["id"]

    r = await client.post(
        "/expenses",
        headers=auth_headers,
        json={
            "wallet_id": wallet_id,
            "category_id": other_category_id,
            "amount": 10.0,
            "occurred_at": datetime.now(timezone.utc).isoformat(),
        },
    )
    assert r.status_code in (400, 404), r.text


async def test_expense_update_rejects_another_users_category(client, auth_headers):
    wallet_id, category_id = await _seed_wallet_and_category(client, auth_headers)

    r = await client.post(
        "/expenses",
        headers=auth_headers,
        json={
            "wallet_id": wallet_id,
            "category_id": category_id,
            "amount": 10.0,
            "occurred_at": datetime.now(timezone.utc).isoformat(),
        },
    )
    assert r.status_code == 201, r.text
    expense_id = r.json()["id"]

    other_headers = await _register_user(client, "owner-of-category-2@example.com")
    other_cats = await client.get(
        "/categories", headers=other_headers, params={"type": "expense"}
    )
    assert other_cats.status_code == 200
    other_category_id = other_cats.json()[0]["id"]

    r = await client.patch(
        f"/expenses/{expense_id}",
        headers=auth_headers,
        json={"category_id": other_category_id},
    )
    assert r.status_code in (400, 404), r.text
