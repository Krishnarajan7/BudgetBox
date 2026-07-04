import api from "./axios";

// Mirrors backend app/calendar_events/schemas.py::EventKind.
export type EventKind =
  | "event"
  | "birthday"
  | "anniversary"
  | "reminder"
  | "important_date";

// Mirrors backend EventResponse. Dates are plain "YYYY-MM-DD" strings (no
// time component) so they must be parsed with local Date math, never
// `new Date(str).toISOString()` which shifts by the UTC offset.
export interface EventResponse {
  id: number;
  title: string;
  date: string; // "YYYY-MM-DD" - the event's original/anchor date
  time: string | null; // "HH:MM"
  kind: EventKind;
  note: string | null;
  recur_yearly: boolean;
  created_at: string;
  occurs_on: string; // "YYYY-MM-DD" - this occurrence's actual date (may
  // differ from `date` for yearly-recurring events viewed in a later year)
  years_since: number | null; // e.g. turning 36; only set for
  // birthday/anniversary kinds
}

export interface EventCreatePayload {
  title: string;
  date: string; // "YYYY-MM-DD"
  time?: string | null; // "HH:MM"
  kind?: EventKind;
  note?: string | null;
  recur_yearly?: boolean;
}

export interface EventUpdatePayload {
  title?: string;
  date?: string;
  time?: string | null;
  kind?: EventKind;
  note?: string | null;
  recur_yearly?: boolean;
}

// Mirrors backend CalendarDay.tasks_due items (app/calendar_events/schemas.py
// TaskDueItem).
export interface TaskDueItem {
  id: number;
  title: string;
  priority: "low" | "medium" | "high" | string;
  completed: boolean;
}

export interface CalendarDay {
  events: EventResponse[];
  tasks_due: TaskDueItem[];
}

// GET /calendar returns only days that have at least one event or task due
// - days with nothing scheduled are simply absent from this map.
export interface CalendarResponse {
  days: Record<string, CalendarDay>;
}

export const createEvent = async (
  payload: EventCreatePayload
): Promise<EventResponse> => {
  const res = await api.post<EventResponse>("/events", payload);
  return res.data;
};

// start_date/end_date are "YYYY-MM-DD"; yearly-recurring events are expanded
// server-side to every occurrence within the range (occurs_on/years_since
// computed per-occurrence).
export const listEvents = async (
  startDate?: string,
  endDate?: string
): Promise<EventResponse[]> => {
  const res = await api.get<EventResponse[]>("/events", {
    params: {
      start_date: startDate,
      end_date: endDate,
    },
  });
  return res.data;
};

export const updateEvent = async (
  eventId: number,
  payload: EventUpdatePayload
): Promise<EventResponse> => {
  const res = await api.patch<EventResponse>(`/events/${eventId}`, payload);
  return res.data;
};

export const deleteEvent = async (eventId: number): Promise<void> => {
  await api.delete(`/events/${eventId}`);
};

// month is "YYYY-MM"; defaults to the current month server-side if omitted.
export const getCalendarMonth = async (
  month?: string
): Promise<CalendarResponse> => {
  const res = await api.get<CalendarResponse>("/calendar", {
    params: { month },
  });
  return res.data;
};
