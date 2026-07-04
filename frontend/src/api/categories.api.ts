import api from "./axios";

export type CategoryType = "income" | "expense";

export interface Category {
  id: number;
  name: string;
  type: CategoryType;
}

export interface CategoryCreatePayload {
  name: string;
  type: CategoryType;
}

export interface CategoryUpdatePayload {
  name?: string;
  type?: CategoryType;
}

export const listCategories = async (type?: CategoryType): Promise<Category[]> => {
  const res = await api.get<Category[]>("/categories", {
    params: type ? { type } : undefined,
  });
  return res.data;
};

export const createCategory = async (
  payload: CategoryCreatePayload
): Promise<Category> => {
  const res = await api.post<Category>("/categories", payload);
  return res.data;
};

export const updateCategory = async (
  id: number,
  payload: CategoryUpdatePayload
): Promise<Category> => {
  const res = await api.patch<Category>(`/categories/${id}`, payload);
  return res.data;
};

export const deleteCategory = async (id: number): Promise<void> => {
  await api.delete(`/categories/${id}`);
};
