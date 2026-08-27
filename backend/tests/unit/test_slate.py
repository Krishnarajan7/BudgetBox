"""The slate: lending is not spending, partial repayment is the normal case,
and the sum of every slate always equals what the ledger parked."""

import datetime as dt

import pytest
from sqlalchemy.orm import Session

from budgetbox.core.errors import Conflict, Invalid
from budgetbox.core.ids import new_id
from budgetbox.modules.accounts.models import Account, AccountKind
from budgetbox.modules.categories.models import Category, CategoryKind
from budgetbox.modules.slate import service
from budgetbox.modules.slate.models import SlateKind
from budgetbox.modules.slate.schemas import AdoptIn, CloseIn, LendIn, PersonIn, RepayIn
from budgetbox.modules.transactions import service as txn_service
from budgetbox.modules.transactions.models import TxnType
from budgetbox.modules.transactions.schemas import TxnIn

UTC = dt.UTC


@pytest.fixture
def gpay(session: Session) -> Account:
    row = Account(id=new_id(), name="GPay", kind=AccountKind.UPI)
    session.add(row)
    session.commit()
    return row


@pytest.fixture
def anu(session: Session) -> str:
    person_id = new_id()
    service.upsert_person(session, person_id, PersonIn(name="Anu", relation="sister"))
    return person_id


def _lend(session: Session, person_id: str, account: Account, rupees: int, day: int = 1):
    return service.lend(
        session,
        person_id,
        LendIn(
            amount_paise=rupees * 100,
            account_id=account.id,
            at=dt.datetime(2026, 8, day, 6, 0, tzinfo=UTC),
        ),
    )


def test_lending_is_a_transfer_not_an_expense(session: Session, gpay: Account, anu: str) -> None:
    entry = _lend(session, anu, gpay, 5000)
    assert entry.kind is SlateKind.LENT

    txn = txn_service.get(session, entry.txn_id or "")
    # The money moved pocket; it was not spent.
    assert txn.type is TxnType.TRANSFER
    assert txn.account_id == gpay.id
    assert txn.to_account_id == service.slate_account(session).id
    assert txn.category_id is None
    assert service.balance(session, anu) == 500_000


def test_partial_repayment_and_the_invariant(session: Session, gpay: Account, anu: str) -> None:
    _lend(session, anu, gpay, 5000)
    service.repay(
        session,
        anu,
        RepayIn(
            amount_paise=200_000,
            account_id=gpay.id,
            at=dt.datetime(2026, 8, 5, 6, 0, tzinfo=UTC),
        ),
    )
    assert service.balance(session, anu) == 300_000

    view = service.person_view(session, anu)
    assert view.lent_paise == 500_000
    assert view.returned_paise == 200_000
    # Still standing, so the loop has not closed and the age still runs.
    assert view.loops_total == 1
    assert view.loops_closed == 0
    assert view.outstanding_since == dt.datetime(2026, 8, 1, 6, 0, tzinfo=UTC)

    overview = service.overview(session)
    assert overview.owed_to_you_paise == 300_000
    assert overview.net_paise == 300_000
    # What every slate says, and what the ledger actually parked, agree.
    assert overview.slate_account_paise == 300_000
    assert overview.balanced is True


def test_full_repayment_closes_the_loop(session: Session, gpay: Account, anu: str) -> None:
    _lend(session, anu, gpay, 1000)
    service.repay(
        session,
        anu,
        RepayIn(
            amount_paise=100_000,
            account_id=gpay.id,
            at=dt.datetime(2026, 8, 3, 6, 0, tzinfo=UTC),
        ),
    )
    view = service.person_view(session, anu)
    assert view.balance_paise == 0
    assert (view.loops_closed, view.loops_total) == (1, 1)
    # A clean slate has no age to print.
    assert view.outstanding_since is None
    assert service.overview(session).balanced is True


def test_two_loops_count_separately(session: Session, gpay: Account, anu: str) -> None:
    for day in (1, 10):
        _lend(session, anu, gpay, 1000, day=day)
        service.repay(
            session,
            anu,
            RepayIn(
                amount_paise=100_000,
                account_id=gpay.id,
                at=dt.datetime(2026, 8, day + 2, 6, 0, tzinfo=UTC),
            ),
        )
    view = service.person_view(session, anu)
    assert (view.loops_closed, view.loops_total) == (2, 2)


def test_borrowing_tips_the_slate_the_other_way(session: Session, gpay: Account, anu: str) -> None:
    service.borrow(
        session,
        anu,
        LendIn(
            amount_paise=30_000,
            account_id=gpay.id,
            at=dt.datetime(2026, 8, 2, 6, 0, tzinfo=UTC),
        ),
    )
    assert service.balance(session, anu) == -30_000
    overview = service.overview(session)
    assert overview.you_owe_paise == 30_000
    assert overview.net_paise == -30_000
    assert overview.balanced is True


