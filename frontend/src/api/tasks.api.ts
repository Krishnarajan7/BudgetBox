import api from "./axios";

// Mirrors backend TaskResponse (app/tasks/schemas.py). GET /tasks
// (app/tasks/router.py -> list_tasks in service.py) now includes completion
// status and priority directly, so no client-side workaround is needed.
export interface TaskResponse {
  id: number;
  title: string;
  description: string | null;
  due_at: string | null;
  is_active: boolean;
  priority: "low" | "medium" | "high";
  completed: boolean;
  completed_at: string | null;
}

export interface TaskCreatePayload {
  title: string;
  description?: string | null;
  due_at?: string | null;
  priority?: "low" | "medium" | "high";
}

// Partial update payload for PATCH /tasks/{task_id} (app/tasks/schemas.py
// TaskUpdate). All fields optional; only provided fields are changed.
export interface TaskUpdatePayload {
  title?: string;
  description?: string | null;
  due_at?: string | null;
  priority?: "low" | "medium" | "high";
}

// Shape returned by both POST /tasks/{id}/complete and
// PATCH /tasks/{id}/logs/today (app/tasks/router.py).
export interface TaskLogResponse {
  task_id: number;
  completed: boolean;
  completed_at: string;
}

export const listTasks = async (): Promise<TaskResponse[]> => {
  const res = await api.get<TaskResponse[]>("/tasks");
  return res.data;
};

export const createTask = async (
  payload: TaskCreatePayload
): Promise<TaskResponse> => {
  const res = await api.post<TaskResponse>("/tasks", payload);
  return res.data;
};

// Partially updates an existing task (title/description/due_at/priority)
// via PATCH /tasks/{task_id}. Preserves the task's id and log history,
// unlike the old delete+recreate workaround.
export const updateTask = async (
  taskId: number,
  payload: TaskUpdatePayload
): Promise<TaskResponse> => {
  const res = await api.patch<TaskResponse>(`/tasks/${taskId}`, payload);
  return res.data;
};

export const deleteTask = async (taskId: number): Promise<void> => {
  await api.delete(`/tasks/${taskId}`);
};

// Marks the task complete "for today". Safe to call even if already
// completed — service.py's complete_task_for_today() returns the existing
// log without erroring in that case.
export const completeTask = async (
  taskId: number
): Promise<TaskLogResponse> => {
  const res = await api.post<TaskLogResponse>(`/tasks/${taskId}/complete`);
  return res.data;
};

// Used to explicitly set completion state (including un-completing, which
// the /complete endpoint has no way to express).
export const patchTaskLogToday = async (
  taskId: number,
  completed: boolean
): Promise<TaskLogResponse> => {
  const res = await api.patch<TaskLogResponse>(
    `/tasks/${taskId}/logs/today`,
    { completed }
  );
  return res.data;
};
