import { useState } from "react";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Droplets, Plus, Minus, Target, TrendingUp } from "lucide-react";
import { cn } from "@/lib/utils";

interface WaterEntry {
  date: string;
  glasses: number;
}

const GOAL = 8;

const initialHistory: WaterEntry[] = [
  { date: "2024-12-05", glasses: 5 },
  { date: "2024-12-04", glasses: 8 },
  { date: "2024-12-03", glasses: 6 },
  { date: "2024-12-02", glasses: 7 },
  { date: "2024-12-01", glasses: 8 },
  { date: "2024-11-30", glasses: 5 },
  { date: "2024-11-29", glasses: 9 },
];

export default function Water() {
  const [glasses, setGlasses] = useState(5);
  const [history] = useState<WaterEntry[]>(initialHistory);

  const progress = Math.min((glasses / GOAL) * 100, 100);
  const avgIntake = (history.reduce((sum, e) => sum + e.glasses, 0) / history.length).toFixed(1);
  const daysMetGoal = history.filter(e => e.glasses >= GOAL).length;

  return (
    <AppLayout title="Water" subtitle="Stay hydrated">
      <div className="max-w-2xl space-y-6">
        {/* Main Tracker */}
        <div className="bg-card rounded-lg border border-border shadow-soft p-8 animate-fade-in">
          <div className="flex flex-col items-center">
            <h3 className="text-sm font-semibold text-muted-foreground mb-6">Today's Intake</h3>
            
            <div className="relative w-48 h-48 mb-6">
              <svg className="w-full h-full -rotate-90">
                <circle
                  cx="96"
                  cy="96"
                  r="88"
                  stroke="hsl(var(--muted))"
                  strokeWidth="12"
                  fill="none"
                />
                <circle
                  cx="96"
                  cy="96"
                  r="88"
                  stroke="hsl(var(--primary))"
                  strokeWidth="12"
                  fill="none"
                  strokeLinecap="round"
                  strokeDasharray={`${progress * 5.53} 553`}
                  className="transition-all duration-500"
                />
              </svg>
              <div className="absolute inset-0 flex flex-col items-center justify-center">
                <Droplets className="w-8 h-8 text-primary mb-2" />
                <span className="text-4xl font-bold text-foreground">{glasses}</span>
                <span className="text-sm text-muted-foreground">of {GOAL} glasses</span>
              </div>
            </div>

            <div className="flex items-center gap-6">
              <Button
                variant="outline"
                size="lg"
                className="h-14 w-14 rounded-full"
                onClick={() => setGlasses(Math.max(0, glasses - 1))}
                disabled={glasses === 0}
              >
                <Minus className="w-6 h-6" />
              </Button>

              <Button
                size="lg"
                className="h-14 w-14 rounded-full"
                onClick={() => setGlasses(glasses + 1)}
              >
                <Plus className="w-6 h-6" />
              </Button>
            </div>

            {glasses >= GOAL && (
              <p className="mt-4 text-sm text-success font-medium">
                Goal achieved! Great job staying hydrated.
              </p>
            )}
          </div>
        </div>

        {/* Stats */}
        <div className="grid grid-cols-3 gap-4">
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft text-center">
            <Target className="w-5 h-5 text-muted-foreground mx-auto mb-2" />
            <p className="text-xs text-muted-foreground">Daily Goal</p>
            <p className="text-xl font-semibold text-foreground">{GOAL} glasses</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft text-center">
            <TrendingUp className="w-5 h-5 text-muted-foreground mx-auto mb-2" />
            <p className="text-xs text-muted-foreground">Avg. Intake</p>
            <p className="text-xl font-semibold text-foreground">{avgIntake}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft text-center">
            <Droplets className="w-5 h-5 text-muted-foreground mx-auto mb-2" />
            <p className="text-xs text-muted-foreground">Goals Met</p>
            <p className="text-xl font-semibold text-success">{daysMetGoal}/{history.length}</p>
          </div>
        </div>

        {/* Weekly Progress */}
        <div className="bg-card rounded-lg border border-border shadow-soft p-4">
          <h3 className="text-sm font-semibold text-foreground mb-4">This Week</h3>
          <div className="flex items-end justify-between gap-2 h-32">
            {history.slice(0, 7).reverse().map((entry, index) => {
              const dayProgress = (entry.glasses / GOAL) * 100;
              const isToday = index === 6;
              return (
                <div key={entry.date} className="flex-1 flex flex-col items-center gap-2">
                  <span className="text-xs text-muted-foreground">{entry.glasses}</span>
                  <div className="w-full bg-muted rounded-t-sm relative flex-1 flex items-end">
                    <div
                      className={cn(
                        "w-full rounded-t-sm transition-smooth",
                        entry.glasses >= GOAL ? "bg-success" : "bg-primary",
                        isToday && "ring-2 ring-primary ring-offset-2"
                      )}
                      style={{ height: `${Math.min(dayProgress, 100)}%` }}
                    />
                  </div>
                  <span className={cn(
                    "text-xs",
                    isToday ? "font-medium text-foreground" : "text-muted-foreground"
                  )}>
                    {new Date(entry.date).toLocaleDateString("en-US", { weekday: "short" }).slice(0, 2)}
                  </span>
                </div>
              );
            })}
          </div>
        </div>

        {/* Quick Add */}
        <div className="bg-card rounded-lg border border-border shadow-soft p-4">
          <h3 className="text-sm font-semibold text-foreground mb-3">Quick Add</h3>
          <div className="flex gap-2">
            {[1, 2, 3, 4].map((amount) => (
              <Button
                key={amount}
                variant="outline"
                className="flex-1"
                onClick={() => setGlasses(glasses + amount)}
              >
                +{amount}
              </Button>
            ))}
          </div>
        </div>
      </div>
    </AppLayout>
  );
}
