import api from "./axios";

export interface Expense {
  id: number;
  amount: number;
  wallet_id: number;
  category_id: number;
  note: string | null;
  // ISO-8601 datetime string
  occurred_at: string;
}

export interface ExpenseCreatePayload {
  wallet_id: number;
  category_id: number;
  amount: number;
  // ISO-8601 datetime string
  occurred_at: string;
  note?: string | null;
}

export interface ExpenseUpdatePayload {
  amount?: number;
  note?: string | null;
  occurred_at?: string;
  category_id?: number;
  wallet_id?: number;
}

export const listExpenses = async (): Promise<Expense[]> => {
  const res = await api.get<Expense[]>("/expenses");
  return res.data;
};

export const createExpense = async (
  payload: ExpenseCreatePayload
): Promise<Expense> => {
  const res = await api.post<Expense>("/expenses", payload);
  return res.data;
};

export const updateExpense = async (
  id: number,
  payload: ExpenseUpdatePayload
): Promise<Expense> => {
  const res = await api.patch<Expense>(`/expenses/${id}`, payload);
  return res.data;
};

export const deleteExpense = async (id: number): Promise<void> => {
  await api.delete(`/expenses/${id}`);
};
