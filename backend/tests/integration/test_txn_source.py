"""An expense can say which pot of income it drew on."""

from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id
from tests.integration.helpers import make_account, make_txn


def _income_category(client: TestClient) -> str:
    cats = client.get("/v1/categories").json()
    return next(c["id"] for c in cats if c["kind"] == "income")


def test_expense_carries_its_source_and_reads_it_back(client: TestClient) -> None:
    acct = make_account(client)
    salary = _income_category(client)
    txn_id = make_txn(client, acct, source_id=salary)
    got = client.get(f"/v1/txns/{txn_id}").json()
    assert got["source_id"] == salary


def test_source_must_exist(client: TestClient) -> None:
    acct = make_account(client)
    body = {
        "amount_paise": 5000,
        "type": "expense",
        "account_id": acct,
        "title": "chai",
        "at": "2026-09-27T10:00:00+05:30",
        "source_id": new_id(),
    }
    resp = client.put(f"/v1/txns/{new_id()}", json=body)
    assert resp.status_code == 422, resp.text


def test_only_an_expense_draws_on_a_source(client: TestClient) -> None:
    acct = make_account(client)
    salary = _income_category(client)
    body = {
        "amount_paise": 5000,
        "type": "income",
        "account_id": acct,
        "title": "salary",
        "at": "2026-09-27T10:00:00+05:30",
        "source_id": salary,
    }
    resp = client.put(f"/v1/txns/{new_id()}", json=body)
    assert resp.status_code == 422, resp.text


def test_patch_moves_a_line_to_another_pot(client: TestClient) -> None:
    acct = make_account(client)
    salary = _income_category(client)
    txn_id = make_txn(client, acct)
    resp = client.patch(f"/v1/txns/{txn_id}", json={"source_id": salary})
    assert resp.status_code == 200, resp.text
    assert resp.json()["source_id"] == salary
