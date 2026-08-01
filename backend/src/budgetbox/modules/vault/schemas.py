"""Wire shapes for the zero-knowledge vault. Every payload field is an opaque
base64 blob the device produced with AES-GCM; the server validates only that the
text *is* base64 and fits the size cap, never what it means."""

import base64
from datetime import datetime

from pydantic import Field, field_validator

from budgetbox.api.schemas import APIModel, Instant

# ~64KB decoded — a vault entry is a short secret, not an attachment store.
MAX_CIPHER_CHARS = 90_000
MAX_NONCE_CHARS = 1_000


class VaultItemIn(APIModel):
    nonce: str = Field(min_length=1, max_length=MAX_NONCE_CHARS)
    cipher: str = Field(min_length=1, max_length=MAX_CIPHER_CHARS)
    expected_updated_at: Instant | None = None
    """Optimistic concurrency: the updated_at the client last read. Omit to
    overwrite unconditionally; send a stale one and the write is refused."""

    @field_validator("nonce", "cipher")
    @classmethod
    def _must_be_base64(cls, value: str) -> str:
        try:
            base64.b64decode(value, validate=True)
        except ValueError as exc:  # binascii.Error subclasses ValueError
            raise ValueError("must be base64 (the device encrypts before it sends)") from exc
        return value


class VaultItemOut(APIModel):
    id: str
    nonce: str
    cipher: str
    created_at: datetime
    updated_at: datetime
