"""Ledger invariants: derived balances always equal anchor + signed ledger,
transfers move money atomically, PUT is idempotent, undo reverses exactly."""

from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id
from tests.integration.helpers import (
    anchor,
    balance,
    expense_category,
    make_account,
    make_txn,
)


def test_new_account_has_zero_balance_and_no_asof(client: TestClient) -> None:
    account_id = make_account(client)
    resp = client.get(f"/v1/accounts/{account_id}").json()
    assert resp["balance_paise"] == 0
    assert resp["as_of"] is None


def test_anchor_sets_balance_and_asof(client: TestClient) -> None:
    account_id = make_account(client)
    anchor(client, account_id, 50_000_00, at="2026-07-01T09:00:00+05:30")
    resp = client.get(f"/v1/accounts/{account_id}").json()
    assert resp["balance_paise"] == 50_000_00
    assert resp["as_of"] is not None


def test_expense_and_income_move_balance(client: TestClient) -> None:
    account_id = make_account(client)
    anchor(client, account_id, 1000_00, at="2026-07-01T09:00:00+05:30")
    make_txn(client, account_id, amount=250_00, at="2026-07-02T10:00:00+05:30")
    make_txn(
        client,
        account_id,
        amount=100_00,
        type_="income",
        at="2026-07-03T10:00:00+05:30",
        title="Refund",
    )
    assert balance(client, account_id) == 1000_00 - 250_00 + 100_00


def test_txn_before_anchor_does_not_count(client: TestClient) -> None:
    account_id = make_account(client)
    make_txn(client, account_id, amount=999_00, at="2026-06-30T10:00:00+05:30")
    anchor(client, account_id, 1000_00, at="2026-07-01T09:00:00+05:30")
    # The anchor is the user's confirmed truth after that spend.
    assert balance(client, account_id) == 1000_00


def test_transfer_moves_between_accounts(client: TestClient) -> None:
    src = make_account(client, "HDFC")
    dst = make_account(client, "Cash", kind="cash")
    anchor(client, src, 1000_00, at="2026-07-01T09:00:00+05:30")
    make_txn(
        client,
        src,
        amount=300_00,
        type_="transfer",
        to_account_id=dst,
        title="ATM",
        at="2026-07-02T10:00:00+05:30",
    )
    assert balance(client, src) == 700_00
    assert balance(client, dst) == 300_00


def test_transfer_shape_enforced(client: TestClient) -> None:
    src = make_account(client)
    txn_id = new_id()
    base = {"amount_paise": 100, "account_id": src, "title": "x", "at": "2026-07-02T10:00:00+05:30"}
    # transfer without target
    resp = client.put(f"/v1/txns/{txn_id}", json={**base, "type": "transfer"})
    assert resp.status_code == 422
    # transfer to itself
    resp = client.put(f"/v1/txns/{txn_id}", json={**base, "type": "transfer", "to_account_id": src})
    assert resp.status_code == 422
    # expense with a transfer target
    other = make_account(client, "Cash", kind="cash")
    resp = client.put(
        f"/v1/txns/{txn_id}", json={**base, "type": "expense", "to_account_id": other}
    )
    assert resp.status_code == 422


def test_float_paise_rejected(client: TestClient) -> None:
    account_id = make_account(client)
    resp = client.put(
        f"/v1/txns/{new_id()}",
        json={
            "amount_paise": 100.5,
            "type": "expense",
            "account_id": account_id,
            "title": "x",
            "at": "2026-07-02T10:00:00+05:30",
        },
    )
    assert resp.status_code == 422


def test_put_txn_is_idempotent(client: TestClient) -> None:
    account_id = make_account(client)
    anchor(client, account_id, 1000_00, at="2026-07-01T09:00:00+05:30")
    txn_id = new_id()
    body = {
        "amount_paise": 100_00,
        "type": "expense",
        "account_id": account_id,
        "title": "Chai",
        "at": "2026-07-02T10:00:00+05:30",
    }
    for _ in range(3):  # offline queue retries blindly
        resp = client.put(f"/v1/txns/{txn_id}", json=body)
        assert resp.status_code == 200
    assert balance(client, account_id) == 900_00
    assert len(client.get("/v1/activities").json()) == 1  # one create, no phantom edits


def test_edit_via_put_changes_and_logs(client: TestClient) -> None:
    account_id = make_account(client)
    txn_id = make_txn(client, account_id, amount=100_00)
    resp = client.put(
        f"/v1/txns/{txn_id}",
        json={
            "amount_paise": 150_00,
            "type": "expense",
            "account_id": account_id,
            "title": "Chai",
            "at": "2026-07-15T10:00:00+05:30",
        },
    )
    assert resp.status_code == 200
    assert resp.json()["amount_paise"] == 150_00
    actions = [a["action"] for a in client.get("/v1/activities").json()]
    assert actions.count("edited") == 1


def test_delete_then_undo_restores_exactly(client: TestClient) -> None:
    account_id = make_account(client)
    anchor(client, account_id, 1000_00, at="2026-07-01T09:00:00+05:30")
    txn_id = make_txn(
        client, account_id, amount=250_00, title="Groceries", category_id=expense_category(client)
    )
    before = client.get(f"/v1/txns/{txn_id}").json()
    assert balance(client, account_id) == 750_00

    assert client.delete(f"/v1/txns/{txn_id}").status_code == 204
    assert balance(client, account_id) == 1000_00

    activity = next(a for a in client.get("/v1/activities").json() if a["action"] == "deleted")
    resp = client.post(f"/v1/activities/{activity['id']}/undo")
    assert resp.status_code == 200
    assert balance(client, account_id) == 750_00
    after = client.get(f"/v1/txns/{txn_id}").json()
    assert after == before  # byte-identical restore, timestamps included


def test_undo_edit_restores_before_image(client: TestClient) -> None:
    account_id = make_account(client)
    txn_id = make_txn(client, account_id, amount=100_00)
    client.patch(f"/v1/txns/{txn_id}", json={"amount_paise": 999_00})
    activity = next(a for a in client.get("/v1/activities").json() if a["action"] == "edited")
    client.post(f"/v1/activities/{activity['id']}/undo")
    assert client.get(f"/v1/txns/{txn_id}").json()["amount_paise"] == 100_00


def test_undo_create_deletes(client: TestClient) -> None:
    account_id = make_account(client)
    txn_id = make_txn(client, account_id)
    activity = client.get("/v1/activities").json()[0]
    assert activity["action"] == "created"
    client.post(f"/v1/activities/{activity['id']}/undo")
    assert client.get(f"/v1/txns/{txn_id}").status_code == 404
    assert client.get("/v1/activities").json() == []  # undo consumed the row
