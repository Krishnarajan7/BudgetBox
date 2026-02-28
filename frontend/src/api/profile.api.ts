import api from "./axios";

export const getProfile = async () => {
  const res = await api.get("/profile");
  return res.data;
};

export const updateProfile = async (payload: any) => {
  const res = await api.put("/profile", payload);
  return res.data;
};
