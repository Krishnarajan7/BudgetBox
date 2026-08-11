from fastapi import FastAPI
from fastapi.testclient import TestClient

from budgetbox.modules.tokens import service as token_service


def test_healthz_is_open(anon_client: TestClient) -> None:
    resp = anon_client.get("/healthz")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["daily_job_ok"] is None  # no run yet on a fresh database


def test_ping_requires_token(anon_client: TestClient) -> None:
    resp = anon_client.get("/v1/ping")
    assert resp.status_code == 401
    body = resp.json()
    assert resp.headers["content-type"] == "application/problem+json"
    assert body["type"] == "urn:budgetbox:problem:unauthorized"
    assert resp.headers["www-authenticate"] == "Bearer"


def test_bad_token_rejected(anon_client: TestClient) -> None:
    resp = anon_client.get("/v1/ping", headers={"Authorization": "Bearer bbx_wrong"})
    assert resp.status_code == 401


def test_valid_token_accepted(client: TestClient) -> None:
    resp = client.get("/v1/ping")
    assert resp.status_code == 200
    assert resp.json() == {"ok": True}


def test_revoked_token_rejected(app: FastAPI, client: TestClient) -> None:
    with app.state.session_factory() as s:
        (row,) = token_service.list_tokens(s)
        token_service.revoke(s, row.id)
    assert client.get("/v1/ping").status_code == 401


def test_revoke_unknown_token_raises(app: FastAPI) -> None:
    import pytest

    from budgetbox.core.errors import NotFound

    with app.state.session_factory() as s, pytest.raises(NotFound):
        token_service.revoke(s, "no-such-id")


def test_malformed_id_on_write_is_refused_not_a_crash(client: TestClient) -> None:
    """A bad client-minted id is the phone's mistake, not the server falling over.

    This distinction is load-bearing: the app's outbox treats 5xx as "still
    owed, keep retrying" and 4xx as "parked". A 500 here would spin a poisoned
    write forever.
    """
    resp = client.put("/v1/accounts/not-a-uuid", json={"name": "X", "kind": "cash"})
    assert resp.status_code == 422
    assert resp.headers["content-type"] == "application/problem+json"
    assert resp.json()["type"] == "urn:budgetbox:problem:invalid"


def test_malformed_id_on_read_is_a_miss(client: TestClient) -> None:
    assert client.get("/v1/txns/not-a-uuid").status_code == 404
