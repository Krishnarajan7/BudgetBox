"""The server copy made visible, and deliberately destroyable."""

from fastapi.testclient import TestClient

from tests.integration.helpers import make_account, make_txn


def test_stats_counts_the_content(client: TestClient) -> None:
    account_id = make_account(client)
    make_txn(client, account_id)

    got = client.get("/v1/book/stats").json()
    assert got["counts"]["accounts"] == 1
    assert got["counts"]["txns"] == 1
    # Seeded categories are content too, and everything sums up.
    assert got["counts"]["categories"] >= 1
    assert got["total"] == sum(got["counts"].values())
    # The door is never counted as content.
    assert "device_tokens" not in got["counts"]


def test_erase_empties_everything_but_keeps_the_door(client: TestClient) -> None:
    account_id = make_account(client)
    make_txn(client, account_id)
    before = client.get("/v1/book/stats").json()
    assert before["total"] > 0

    wiped = client.post("/v1/book/erase").json()
    assert wiped["erased"] >= before["total"]

    after = client.get("/v1/book/stats").json()
    assert after["total"] == 0
    assert after["counts"] == {}
    # The token still opens the door — an erased book still answers.
    assert client.get("/v1/ping").status_code in (200, 204)
    # And the change log is gone too: no tombstones to resurrect anything.
    changes = client.get("/v1/changes").json()
    assert changes["items"] == []
