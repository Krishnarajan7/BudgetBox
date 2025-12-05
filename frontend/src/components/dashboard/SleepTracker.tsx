import { Moon, Sun } from "lucide-react";

const sleepData = [
  { day: "Mon", hours: 7.5, quality: "good" },
  { day: "Tue", hours: 6, quality: "poor" },
  { day: "Wed", hours: 8, quality: "great" },
  { day: "Thu", hours: 7, quality: "good" },
  { day: "Fri", hours: 5.5, quality: "poor" },
  { day: "Sat", hours: 9, quality: "great" },
  { day: "Sun", hours: 8, quality: "great" },
];

const qualityColors = {
  poor: "bg-destructive/20",
  good: "bg-warning/20",
  great: "bg-success/20",
};

export function SleepTracker() {
  const avgSleep = (sleepData.reduce((sum, d) => sum + d.hours, 0) / sleepData.length).toFixed(1);

  return (
    <div className="bg-card rounded-lg border border-border shadow-soft animate-fade-in">
      <div className="p-4 border-b border-border">
        <h3 className="text-sm font-semibold text-foreground">Sleep Log</h3>
        <p className="text-xs text-muted-foreground mt-0.5">Weekly sleep patterns</p>
      </div>

      <div className="p-4 space-y-3">
        {sleepData.slice(0, 4).map((item, index) => (
          <div
            key={index}
            className="flex items-center gap-3"
          >
            <span className="text-xs text-muted-foreground w-8">{item.day}</span>
            <div className="flex-1 h-6 bg-muted rounded-sm overflow-hidden">
              <div
                className={`h-full rounded-sm transition-smooth ${qualityColors[item.quality as keyof typeof qualityColors]}`}
                style={{ width: `${(item.hours / 10) * 100}%` }}
              />
            </div>
            <span className="text-sm font-medium text-foreground w-12 text-right">
              {item.hours}h
            </span>
          </div>
        ))}
      </div>

      <div className="p-4 border-t border-border">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Moon className="w-4 h-4 text-muted-foreground" />
            <span className="text-xs text-muted-foreground">Avg. sleep</span>
          </div>
          <span className="text-sm font-semibold text-foreground">{avgSleep}h</span>
        </div>
      </div>
    </div>
  );
}
