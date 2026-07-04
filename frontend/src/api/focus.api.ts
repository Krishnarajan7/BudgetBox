import api from "./axios";

// Mirrors backend app/focus/schemas.py + app/models/focus_session.py.
export type FocusKind = "work" | "break";

export interface FocusSessionResponse {
  id: number;
  started_at: string;
  duration_min: number;
  kind: FocusKind;
  label: string | null;
  completed: boolean;
  created_at: string;
}

export interface FocusSessionCreatePayload {
  started_at: string;
  duration_min: number;
  kind: FocusKind;
  label?: string | null;
  completed: boolean;
}

export interface FocusStatsResponse {
  today_minutes: number;
  week_minutes: number;
  today_sessions: number;
  week_sessions: number;
  current_streak_days: number;
}

export interface ListFocusSessionsParams {
  start_date?: string;
  end_date?: string;
}

// GET /focus/sessions - ordered started_at desc by the backend.
export const listFocusSessions = async (
  params?: ListFocusSessionsParams
): Promise<FocusSessionResponse[]> => {
  const res = await api.get<FocusSessionResponse[]>("/focus/sessions", { params });
  return res.data;
};

// POST /focus/sessions - logged client-side once a pomodoro phase ends
// (naturally or via an early manual stop).
export const createFocusSession = async (
  payload: FocusSessionCreatePayload
): Promise<FocusSessionResponse> => {
  const res = await api.post<FocusSessionResponse>("/focus/sessions", payload);
  return res.data;
};

export const deleteFocusSession = async (sessionId: number): Promise<void> => {
  await api.delete(`/focus/sessions/${sessionId}`);
};

// GET /focus/stats -> today/week totals + current streak.
export const getFocusStats = async (): Promise<FocusStatsResponse> => {
  const res = await api.get<FocusStatsResponse>("/focus/stats");
  return res.data;
};
