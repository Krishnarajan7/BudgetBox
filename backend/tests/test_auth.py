async def test_register_login_refresh(client):
    email = "krish@example.com"
    password = "longenoughpassword"

    # Register
    r = await client.post(
        "/auth/register",
        json={"email": email, "password": password},
    )
    assert r.status_code == 201
    assert r.json()["email"] == email

    # Duplicate registration is rejected
    r = await client.post(
        "/auth/register",
        json={"email": email, "password": password},
    )
    assert r.status_code == 400

    # Login
    r = await client.post(
        "/auth/login",
        json={"email": email, "password": password},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["access_token"]
    assert body["refresh_token"]

    # Refresh
    r = await client.post(
        "/auth/refresh",
        json={"refresh_token": body["refresh_token"]},
    )
    assert r.status_code == 200
    assert r.json()["access_token"]


async def test_login_wrong_password(client):
    await client.post(
        "/auth/register",
        json={"email": "x@y.com", "password": "rightpassword"},
    )
    r = await client.post(
        "/auth/login",
        json={"email": "x@y.com", "password": "wrong"},
    )
    assert r.status_code == 401


async def test_protected_route_requires_token(client):
    r = await client.get("/profile")
    assert r.status_code == 401


async def test_refresh_fails_for_deactivated_user(client, db_session_factory):
    from sqlalchemy import select
    from app.models.user import User

    email = "deactivated@example.com"
    password = "longenoughpassword"

    r = await client.post(
        "/auth/register",
        json={"email": email, "password": password},
    )
    assert r.status_code == 201

    r = await client.post(
        "/auth/login",
        json={"email": email, "password": password},
    )
    assert r.status_code == 200
    refresh_token = r.json()["refresh_token"]

    async with db_session_factory() as session:
        result = await session.execute(select(User).where(User.email == email))
        user = result.scalar_one()
        user.is_active = False
        await session.commit()

    r = await client.post(
        "/auth/refresh",
        json={"refresh_token": refresh_token},
    )
    assert r.status_code == 401
