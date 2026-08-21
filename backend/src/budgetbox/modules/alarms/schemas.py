from datetime import datetime
from typing import Annotated

from pydantic import Field

from budgetbox.api.schemas import APIModel

# Minutes past local midnight. Local, not UTC: 6 a.m. means 6 a.m. wherever
# the phone wakes up, and an alarm that drifted with a timezone would be a bug.
MinuteOfDay = Annotated[int, Field(strict=True, ge=0, le=1439)]
# Monday is bit 0 … Sunday is bit 6; 0 = ring once and switch off.
DaysMask = Annotated[int, Field(strict=True, ge=0, le=127)]
SnoozeMinutes = Annotated[int, Field(strict=True, ge=1, le=60)]
Label = Annotated[str, Field(max_length=60)]


class AlarmIn(APIModel):
    label: Label = ""
    minute_of_day: MinuteOfDay
    days: DaysMask = 0
    enabled: bool = True
    snooze_minutes: SnoozeMinutes = 9
    vibrate: bool = True


class AlarmOut(APIModel):
    id: str
    label: str
    minute_of_day: int
    days: int
    enabled: bool
    snooze_minutes: int
    vibrate: bool
    created_at: datetime
    updated_at: datetime
