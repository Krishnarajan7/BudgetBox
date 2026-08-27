"""The folio: buying is not spending, units carry the worth, and the gap
between cost and value is the only return figure."""

import datetime as dt

import pytest
from sqlalchemy.orm import Session

from budgetbox.core.errors import Conflict, Invalid
from budgetbox.core.ids import new_id
from budgetbox.modules.accounts.models import Account, AccountKind, BalanceAnchor
from budgetbox.modules.folio import amfi, service
from budgetbox.modules.folio.models import FolioEntryKind, Fund
from budgetbox.modules.folio.schemas import ContributeIn, FundIn, RedeemIn, ValueIn
from budgetbox.modules.transactions import service as txn_service
from budgetbox.modules.transactions.models import TxnType

UTC = dt.UTC

# Two rows of the real file, plus the furniture AMFI interleaves between them.
SAMPLE = (
    "Scheme Code;ISIN Div Payout/ ISIN Growth;ISIN Div Reinvestment;"
    "Scheme Name;Plan;Option;Net Asset Value;Date\n"
    "\n"
    "Open Ended Schemes(Equity Scheme - Flexi Cap Fund)\n"
    "\n"
    "PPFAS Mutual Fund\n"
    "\n"
    "122639;INF879O01027;-;Parag Parikh Flexi Cap Fund;Direct Plan;Growth;"
    "45.2000;25-Aug-2026\n"
    "122640;INF879O01035;-;Parag Parikh Flexi Cap Fund;Regular Plan;Growth;"
    "41.1000;25-Aug-2026\n"
    "999999;-;-;Broken Fund;Direct Plan;Growth;N.A.;25-Aug-2026\n"
)


@pytest.fixture
def bank(session: Session) -> Account:
    row = Account(id=new_id(), name="HDFC", kind=AccountKind.BANK)
    session.add(row)
    session.commit()
    return row


@pytest.fixture
def fund(session: Session) -> Fund:
    row = service.upsert_fund(session, new_id(), FundIn(name="Parag Parikh Flexi Cap"))
    # Price it by hand rather than reaching for the network in a unit test.
    row.nav = 45.20
    row.nav_date = dt.date(2026, 8, 25)
    row.scheme_code = "122639"
    session.commit()
    return row


def _put(
    session: Session, fund: Fund, bank: Account, rupees: int, day: int = 1, kind=FolioEntryKind.SIP
):
    return service.contribute(
        session,
        fund.id,
        ContributeIn(
            amount_paise=rupees * 100,
            account_id=bank.id,
            kind=kind,
            at=dt.datetime(2026, 8, day, 6, 0, tzinfo=UTC),
        ),
    )


# ————— AMFI's file —————


def test_parse_keeps_rows_and_drops_furniture() -> None:
    schemes = amfi.parse(SAMPLE)
    # The header, the blank lines, the category and fund-house headings and
    # the unpriced row are all furniture.
    assert [s.code for s in schemes] == ["122639", "122640"]
    first = schemes[0]
    assert first.nav == 45.20
    assert first.nav_date == dt.date(2026, 8, 25)
    assert first.label == "Parag Parikh Flexi Cap Fund · Direct Plan · Growth"


def test_search_needs_every_word_and_prefers_the_shorter_label() -> None:
    schemes = amfi.parse(SAMPLE)
    assert [s.code for s in amfi.search(schemes, "parag direct growth", 5)] == ["122639"]
    assert amfi.search(schemes, "parag nifty", 5) == []


# ————— money —————


def test_buying_is_a_transfer_and_buys_units(session: Session, bank: Account, fund: Fund) -> None:
    entry = _put(session, fund, bank, 5000)

    txn = txn_service.get(session, entry.txn_id or "")
    assert txn.type is TxnType.TRANSFER
    assert txn.account_id == bank.id
    assert txn.to_account_id == service.folio_account(session).id
    assert txn.category_id is None
    # 5000 / 45.20 = 110.61947 units
    assert entry.units == pytest.approx(110.61947, abs=1e-5)

    view = service.fund_view(session, fund)
    assert view.cost_paise == 500_000
    # Priced at the same NAV it bought at, so it is worth what it cost.
    assert view.value_paise == pytest.approx(500_000, abs=2)
    assert view.sip_count == 1


def test_the_gap_between_cost_and_value_is_the_gain(
    session: Session, bank: Account, fund: Fund
) -> None:
    _put(session, fund, bank, 5000)
    # The market moves; nothing else does.
    fund.nav = 49.72  # +10%
    session.commit()

    view = service.fund_view(session, fund)
    assert view.cost_paise == 500_000
    assert view.value_paise == pytest.approx(550_000, abs=200)
    assert view.gain_paise == pytest.approx(50_000, abs=200)
    assert view.return_ratio == pytest.approx(0.10, abs=0.001)


