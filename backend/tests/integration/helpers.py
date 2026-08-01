"""Small builders shared by integration tests. All money in paise."""

from typing import Any

from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id


def make_account(client: TestClient, name: str = "HDFC", kind: str = "bank") -> str:
    account_id = new_id()
    resp = client.put(f"/v1/accounts/{account_id}", json={"name": name, "kind": kind})
    assert resp.status_code == 200, resp.text
    return account_id


def anchor(client: TestClient, account_id: str, balance_paise: int, at: str | None = None) -> None:
    body: dict[str, Any] = {"balance_paise": balance_paise}
    if at is not None:
        body["at"] = at
    resp = client.post(f"/v1/accounts/{account_id}/anchors", json=body)
    assert resp.status_code == 201, resp.text


def expense_category(client: TestClient) -> str:
    cats = client.get("/v1/categories").json()
    return next(c["id"] for c in cats if c["kind"] == "expense")


def make_txn(
    client: TestClient,
    account_id: str,
    *,
    amount: int = 100_00,
    type_: str = "expense",
    at: str = "2026-07-15T10:00:00+05:30",
    title: str = "Chai",
    **extra: Any,
) -> str:
    txn_id = new_id()
    body = {
        "amount_paise": amount,
        "type": type_,
        "account_id": account_id,
        "title": title,
        "at": at,
        **extra,
    }
    resp = client.put(f"/v1/txns/{txn_id}", json=body)
    assert resp.status_code == 200, resp.text
    return txn_id


def balance(client: TestClient, account_id: str) -> int:
    resp = client.get(f"/v1/accounts/{account_id}")
    assert resp.status_code == 200, resp.text
    return resp.json()["balance_paise"]
