import base64

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User
from app.models.vault_item import VaultItem

from app.vault.schemas import (
    VaultSetup,
    VaultConfigResponse,
    VaultItemCreate,
    VaultItemUpdate,
    VaultItemListResponse,
    VaultItemDetailResponse,
)
from app.vault.service import (
    get_vault_config,
    setup_vault,
    create_item,
    list_items,
    get_item,
    update_item,
    delete_item,
    delete_vault,
)

router = APIRouter(prefix="/vault", tags=["vault"])


def _to_list_response(item: VaultItem) -> VaultItemListResponse:
    return VaultItemListResponse(
        id=item.id,
        item_type=item.item_type,
        title_ct=item.title_ct,
        payload_ct=item.payload_ct,
        iv=item.iv,
        has_file=item.file_data is not None,
        file_size=item.file_size,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


def _to_detail_response(item: VaultItem) -> VaultItemDetailResponse:
    file_data_b64 = (
        base64.b64encode(item.file_data).decode("ascii")
        if item.file_data is not None
        else None
    )
    return VaultItemDetailResponse(
        id=item.id,
        item_type=item.item_type,
        title_ct=item.title_ct,
        payload_ct=item.payload_ct,
        iv=item.iv,
        has_file=item.file_data is not None,
        file_size=item.file_size,
        file_data_b64=file_data_b64,
        file_iv=item.file_iv,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


@router.get("/config", response_model=VaultConfigResponse)
async def read_config(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await get_vault_config(db, user.id)


@router.post("/setup", response_model=VaultConfigResponse, status_code=status.HTTP_201_CREATED)
async def setup(
    data: VaultSetup,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await setup_vault(
        db,
        user.id,
        kdf_salt=data.kdf_salt,
        kdf_iterations=data.kdf_iterations,
        canary_ct=data.canary_ct,
        canary_iv=data.canary_iv,
    )


@router.post("/items", response_model=VaultItemDetailResponse, status_code=status.HTTP_201_CREATED)
async def create(
    data: VaultItemCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = await create_item(
        db,
        user.id,
        item_type=data.item_type,
        title_ct=data.title_ct,
        payload_ct=data.payload_ct,
        iv=data.iv,
        file_data_b64=data.file_data_b64,
        file_iv=data.file_iv,
    )
    return _to_detail_response(item)


@router.get("/items", response_model=list[VaultItemListResponse])
async def list_all(
    item_type: str | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    items = await list_items(db, user.id, item_type=item_type)
    return [_to_list_response(item) for item in items]


@router.get("/items/{item_id}", response_model=VaultItemDetailResponse)
async def read_one(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = await get_item(db, user.id, item_id)
    return _to_detail_response(item)


@router.patch("/items/{item_id}", response_model=VaultItemDetailResponse)
async def update(
    item_id: int,
    data: VaultItemUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = await update_item(
        db,
        user.id,
        item_id,
        title_ct=data.title_ct,
        payload_ct=data.payload_ct,
        iv=data.iv,
        file_data_b64=data.file_data_b64,
        file_iv=data.file_iv,
    )
    return _to_detail_response(item)


@router.delete("/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_one(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await delete_item(db, user.id, item_id)


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
async def reset_vault(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await delete_vault(db, user.id)