def test_the_folio_account_is_never_the_source(session: Session, fund: Fund) -> None:
    holding = service.folio_account(session)
    session.commit()
    with pytest.raises(Invalid):
        service.contribute(
            session,
            fund.id,
            ContributeIn(amount_paise=100, account_id=holding.id),
        )


def test_redeeming_takes_cost_out_in_proportion(
    session: Session, bank: Account, fund: Fund
) -> None:
    _put(session, fund, bank, 10000)
    fund.nav = 90.40  # doubled
    session.commit()

    # Sell half the value: half the units, so half the cost goes with them.
    service.redeem(
        session,
        fund.id,
        RedeemIn(
            amount_paise=1_000_000,
            account_id=bank.id,
            at=dt.datetime(2026, 8, 10, 6, 0, tzinfo=UTC),
        ),
    )
    view = service.fund_view(session, fund)
    # 10,000 at 45.20 bought 221.23894 units; selling 10,000 at the doubled
    # NAV takes exactly half of them back.
    assert view.units == pytest.approx(221.23894 / 2, abs=1e-3)
    assert view.cost_paise == pytest.approx(500_000, abs=200)
    assert view.value_paise == pytest.approx(1_000_000, abs=400)
    # Still showing the same doubling on what is left.
    assert view.return_ratio == pytest.approx(1.0, abs=0.01)


def test_redeeming_more_than_is_held_is_refused(
    session: Session, bank: Account, fund: Fund
) -> None:
    _put(session, fund, bank, 1000)
    with pytest.raises(Invalid):
        service.redeem(
            session,
            fund.id,
            RedeemIn(amount_paise=500_000, account_id=bank.id),
        )
    # The refusal left nothing behind.
    assert service.fund_view(session, fund).cost_paise == 100_000


def test_a_hand_priced_fund_takes_a_value(session: Session, bank: Account) -> None:
    ppf = service.upsert_fund(session, new_id(), FundIn(name="PPF"))
    _put(session, ppf, bank, 5000)
    view = service.fund_view(session, ppf)
    # Nothing prices it, so what went in is the only honest figure.
    assert view.priced is False
    assert view.value_paise == 500_000

    service.set_value(session, ppf.id, ValueIn(value_paise=560_000))
    assert service.fund_view(session, ppf).gain_paise == 60_000


def test_a_priced_fund_refuses_a_hand_value(session: Session, fund: Fund) -> None:
    with pytest.raises(Conflict):
        service.set_value(session, fund.id, ValueIn(value_paise=1))


def test_overview_totals_and_the_month(session: Session, bank: Account, fund: Fund) -> None:
    _put(session, fund, bank, 5000)
    _put(session, fund, bank, 3000, day=15, kind=FolioEntryKind.LUMPSUM)
    fund.nav = 49.72
    session.commit()

    o = service.overview(session)
    assert o.cost_paise == 800_000
    assert o.gain_paise == pytest.approx(80_000, abs=400)
    assert o.funds == 1
    assert o.unpriced_funds == 0


def test_anchor_writes_market_worth_onto_the_account(
    session: Session, bank: Account, fund: Fund
) -> None:
    """The ledger alone shows only what was paid in; the anchor is how the
    market's half reaches net worth."""
    _put(session, fund, bank, 5000)
    fund.nav = 49.72
    session.commit()

    service.anchor_worth(session)
    account = service.folio_account(session)
    anchors = session.query(BalanceAnchor).filter(BalanceAnchor.account_id == account.id).all()
    assert len(anchors) == 1

    # Running it twice in a day replaces rather than stacks.
    service.anchor_worth(session)
    again = session.query(BalanceAnchor).filter(BalanceAnchor.account_id == account.id).all()
    assert len(again) == 1
    assert again[0].balance_paise == pytest.approx(550_000, abs=300)


def test_series_draws_both_lines(session: Session, bank: Account, fund: Fund) -> None:
    _put(session, fund, bank, 5000, day=1)
    _put(session, fund, bank, 5000, day=2)
    points = service.series(session, days=365)
    assert points
    # Cost is a staircase: it only steps when money went in.
    assert points[0].cost_paise == 500_000
    assert points[-1].cost_paise == 1_000_000
    assert all(p.value_paise > 0 for p in points)


def test_a_fund_holding_money_cannot_be_deleted(
    session: Session, bank: Account, fund: Fund
) -> None:
    _put(session, fund, bank, 100)
    with pytest.raises(Conflict):
        service.delete_fund(session, fund.id)


def test_overview_over_api(client) -> None:  # type: ignore[no-untyped-def]
    body = client.get("/v1/folio/overview").json()
    assert body["cost_paise"] == 0
    assert body["funds"] == 0
