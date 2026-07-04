import api from "./axios";

// ---------------------------------------------------------------------------
// Analytics — GET /analytics/dashboard (app/analytics/service.py::dashboard_summary)
// ---------------------------------------------------------------------------

export interface PeriodSummary {
  income: number;
  expense: number;
  profit: number;
}

export interface TopCategory {
  category: string;
  amount: number;
}

// Mirrors the dicts appended in app/analytics/alerts.py::expense_alerts /
// _budget_alerts. "type" drives the icon/color in the UI.
export interface DashboardAlert {
  type: "danger" | "warning" | "info" | "success";
  message: string;
}

export interface DashboardSummary {
  weekly: PeriodSummary;
  monthly: PeriodSummary;
  top_categories: TopCategory[];
  alerts: DashboardAlert[];
}

export const getDashboardSummary = async (): Promise<DashboardSummary> => {
  const res = await api.get<DashboardSummary>("/analytics/dashboard");
  return res.data;
};

// Mirrors GET /analytics/compare/monthly (app/analytics/service.py::month_comparison).
// Used only for an optional, honest "vs last month" trend on the Spend metric
// card — omitted entirely by the UI if the previous month has no data.
export interface MonthComparison {
  current_month: PeriodSummary;
  previous_month: PeriodSummary;
  difference: { expense: number; income: number; profit: number };
  insight: string;
}

export const getMonthComparison = async (): Promise<MonthComparison> => {
  const res = await api.get<MonthComparison>("/analytics/compare/monthly");
  return res.data;
};

// ---------------------------------------------------------------------------
// Calendar — GET /calendar (app/calendar_events/schemas.py + service.py)
// ---------------------------------------------------------------------------

export interface CalendarEventItem {
  id: number;
  title: string;
  date: string; // "YYYY-MM-DD"
  time: string | null;
  kind: string;
  note: string | null;
  recur_yearly: boolean;
  created_at: string;
  occurs_on: string; // "YYYY-MM-DD" — the date this occurrence actually falls on
  years_since: number | null;
}

export interface CalendarTaskDue {
  id: number;
  title: string;
  priority: string;
  completed: boolean;
}

export interface CalendarDay {
  events: CalendarEventItem[];
  tasks_due: CalendarTaskDue[];
}

export interface CalendarResponse {
  days: Record<string, CalendarDay>;
}

/** month must be "YYYY-MM"; omit to let the backend default to the current month. */
export const getCalendarMonth = async (
  month?: string
): Promise<CalendarResponse> => {
  const res = await api.get<CalendarResponse>("/calendar", {
    params: month ? { month } : undefined,
  });
  return res.data;
};

// ---------------------------------------------------------------------------
// Wellness — GET /water, /sleep, /mood (app/wellness/schemas.py + service.py)
// ---------------------------------------------------------------------------

export interface WaterLogEntry {
  id: number;
  date: string; // "YYYY-MM-DD"
  glasses: number;
  goal: number;
}

export interface SleepEntryResponse {
  id: number;
  date: string; // "YYYY-MM-DD" — the morning this sleep session ended
  hours: number;
  quality: number | null;
  bedtime: string | null;
  wake_time: string | null;
}

export interface MoodEntryResponse {
  id: number;
  date: string; // "YYYY-MM-DD"
  mood: number;
  note: string | null;
}

export const listWaterLogs = async (
  startDate: string,
  endDate: string
): Promise<WaterLogEntry[]> => {
  const res = await api.get<WaterLogEntry[]>("/water", {
    params: { start_date: startDate, end_date: endDate },
  });
  return res.data;
};

export const listSleepEntries = async (
  startDate: string,
  endDate: string
): Promise<SleepEntryResponse[]> => {
  const res = await api.get<SleepEntryResponse[]>("/sleep", {
    params: { start_date: startDate, end_date: endDate },
  });
  return res.data;
};

export const listMoodEntries = async (
  startDate: string,
  endDate: string
): Promise<MoodEntryResponse[]> => {
  const res = await api.get<MoodEntryResponse[]>("/mood", {
    params: { start_date: startDate, end_date: endDate },
  });
  return res.data;
};

// ---------------------------------------------------------------------------
// Shared local-date helpers + query key factory
//
// Always derive "today" from local Date getters (never toISOString, which is
// UTC and can land on the wrong calendar day near midnight in most timezones).
// ---------------------------------------------------------------------------

export function toLocalDateString(d: Date = new Date()): string {
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

/** "YYYY-MM" for the given date's month, in local time. */
export function toLocalMonthString(d: Date = new Date()): string {
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, "0");
  return `${year}-${month}`;
}

/** Local-time date N days before `d` (N may be negative to go forward). */
export function addLocalDays(d: Date, days: number): Date {
  const copy = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  copy.setDate(copy.getDate() + days);
  return copy;
}

/**
 * True if an ISO datetime string (e.g. a task's due_at/completed_at) falls on
 * the same local calendar day as `referenceLocalDateStr` ("YYYY-MM-DD").
 */
export function isSameLocalDay(
  iso: string | null | undefined,
  referenceLocalDateStr: string
): boolean {
  if (!iso) return false;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return false;
  return toLocalDateString(d) === referenceLocalDateStr;
}

// Centralized so every dashboard widget that reads the "same query" as a
// MetricCard actually shares the same react-query cache entry instead of
// re-fetching independently.
export const dashboardKeys = {
  summary: ["dashboard", "analytics-summary"] as const,
  monthComparison: ["dashboard", "month-comparison"] as const,
  calendar: (month: string) => ["dashboard", "calendar", month] as const,
  water: (start: string, end: string) =>
    ["dashboard", "water", start, end] as const,
  sleep: (start: string, end: string) =>
    ["dashboard", "sleep", start, end] as const,
  mood: (start: string, end: string) =>
    ["dashboard", "mood", start, end] as const,
};
