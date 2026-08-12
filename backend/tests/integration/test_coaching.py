import time_machine
from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id
from tests.integration.helpers import expense_category, make_account, make_txn


def rule(
    client: TestClient,
    *,
    match: str = "Swiggy Order #123",
    merchant: str = "Swiggy",
    classification: str = "discretionary",
) -> str:
    rule_id = new_id()
    response = client.put(
        f"/v1/coaching/merchant-rules/{rule_id}",
        json={
            "match_text": match,
            "merchant_name": merchant,
            "classification": classification,
            "active": True,
        },
    )
    assert response.status_code == 200, response.text
    return rule_id


@time_machine.travel("2026-08-12T10:00:00+05:30")
def test_merchant_surge_is_explainable_and_deduplicated(client: TestClient) -> None:
    account = make_account(client)
    category = expense_category(client)
    rule_id = rule(client)

    # Same elapsed portion of each previous month: a stable ₹300 baseline.
    for month in (5, 6, 7):
        make_txn(
            client,
            account,
            amount=300_00,
            title="Swiggy Order #123",
            category_id=category,
            at=f"2026-{month:02d}-05T12:00:00+05:30",
        )
    current_ids = [
        make_txn(
            client,
            account,
            amount=400_00,
            title="Swiggy Order #123",
            category_id=category,
            at=f"2026-08-{day:02d}T12:00:00+05:30",
        )
        for day in (2, 6, 10)
    ]

    feed = client.get("/v1/coaching/feed").json()
    surge = next(item for item in feed if item["kind"] == "merchant_surge")
    assert surge["current_paise"] == 1_200_00
    assert surge["baseline_paise"] == 300_00
    assert surge["difference_paise"] == 900_00
    assert surge["evidence"] == {
        "reason": "same_elapsed_days_median",
        "merchant_rule_id": rule_id,
        "merchant_name": "Swiggy",
        "classification": "discretionary",
        "transaction_ids": current_ids,
        "comparison_months": ["2026-07", "2026-06", "2026-05"],
        "count": 3,
        "budget_id": None,
        "budget_name": None,
        "projected_paise": None,
        "limit_paise": None,
    }
    assert "above the median" in surge["message"]
    assert [item["kind"] for item in feed].count("repeated_discretionary") == 0

    again = client.get("/v1/coaching/feed").json()
    assert [item["id"] for item in again] == [item["id"] for item in feed]


@time_machine.travel("2026-08-12T10:00:00+05:30")
def test_user_classification_controls_repeat_coaching(client: TestClient) -> None:
    account = make_account(client)
    category = expense_category(client)
    rule(client, match="Tea Stall", merchant="Tea stall", classification="essential")
    for day in (1, 2, 3, 4):
        make_txn(
            client,
            account,
            amount=100_00,
            title="tea---stall",
            category_id=category,
            at=f"2026-08-{day:02d}T08:00:00+05:30",
        )

    assert client.get("/v1/coaching/feed").json() == []


@time_machine.travel("2026-08-12T10:00:00+05:30")
def test_feedback_does_not_get_undone_by_regeneration(client: TestClient) -> None:
    account = make_account(client)
    category = expense_category(client)
    rule(client, match="Coffee", merchant="Coffee", classification="avoid")
    for day in (1, 2, 3):
        make_txn(
            client,
            account,
            amount=150_00,
            title="Coffee",
            category_id=category,
            at=f"2026-08-{day:02d}T08:00:00+05:30",
        )

    card = client.get("/v1/coaching/feed").json()[0]
    response = client.post(
        f"/v1/coaching/insights/{card['id']}/feedback", json={"action": "dismiss"}
    )
    assert response.status_code == 200
    assert response.json()["status"] == "dismissed"
    assert client.get("/v1/coaching/feed").json() == []


def test_preferences_can_disable_the_book_speaking(client: TestClient) -> None:
    response = client.put(
        "/v1/coaching/preferences",
        json={
            "enabled": False,
            "max_cards": 2,
            "minimum_increase_paise": 50_000,
            "surge_ratio": 2,
            "repeat_count": 4,
        },
    )
    assert response.status_code == 200
    assert client.get("/v1/coaching/preferences").json()["enabled"] is False
    assert client.get("/v1/coaching/feed").json() == []


def test_merchant_rule_can_be_renamed_reclassified_and_paused(client: TestClient) -> None:
    rule_id = rule(client, match="  Tea---STAll  ", merchant="Tea stall")
    listed = client.get("/v1/coaching/merchant-rules").json()
    assert listed[0]["match_text"] == "tea stall"

    changed = client.patch(
        f"/v1/coaching/merchant-rules/{rule_id}",
        json={"merchant_name": "Corner tea", "classification": "avoid", "active": False},
    )
    assert changed.status_code == 200
    assert changed.json()["merchant_name"] == "Corner tea"
    assert changed.json()["classification"] == "avoid"
    assert client.get("/v1/coaching/merchant-rules").json() == []
    assert len(client.get("/v1/coaching/merchant-rules?include_inactive=true").json()) == 1
