import api from "./axios";

// Matches app/budgets/schemas.py::BudgetUsageResponse — the shape returned
// by GET /budgets, already joined with spend for the month.
export interface Budget {
  id: number;
  category_id: number;
  category_name: string;
  // "YYYY-MM"
  month: string;
  limit: number;
  spent: number;
  remaining: number;
  percent_used: number;
}

// Matches app/budgets/schemas.py::BudgetResponse — returned by
// POST /budgets and PATCH /budgets/{id}, which don't carry usage data.
export interface BudgetRecord {
  id: number;
  category_id: number;
  month: string;
  limit: number;
}

export interface BudgetCreatePayload {
  category_id: number;
  // "YYYY-MM"
  month: string;
  limit: number;
}

export interface BudgetUpdatePayload {
  limit?: number;
}

// `month` defaults to the current month server-side (app/budgets/router.py)
// when omitted, but callers here always pass one explicitly so the UI and
// the query cache key stay in sync.
export const listBudgets = async (month: string): Promise<Budget[]> => {
  const res = await api.get<Budget[]>("/budgets", { params: { month } });
  return res.data;
};

export const createBudget = async (
  payload: BudgetCreatePayload
): Promise<BudgetRecord> => {
  const res = await api.post<BudgetRecord>("/budgets", payload);
  return res.data;
};

export const updateBudget = async (
  id: number,
  payload: BudgetUpdatePayload
): Promise<BudgetRecord> => {
  const res = await api.patch<BudgetRecord>(`/budgets/${id}`, payload);
  return res.data;
};

export const deleteBudget = async (id: number): Promise<void> => {
  await api.delete(`/budgets/${id}`);
};
