"""Alarm storage. The server never rings anything — it keeps the set so that a
reinstall, or a second phone, wakes up to the same mornings."""

from sqlalchemy import select
from sqlalchemy.orm import Session

from budgetbox.core.errors import NotFound
from budgetbox.core.ids import require_uuid
from budgetbox.modules.alarms.models import Alarm
from budgetbox.modules.alarms.schemas import AlarmIn


def list_alarms(session: Session) -> list[Alarm]:
    """Earliest first — the order the alarms page reads them in."""
    return list(session.scalars(select(Alarm).order_by(Alarm.minute_of_day, Alarm.id)))


def get(session: Session, alarm_id: str) -> Alarm:
    row = session.get(Alarm, alarm_id)
    if row is None:
        raise NotFound(f"no alarm {alarm_id}")
    return row


def upsert(session: Session, alarm_id: str, data: AlarmIn) -> Alarm:
    alarm_id = require_uuid(alarm_id)
    row = session.get(Alarm, alarm_id)
    if row is None:
        row = Alarm(id=alarm_id)
        session.add(row)
    row.label = data.label
    row.minute_of_day = data.minute_of_day
    row.days = data.days
    row.enabled = data.enabled
    row.snooze_minutes = data.snooze_minutes
    row.vibrate = data.vibrate
    session.commit()
    return row


def delete(session: Session, alarm_id: str) -> None:
    row = get(session, alarm_id)
    session.delete(row)
    session.commit()
