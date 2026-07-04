import api from "./axios";

// Mirrors backend app/wellness/schemas.py + router.py. All three routers
// (mood/water/sleep) share the same shape: list is GET with optional
// start_date/end_date filters (returned ordered by date desc), a single-day
// row is upserted via PUT /{date}, and removed via DELETE /{date}.

export interface DateRangeParams {
  start_date?: string; // "YYYY-MM-DD"
  end_date?: string; // "YYYY-MM-DD"
}

// ---------------------------------------------------------------------------
// Mood — app/wellness/schemas.py::MoodResponse / MoodUpsert
// ---------------------------------------------------------------------------

export interface MoodEntry {
  id: number;
  date: string; // "YYYY-MM-DD"
  mood: number; // 1-5
  note: string | null;
}

export interface MoodUpsertPayload {
  mood: number;
  note?: string;
}

export const listMoodEntries = async (
  params: DateRangeParams = {}
): Promise<MoodEntry[]> => {
  const res = await api.get<MoodEntry[]>("/mood", { params });
  return res.data;
};

export const upsertMoodEntry = async (
  date: string,
  payload: MoodUpsertPayload
): Promise<MoodEntry> => {
  const res = await api.put<MoodEntry>(`/mood/${date}`, payload);
  return res.data;
};

export const deleteMoodEntry = async (date: string): Promise<void> => {
  await api.delete(`/mood/${date}`);
};

// ---------------------------------------------------------------------------
// Water — app/wellness/schemas.py::WaterResponse / WaterUpsert
// ---------------------------------------------------------------------------

// Mirrors app/wellness/service.py::DEFAULT_WATER_GOAL — used purely as a
// client-side display default before today's row exists on the server.
export const DEFAULT_WATER_GOAL = 8;

export interface WaterEntry {
  id: number;
  date: string; // "YYYY-MM-DD"
  glasses: number;
  goal: number;
}

export interface WaterUpsertPayload {
  glasses: number;
  goal?: number;
}

export const listWaterLogs = async (
  params: DateRangeParams = {}
): Promise<WaterEntry[]> => {
  const res = await api.get<WaterEntry[]>("/water", { params });
  return res.data;
};

export const upsertWaterLog = async (
  date: string,
  payload: WaterUpsertPayload
): Promise<WaterEntry> => {
  const res = await api.put<WaterEntry>(`/water/${date}`, payload);
  return res.data;
};

export const deleteWaterLog = async (date: string): Promise<void> => {
  await api.delete(`/water/${date}`);
};

// ---------------------------------------------------------------------------
// Sleep — app/wellness/schemas.py::SleepResponse / SleepUpsert
// ---------------------------------------------------------------------------

export interface SleepEntry {
  id: number;
  date: string; // "YYYY-MM-DD"
  hours: string; // Decimal serialized as a string, e.g. "7.50"
  quality: number | null; // 1-5, optional
  bedtime: string | null; // "HH:MM"
  wake_time: string | null; // "HH:MM"
}

export interface SleepUpsertPayload {
  hours: number;
  quality?: number;
  bedtime?: string;
  wake_time?: string;
}

export const listSleepEntries = async (
  params: DateRangeParams = {}
): Promise<SleepEntry[]> => {
  const res = await api.get<SleepEntry[]>("/sleep", { params });
  return res.data;
};

export const upsertSleepEntry = async (
  date: string,
  payload: SleepUpsertPayload
): Promise<SleepEntry> => {
  const res = await api.put<SleepEntry>(`/sleep/${date}`, payload);
  return res.data;
};

export const deleteSleepEntry = async (date: string): Promise<void> => {
  await api.delete(`/sleep/${date}`);
};

/**
 * `hours` comes back from the API as a Decimal-serialized string (e.g.
 * "7.50"). Parse it defensively — an unparseable value renders as 0 rather
 * than propagating NaN into charts/aggregates.
 */
export const parseSleepHours = (hours: string | null | undefined): number => {
  const parsed = Number(hours);
  return Number.isFinite(parsed) ? parsed : 0;
};
