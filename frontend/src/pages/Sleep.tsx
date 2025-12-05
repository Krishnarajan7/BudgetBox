import { useState } from "react";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Moon, Sun, Clock, TrendingUp, Calendar } from "lucide-react";
import { cn } from "@/lib/utils";

interface SleepEntry {
  id: string;
  date: string;
  bedtime: string;
  wakeTime: string;
  hours: number;
  quality: "poor" | "fair" | "good" | "great";
}

const qualityColors = {
  poor: "bg-destructive/20 text-destructive",
  fair: "bg-warning/20 text-warning-foreground",
  good: "bg-info/20 text-info",
  great: "bg-success/20 text-success",
};

const initialEntries: SleepEntry[] = [
  { id: "1", date: "2024-12-05", bedtime: "23:00", wakeTime: "06:30", hours: 7.5, quality: "good" },
  { id: "2", date: "2024-12-04", bedtime: "00:30", wakeTime: "06:30", hours: 6, quality: "poor" },
  { id: "3", date: "2024-12-03", bedtime: "22:30", wakeTime: "06:30", hours: 8, quality: "great" },
  { id: "4", date: "2024-12-02", bedtime: "23:30", wakeTime: "06:30", hours: 7, quality: "good" },
  { id: "5", date: "2024-12-01", bedtime: "01:00", wakeTime: "06:30", hours: 5.5, quality: "poor" },
  { id: "6", date: "2024-11-30", bedtime: "22:00", wakeTime: "07:00", hours: 9, quality: "great" },
  { id: "7", date: "2024-11-29", bedtime: "23:00", wakeTime: "07:00", hours: 8, quality: "great" },
];

