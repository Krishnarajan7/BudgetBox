"""The work book on the server: a client, a project whose quote moves, and
the ledger lines the project claims. Everything round-trips verbatim; the
phone owns the arithmetic."""

from typing import Any

from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id
from tests.integration.helpers import make_account, make_txn


def put_client(client: TestClient, client_id: str, **body: Any) -> Any:
    return client.put(f"/v1/clients/{client_id}", json={"name": "Ghouthia", **body})


def put_project(client: TestClient, project_id: str, client_id: str, **body: Any) -> Any:
    payload: dict[str, Any] = {
        "client_id": client_id,
        "name": "Website",
        "kind": "one_time",
        "quote_paise": 5_000_000,
        "started_at": "2026-09-01T04:30:00Z",
        **body,
    }
    return client.put(f"/v1/projects/{project_id}", json=payload)


def test_client_project_and_quote_history_round_trip(client: TestClient) -> None:
    cid, pid = new_id(), new_id()
    assert put_client(client, cid).status_code == 200
    assert put_project(client, pid, cid).status_code == 200

    # The quote moved: 50k, then 40k when the scope shrank.
    for paise, reason, at in (
        (5_000_000, "first quote", "2026-09-01T04:30:00Z"),
        (4_000_000, "scope cut", "2026-09-12T04:30:00Z"),
    ):
        resp = client.put(
            f"/v1/quotes/{new_id()}",
            json={"project_id": pid, "paise": paise, "reason": reason, "at": at},
        )
        assert resp.status_code == 200, resp.text
    assert put_project(client, pid, cid, quote_paise=4_000_000).status_code == 200

    quotes = client.get("/v1/quotes").json()
    assert [q["paise"] for q in quotes] == [5_000_000, 4_000_000]
    assert client.get("/v1/projects").json()[0]["quote_paise"] == 4_000_000


def test_links_claim_real_ledger_lines(client: TestClient) -> None:
    cid, pid = new_id(), new_id()
    put_client(client, cid)
    put_project(client, pid, cid, kind="monthly", billing_day=5, quote_paise=1_000_000)
    account = make_account(client)
    received = make_txn(client, account, amount=1_000_000, type_="income", title="Ghouthia Sept")
    cost = make_txn(client, account, amount=106_000, title="domain renewal")
    for txn, role, billable in ((received, "received", False), (cost, "cost", True)):
        resp = client.put(
            f"/v1/project-links/{new_id()}",
            json={
                "project_id": pid,
                "txn_id": txn,
                "role": role,
                "billable": billable,
                "at": "2026-09-06T04:30:00Z",
            },
        )
        assert resp.status_code == 200, resp.text
    links = client.get("/v1/project-links").json()
    assert {link["role"] for link in links} == {"received", "cost"}
    assert next(link for link in links if link["role"] == "cost")["billable"] is True


def test_a_link_to_nothing_is_refused(client: TestClient) -> None:
    cid, pid = new_id(), new_id()
    put_client(client, cid)
    put_project(client, pid, cid)
    resp = client.put(
        f"/v1/project-links/{new_id()}",
        json={"project_id": pid, "txn_id": new_id(), "role": "cost", "at": "2026-09-06T04:30:00Z"},
    )
    assert resp.status_code == 404


def test_deleting_a_project_takes_its_quotes_and_links(client: TestClient) -> None:
    cid, pid = new_id(), new_id()
    put_client(client, cid)
    put_project(client, pid, cid)
    client.put(
        f"/v1/quotes/{new_id()}",
        json={"project_id": pid, "paise": 5_000_000, "at": "2026-09-01T04:30:00Z"},
    )
    assert client.delete(f"/v1/projects/{pid}").status_code == 204
    assert client.get("/v1/projects").json() == []
    assert client.get("/v1/quotes").json() == []
    feed = client.get("/v1/changes", params={"after": 0}).json()
    ops = {(c["resource"], c["operation"]) for c in feed["items"]}
    assert ("projects", "delete") in ops
    assert ("quote_revisions", "delete") in ops
