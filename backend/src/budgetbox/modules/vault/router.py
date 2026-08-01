"""/v1/vault — opaque encrypted blobs in, opaque encrypted blobs out.
No request or response body from this module is ever logged."""

from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.modules.vault import service
from budgetbox.modules.vault.models import VaultItem
from budgetbox.modules.vault.schemas import VaultItemIn, VaultItemOut

router = APIRouter(prefix="/vault", tags=["vault"])


@router.get("")
def list_vault(session: SessionDep) -> list[VaultItemOut]:
    return [VaultItemOut.model_validate(r) for r in service.list_items(session)]


@router.put("/{item_id}")
def upsert_vault_item(session: SessionDep, item_id: str, data: VaultItemIn) -> VaultItemOut:
    return VaultItemOut.model_validate(service.upsert(session, item_id, data))


@router.delete("/{item_id}", status_code=204)
def delete_vault_item(session: SessionDep, item_id: str) -> None:
    service.delete(session, item_id)


from budgetbox.modules.changes.router import register  # noqa: E402

register("vault_items", VaultItem, VaultItem.id)
