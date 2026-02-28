import { useEffect, useState } from "react";
import { getProfile, updateProfile } from "@/api/profile.api";

export function useProfile() {
  const [profile, setProfile] = useState<any>(null);
  const [stats, setStats] = useState<any>(null);
  const [activity, setActivity] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchProfile = async () => {
    try {
      setLoading(true);
      const data = await getProfile();
      setProfile(data.profile);
      setStats(data.stats);
      setActivity(data.activity);
    } catch (err: any) {
      setError("Failed to load profile");
    } finally {
      setLoading(false);
    }
  };

  const saveProfile = async (payload: any) => {
    try {
      setSaving(true);
      const updated = await updateProfile(payload);
      setProfile(updated);
    } catch {
      throw new Error("Update failed");
    } finally {
      setSaving(false);
    }
  };

  useEffect(() => {
    fetchProfile();
  }, []);

  return {
    profile,
    stats,
    activity,
    loading,
    saving,
    error,
    saveProfile,
    refetch: fetchProfile,
  };
}
