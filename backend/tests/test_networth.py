from app.main import app
from app.networth.router import router as networth_router

# The networth module is intentionally self-contained (see task scope) and is
# mounted here at test-collection time rather than in app/main.py.
if not any(getattr(r, "path", None) in ("/assets", "/networth") for r in app.routes):
    app.include_router(networth_router)


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


async def _wallet_id(client, headers):
    wallets = await client.get("/wallets", headers=headers)
    assert wallets.status_code == 200
    return wallets.json()[0]["id"]


async def test_asset_crud(client, auth_headers):
    r = await client.post(
        "/assets",
        headers=auth_headers,
        json={
            "name": "Family Home",
            "kind": "asset",
            "category": "property",
            "value": 250000.00,
            "note": "primary residence",
        },
    )
    assert r.status_code == 201, r.text
    asset = r.json()
    assert asset["name"] == "Family Home"
    assert asset["kind"] == "asset"
    assert asset["category"] == "property"
    assert float(asset["value"]) == 250000.00
    asset_id = asset["id"]

    r = await client.get("/assets", headers=auth_headers)
    assert r.status_code == 200
    assert len(r.json()) == 1

    r = await client.patch(
        f"/assets/{asset_id}",
        headers=auth_headers,
        json={"value": 260000.00, "note": "updated valuation"},
    )
    assert r.status_code == 200, r.text
    assert float(r.json()["value"]) == 260000.00
    assert r.json()["note"] == "updated valuation"

    r = await client.delete(f"/assets/{asset_id}", headers=auth_headers)
    assert r.status_code == 204

    r = await client.get("/assets", headers=auth_headers)
    assert r.status_code == 200
    assert r.json() == []


async def test_asset_value_must_be_positive(client, auth_headers):
    r = await client.post(
        "/assets",
        headers=auth_headers,
        json={
            "name": "Bad Asset",
            "kind": "asset",
            "category": "investment",
            "value": 0,
        },
    )
    assert r.status_code == 422, r.text

    r = await client.post(
        "/assets",
        headers=auth_headers,
        json={
            "name": "Bad Asset",
            "kind": "asset",
            "category": "investment",
            "value": -10,
        },
    )
    assert r.status_code == 422, r.text


async def test_patch_and_delete_nonexistent_asset_returns_404(client, auth_headers):
    r = await client.patch(
        "/assets/999999",
        headers=auth_headers,
        json={"value": 10.0},
    )
    assert r.status_code == 404, r.text

    r = await client.delete("/assets/999999", headers=auth_headers)
    assert r.status_code == 404, r.text


async def test_networth_math(client, auth_headers):
    wallet_id = await _wallet_id(client, auth_headers)

    r = await client.patch(
        f"/wallets/{wallet_id}",
        headers=auth_headers,
        json={"balance": 1000.00},
    )
    assert r.status_code == 200, r.text

    r = await client.post(
        "/assets",
        headers=auth_headers,
        json={
            "name": "Car",
            "kind": "asset",
            "category": "vehicle",
            "value": 500.00,
        },
    )
    assert r.status_code == 201, r.text

    r = await client.post(
        "/assets",
        headers=auth_headers,
        json={
            "name": "Car Loan",
            "kind": "liability",
            "category": "loan",
            "value": 200.00,
        },
    )
    assert r.status_code == 201, r.text

    r = await client.get("/networth", headers=auth_headers)
    assert r.status_code == 200, r.text
    body = r.json()

    assert float(body["wallets_total"]) == 1000.00
    assert float(body["assets_total"]) == 500.00
    assert float(body["liabilities_total"]) == 200.00
    assert float(body["net_worth"]) == 1300.00

    breakdown = body["breakdown"]
    assert len(breakdown["wallets"]) == 1
    assert breakdown["wallets"][0]["id"] == wallet_id
    assert float(breakdown["wallets"][0]["balance"]) == 1000.00

    assert len(breakdown["assets"]) == 1
    assert breakdown["assets"][0]["name"] == "Car"
    assert float(breakdown["assets"][0]["value"]) == 500.00

    assert len(breakdown["liabilities"]) == 1
    assert breakdown["liabilities"][0]["name"] == "Car Loan"
    assert float(breakdown["liabilities"][0]["value"]) == 200.00


async def test_cross_user_isolation(client, auth_headers):
    r = await client.post(
        "/assets",
        headers=auth_headers,
        json={
            "name": "Owner Asset",
            "kind": "asset",
            "category": "investment",
            "value": 100.00,
        },
    )
    assert r.status_code == 201, r.text
    asset_id = r.json()["id"]

    other_headers = await _register_user(client, "networth-other@example.com")

    r = await client.get("/assets", headers=other_headers)
    assert r.status_code == 200
    assert r.json() == []

    r = await client.patch(
        f"/assets/{asset_id}",
        headers=other_headers,
        json={"value": 999.0},
    )
    assert r.status_code == 404, r.text

    r = await client.delete(f"/assets/{asset_id}", headers=other_headers)
    assert r.status_code == 404, r.text

    r = await client.get("/networth", headers=other_headers)
    assert r.status_code == 200
    body = r.json()
    assert float(body["assets_total"]) == 0.0
    assert float(body["net_worth"]) == float(body["wallets_total"])

    r = await client.get("/networth", headers=auth_headers)
    assert r.status_code == 200
    body = r.json()
    assert float(body["assets_total"]) == 100.00
