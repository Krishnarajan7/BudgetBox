import calendar
from datetime import date, datetime, time as dtime

from sqlalchemy import select, desc, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.calendar_events.schemas import (
    EventCreate,
    EventUpdate,
    EventResponse,
    TaskDueItem,
    CalendarDay,
    CalendarResponse,
)
from app.models.event import Event
from app.models.task import Task
from app.models.task_log import TaskLog
from app.core.errors import AppError

RECUR_YEARS_SINCE_KINDS = ("birthday", "anniversary")


def _to_response(
    event: Event,
    occurs_on: date | None = None,
    years_since: int | None = None,
) -> EventResponse:
    return EventResponse(
        id=event.id,
        title=event.title,
        date=event.date,
        time=event.time,
        kind=event.kind,
        note=event.note,
        recur_yearly=event.recur_yearly,
        created_at=event.created_at,
        occurs_on=occurs_on if occurs_on is not None else event.date,
        years_since=years_since,
    )


def _current_month_range() -> tuple[date, date]:
    today = date.today()
    return _month_range(today.year, today.month)


def _month_range(year: int, month: int) -> tuple[date, date]:
    last_day = calendar.monthrange(year, month)[1]
    return date(year, month, 1), date(year, month, last_day)


async def create_event(
    db: AsyncSession,
    user_id: int,
    data: EventCreate,
) -> EventResponse:
    event = Event(
        user_id=user_id,
        title=data.title,
        date=data.date,
        time=data.time,
        kind=data.kind,
        note=data.note,
        recur_yearly=data.recur_yearly,
    )
    db.add(event)
    await db.commit()
    await db.refresh(event)
    return _to_response(event)


async def _get_event_occurrences(
    db: AsyncSession,
    user_id: int,
    start_date: date,
    end_date: date,
) -> list[EventResponse]:
    """Return every event occurrence (direct + yearly-recurring) within range."""
    occurrences: list[EventResponse] = []

    # Non-recurring events whose actual date falls in the range.
    result = await db.execute(
        select(Event).where(
            Event.user_id == user_id,
            Event.recur_yearly.is_(False),
            Event.date.between(start_date, end_date),
        )
    )
    for event in result.scalars().all():
        occurrences.append(_to_response(event, occurs_on=event.date, years_since=None))

    # Yearly-recurring events: their month/day may fall in the range in any
    # year overlapping the requested window, regardless of the original year.
    result = await db.execute(
        select(Event).where(
            Event.user_id == user_id,
            Event.recur_yearly.is_(True),
        )
    )
    for event in result.scalars().all():
        for year in range(start_date.year, end_date.year + 1):
            try:
                occurs_on = date(year, event.date.month, event.date.day)
            except ValueError:
                # e.g. Feb 29 birthday in a non-leap year - no occurrence.
                continue

            if start_date <= occurs_on <= end_date:
                years_since = (
                    year - event.date.year
                    if event.kind in RECUR_YEARS_SINCE_KINDS
                    else None
                )
                occurrences.append(
                    _to_response(event, occurs_on=occurs_on, years_since=years_since)
                )

    occurrences.sort(key=lambda e: (e.occurs_on, e.id))
    return occurrences


async def list_events(
    db: AsyncSession,
    user_id: int,
    start_date: date | None,
    end_date: date | None,
) -> list[EventResponse]:
    if start_date is None or end_date is None:
        default_start, default_end = _current_month_range()
        start_date = start_date or default_start
        end_date = end_date or default_end

    return await _get_event_occurrences(db, user_id, start_date, end_date)


async def update_event(
    db: AsyncSession,
    user_id: int,
    event_id: int,
    data: EventUpdate,
) -> EventResponse:
    result = await db.execute(
        select(Event).where(Event.id == event_id, Event.user_id == user_id)
    )
    event = result.scalar_one_or_none()
    if not event:
        raise AppError("EVENT_NOT_FOUND", "Event not found", 404)

    if data.title is not None:
        event.title = data.title
    if data.date is not None:
        event.date = data.date
    if data.time is not None:
        event.time = data.time
    if data.kind is not None:
        event.kind = data.kind
    if data.note is not None:
        event.note = data.note
    if data.recur_yearly is not None:
        event.recur_yearly = data.recur_yearly

    await db.commit()
    await db.refresh(event)
    return _to_response(event)


async def delete_event(
    db: AsyncSession,
    user_id: int,
    event_id: int,
) -> None:
    result = await db.execute(
        select(Event).where(Event.id == event_id, Event.user_id == user_id)
    )
    event = result.scalar_one_or_none()
    if not event:
        raise AppError("EVENT_NOT_FOUND", "Event not found", 404)

    await db.delete(event)
    await db.commit()


async def _tasks_due_map(
    db: AsyncSession,
    user_id: int,
    start_date: date,
    end_date: date,
) -> dict[str, list[TaskDueItem]]:
    start_dt = datetime.combine(start_date, dtime.min)
    end_dt = datetime.combine(end_date, dtime.max)

    # Same "latest log per task" window-function pattern used in
    # app/tasks/service.py::list_tasks, so completion state matches.
    latest_log = (
        select(
            TaskLog.task_id.label("task_id"),
            TaskLog.completed.label("completed"),
            func.row_number()
            .over(
                partition_by=TaskLog.task_id,
                order_by=(desc(TaskLog.completed_at), desc(TaskLog.id)),
            )
            .label("rn"),
        )
    ).subquery()

    result = await db.execute(
        select(Task, latest_log.c.completed)
        .outerjoin(
            latest_log,
            (latest_log.c.task_id == Task.id) & (latest_log.c.rn == 1),
        )
        .where(
            Task.user_id == user_id,
            Task.is_active.is_(True),
            Task.due_at.isnot(None),
            Task.due_at.between(start_dt, end_dt),
        )
    )

    tasks_by_day: dict[str, list[TaskDueItem]] = {}
    for task, completed in result.all():
        key = task.due_at.date().isoformat()
        tasks_by_day.setdefault(key, []).append(
            TaskDueItem(
                id=task.id,
                title=task.title,
                priority=task.priority,
                completed=bool(completed) if completed is not None else False,
            )
        )
    return tasks_by_day


async def get_calendar_month(
    db: AsyncSession,
    user_id: int,
    month: str | None,
) -> CalendarResponse:
    if month:
        try:
            year_str, month_str = month.split("-")
            year, mon = int(year_str), int(month_str)
            if not (1 <= mon <= 12):
                raise ValueError
        except ValueError:
            raise AppError(
                "INVALID_MONTH", "month must be in YYYY-MM format", 400
            )
        start_date, end_date = _month_range(year, mon)
    else:
        start_date, end_date = _current_month_range()

    events = await _get_event_occurrences(db, user_id, start_date, end_date)
    tasks_by_day = await _tasks_due_map(db, user_id, start_date, end_date)

    days: dict[str, CalendarDay] = {}

    for event in events:
        key = event.occurs_on.isoformat()
        if key not in days:
            days[key] = CalendarDay(events=[], tasks_due=[])
        days[key].events.append(event)

    for key, tasks in tasks_by_day.items():
        if key not in days:
            days[key] = CalendarDay(events=[], tasks_due=[])
        days[key].tasks_due.extend(tasks)

    return CalendarResponse(days=days)
