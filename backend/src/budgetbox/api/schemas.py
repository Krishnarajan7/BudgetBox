"""Shared wire-schema conventions. Every response model derives from APIModel;
money fields use the strict paise types so a float can never sneak into an amount."""

from typing import Annotated

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field


class APIModel(BaseModel):
    model_config = ConfigDict(from_attributes=True, extra="forbid")


# Strict: rejects floats, strings, bools — an amount is an int of paise or a 422.
StrictPaise = Annotated[int, Field(strict=True)]
PositivePaise = Annotated[int, Field(strict=True, gt=0)]

# Instants on the wire are tz-aware ISO-8601; naive datetimes are rejected.
Instant = AwareDatetime
