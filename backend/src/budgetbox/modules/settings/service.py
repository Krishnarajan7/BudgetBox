from sqlalchemy import select
from sqlalchemy.orm import Session

from budgetbox.modules.settings.models import Setting

# Well-known keys (mirrors the app's settings_repo).
KEY_NAME = "name"
KEY_SALARY_DAY = "salary_day"
KEY_SETUP_DONE = "setup_done"
KEY_THEME_MODE = "theme_mode"


def get(session: Session, key: str) -> str | None:
    row = session.get(Setting, key)
    return row.value if row else None


def set_value(session: Session, key: str, value: str) -> Setting:
    row = session.get(Setting, key)
    if row is None:
        row = Setting(key=key, value=value)
        session.add(row)
    else:
        row.value = value
    session.commit()
    return row


def all_settings(session: Session) -> dict[str, str]:
    return {row.key: row.value for row in session.scalars(select(Setting))}


def salary_day(session: Session) -> int:
    raw = get(session, KEY_SALARY_DAY)
    try:
        day = int(raw) if raw is not None else 1
    except ValueError:
        return 1
    return min(max(day, 1), 31)