export default function Sleep() {
  const [entries, setEntries] = useState<SleepEntry[]>(initialEntries);
  const [showLog, setShowLog] = useState(false);
  const [bedtime, setBedtime] = useState("23:00");
  const [wakeTime, setWakeTime] = useState("07:00");

  const calculateHours = (bed: string, wake: string): number => {
    const [bedH, bedM] = bed.split(":").map(Number);
    const [wakeH, wakeM] = wake.split(":").map(Number);
    let hours = wakeH - bedH + (wakeM - bedM) / 60;
    if (hours < 0) hours += 24;
    return Math.round(hours * 10) / 10;
  };

  const logSleep = () => {
    const hours = calculateHours(bedtime, wakeTime);
    let quality: SleepEntry["quality"] = "good";
    if (hours < 6) quality = "poor";
    else if (hours < 7) quality = "fair";
    else if (hours >= 8) quality = "great";

    const newEntry: SleepEntry = {
      id: Date.now().toString(),
      date: new Date().toISOString().split("T")[0],
      bedtime,
      wakeTime,
      hours,
      quality
    };
    setEntries([newEntry, ...entries]);
    setShowLog(false);
  };

  const avgSleep = (entries.reduce((sum, e) => sum + e.hours, 0) / entries.length).toFixed(1);
  const avgBedtime = "23:15";
  const bestNight = Math.max(...entries.map(e => e.hours));

  return (
    <AppLayout title="Sleep" subtitle="Track your rest">
      <div className="max-w-3xl space-y-6">
        {/* Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <div className="flex items-center gap-2 mb-2">
              <Moon className="w-4 h-4 text-muted-foreground" />
              <p className="text-xs text-muted-foreground">Avg. Sleep</p>
            </div>
            <p className="text-2xl font-semibold text-foreground">{avgSleep}h</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <div className="flex items-center gap-2 mb-2">
              <Clock className="w-4 h-4 text-muted-foreground" />
              <p className="text-xs text-muted-foreground">Avg. Bedtime</p>
            </div>
            <p className="text-2xl font-semibold text-foreground">{avgBedtime}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <div className="flex items-center gap-2 mb-2">
              <TrendingUp className="w-4 h-4 text-muted-foreground" />
              <p className="text-xs text-muted-foreground">Best Night</p>
            </div>
            <p className="text-2xl font-semibold text-success">{bestNight}h</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <div className="flex items-center gap-2 mb-2">
              <Calendar className="w-4 h-4 text-muted-foreground" />
              <p className="text-xs text-muted-foreground">Logged Days</p>
            </div>
            <p className="text-2xl font-semibold text-foreground">{entries.length}</p>
          </div>
        </div>

        {/* Log Sleep */}
        {showLog ? (
          <div className="bg-card rounded-lg border border-border shadow-soft p-6 animate-fade-in">
            <h3 className="text-sm font-semibold text-foreground mb-4">Log Last Night's Sleep</h3>
            <div className="grid grid-cols-2 gap-4 mb-4">
              <div>
                <label className="text-xs text-muted-foreground mb-1 block">Bedtime</label>
                <Input
                  type="time"
                  value={bedtime}
                  onChange={(e) => setBedtime(e.target.value)}
                />
              </div>
              <div>
                <label className="text-xs text-muted-foreground mb-1 block">Wake Time</label>
                <Input
                  type="time"
                  value={wakeTime}
                  onChange={(e) => setWakeTime(e.target.value)}
                />
              </div>
            </div>
            <p className="text-sm text-muted-foreground mb-4">
              Total sleep: <span className="font-medium text-foreground">{calculateHours(bedtime, wakeTime)}h</span>
            </p>
            <div className="flex gap-2">
              <Button onClick={logSleep}>Save</Button>
              <Button variant="outline" onClick={() => setShowLog(false)}>Cancel</Button>
            </div>
          </div>
        ) : (
          <Button className="w-full gap-2" onClick={() => setShowLog(true)}>
            <Moon className="w-4 h-4" />
            Log Sleep
          </Button>
        )}

        {/* Weekly Chart */}
        <div className="bg-card rounded-lg border border-border shadow-soft p-4">
          <h3 className="text-sm font-semibold text-foreground mb-4">This Week</h3>
          <div className="flex items-end justify-between gap-2 h-40">
            {entries.slice(0, 7).reverse().map((entry, index) => {
              const heightPercent = (entry.hours / 10) * 100;
              return (
                <div key={entry.id} className="flex-1 flex flex-col items-center gap-2">
                  <span className="text-xs text-muted-foreground">{entry.hours}h</span>
                  <div className="w-full bg-muted rounded-t-sm relative flex-1 flex items-end">
                    <div
                      className={cn(
                        "w-full rounded-t-sm transition-smooth",
                        entry.hours >= 8 ? "bg-success" : entry.hours >= 7 ? "bg-primary" : "bg-warning"
                      )}
                      style={{ height: `${heightPercent}%` }}
                    />
                  </div>
                  <span className="text-xs text-muted-foreground">
                    {new Date(entry.date).toLocaleDateString("en-US", { weekday: "short" }).slice(0, 2)}
                  </span>
                </div>
              );
            })}
          </div>
        </div>

        {/* Sleep Log */}
        <div className="bg-card rounded-lg border border-border shadow-soft">
          <div className="p-4 border-b border-border">
            <h3 className="text-sm font-semibold text-foreground">Sleep History</h3>
          </div>
          <div className="divide-y divide-border">
            {entries.map((entry) => (
              <div key={entry.id} className="flex items-center gap-4 p-4 hover:bg-muted/30 transition-smooth">
                <div className="w-10 h-10 rounded-md bg-accent flex items-center justify-center">
                  <Moon className="w-5 h-5 text-accent-foreground" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-foreground">{entry.hours} hours</p>
                  <p className="text-xs text-muted-foreground">
                    {entry.bedtime} → {entry.wakeTime}
                  </p>
                </div>
                <span className={cn(
                  "text-xs font-medium px-2 py-1 rounded-full capitalize",
                  qualityColors[entry.quality]
                )}>
                  {entry.quality}
                </span>
                <span className="text-xs text-muted-foreground">
                  {new Date(entry.date).toLocaleDateString("en-US", { month: "short", day: "numeric" })}
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </AppLayout>
  );
}