def test_letting_go_becomes_an_expense_dated_the_decision(
    session: Session, gpay: Account, anu: str
) -> None:
    _lend(session, anu, gpay, 2000)
    decided = dt.datetime(2026, 8, 20, 6, 0, tzinfo=UTC)
    entry = service.close(session, anu, CloseIn(at=decided))

    assert entry.kind is SlateKind.FORGIVEN
    txn = txn_service.get(session, entry.txn_id or "")
    # Only now is it spending — and dated when the decision was made.
    assert txn.type is TxnType.EXPENSE
    assert txn.at == decided
    assert service.balance(session, anu) == 0
    # Let go is not "returned": the loop closed, but not by being paid.
    view = service.person_view(session, anu)
    assert view.loops_closed == 0
    assert service.overview(session).balanced is True


def test_closing_a_clean_slate_is_refused(session: Session, anu: str) -> None:
    with pytest.raises(Conflict):
        service.close(session, anu, CloseIn())


def test_adopting_an_expense_converts_rather_than_duplicates(
    session: Session, gpay: Account, anu: str
) -> None:
    category = Category(id=new_id(), name="Misc", kind=CategoryKind.EXPENSE)
    session.add(category)
    session.commit()
    txn, _ = txn_service.upsert(
        session,
        new_id(),
        TxnIn(
            amount_paise=150_000,
            type=TxnType.EXPENSE,
            account_id=gpay.id,
            category_id=category.id,
            title="sent to Anu",
            at=dt.datetime(2026, 7, 4, 6, 0, tzinfo=UTC),
        ),
    )

    entry = service.adopt(session, anu, AdoptIn(txn_id=txn.id))

    # The same line, reclassified — not a second one beside it.
    assert entry.txn_id == txn.id
    converted = txn_service.get(session, txn.id)
    assert converted.type is TxnType.TRANSFER
    assert converted.category_id is None
    assert converted.to_account_id == service.slate_account(session).id
    assert service.balance(session, anu) == 150_000
    assert service.overview(session).balanced is True

    # It cannot be taken twice.
    with pytest.raises(Conflict):
        service.adopt(session, anu, AdoptIn(txn_id=txn.id))


def test_adoptable_hides_what_is_already_taken(session: Session, gpay: Account, anu: str) -> None:
    category = Category(id=new_id(), name="Misc", kind=CategoryKind.EXPENSE)
    session.add(category)
    session.commit()
    ids = []
    for i in range(2):
        txn, _ = txn_service.upsert(
            session,
            new_id(),
            TxnIn(
                amount_paise=10_000,
                type=TxnType.EXPENSE,
                account_id=gpay.id,
                category_id=category.id,
                title=f"thing {i}",
                at=dt.datetime(2026, 7, 4 + i, 6, 0, tzinfo=UTC),
            ),
        )
        ids.append(txn.id)

    assert {a.txn_id for a in service.adoptable(session, 40)} == set(ids)
    service.adopt(session, anu, AdoptIn(txn_id=ids[0]))
    assert {a.txn_id for a in service.adoptable(session, 40)} == {ids[1]}


def test_slate_account_is_not_a_pocket(session: Session, anu: str) -> None:
    slate = service.slate_account(session)
    session.commit()
    with pytest.raises(Invalid):
        service.lend(session, anu, LendIn(amount_paise=100, account_id=slate.id))


def test_a_person_with_history_cannot_be_deleted(session: Session, gpay: Account, anu: str) -> None:
    _lend(session, anu, gpay, 100)
    with pytest.raises(Conflict):
        service.delete_person(session, anu)


def test_people_sort_owed_first_then_clean_last(session: Session, gpay: Account) -> None:
    ids = {}
    for name in ("Small", "Big", "Clean"):
        pid = new_id()
        service.upsert_person(session, pid, PersonIn(name=name))
        ids[name] = pid
    _lend(session, ids["Small"], gpay, 100)
    _lend(session, ids["Big"], gpay, 900)
    _lend(session, ids["Clean"], gpay, 500)
    service.repay(
        session,
        ids["Clean"],
        RepayIn(
            amount_paise=50_000,
            account_id=gpay.id,
            at=dt.datetime(2026, 8, 9, 6, 0, tzinfo=UTC),
        ),
    )
    assert [v.name for v in service.people(session)] == ["Big", "Small", "Clean"]


def test_overview_over_api(client) -> None:  # type: ignore[no-untyped-def]
    body = client.get("/v1/slate/overview").json()
    assert body["net_paise"] == 0
    assert body["balanced"] is True
