"""Net worth: live current figure, snapshot backfill exactness, series ranges,
per-account sparklines, and convergence after backdated edits."""

import time_machine
from fastapi import FastAPI
from fastapi.testclient import TestClient

from budgetbox.jobs.daily import run_daily
from tests.integration.helpers import anchor, make_account, make_txn


@time_machine.travel("2026-07-10T10:00:00+05:30")
def test_current_splits_assets_and_liabilities(client: TestClient) -> None:
    bank = make_account(client, "HDFC")
    card = make_account(client, "Amex", kind="card")
    anchor(client, bank, 50_000_00, at="2026-07-01T09:00:00+05:30")
    anchor(client, card, 12_000_00, at="2026-07-01T09:00:00+05:30")  # owed
    got = client.get("/v1/networth/current").json()
    assert got["assets_paise"] == 50_000_00
    assert got["liabilities_paise"] == 12_000_00
    assert got["net_worth_paise"] == 38_000_00
    assert got["day"] == "2026-07-10"


@time_machine.travel("2026-07-10T10:00:00+05:30")
def test_snapshot_backfill_and_series(app: FastAPI, client: TestClient) -> None:
    bank = make_account(client, "HDFC")
    anchor(client, bank, 10_000_00, at="2026-07-01T09:00:00+05:30")
    make_txn(client, bank, amount=1_000_00, at="2026-07-03T12:00:00+05:30")
    make_txn(client, bank, amount=2_000_00, at="2026-07-07T12:00:00+05:30")

    assert run_daily(app.state.session_factory) is True
    got = client.get("/v1/networth/series", params={"range": "1m"}).json()
    values = {p["date"]: p["value_paise"] for p in got["points"]}
    assert values["2026-07-01"] == 10_000_00
    assert values["2026-07-02"] == 10_000_00
    assert values["2026-07-03"] == 9_000_00
    assert values["2026-07-06"] == 9_000_00
    assert values["2026-07-07"] == 7_000_00
    assert values["2026-07-10"] == 7_000_00
    assert min(values) == "2026-07-01" and max(values) == "2026-07-10"


@time_machine.travel("2026-07-10T10:00:00+05:30")
def test_backdated_edit_converges_on_next_run(app: FastAPI, client: TestClient) -> None:
    bank = make_account(client, "HDFC")
    anchor(client, bank, 10_000_00, at="2026-07-01T09:00:00+05:30")
    run_daily(app.state.session_factory)
    # A forgotten expense from the 2nd lands late.
    make_txn(client, bank, amount=500_00, at="2026-07-02T12:00:00+05:30", title="Forgot")
    run_daily(app.state.session_factory)
    got = client.get("/v1/networth/series", params={"range": "1m"}).json()
    values = {p["date"]: p["value_paise"] for p in got["points"]}
    assert values["2026-07-02"] == 9_500_00  # snapshot was re-derived, not stale


@time_machine.travel("2026-07-10T10:00:00+05:30")
def test_per_account_sparkline_series(app: FastAPI, client: TestClient) -> None:
    bank = make_account(client, "HDFC")
    cash = make_account(client, "Cash", kind="cash")
    anchor(client, bank, 10_000_00, at="2026-07-05T09:00:00+05:30")
    anchor(client, cash, 2_000_00, at="2026-07-05T09:00:00+05:30")
    run_daily(app.state.session_factory)
    got = client.get("/v1/networth/series", params={"range": "1m", "account_id": cash}).json()
    assert {p["value_paise"] for p in got["points"]} == {2_000_00}


def test_series_empty_before_any_snapshot(client: TestClient) -> None:
    got = client.get("/v1/networth/series").json()
    assert got["points"] == []


@time_machine.travel("2026-07-10T10:00:00+05:30")
def test_series_reports_the_travel_and_the_high_water_mark(
    app: FastAPI, client: TestClient
) -> None:
    bank = make_account(client, "HDFC")
    anchor(client, bank, 10_000_00, at="2026-07-01T09:00:00+05:30")
    make_txn(
        client,
        bank,
        amount=5_000_00,
        type_="income",
        at="2026-07-03T12:00:00+05:30",
        title="Freelance",
    )
    make_txn(client, bank, amount=6_000_00, at="2026-07-07T12:00:00+05:30")
    run_daily(app.state.session_factory)

    got = client.get("/v1/networth/series", params={"range": "1m"}).json()
    assert got["first_paise"] == 10_000_00
    assert got["last_paise"] == 9_000_00
    assert got["delta_paise"] == -1_000_00
    assert (got["peak_paise"], got["peak_date"]) == (15_000_00, "2026-07-03")
    assert (got["all_time_peak_paise"], got["all_time_peak_date"]) == (15_000_00, "2026-07-03")


@time_machine.travel("2026-08-20T10:00:00+05:30")
def test_a_short_range_never_hides_the_true_high_water_mark(
    app: FastAPI, client: TestClient
) -> None:
    bank = make_account(client, "HDFC")
    anchor(client, bank, 90_000_00, at="2026-05-01T09:00:00+05:30")
    make_txn(client, bank, amount=40_000_00, at="2026-05-10T12:00:00+05:30", title="Deposit paid")
    run_daily(app.state.session_factory)

    month = client.get("/v1/networth/series", params={"range": "1m"}).json()
    assert month["peak_paise"] == 50_000_00  # the peak he can see
    assert month["all_time_peak_paise"] == 90_000_00  # the peak that really happened
    assert month["all_time_peak_date"] == "2026-05-01"


@time_machine.travel("2026-07-10T10:00:00+05:30")
def test_account_rows_carry_balance_as_of_and_their_readings(
    app: FastAPI, client: TestClient
) -> None:
    bank = make_account(client, "HDFC")
    card = make_account(client, "Amex", kind="card")
    anchor(client, bank, 10_000_00, at="2026-07-05T09:00:00+05:30")
    anchor(client, card, 3_000_00, at="2026-07-05T09:00:00+05:30")
    make_txn(client, bank, amount=1_000_00, at="2026-07-08T12:00:00+05:30")
    run_daily(app.state.session_factory)

    rows = {r["name"]: r for r in client.get("/v1/networth/accounts").json()}
    assert rows["HDFC"]["balance_paise"] == 9_000_00
    assert rows["HDFC"]["as_of"].startswith("2026-07-05")
    assert rows["HDFC"]["low_paise"] == 9_000_00
    assert rows["HDFC"]["high_paise"] == 10_000_00
    assert rows["HDFC"]["readings"] == 6  # the 5th through the 10th
    assert [p["value_paise"] for p in rows["HDFC"]["points"]] == [10_000_00] * 3 + [9_000_00] * 3
    assert rows["Amex"]["kind"] == "card"
    assert rows["Amex"]["balance_paise"] == 3_000_00  # what is owed, unsigned


def test_account_rows_survive_an_unwritten_book(client: TestClient) -> None:
    make_account(client, "HDFC")
    rows = client.get("/v1/networth/accounts").json()
    assert rows[0]["points"] == []
    assert rows[0]["readings"] == 0
    assert rows[0]["low_paise"] is None
