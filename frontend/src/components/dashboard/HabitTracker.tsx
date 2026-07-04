import { Link } from "react-router-dom";
import { useQueries, useQuery } from "@tanstack/react-query";
import { AlertCircle, Flame, Target } from "lucide-react";
import { cn } from "@/lib/utils";
import { Skeleton } from "@/components/ui/skeleton";
import { getHabitInsights, getHabitToday, listHabits } from "@/api/habits.api";

// Read-only preview of the Habits page. Uses the same "habits" /
// "habit-today" / "habit-insights" query keys as Habits.tsx so the cache is
// shared instead of double-fetched.
//
// Note: the backend only exposes an aggregate weekly score per habit
// (app/habits/intelligence.py::weekly_performance), not which specific past
// days were completed — so unlike the old mock, this shows a real progress
// bar instead of a fabricated 7-day checkbox grid.
export function HabitTracker() {
  const {
    data: habits,
    isLoading: habitsLoading,
    isError: habitsError,
  } = useQuery({
    queryKey: ["habits"],
    queryFn: listHabits,
  });

  const activeHabits = (habits ?? []).filter((h) => h.is_active);

  const todayQueries = useQueries({
    queries: activeHabits.map((habit) => ({
      queryKey: ["habit-today", habit.id],
      queryFn: () => getHabitToday(habit.id),
    })),
  });

  const insightsQueries = useQueries({
    queries: activeHabits.map((habit) => ({
      queryKey: ["habit-insights", habit.id],
      queryFn: () => getHabitInsights(habit.id),
    })),
  });

  const doneToday = todayQueries.filter((q) => q.data?.completed).length;
  const percentDone =
    activeHabits.length > 0
      ? Math.round((doneToday / activeHabits.length) * 100)
      : 0;

  const isLoading = habitsLoading;
  const preview = activeHabits.slice(0, 4);

  return (
    <div className="bg-card rounded-lg border border-border shadow-soft animate-fade-in">
      <div className="p-4 border-b border-border flex items-center justify-between">
        <div>
          <h3 className="text-sm font-semibold text-foreground">Habits</h3>
          <p className="text-xs text-muted-foreground mt-0.5">
            {isLoading
              ? "Loading…"
              : `${doneToday}/${activeHabits.length} done today · ${percentDone}%`}
          </p>
        </div>
        <Link to="/habits" className="text-xs font-medium text-primary hover:underline">
          View all
        </Link>
      </div>

      {isLoading ? (
        <div className="p-4 space-y-4">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-10 w-full" />
          ))}
        </div>
      ) : habitsError ? (
        <div className="p-8 text-center">
          <AlertCircle className="w-6 h-6 text-destructive mx-auto mb-2" />
          <p className="text-sm text-muted-foreground">Couldn't load habits</p>
        </div>
      ) : preview.length === 0 ? (
        <div className="p-8 text-center">
          <Target className="w-6 h-6 text-muted-foreground mx-auto mb-2" />
          <p className="text-sm text-muted-foreground">No habits yet</p>
          <Link to="/habits" className="text-xs text-primary hover:underline">
            Start a habit
          </Link>
        </div>
      ) : (
        <div className="p-4 space-y-4">
          {preview.map((habit, index) => {
            const completedToday = todayQueries[index]?.data?.completed ?? false;
            const insights = insightsQueries[index]?.data;
            const streak = insights?.streak.current_streak ?? 0;
            const score = insights?.weekly.score ?? 0;

            return (
              <div key={habit.id}>
                <div className="flex items-center justify-between mb-1.5">
                  <div className="flex items-center gap-2 min-w-0">
                    <div
                      className={cn(
                        "w-4 h-4 rounded-full flex items-center justify-center flex-shrink-0",
                        completedToday ? "bg-primary" : "bg-muted"
                      )}
                    />
                    <span className="text-sm font-medium text-foreground truncate">
                      {habit.name}
                    </span>
                  </div>
                  <span className="text-xs text-muted-foreground flex items-center gap-1 flex-shrink-0">
                    <Flame className="w-3 h-3 text-warning" />
                    {streak} day{streak === 1 ? "" : "s"}
                  </span>
                </div>
                <div className="h-2 rounded-full bg-muted overflow-hidden">
                  <div
                    className="h-full rounded-full bg-primary transition-smooth"
                    style={{ width: `${Math.min(score, 100)}%` }}
                  />
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
