import axios, { AxiosError, InternalAxiosRequestConfig } from "axios";

const BASE_URL = import.meta.env.VITE_API_URL || "http://localhost:8000";

const api = axios.create({
  baseURL: BASE_URL,
  withCredentials: false,
});

interface RetryableRequestConfig extends InternalAxiosRequestConfig {
  _retry?: boolean;
}

// Attach access token automatically
api.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem("access_token");
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => Promise.reject(error)
);

function clearTokens() {
  localStorage.removeItem("access_token");
  localStorage.removeItem("refresh_token");
}

function redirectToAuth() {
  if (typeof window !== "undefined") {
    window.location.href = "/auth";
  }
}

// Single in-flight refresh shared by all concurrent 401s
let refreshPromise: Promise<string> | null = null;

async function performRefresh(): Promise<string> {
  const storedRefreshToken = localStorage.getItem("refresh_token");
  if (!storedRefreshToken) {
    throw new Error("No refresh token available");
  }

  // Use a bare axios call (not the `api` instance) so this request never
  // passes back through the response interceptor below.
  const { data } = await axios.post(`${BASE_URL}/auth/refresh`, {
    refresh_token: storedRefreshToken,
  });

  localStorage.setItem("access_token", data.access_token);
  localStorage.setItem("refresh_token", data.refresh_token);

  return data.access_token as string;
}

// Handle auth errors globally
api.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const originalRequest = error.config as RetryableRequestConfig | undefined;

    if (error.response?.status !== 401 || !originalRequest) {
      return Promise.reject(error);
    }

    const isRefreshCall = originalRequest.url?.includes("/auth/refresh");
    const isAuthEntryCall =
      originalRequest.url?.includes("/auth/login") ||
      originalRequest.url?.includes("/auth/register");

    // A failed login/register attempt is not an expired session — just let
    // the caller handle the error (e.g. show "invalid credentials").
    if (isAuthEntryCall) {
      return Promise.reject(error);
    }

    // Never try to refresh in response to the refresh call itself, and
    // never retry a request more than once.
    if (isRefreshCall || originalRequest._retry) {
      clearTokens();
      redirectToAuth();
      return Promise.reject(error);
    }

    if (!localStorage.getItem("refresh_token")) {
      clearTokens();
      redirectToAuth();
      return Promise.reject(error);
    }

    originalRequest._retry = true;

    try {
      if (!refreshPromise) {
        refreshPromise = performRefresh().finally(() => {
          refreshPromise = null;
        });
      }

      const newAccessToken = await refreshPromise;

      originalRequest.headers.Authorization = `Bearer ${newAccessToken}`;

      return api(originalRequest);
    } catch (refreshError) {
      clearTokens();
      redirectToAuth();
      return Promise.reject(refreshError);
    }
  }
);

export default api;
