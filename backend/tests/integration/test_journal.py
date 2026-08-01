"""Journal: one entry per IST day, keyed by the day itself, so PUT is a natural upsert."""

from fastapi.testclient import TestClient


def test_put_creates_then_updates_same_day(client: TestClient) -> None:
    resp = client.put("/v1/journal/2026-07-15", json={"body": "long day", "mood": 3})
    assert resp.status_code == 200, resp.text
    created = resp.json()
    assert created["date"] == "2026-07-15"
    assert created["body"] == "long day"
    assert created["mood"] == 3

    resp = client.put("/v1/journal/2026-07-15", json={"body": "better by evening", "mood": 5})
    assert resp.status_code == 200, resp.text
    updated = resp.json()
    assert updated["body"] == "better by evening"
    assert updated["mood"] == 5
    assert updated["created_at"] == created["created_at"]  # same row, not a second one
    assert updated["updated_at"] > created["updated_at"]

    assert (
        len(
            client.get(
                "/v1/journal", params={"from_day": "2026-07-01", "to_day": "2026-08-01"}
            ).json()
        )
        == 1
    )


def test_put_defaults_body_and_allows_null_mood(client: TestClient) -> None:
    entry = client.put("/v1/journal/2026-07-15", json={}).json()
    assert entry["body"] == ""
    assert entry["mood"] is None


def test_mood_out_of_range_rejected(client: TestClient) -> None:
    assert client.put("/v1/journal/2026-07-15", json={"mood": 0}).status_code == 422
    assert client.put("/v1/journal/2026-07-15", json={"mood": 6}).status_code == 422
    assert client.get("/v1/journal/2026-07-15").status_code == 404  # nothing was written


def test_get_missing_day_is_problem_json(client: TestClient) -> None:
    resp = client.get("/v1/journal/2026-07-15")
    assert resp.status_code == 404
    assert resp.json()["type"] == "urn:budgetbox:problem:not-found"


def test_range_is_newest_first_and_to_day_exclusive(client: TestClient) -> None:
    for day in ("2026-07-09", "2026-07-10", "2026-07-12", "2026-07-15"):
        assert client.put(f"/v1/journal/{day}", json={"body": day}).status_code == 200

    rows = client.get(
        "/v1/journal", params={"from_day": "2026-07-10", "to_day": "2026-07-15"}
    ).json()
    assert [r["date"] for r in rows] == ["2026-07-12", "2026-07-10"]


def test_range_requires_both_bounds(client: TestClient) -> None:
    assert client.get("/v1/journal", params={"from_day": "2026-07-10"}).status_code == 422
    assert client.get("/v1/journal", params={"to_day": "2026-07-15"}).status_code == 422


def test_delete_then_404(client: TestClient) -> None:
    client.put("/v1/journal/2026-07-15", json={"body": "gone soon"})
    assert client.delete("/v1/journal/2026-07-15").status_code == 204
    assert client.get("/v1/journal/2026-07-15").status_code == 404
    assert client.delete("/v1/journal/2026-07-15").status_code == 404


def test_entry_shows_up_in_changes(client: TestClient) -> None:
    client.put("/v1/journal/2026-07-15", json={"body": "hello", "mood": 4})
    changed = client.get("/v1/changes", params={"since": "2020-01-01T00:00:00Z"}).json()["changed"]
    assert changed["journal_entries"] == ["2026-07-15"]
