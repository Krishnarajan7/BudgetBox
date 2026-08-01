"""Vault: the server is a dumb blob store. These tests assert it stays that way —
blobs come back byte-identical, and concurrent edits are refused, not merged."""

import base64
from typing import Any

from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id

NONCE = base64.b64encode(b"twelve-bytes").decode()
CIPHER = base64.b64encode(b"\x00\x01gibberish that only the phone can read\xff").decode()


def put(client: TestClient, item_id: str, **body: Any) -> Any:
    payload: dict[str, Any] = {"nonce": NONCE, "cipher": CIPHER, **body}
    return client.put(f"/v1/vault/{item_id}", json=payload)


def test_create_and_read_back_blobs_verbatim(client: TestClient) -> None:
    item_id = new_id()
    resp = put(client, item_id)
    assert resp.status_code == 200, resp.text
    created = resp.json()
    assert (created["id"], created["nonce"], created["cipher"]) == (item_id, NONCE, CIPHER)

    listed = client.get("/v1/vault").json()
    assert len(listed) == 1
    assert listed[0] == created  # stamps included, nothing rewritten server-side


def test_overwrite_without_precondition_wins(client: TestClient) -> None:
    item_id = new_id()
    first = put(client, item_id).json()
    newer = base64.b64encode(b"rotated secret").decode()

    resp = put(client, item_id, cipher=newer)
    assert resp.status_code == 200, resp.text
    after = resp.json()
    assert after["cipher"] == newer
    assert after["created_at"] == first["created_at"]  # same row, replaced in place
    assert after["updated_at"] > first["updated_at"]


def test_stale_expected_updated_at_conflicts(client: TestClient) -> None:
    item_id = new_id()
    stale = put(client, item_id).json()["updated_at"]
    put(client, item_id, cipher=base64.b64encode(b"someone else edited").decode())

    resp = put(client, item_id, cipher=CIPHER, expected_updated_at=stale)
    assert resp.status_code == 409, resp.text
    body = resp.json()
    assert body["type"] == "urn:budgetbox:problem:conflict"
    assert body["detail"] == "vault item changed since you loaded it"
    # The refused write left the stored blob alone.
    assert client.get("/v1/vault").json()[0]["cipher"] != CIPHER


def test_matching_expected_updated_at_succeeds(client: TestClient) -> None:
    item_id = new_id()
    current = put(client, item_id).json()["updated_at"]
    rotated = base64.b64encode(b"rotated with a precondition").decode()

    resp = put(client, item_id, cipher=rotated, expected_updated_at=current)
    assert resp.status_code == 200, resp.text
    assert resp.json()["cipher"] == rotated


def test_precondition_ignored_when_the_item_is_new(client: TestClient) -> None:
    """A never-seen id can't be stale — creating with a precondition is a create."""
    resp = put(client, new_id(), expected_updated_at="2026-07-01T00:00:00+00:00")
    assert resp.status_code == 200, resp.text


def test_non_base64_rejected(client: TestClient) -> None:
    for field in ("nonce", "cipher"):
        resp = put(client, new_id(), **{field: "not base64!!"})
        assert resp.status_code == 422, resp.text
        assert resp.json()["type"] == "urn:budgetbox:problem:validation-error"
        assert resp.json()["errors"][0]["loc"][-1] == field


def test_oversize_cipher_rejected(client: TestClient) -> None:
    huge = base64.b64encode(b"x" * 70_000).decode()
    assert len(huge) > 90_000
    resp = put(client, new_id(), cipher=huge)
    assert resp.status_code == 422, resp.text

    fits = base64.b64encode(b"x" * 60_000).decode()
    assert len(fits) < 90_000
    assert put(client, new_id(), cipher=fits).status_code == 200


def test_delete_is_hard_and_then_404(client: TestClient) -> None:
    item_id = new_id()
    put(client, item_id)
    assert client.delete(f"/v1/vault/{item_id}").status_code == 204
    assert client.get("/v1/vault").json() == []

    resp = client.delete(f"/v1/vault/{item_id}")
    assert resp.status_code == 404
    assert resp.json()["type"] == "urn:budgetbox:problem:not-found"


def test_vault_items_show_up_in_changes(client: TestClient) -> None:
    item_id = new_id()
    put(client, item_id)
    changed = client.get("/v1/changes", params={"since": "2020-01-01T00:00:00+00:00"}).json()
    assert changed["changed"]["vault_items"] == [item_id]
