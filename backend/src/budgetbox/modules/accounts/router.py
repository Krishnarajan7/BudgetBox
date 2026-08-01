from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.modules.accounts import service
from budgetbox.modules.accounts.models import Account
from budgetbox.modules.accounts.schemas import AccountIn, AccountOut, AccountPatch, AnchorIn

router = APIRouter(prefix="/accounts", tags=["accounts"])


def _out(session: SessionDep, row: Account) -> AccountOut:
    balance, as_of = service.balance_as_of(session, row.id)
    return AccountOut(
        id=row.id,
        name=row.name,
        kind=row.kind,
        sort_order=row.sort_order,
        archived=row.archived,
        balance_paise=balance,
        as_of=as_of,
        created_at=row.created_at,
        updated_at=row.updated_at,
    )


@router.get("")
def list_accounts(session: SessionDep, include_archived: bool = False) -> list[AccountOut]:
    rows = service.list_accounts(session, include_archived=include_archived)
    return [_out(session, r) for r in rows]


@router.get("/{account_id}")
def get_account(session: SessionDep, account_id: str) -> AccountOut:
    return _out(session, service.get(session, account_id))


@router.put("/{account_id}")
def upsert_account(session: SessionDep, account_id: str, data: AccountIn) -> AccountOut:
    return _out(session, service.upsert(session, account_id, data))


@router.patch("/{account_id}")
def patch_account(session: SessionDep, account_id: str, data: AccountPatch) -> AccountOut:
    return _out(session, service.patch(session, account_id, data))


@router.post("/{account_id}/anchors", status_code=201)
def add_anchor(session: SessionDep, account_id: str, data: AnchorIn) -> AccountOut:
    service.add_anchor(session, account_id, data)
    return _out(session, service.get(session, account_id))
