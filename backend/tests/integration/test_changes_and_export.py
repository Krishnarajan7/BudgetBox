"""The /changes cache-refresh feed and the CSV export."""

import time_machine
from fastapi.testclient import TestClient

from tests.integration.helpers import expense_category, make_account, make_txn


def test_changes_reports_touched_resources(client: TestClient) -> None:
    baseline = client.get("/v1/changes", params={"since": "2000-01-01T00:00:00Z"}).json()
    assert "categories" in baseline["changed"]  # seeds

    mark = baseline["now"]
    account_id = make_account(client)
    txn_id = make_txn(client, account_id)
    client.put("/v1/settings/salary_day", json={"value": "5"})

    got = client.get("/v1/changes", params={"since": mark}).json()
    assert got["changed"]["accounts"] == [account_id]
    assert got["changed"]["txns"] == [txn_id]
    assert got["changed"]["settings"] == ["salary_day"]
    assert "activities" in got["changed"]  # the create was logged
    assert "categories" not in got["changed"]  # untouched since mark


def test_changes_requires_since(client: TestClient) -> None:
    assert client.get("/v1/changes").status_code == 422


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
