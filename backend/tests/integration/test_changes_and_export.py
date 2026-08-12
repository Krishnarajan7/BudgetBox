"""The deletion-aware /changes sync feed and the CSV export."""

import time_machine
from fastapi.testclient import TestClient

from tests.integration.helpers import expense_category, make_account, make_txn


def test_changes_reports_touched_resources(client: TestClient) -> None:
    baseline = client.get("/v1/changes").json()
    assert any(item["resource"] == "categories" for item in baseline["items"])

    mark = baseline["next_cursor"]
    account_id = make_account(client)
    txn_id = make_txn(client, account_id)
    client.put("/v1/settings/salary_day", json={"value": "5"})

    got = client.get("/v1/changes", params={"after": mark}).json()
    touched = {(item["resource"], item["resource_id"], item["operation"]) for item in got["items"]}
    assert ("accounts", account_id, "upsert") in touched
    assert ("txns", txn_id, "upsert") in touched
    assert ("settings", "salary_day", "upsert") in touched
    assert not any(resource == "categories" for resource, _id, _op in touched)


def test_changes_paginates_without_skipping(client: TestClient) -> None:
    first = client.get("/v1/changes", params={"limit": 3}).json()
    assert len(first["items"]) == 3
    assert first["has_more"] is True

    second = client.get("/v1/changes", params={"after": first["next_cursor"], "limit": 3}).json()
    assert second["items"]
    assert second["items"][0]["sequence"] > first["items"][-1]["sequence"]
    assert {item["sequence"] for item in first["items"]}.isdisjoint(
        item["sequence"] for item in second["items"]
    )


def test_changes_keeps_transaction_delete_tombstone(client: TestClient) -> None:
    account_id = make_account(client)
    txn_id = make_txn(client, account_id)
    mark = client.get("/v1/changes").json()["next_cursor"]

    assert client.delete(f"/v1/txns/{txn_id}").status_code == 204

    got = client.get("/v1/changes", params={"after": mark}).json()
    assert {
        (item["resource"], item["resource_id"], item["operation"]) for item in got["items"]
    } >= {("txns", txn_id, "delete")}


def test_changes_validates_cursor_and_limit(client: TestClient) -> None:
    assert client.get("/v1/changes", params={"after": -1}).status_code == 422
    assert client.get("/v1/changes", params={"limit": 501}).status_code == 422


def test_changes_keeps_timestamp_contract_for_older_apps(client: TestClient) -> None:
    account_id = make_account(client)
    got = client.get("/v1/changes", params={"since": "2020-01-01T00:00:00Z"}).json()

    assert account_id in got["changed"]["accounts"]
    assert got["now"] == got["server_time"]


@time_machine.travel("2026-07-15T10:00:00+05:30")
def test_csv_export(client: TestClient) -> None:
    account_id = make_account(client, "HDFC")
    cat = expense_category(client)
    make_txn(
        client,
        account_id,
        amount=123_45,
        title="Chai, extra strong",
        category_id=cat,
        at="2026-07-31T18:00:00+00:00",
    )  # 23:30 IST

    resp = client.get("/v1/export/txns.csv")
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/csv")
    lines = resp.text.strip().splitlines()
    assert lines[0].startswith("date_ist,time_ist,type,amount_inr,amount_paise")
    assert lines[1].startswith(
        '2026-07-31,23:30:00,expense,123.45,12345,"Chai, extra strong",Food & chai,HDFC'
    )
