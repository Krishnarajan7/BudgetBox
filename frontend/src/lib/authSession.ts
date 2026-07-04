import { useEffect, useState } from "react";
import type { NavigateFunction } from "react-router-dom";
import api from "@/api/axios";
import { logout as logoutRequest } from "@/api/auth.api";

const ACCESS_TOKEN_KEY = "access_token";
const REFRESH_TOKEN_KEY = "refresh_token";

export function isAuthenticated(): boolean {
  return Boolean(localStorage.getItem(ACCESS_TOKEN_KEY));
}

export function clearAuthTokens() {
  localStorage.removeItem(ACCESS_TOKEN_KEY);
  localStorage.removeItem(REFRESH_TOKEN_KEY);
}

/**
 * Revokes the current session on the server and clears local tokens, then
 * navigates to /auth. Local state is always cleared and the user is always
 * redirected, even if the server call fails (expired/invalid refresh token,
 * network error, etc).
 */
export async function signOut(navigate: NavigateFunction) {
  const refreshToken = localStorage.getItem(REFRESH_TOKEN_KEY);

  try {
    if (refreshToken) {
      await logoutRequest(refreshToken);
    }
  } catch (error) {
    console.warn("Failed to revoke session on the server", error);
  } finally {
    clearAuthTokens();
    navigate("/auth", { replace: true });
  }
}

interface CurrentUser {
  name: string;
  email: string;
}

/**
 * Lightweight hook that fetches the signed-in user's display name/email for
 * layout chrome (header, sidebars). Intentionally separate from the
 * profile page's data hook — this only cares about a name/email to render
 * instead of the "Alex Johnson" placeholder.
 */
export function useCurrentUser(): CurrentUser | null {
  const [user, setUser] = useState<CurrentUser | null>(null);

  useEffect(() => {
    if (!isAuthenticated()) {
      return;
    }

    let isMounted = true;

    api
      .get("/profile")
      .then((res) => {
        if (!isMounted) return;
        const profile = res.data?.profile;
        if (!profile) return;

        const name = [profile.first_name, profile.last_name]
          .filter(Boolean)
          .join(" ")
          .trim();

        setUser({
          name: name || profile.email,
          email: profile.email,
        });
      })
      .catch(() => {
        // Silently ignore — layout falls back to placeholder text.
      });

    return () => {
      isMounted = false;
    };
  }, []);

  return user;
}
