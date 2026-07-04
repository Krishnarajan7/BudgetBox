import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { Droplets, AlertCircle } from "lucide-react";
import { cn } from "@/lib/utils";
import { Skeleton } from "@/components/ui/skeleton";
import { dashboardKeys, listWaterLogs, toLocalDateString } from "@/api/dashboard.api";

const DEFAULT_GOAL = 8;

// Read-only preview — logging glasses stays on the /water page.
export function WaterTracker() {
  const today = toLocalDateString();

  const { data, isLoading, isError } = useQuery({
    queryKey: dashboardKeys.water(today, today),
    queryFn: () => listWaterLogs(today, today),
  });

  const todayEntry = data?.[0];
  const glasses = todayEntry?.glasses ?? 0;
  const goal = todayEntry?.goal ?? DEFAULT_GOAL;
  const progress = Math.min((glasses / goal) * 100, 100);

  return (
    <div className="bg-card rounded-lg border border-border shadow-soft animate-fade-in">
      <div className="p-4 border-b border-border flex items-center justify-between">
        <div>
          <h3 className="text-sm font-semibold text-foreground">Water Intake</h3>
          <p className="text-xs text-muted-foreground mt-0.5">Daily hydration goal</p>
        </div>
        <Link to="/water" className="text-xs font-medium text-primary hover:underline">
          Log water
        </Link>
      </div>

      <div className="p-4">
        {isLoading ? (
          <div className="flex justify-center">
            <Skeleton className="w-24 h-24 rounded-full" />
          </div>
        ) : isError ? (
          <div className="text-center py-4">
            <AlertCircle className="w-6 h-6 text-destructive mx-auto mb-2" />
            <p className="text-sm text-muted-foreground">Couldn't load water intake</p>
          </div>
        ) : (
          <>
            <div className="flex items-center justify-center">
              <div className="relative w-24 h-24">
                <svg className="w-full h-full -rotate-90">
                  <circle
                    cx="48"
                    cy="48"
                    r="40"
                    stroke="hsl(var(--muted))"
                    strokeWidth="8"
                    fill="none"
                  />
                  <circle
                    cx="48"
                    cy="48"
                    r="40"
                    stroke="hsl(var(--primary))"
                    strokeWidth="8"
                    fill="none"
                    strokeLinecap="round"
                    strokeDasharray={`${progress * 2.51} 251`}
                    className="transition-all duration-300"
                  />
                </svg>
                <div className="absolute inset-0 flex flex-col items-center justify-center">
                  <Droplets className="w-5 h-5 text-primary mb-1" />
                  <span className="text-lg font-semibold text-foreground">{glasses}</span>
                  <span className="text-[10px] text-muted-foreground">of {goal}</span>
                </div>
              </div>
            </div>

            <div className="mt-4 pt-4 border-t border-border">
              <div className="flex items-center justify-between text-xs">
                <span className="text-muted-foreground">
                  {todayEntry ? "Progress" : "Nothing logged today"}
                </span>
                <span
                  className={cn(
                    "font-medium",
                    glasses >= goal ? "text-success" : "text-foreground"
                  )}
                >
                  {Math.round(progress)}%
                </span>
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
