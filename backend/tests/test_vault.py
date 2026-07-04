import base64

from app.main import app as _fastapi_app
from app.vault.router import router as _vault_router

# The vault router is owned by this module in isolation and is registered in
# app/main.py by a separate concurrent change outside this module's scope.
# Register it here defensively (idempotently) so this test file can exercise
# the endpoints even if that wiring hasn't landed yet; harmless no-op once it
# has (FastAPI dedupes by path+methods for routing purposes here since it's
# the exact same router object either way).
if not any(getattr(r, "path", "").startswith("/vault") for r in _fastapi_app.routes):
    _fastapi_app.include_router(_vault_router)


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


def _setup_payload():
    return {
        "kdf_salt": base64.b64encode(b"some-random-salt").decode(),
        "kdf_iterations": 210_000,
        "canary_ct": base64.b64encode(b"encrypted-canary-bytes").decode(),
        "canary_iv": base64.b64encode(b"nonce12b").decode(),
    }


async def test_config_missing_before_setup(client, auth_headers):
    r = await client.get("/vault/config", headers=auth_headers)
    assert r.status_code == 404, r.text
    assert r.json()["error"]["code"] == "VAULT_NOT_SETUP"


async def test_setup_then_config_roundtrip(client, auth_headers):
    payload = _setup_payload()

    r = await client.post("/vault/setup", headers=auth_headers, json=payload)
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["kdf_salt"] == payload["kdf_salt"]
    assert body["kdf_iterations"] == payload["kdf_iterations"]
    assert body["canary_ct"] == payload["canary_ct"]
    assert body["canary_iv"] == payload["canary_iv"]
    assert "id" in body and "created_at" in body

    r = await client.get("/vault/config", headers=auth_headers)
    assert r.status_code == 200, r.text
    body2 = r.json()
    assert body2["kdf_salt"] == payload["kdf_salt"]
    assert body2["canary_ct"] == payload["canary_ct"]


async def test_double_setup_returns_409(client, auth_headers):
    payload = _setup_payload()

    r = await client.post("/vault/setup", headers=auth_headers, json=payload)
    assert r.status_code == 201, r.text

    r = await client.post("/vault/setup", headers=auth_headers, json=payload)
    assert r.status_code == 409, r.text
    assert r.json()["error"]["code"] == "VAULT_ALREADY_SETUP"


async def test_item_before_setup_returns_400(client, auth_headers):
    r = await client.post(
        "/vault/items",
        headers=auth_headers,
        json={
            "item_type": "note",
            "title_ct": "ct-title",
            "payload_ct": "ct-payload",
            "iv": "ct-iv",
        },
    )
    assert r.status_code == 400, r.text
    assert r.json()["error"]["code"] == "VAULT_NOT_SETUP"


async def test_item_crud_with_base64_file(client, auth_headers):
    setup = await client.post("/vault/setup", headers=auth_headers, json=_setup_payload())
    assert setup.status_code == 201, setup.text

    file_bytes = b"encrypted-file-bytes-blob"
    file_data_b64 = base64.b64encode(file_bytes).decode()

    create = await client.post(
        "/vault/items",
        headers=auth_headers,
        json={
            "item_type": "file",
            "title_ct": "ct-title",
            "payload_ct": "ct-payload-json",
            "iv": "ct-iv",
            "file_data_b64": file_data_b64,
            "file_iv": "ct-file-iv",
        },
    )
    assert create.status_code == 201, create.text
    item = create.json()
    item_id = item["id"]
    assert item["has_file"] is True
    assert item["file_size"] == len(file_bytes)
    assert item["file_data_b64"] == file_data_b64
    assert item["file_iv"] == "ct-file-iv"

    # GET single item returns full file data
    r = await client.get(f"/vault/items/{item_id}", headers=auth_headers)
    assert r.status_code == 200, r.text
    assert r.json()["file_data_b64"] == file_data_b64

    # PATCH updates ciphertext fields
    patch = await client.patch(
        f"/vault/items/{item_id}",
        headers=auth_headers,
        json={"title_ct": "new-ct-title", "payload_ct": "new-ct-payload"},
    )
    assert patch.status_code == 200, patch.text
    assert patch.json()["title_ct"] == "new-ct-title"
    assert patch.json()["payload_ct"] == "new-ct-payload"
    # file untouched
    assert patch.json()["file_data_b64"] == file_data_b64

    # DELETE removes it
    d = await client.delete(f"/vault/items/{item_id}", headers=auth_headers)
    assert d.status_code == 204, d.text

    r = await client.get(f"/vault/items/{item_id}", headers=auth_headers)
    assert r.status_code == 404, r.text


