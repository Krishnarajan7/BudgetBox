import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { AlertCircle, CalendarDays, CheckCircle2, Circle } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import {
  dashboardKeys,
  getCalendarMonth,
  toLocalDateString,
  toLocalMonthString,
} from "@/api/dashboard.api";

const WEEKDAY_LABELS = ["S", "M", "T", "W", "T", "F", "S"];

// The shared ui/calender.tsx <Calendar> component has no way to annotate
// individual days (no dot/modifier slot), so this widget renders its own
// compact month grid instead — it's the only way to honestly show which
// days actually have calendar entries without touching a component owned
// by another part of the app.
export function DashboardCalendar() {
  const now = new Date();
  const year = now.getFullYear();
  const month = now.getMonth(); // 0-indexed
  const monthKey = toLocalMonthString(now);
  const todayKey = toLocalDateString(now);

  const [selectedKey, setSelectedKey] = useState(todayKey);

  const { data, isLoading, isError } = useQuery({
    queryKey: dashboardKeys.calendar(monthKey),
    queryFn: () => getCalendarMonth(monthKey),
  });

  const days = data?.days ?? {};

  const cells = useMemo(() => {
    const firstOfMonth = new Date(year, month, 1);
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    const leading = firstOfMonth.getDay(); // 0 = Sunday

    const result: { key: string; day: number }[] = [];
    for (let i = 0; i < leading; i++) {
      result.push({ key: `blank-${i}`, day: 0 });
    }
    for (let d = 1; d <= daysInMonth; d++) {
      const key = `${year}-${String(month + 1).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
      result.push({ key, day: d });
    }
    return result;
  }, [year, month]);

  const selectedDay = days[selectedKey];
  const selectedLabel = useMemo(() => {
    const [y, m, d] = selectedKey.split("-").map(Number);
    return new Date(y, m - 1, d).toLocaleDateString("en-US", {
      weekday: "long",
      month: "long",
      day: "numeric",
    });
  }, [selectedKey]);

  return (
    <Card className="border-border/50">
      <CardHeader className="pb-3">
        <CardTitle className="text-base font-medium flex items-center gap-2">
          <CalendarDays className="w-4 h-4 text-primary" />
          Calendar
        </CardTitle>
      </CardHeader>
      <CardContent className="pt-0">
        {isLoading ? (
          <Skeleton className="h-64 w-full" />
        ) : isError ? (
          <div className="text-center py-6">
            <AlertCircle className="w-6 h-6 text-destructive mx-auto mb-2" />
            <p className="text-sm text-muted-foreground">Couldn't load calendar</p>
          </div>
        ) : (
          <>
            <p className="text-xs text-muted-foreground mb-2 text-center">
              {now.toLocaleDateString("en-US", { month: "long", year: "numeric" })}
            </p>
            <div className="grid grid-cols-7 gap-1 mb-1">
              {WEEKDAY_LABELS.map((label, i) => (
                <div
                  key={i}
                  className="h-6 flex items-center justify-center text-[10px] text-muted-foreground"
                >
                  {label}
                </div>
              ))}
            </div>
            <div className="grid grid-cols-7 gap-1">
              {cells.map((cell) => {
                if (cell.day === 0) {
                  return <div key={cell.key} />;
                }
                const dayData = days[cell.key];
                const hasEntries =
                  !!dayData &&
                  (dayData.events.length > 0 || dayData.tasks_due.length > 0);
                const isToday = cell.key === todayKey;
                const isSelected = cell.key === selectedKey;

                return (
                  <button
                    key={cell.key}
                    onClick={() => setSelectedKey(cell.key)}
                    className={cn(
                      "relative h-8 w-8 mx-auto flex items-center justify-center rounded-md text-xs transition-smooth",
                      isSelected
                        ? "bg-primary text-primary-foreground font-semibold"
                        : isToday
                        ? "bg-accent text-accent-foreground font-semibold"
                        : "text-foreground hover:bg-muted"
                    )}
                  >
                    {cell.day}
                    {hasEntries && (
                      <span
                        className={cn(
                          "absolute bottom-0.5 w-1 h-1 rounded-full",
                          isSelected ? "bg-primary-foreground" : "bg-primary"
                        )}
                      />
                    )}
                  </button>
                );
              })}
            </div>

            <div className="mt-4 pt-4 border-t border-border">
              <p className="text-xs font-medium text-foreground mb-2">{selectedLabel}</p>
              {!selectedDay ||
              (selectedDay.events.length === 0 && selectedDay.tasks_due.length === 0) ? (
                <p className="text-xs text-muted-foreground">Nothing scheduled</p>
              ) : (
                <div className="space-y-1.5">
                  {selectedDay.events.map((event) => (
                    <div key={`event-${event.id}`} className="flex items-center gap-2 text-xs">
                      <span className="w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0" />
                      <span className="text-foreground truncate">{event.title}</span>
                      {event.time && (
                        <span className="text-muted-foreground flex-shrink-0">{event.time}</span>
                      )}
                    </div>
                  ))}
                  {selectedDay.tasks_due.map((task) => (
                    <div key={`task-${task.id}`} className="flex items-center gap-2 text-xs">
                      {task.completed ? (
                        <CheckCircle2 className="w-3 h-3 text-success flex-shrink-0" />
                      ) : (
                        <Circle className="w-3 h-3 text-muted-foreground flex-shrink-0" />
                      )}
                      <span
                        className={cn(
                          "truncate",
                          task.completed ? "text-muted-foreground line-through" : "text-foreground"
                        )}
                      >
                        {task.title}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </>
        )}
      </CardContent>
    </Card>
  );
}
