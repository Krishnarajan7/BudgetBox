"""Golden month: a hand-built July 2026 with hand-computed expectations for the
month story — the regression net for the insights math."""

import time_machine
from fastapi.testclient import TestClient

from tests.integration.helpers import expense_category, make_account, make_txn


def _income_category(client: TestClient) -> str:
    cats = client.get("/v1/categories").json()
    return next(c["id"] for c in cats if c["name"] == "Salary")


@time_machine.travel("2026-08-02T10:00:00+05:30")
def test_july_2026_month_story(client: TestClient) -> None:
    account_id = make_account(client)
    food = expense_category(client)  # "Food & chai"
    salary = _income_category(client)

    make_txn(
        client,
        account_id,
        amount=60_000_00,
        type_="income",
        title="Salary",
        at="2026-07-01T09:00:00+05:30",
        category_id=salary,
    )
    # Food: 3 chai + one big dinner = 1500 + 2500 total food 4000... hand math below.
    make_txn(
        client,
        account_id,
        amount=500_00,
        title="Chai",
        category_id=food,
        at="2026-07-02T08:00:00+05:30",
    )
    make_txn(
        client,
        account_id,
        amount=1_000_00,
        title="Lunch",
        category_id=food,
        at="2026-07-02T13:00:00+05:30",
    )
    make_txn(
        client,
        account_id,
        amount=2_500_00,
        title="Dinner out",
        category_id=food,
        at="2026-07-18T20:00:00+05:30",
    )
    make_txn(
        client, account_id, amount=3_000_00, title="Auto pass", at="2026-07-10T09:00:00+05:30"
    )  # uncategorised
    # June spend for the verdict:
    make_txn(
        client, account_id, amount=10_000_00, title="June groceries", at="2026-06-15T10:00:00+05:30"
    )

    got = client.get("/v1/insights/month-story", params={"month": "2026-07"}).json()

    assert got["month"] == "2026-07"
    assert got["label"] == "July 2026"
    assert got["spent_paise"] == 7_000_00  # 500+1000+2500+3000
    assert got["income_paise"] == 60_000_00
    assert got["kept_paise"] == 53_000_00
    assert got["top_category"] == {"name": "Food & chai", "paise": 4_000_00}
    assert got["biggest_day"] == {"date": "2026-07-10", "paise": 3_000_00}
    # 31 days, spending on 3 of them.
    assert got["quiet_days"] == 28
    assert got["flows"] == [
        {"name": "Salary", "paise": 60_000_00, "is_income": True},
        {"name": "Food & chai", "paise": 4_000_00, "is_income": False},
        {"name": "Uncategorised", "paise": 3_000_00, "is_income": False},
        {"name": "Kept", "paise": 53_000_00, "is_income": False},
    ]
    # July spent 7000 vs June 10000: spent less.
    assert got["vs_last_month"] == {"spent_delta_paise": -3_000_00, "verdict": "less"}


@time_machine.travel("2026-07-10T15:00:00+05:30")
def test_current_month_quiet_days_stop_at_today(client: TestClient) -> None:
    account_id = make_account(client)
    make_txn(client, account_id, amount=100_00, at="2026-07-05T10:00:00+05:30")
    got = client.get("/v1/insights/month-story").json()
    # 10 elapsed days, one with spending.
    assert got["quiet_days"] == 9
