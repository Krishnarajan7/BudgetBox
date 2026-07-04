import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { AlertCircle, Smile } from "lucide-react";
import {
  addLocalDays,
  dashboardKeys,
  listMoodEntries,
  toLocalDateString,
} from "@/api/dashboard.api";
import { Skeleton } from "@/components/ui/skeleton";

const MAX_MOOD = 5;
const MOOD_EMOJI: Record<number, string> = {
  1: "😢",
  2: "😔",
  3: "😐",
  4: "😊",
  5: "😄",
};

export function MoodChart() {
  const today = new Date();
  const todayStr = toLocalDateString(today);
  const startStr = toLocalDateString(addLocalDays(today, -6));

  const { data, isLoading, isError } = useQuery({
    queryKey: dashboardKeys.mood(startStr, todayStr),
    queryFn: () => listMoodEntries(startStr, todayStr),
  });

  const entries = data ?? [];
  const byDate = new Map(entries.map((e) => [e.date, e]));

  // Always render the last 7 local calendar days, even the ones with no
  // logged entry — those simply render as an empty bar instead of a
  // fabricated value.
  const days = Array.from({ length: 7 }, (_, i) => addLocalDays(today, -6 + i));

  const avgMood =
    entries.length > 0
      ? (entries.reduce((sum, e) => sum + e.mood, 0) / entries.length).toFixed(1)
      : null;

  return (
    <div className="bg-card rounded-lg border border-border shadow-soft animate-fade-in">
      <div className="p-4 border-b border-border flex items-center justify-between">
        <div>
          <h3 className="text-sm font-semibold text-foreground">Weekly Mood</h3>
          <p className="text-xs text-muted-foreground mt-0.5">How you've been feeling</p>
        </div>
        <Link to="/mood" className="text-xs font-medium text-primary hover:underline">
          Log mood
        </Link>
      </div>

      <div className="p-4">
        {isLoading ? (
          <Skeleton className="h-32 w-full" />
        ) : isError ? (
          <div className="text-center py-4">
            <AlertCircle className="w-6 h-6 text-destructive mx-auto mb-2" />
            <p className="text-sm text-muted-foreground">Couldn't load mood data</p>
          </div>
        ) : entries.length === 0 ? (
          <div className="text-center py-6">
            <Smile className="w-6 h-6 text-muted-foreground mx-auto mb-2" />
            <p className="text-sm text-muted-foreground">No mood entries yet</p>
          </div>
        ) : (
          <div className="flex items-end justify-between gap-2 h-32">
            {days.map((day) => {
              const key = toLocalDateString(day);
              const entry = byDate.get(key);
              return (
                <div key={key} className="flex-1 flex flex-col items-center gap-2">
                  <span className="text-lg">{entry ? MOOD_EMOJI[entry.mood] : ""}</span>
                  <div className="w-full bg-muted rounded-t-sm relative flex-1 flex items-end">
                    {entry && (
                      <div
                        className="w-full bg-primary rounded-t-sm transition-smooth"
                        style={{ height: `${(entry.mood / MAX_MOOD) * 100}%` }}
                      />
                    )}
                  </div>
                  <span className="text-xs text-muted-foreground">
                    {day.toLocaleDateString("en-US", { weekday: "short" }).slice(0, 3)}
                  </span>
                </div>
              );
            })}
          </div>
        )}

        <div className="mt-4 pt-4 border-t border-border flex items-center justify-between">
          <span className="text-xs text-muted-foreground">Average mood (7d)</span>
          <span className="text-sm font-medium text-foreground">
            {avgMood ? `${avgMood} / 5` : "—"}
          </span>
        </div>
      </div>
    </div>
  );
}
