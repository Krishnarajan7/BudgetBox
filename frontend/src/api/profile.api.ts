import api from "./axios";

export interface ProfileData {
  first_name: string;
  last_name: string;
  email: string;
  phone: string | null;
  location: string | null;
  occupation: string | null;
  website: string | null;
  bio: string | null;
  timezone: string;
  avatar_url: string | null;
  join_date: string;
}

// Mirrors backend ProfileUpdate (app/profile/schemas.py) — email is
// intentionally excluded since the backend does not accept it.
export interface ProfileUpdatePayload {
  first_name: string;
  last_name: string;
  phone: string | null;
  location: string | null;
  occupation: string | null;
  website: string | null;
  bio: string | null;
  timezone: string;
  avatar_url: string | null;
}

export interface StreakStats {
  current_streak: number;
  longest_streak: number;
  active_days: number;
}

export interface ProfileStats {
  task_streak: StreakStats;
  habit_streak: StreakStats;
  total_tasks_completed: number;
  total_habits_completed: number;
  total_expenses: number;
  total_income: number;
  total_budgets: number;
  total_categories: number;
  total_food_logs: number;
  total_nutrient_profiles: number;
  achievements_unlocked: number;
  total_achievements: number;
}

// Keyed by ISO date ("YYYY-MM-DD") -> activity count for that day.
export type ProfileActivity = Record<string, number>;

export interface ProfileGetResponse {
  profile: ProfileData;
  stats: ProfileStats;
  activity: ProfileActivity;
}

export const getProfile = async (): Promise<ProfileGetResponse> => {
  const res = await api.get("/profile");
  return res.data;
};

export const updateProfile = async (
  payload: ProfileUpdatePayload
): Promise<ProfileData> => {
  const res = await api.put("/profile", payload);
  return res.data;
};
