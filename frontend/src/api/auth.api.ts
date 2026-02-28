import api from "./axios";

export interface TokenResponse {
  access_token: string;
  refresh_token: string;
}

export const login = async (
  email: string,
  password: string
): Promise<TokenResponse> => {
  const res = await api.post("/auth/login", {
    email,
    password,
  });
  return res.data;
};

export const register = async (email: string, password: string) => {
  const res = await api.post("/auth/register", {
    email,
    password,
  });
  return res.data;
};

export const refreshToken = async (
  token: string
): Promise<{ access_token: string }> => {
  const res = await api.post("/auth/refresh", {
    refresh_token: token,
  });
  return res.data;
};

export const logout = async (refreshToken: string) => {
  await api.post("/auth/logout", {
    refresh_token: refreshToken,
  });
};
