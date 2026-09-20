"""The diet book on the server: rows round-trip verbatim (nutrients included,
never recomputed), deletions leave a tombstone, and the change feed carries
both — so a reinstall gets the plate back whole."""

from typing import Any

from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id


def put_meal(client: TestClient, meal_id: str, **body: Any) -> Any:
    payload: dict[str, Any] = {
        "date": "2026-09-18",
        "slot": "lunch",
        "name": "Idli",
        "at": "2026-09-18T07:40:00Z",
        **body,
    }
    return client.put(f"/v1/meals/{meal_id}", json=payload)


def test_meal_round_trips_with_its_facts(client: TestClient) -> None:
    meal_id = new_id()
    facts = '{"kcal":102,"pro":3.6,"carb":21.6}'
    resp = put_meal(
        client,
        meal_id,
        food_key="ASC120",
        servings=3,
        facts=facts,
    )
    assert resp.status_code == 200, resp.text
    row = resp.json()
    assert (row["id"], row["slot"], row["name"]) == (meal_id, "lunch", "Idli")
    assert row["servings"] == 3
    # Stored as sent — the server has no catalogue to disagree with.
    assert row["facts"] == facts
    assert client.get("/v1/meals").json() == [row]


def test_a_skip_is_a_row(client: TestClient) -> None:
    resp = put_meal(client, new_id(), slot="breakfast", name="skipped", servings=0, skipped=True)
    assert resp.status_code == 200, resp.text
    assert resp.json()["skipped"] is True


def test_unmeasured_words_need_no_facts(client: TestClient) -> None:
    resp = put_meal(client, new_id(), name="mess lunch")
    assert resp.status_code == 200, resp.text
    assert resp.json()["facts"] is None
    assert resp.json()["food_key"] is None


def test_meals_filter_by_day_range(client: TestClient) -> None:
    for day in ("2026-09-16", "2026-09-18", "2026-09-20"):
        put_meal(client, new_id(), date=day, at=f"{day}T07:40:00Z")
    rows = client.get("/v1/meals", params={"from_day": "2026-09-17", "to_day": "2026-09-19"}).json()
    assert [r["date"] for r in rows] == ["2026-09-18"]


def test_delete_leaves_a_tombstone_in_the_feed(client: TestClient) -> None:
    meal_id = new_id()
    assert put_meal(client, meal_id).status_code == 200
    assert client.delete(f"/v1/meals/{meal_id}").status_code == 204
    assert client.get("/v1/meals").json() == []
    feed = client.get("/v1/changes", params={"after": 0}).json()
    ops = [(c["resource"], c["resource_id"], c["operation"]) for c in feed["items"]]
    assert ("meals", meal_id, "upsert") in ops
    assert ("meals", meal_id, "delete") in ops


def test_a_bad_slot_is_refused(client: TestClient) -> None:
    resp = put_meal(client, new_id(), slot="brunch")
    assert resp.status_code == 422
