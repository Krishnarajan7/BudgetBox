import api from "./axios";

// Mirrors backend app/habits/schemas.py::HabitResponse (id, name, is_active).
// Note: the backend does not persist a "color" for a habit — any color shown
// in the UI is a purely client-side cosmetic choice (see Habits.tsx).
export interface Habit {
  id: number;
  name: string;
  is_active: boolean;
}

// Mirrors the dict returned by app/habits/intelligence.py::habit_streak
export interface HabitStreak {
  current_streak: number;
  best_streak: number;
  consistency: number;
}

// Mirrors the dict returned by app/habits/intelligence.py::weekly_performance
// This is an aggregate over the last 7 days — the backend does NOT return
// which specific days were completed, only counts/score.
export interface HabitWeekly {
  completed_days: number;
  missed_days: number;
  score: number;
}

// Mirrors the response of GET /habits/{id}/insights (app/habits/service.py::habit_insights)
export interface HabitInsights {
  streak: HabitStreak;
  weekly: HabitWeekly;
  momentum: "improving" | "declining";
}

// Mirrors app/habits/schemas.py::HabitLogResponse (shape returned by the
// PATCH /habits/{id}/logs/today endpoint).
export interface HabitLog {
  habit_id: number;
  date: string; // "YYYY-MM-DD"
  completed: boolean;
}

// Mirrors app/habits/schemas.py::HabitLogPatch — both fields optional.
export interface HabitLogPatchPayload {
  date?: string;
  completed?: boolean;
}

// Mirrors app/habits/schemas.py::HabitUpdate — both fields optional.
export interface HabitUpdatePayload {
  name?: string;
  is_active?: boolean;
}

/** Local (not UTC) "YYYY-MM-DD" for a given Date, defaulting to now. */
export function toLocalDateString(d: Date = new Date()): string {
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export const listHabits = async (): Promise<Habit[]> => {
  const res = await api.get<Habit[]>("/habits");
  return res.data;
};

export const createHabit = async (name: string): Promise<Habit> => {
  const res = await api.post<Habit>("/habits", { name });
  return res.data;
};

export const deleteHabit = async (habitId: number): Promise<void> => {
  await api.delete(`/habits/${habitId}`);
};

export const getHabitInsights = async (
  habitId: number
): Promise<HabitInsights> => {
  const res = await api.get<HabitInsights>(`/habits/${habitId}/insights`);
  return res.data;
};

/**
 * GET /habits/{id}/logs/today — reads today's completion status without
 * creating a log row (unlike the PATCH endpoint, which persists a row as
 * a side effect).
 */
export const getHabitToday = async (habitId: number): Promise<HabitLog> => {
  const res = await api.get<HabitLog>(`/habits/${habitId}/logs/today`);
  return res.data;
};

/** PATCH /habits/{id}/logs/today — used to toggle today's completion. */
export const patchHabitToday = async (
  habitId: number,
  payload: HabitLogPatchPayload = {}
): Promise<HabitLog> => {
  const res = await api.patch<HabitLog>(
    `/habits/${habitId}/logs/today`,
    payload
  );
  return res.data;
};

/** PATCH /habits/{id} — partial update (rename / activate-deactivate). */
export const updateHabit = async (
  habitId: number,
  payload: HabitUpdatePayload
): Promise<Habit> => {
  const res = await api.patch<Habit>(`/habits/${habitId}`, payload);
  return res.data;
};
