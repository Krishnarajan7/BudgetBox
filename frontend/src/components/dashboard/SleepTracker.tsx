import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { Moon, AlertCircle } from "lucide-react";
import {
  addLocalDays,
  dashboardKeys,
  listSleepEntries,
  toLocalDateString,
} from "@/api/dashboard.api";
import { Skeleton } from "@/components/ui/skeleton";

// quality is an optional 1-5 rating (app/wellness/schemas.py::SleepUpsert).
// Map it to the same poor/good/great tiers the old mock used, but only when
// the user actually recorded a quality — otherwise stay neutral rather than
// inventing one.
function qualityClass(quality: number | null): string {
  if (quality === null) return "bg-muted-foreground/30";
  if (quality >= 4) return "bg-success/40";
  if (quality >= 3) return "bg-warning/40";
  return "bg-destructive/40";
}

export function SleepTracker() {
  const today = new Date();
  const todayStr = toLocalDateString(today);
  const startStr = toLocalDateString(addLocalDays(today, -6));

  const { data, isLoading, isError } = useQuery({
    queryKey: dashboardKeys.sleep(startStr, todayStr),
    queryFn: () => listSleepEntries(startStr, todayStr),
  });

  // Backend orders by date desc; take the most recent few nights for the bars.
  const entries = data ?? [];
  const lastNight = entries.find((e) => e.date === todayStr);
  const avgSleep =
    entries.length > 0
      ? (entries.reduce((sum, e) => sum + Number(e.hours), 0) / entries.length).toFixed(1)
      : null;

  return (
    <div className="bg-card rounded-lg border border-border shadow-soft animate-fade-in">
      <div className="p-4 border-b border-border flex items-center justify-between">
        <div>
          <h3 className="text-sm font-semibold text-foreground">Sleep Log</h3>
          <p className="text-xs text-muted-foreground mt-0.5">Recent sleep patterns</p>
        </div>
        <Link to="/sleep" className="text-xs font-medium text-primary hover:underline">
          View log
        </Link>
      </div>

      {isLoading ? (
        <div className="p-4 space-y-3">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-6 w-full" />
          ))}
        </div>
      ) : isError ? (
        <div className="p-8 text-center">
          <AlertCircle className="w-6 h-6 text-destructive mx-auto mb-2" />
          <p className="text-sm text-muted-foreground">Couldn't load sleep data</p>
        </div>
      ) : entries.length === 0 ? (
        <div className="p-8 text-center">
          <Moon className="w-6 h-6 text-muted-foreground mx-auto mb-2" />
          <p className="text-sm text-muted-foreground">No sleep logged this week</p>
          <Link to="/sleep" className="text-xs text-primary hover:underline">
            Log last night
          </Link>
        </div>
      ) : (
        <div className="p-4 space-y-3">
          {entries.slice(0, 4).map((item) => (
            <div key={item.id} className="flex items-center gap-3">
              <span className="text-xs text-muted-foreground w-14">
                {new Date(item.date + "T00:00:00").toLocaleDateString("en-US", {
                  month: "short",
                  day: "numeric",
                })}
              </span>
              <div className="flex-1 h-6 bg-muted rounded-sm overflow-hidden">
                <div
                  className={`h-full rounded-sm transition-smooth ${qualityClass(item.quality)}`}
                  style={{ width: `${Math.min((Number(item.hours) / 10) * 100, 100)}%` }}
                />
              </div>
              <span className="text-sm font-medium text-foreground w-12 text-right">
                {Number(item.hours)}h
              </span>
            </div>
          ))}
        </div>
      )}

      <div className="p-4 border-t border-border">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Moon className="w-4 h-4 text-muted-foreground" />
            <span className="text-xs text-muted-foreground">
              {lastNight ? "Last night" : "This week's avg."}
            </span>
          </div>
          <span className="text-sm font-semibold text-foreground">
            {lastNight ? `${Number(lastNight.hours)}h` : avgSleep ? `${avgSleep}h` : "—"}
          </span>
        </div>
      </div>
    </div>
  );
}
