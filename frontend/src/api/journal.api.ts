import api from "./axios";

// Mirrors backend app/journal/schemas.py + router.py. Two resources share
// this router: Notes (mounted at /notes) and Journal entries (mounted at
// /journal). Neither is behind an /api prefix — main.py registers the
// combined router directly, same as every other module's router.

// ---------------------------------------------------------------------------
// Notes — app/journal/schemas.py::NoteCreate / NoteUpdate / NoteResponse
// ---------------------------------------------------------------------------

export interface Note {
  id: number;
  title: string;
  body: string;
  pinned: boolean;
  created_at: string;
  updated_at: string;
}

export interface NoteCreatePayload {
  title: string;
  body: string;
  pinned?: boolean;
}

// Partial update payload for PATCH /notes/{note_id} (NoteUpdate). All
// fields optional; only provided fields are changed.
export interface NoteUpdatePayload {
  title?: string;
  body?: string;
  pinned?: boolean;
}

export interface ListNotesParams {
  q?: string;
  pinned?: boolean;
}

export const listNotes = async (
  params: ListNotesParams = {}
): Promise<Note[]> => {
  const res = await api.get<Note[]>("/notes", { params });
  return res.data;
};

export const createNote = async (
  payload: NoteCreatePayload
): Promise<Note> => {
  const res = await api.post<Note>("/notes", payload);
  return res.data;
};

export const updateNote = async (
  noteId: number,
  patch: NoteUpdatePayload
): Promise<Note> => {
  const res = await api.patch<Note>(`/notes/${noteId}`, patch);
  return res.data;
};

export const deleteNote = async (noteId: number): Promise<void> => {
  await api.delete(`/notes/${noteId}`);
};

// ---------------------------------------------------------------------------
// Journal entries — app/journal/schemas.py::JournalEntryUpsert /
// JournalEntryResponse
// ---------------------------------------------------------------------------

export interface JournalEntry {
  id: number;
  date: string; // "YYYY-MM-DD"
  body: string;
  mood_note: string | null;
  created_at: string;
  updated_at: string;
}

export interface JournalEntryUpsertPayload {
  body: string;
  mood_note?: string | null;
}

export interface ListJournalEntriesParams {
  start_date?: string; // "YYYY-MM-DD"
  end_date?: string; // "YYYY-MM-DD"
}

export const listJournalEntries = async (
  params: ListJournalEntriesParams = {}
): Promise<JournalEntry[]> => {
  const res = await api.get<JournalEntry[]>("/journal", { params });
  return res.data;
};

export const upsertJournalEntry = async (
  date: string,
  payload: JournalEntryUpsertPayload
): Promise<JournalEntry> => {
  const res = await api.put<JournalEntry>(`/journal/${date}`, payload);
  return res.data;
};

export const deleteJournalEntry = async (date: string): Promise<void> => {
  await api.delete(`/journal/${date}`);
};

// ---------------------------------------------------------------------------
// Day summary — GET /journal/{date}/day (app/journal/service.py::get_day_summary).
// No explicit pydantic response_model on the backend; shape below mirrors
// the plain dict the service function returns.
// ---------------------------------------------------------------------------

// Mirrors app/models/transaction.py::TransactionType ("income" | "expense").
export type TransactionType = "income" | "expense";

export interface JournalDayTransaction {
  id: number;
  type: TransactionType;
  amount: number;
  note: string | null;
  category_id: number;
  occurred_at: string;
}

export interface JournalDayTaskCompleted {
  id: number;
  title: string;
}

export interface JournalDayHabitCompleted {
  id: number;
  name: string;
}

export interface JournalDay {
  date: string; // "YYYY-MM-DD"
  entry: JournalEntry | null;
  transactions: JournalDayTransaction[];
  tasks_completed: JournalDayTaskCompleted[];
  habits_completed: JournalDayHabitCompleted[];
}

export const getJournalDay = async (date: string): Promise<JournalDay> => {
  const res = await api.get<JournalDay>(`/journal/${date}/day`);
  return res.data;
};