async def test_list_omits_file_data(client, auth_headers):
    setup = await client.post("/vault/setup", headers=auth_headers, json=_setup_payload())
    assert setup.status_code == 201, setup.text

    file_bytes = b"another-encrypted-blob"
    file_data_b64 = base64.b64encode(file_bytes).decode()

    create = await client.post(
        "/vault/items",
        headers=auth_headers,
        json={
            "item_type": "file",
            "title_ct": "ct-title-2",
            "payload_ct": "ct-payload-2",
            "iv": "ct-iv-2",
            "file_data_b64": file_data_b64,
            "file_iv": "ct-file-iv-2",
        },
    )
    assert create.status_code == 201, create.text

    r = await client.get("/vault/items", headers=auth_headers)
    assert r.status_code == 200, r.text
    items = r.json()
    assert len(items) >= 1
    for entry in items:
        assert "file_data_b64" not in entry
        if entry["item_type"] == "file":
            assert entry["has_file"] is True
            assert entry["file_size"] == len(file_bytes)

    # filter by item_type
    r = await client.get("/vault/items", headers=auth_headers, params={"item_type": "note"})
    assert r.status_code == 200, r.text
    assert all(entry["item_type"] == "note" for entry in r.json())


async def test_cross_user_isolation(client, auth_headers):
    owner = auth_headers
    intruder = await _register_and_login(client, "vault-intruder@example.com")

    setup = await client.post("/vault/setup", headers=owner, json=_setup_payload())
    assert setup.status_code == 201, setup.text

    create = await client.post(
        "/vault/items",
        headers=owner,
        json={
            "item_type": "credential",
            "title_ct": "ct-title-3",
            "payload_ct": "ct-payload-3",
            "iv": "ct-iv-3",
        },
    )
    assert create.status_code == 201, create.text
    item_id = create.json()["id"]

    # Intruder has no vault config of their own
    r = await client.get("/vault/config", headers=intruder)
    assert r.status_code == 404, r.text
    assert r.json()["error"]["code"] == "VAULT_NOT_SETUP"

    # Intruder cannot read owner's item
    r = await client.get(f"/vault/items/{item_id}", headers=intruder)
    assert r.status_code == 404, r.text

    # Intruder cannot update or delete owner's item
    r = await client.patch(
        f"/vault/items/{item_id}", headers=intruder, json={"title_ct": "hijacked"}
    )
    assert r.status_code == 404, r.text

    r = await client.delete(f"/vault/items/{item_id}", headers=intruder)
    assert r.status_code == 404, r.text

    # Owner's item is still intact
    r = await client.get(f"/vault/items/{item_id}", headers=owner)
    assert r.status_code == 200, r.text


async def test_oversize_file_rejected(client, auth_headers):
    setup = await client.post("/vault/setup", headers=auth_headers, json=_setup_payload())
    assert setup.status_code == 201, setup.text

    too_big = b"a" * (10 * 1024 * 1024 + 1)
    file_data_b64 = base64.b64encode(too_big).decode()

    r = await client.post(
        "/vault/items",
        headers=auth_headers,
        json={
            "item_type": "file",
            "title_ct": "ct-title",
            "payload_ct": "ct-payload",
            "iv": "ct-iv",
            "file_data_b64": file_data_b64,
            "file_iv": "ct-file-iv",
        },
    )
    assert r.status_code == 400, r.text
    assert r.json()["error"]["code"] == "VAULT_FILE_TOO_LARGE"


async def test_delete_whole_vault_removes_config_and_items(client, auth_headers):
    setup = await client.post("/vault/setup", headers=auth_headers, json=_setup_payload())
    assert setup.status_code == 201, setup.text

    create = await client.post(
        "/vault/items",
        headers=auth_headers,
        json={
            "item_type": "note",
            "title_ct": "ct-title-4",
            "payload_ct": "ct-payload-4",
            "iv": "ct-iv-4",
        },
    )
    assert create.status_code == 201, create.text
    item_id = create.json()["id"]

    r = await client.delete("/vault", headers=auth_headers)
    assert r.status_code == 204, r.text

    r = await client.get("/vault/config", headers=auth_headers)
    assert r.status_code == 404, r.text

    r = await client.get(f"/vault/items/{item_id}", headers=auth_headers)
    assert r.status_code == 404, r.text
