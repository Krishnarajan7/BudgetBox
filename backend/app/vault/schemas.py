from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field

VAULT_ITEM_TYPES = ("note", "date", "credential", "file")


class VaultSetup(BaseModel):
    kdf_salt: str = Field(min_length=1)
    kdf_iterations: int = Field(gt=0)
    canary_ct: str = Field(min_length=1)
    canary_iv: str = Field(min_length=1)


class VaultConfigResponse(BaseModel):
    id: int
    kdf_salt: str
    kdf_iterations: int
    canary_ct: str
    canary_iv: str
    created_at: datetime

    class Config:
        from_attributes = True


class VaultItemCreate(BaseModel):
    item_type: str = Field(min_length=1)
    title_ct: str = Field(min_length=1)
    payload_ct: str = Field(min_length=1)
    iv: str = Field(min_length=1)
    file_data_b64: Optional[str] = None
    file_iv: Optional[str] = None


class VaultItemUpdate(BaseModel):
    title_ct: Optional[str] = None
    payload_ct: Optional[str] = None
    iv: Optional[str] = None
    file_data_b64: Optional[str] = None
    file_iv: Optional[str] = None


class VaultItemListResponse(BaseModel):
    id: int
    item_type: str
    title_ct: str
    payload_ct: str
    iv: str
    has_file: bool
    file_size: Optional[int] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class VaultItemDetailResponse(BaseModel):
    id: int
    item_type: str
    title_ct: str
    payload_ct: str
    iv: str
    has_file: bool
    file_size: Optional[int] = None
    file_data_b64: Optional[str] = None
    file_iv: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
