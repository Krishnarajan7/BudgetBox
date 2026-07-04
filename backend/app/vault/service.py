import base64
import binascii

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.errors import AppError
from app.models.vault_config import VaultConfig
from app.models.vault_item import VaultItem, VAULT_ITEM_TYPES

MAX_FILE_BYTES = 10 * 1024 * 1024  # 10MB, decoded


def _decode_file_b64(file_data_b64: str) -> bytes:
    try:
        raw = base64.b64decode(file_data_b64, validate=True)
    except (binascii.Error, ValueError):
        raise AppError("VAULT_INVALID_FILE", "file_data_b64 is not valid base64", 400)

    if len(raw) > MAX_FILE_BYTES:
        raise AppError(
            "VAULT_FILE_TOO_LARGE",
            "Encrypted file exceeds the 10MB limit",
            400,
        )

    return raw


async def _get_config(db: AsyncSession, user_id: int) -> VaultConfig | None:
    result = await db.execute(
        select(VaultConfig).where(VaultConfig.user_id == user_id)
    )
    return result.scalar_one_or_none()


async def get_vault_config(db: AsyncSession, user_id: int) -> VaultConfig:
    config = await _get_config(db, user_id)
    if not config:
        raise AppError("VAULT_NOT_SETUP", "Vault has not been set up", 404)
    return config


async def setup_vault(
    db: AsyncSession,
    user_id: int,
    kdf_salt: str,
    kdf_iterations: int,
    canary_ct: str,
    canary_iv: str,
) -> VaultConfig:
    existing = await _get_config(db, user_id)
    if existing:
        raise AppError("VAULT_ALREADY_SETUP", "Vault is already set up", 409)

    config = VaultConfig(
        user_id=user_id,
        kdf_salt=kdf_salt,
        kdf_iterations=kdf_iterations,
        canary_ct=canary_ct,
        canary_iv=canary_iv,
    )
    db.add(config)
    await db.commit()
    await db.refresh(config)
    return config


async def create_item(
    db: AsyncSession,
    user_id: int,
    item_type: str,
    title_ct: str,
    payload_ct: str,
    iv: str,
    file_data_b64: str | None = None,
    file_iv: str | None = None,
) -> VaultItem:
    config = await _get_config(db, user_id)
    if not config:
        raise AppError("VAULT_NOT_SETUP", "Vault has not been set up", 400)

    if item_type not in VAULT_ITEM_TYPES:
        raise AppError(
            "VAULT_INVALID_ITEM_TYPE",
            f"item_type must be one of {VAULT_ITEM_TYPES}",
            400,
        )

    file_data: bytes | None = None
    file_size: int | None = None
    if file_data_b64 is not None:
        file_data = _decode_file_b64(file_data_b64)
        file_size = len(file_data)

    item = VaultItem(
        user_id=user_id,
        item_type=item_type,
        title_ct=title_ct,
        payload_ct=payload_ct,
        iv=iv,
        file_data=file_data,
        file_iv=file_iv,
        file_size=file_size,
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return item


async def list_items(
    db: AsyncSession,
    user_id: int,
    item_type: str | None = None,
):
    stmt = select(VaultItem).where(VaultItem.user_id == user_id)
    if item_type is not None:
        stmt = stmt.where(VaultItem.item_type == item_type)

    result = await db.execute(stmt.order_by(VaultItem.created_at.desc()))
    return result.scalars().all()


async def _get_owned_item(db: AsyncSession, user_id: int, item_id: int) -> VaultItem:
    result = await db.execute(
        select(VaultItem).where(
            VaultItem.id == item_id,
            VaultItem.user_id == user_id,
        )
    )
    item = result.scalar_one_or_none()
    if not item:
        raise AppError("VAULT_ITEM_NOT_FOUND", "Vault item not found", 404)
    return item


async def get_item(db: AsyncSession, user_id: int, item_id: int) -> VaultItem:
    return await _get_owned_item(db, user_id, item_id)


async def update_item(
    db: AsyncSession,
    user_id: int,
    item_id: int,
    title_ct: str | None = None,
    payload_ct: str | None = None,
    iv: str | None = None,
    file_data_b64: str | None = None,
    file_iv: str | None = None,
) -> VaultItem:
    item = await _get_owned_item(db, user_id, item_id)

    if title_ct is not None:
        item.title_ct = title_ct
    if payload_ct is not None:
        item.payload_ct = payload_ct
    if iv is not None:
        item.iv = iv
    if file_iv is not None:
        item.file_iv = file_iv
    if file_data_b64 is not None:
        raw = _decode_file_b64(file_data_b64)
        item.file_data = raw
        item.file_size = len(raw)

    await db.commit()
    await db.refresh(item)
    return item


async def delete_item(db: AsyncSession, user_id: int, item_id: int) -> None:
    item = await _get_owned_item(db, user_id, item_id)
    await db.delete(item)
    await db.commit()


async def delete_vault(db: AsyncSession, user_id: int) -> None:
    result = await db.execute(select(VaultItem).where(VaultItem.user_id == user_id))
    for item in result.scalars().all():
        await db.delete(item)

    config = await _get_config(db, user_id)
    if config:
        await db.delete(config)

    await db.commit()
