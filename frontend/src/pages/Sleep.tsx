import { useState } from "react";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Moon, Sun, Clock, TrendingUp, Calendar, Plus, Trash2, Pencil } from "lucide-react";
import { cn } from "@/lib/utils";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

interface SleepEntry {
  id: string;
  date: string;
  bedtime: string;
  wakeTime: string;
  hours: number;
  quality: "poor" | "fair" | "good" | "great";
}

const qualityOptions = [
  { value: "poor", label: "Poor", color: "bg-destructive/20 text-destructive" },
  { value: "fair", label: "Fair", color: "bg-warning/20 text-warning-foreground" },
  { value: "good", label: "Good", color: "bg-info/20 text-info" },
  { value: "great", label: "Great", color: "bg-success/20 text-success" },
];

const todayStr = new Date().toISOString().split("T")[0];

const initialEntries: SleepEntry[] = [
  { id: "1", date: todayStr, bedtime: "23:00", wakeTime: "06:30", hours: 7.5, quality: "good" },
  { id: "2", date: "2024-12-04", bedtime: "00:30", wakeTime: "06:30", hours: 6, quality: "poor" },
  { id: "3", date: "2024-12-03", bedtime: "22:30", wakeTime: "06:30", hours: 8, quality: "great" },
  { id: "4", date: "2024-12-02", bedtime: "23:30", wakeTime: "06:30", hours: 7, quality: "good" },
  { id: "5", date: "2024-12-01", bedtime: "01:00", wakeTime: "06:30", hours: 5.5, quality: "poor" },
  { id: "6", date: "2024-11-30", bedtime: "22:00", wakeTime: "07:00", hours: 9, quality: "great" },
];

export default function Sleep() {
  const [entries, setEntries] = useState<SleepEntry[]>(initialEntries);
  const [isAddOpen, setIsAddOpen] = useState(false);
  const [editingEntry, setEditingEntry] = useState<SleepEntry | null>(null);
  const [formData, setFormData] = useState({
    date: todayStr,
    bedtime: "23:00",
    wakeTime: "07:00",
    quality: "good" as SleepEntry["quality"],
  });

  const calculateHours = (bed: string, wake: string): number => {
    const [bedH, bedM] = bed.split(":").map(Number);
    const [wakeH, wakeM] = wake.split(":").map(Number);
    let hours = wakeH - bedH + (wakeM - bedM) / 60;
    if (hours < 0) hours += 24;
    return Math.round(hours * 10) / 10;
  };

  const resetForm = () => {
    setFormData({ date: todayStr, bedtime: "23:00", wakeTime: "07:00", quality: "good" });
    setEditingEntry(null);
  };

  const addEntry = () => {
    const hours = calculateHours(formData.bedtime, formData.wakeTime);
    const newEntry: SleepEntry = {
      id: Date.now().toString(),
      date: formData.date,
      bedtime: formData.bedtime,
      wakeTime: formData.wakeTime,
      hours,
      quality: formData.quality
    };
    setEntries([newEntry, ...entries.filter(e => e.date !== formData.date)]);
    resetForm();
    setIsAddOpen(false);
  };

  const updateEntry = () => {
    if (!editingEntry) return;
    const hours = calculateHours(formData.bedtime, formData.wakeTime);
    setEntries(entries.map(e => e.id === editingEntry.id ? {
      ...e,
      date: formData.date,
      bedtime: formData.bedtime,
      wakeTime: formData.wakeTime,
      hours,
      quality: formData.quality,
    } : e));
    resetForm();
  };

  const deleteEntry = (id: string) => {
    setEntries(entries.filter(e => e.id !== id));
  };

  const startEdit = (entry: SleepEntry) => {
    setEditingEntry(entry);
    setFormData({
      date: entry.date,
      bedtime: entry.bedtime,
      wakeTime: entry.wakeTime,
      quality: entry.quality,
    });
  };

  const avgSleep = entries.length > 0 
    ? (entries.reduce((sum, e) => sum + e.hours, 0) / entries.length).toFixed(1) 
    : "0";
  const bestNight = entries.length > 0 ? Math.max(...entries.map(e => e.hours)) : 0;
  const todayEntry = entries.find(e => e.date === todayStr);

  // Calculate average bedtime
  const avgBedtimeMinutes = entries.length > 0 
    ? entries.reduce((sum, e) => {
        const [h, m] = e.bedtime.split(":").map(Number);
        let mins = h * 60 + m;
        if (h < 12) mins += 24 * 60; // Adjust for after midnight
        return sum + mins;
      }, 0) / entries.length
    : 0;
  const avgBedtimeH = Math.floor((avgBedtimeMinutes % (24 * 60)) / 60);
  const avgBedtimeM = Math.floor(avgBedtimeMinutes % 60);
  const avgBedtime = `${String(avgBedtimeH).padStart(2, "0")}:${String(avgBedtimeM).padStart(2, "0")}`;

  return (
    <AppLayout title="Sleep" subtitle="Track your rest">
      <div className="w-full max-w-5xl mx-auto space-y-6">
        {/* Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 md:gap-4">
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <div className="flex items-center gap-2 mb-1">
              <Moon className="w-4 h-4 text-muted-foreground" />
              <p className="text-xs text-muted-foreground">Avg. Sleep</p>
            </div>
            <p className="text-2xl font-semibold text-foreground">{avgSleep}h</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <div className="flex items-center gap-2 mb-1">
              <Clock className="w-4 h-4 text-muted-foreground" />
              <p className="text-xs text-muted-foreground">Avg. Bedtime</p>
            </div>
            <p className="text-2xl font-semibold text-foreground">{avgBedtime}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <div className="flex items-center gap-2 mb-1">
              <TrendingUp className="w-4 h-4 text-muted-foreground" />
              <p className="text-xs text-muted-foreground">Best Night</p>
            </div>
            <p className="text-2xl font-semibold text-success">{bestNight}h</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <div className="flex items-center gap-2 mb-1">
              <Calendar className="w-4 h-4 text-muted-foreground" />
              <p className="text-xs text-muted-foreground">Logged Days</p>
            </div>
            <p className="text-2xl font-semibold text-foreground">{entries.length}</p>
          </div>
        </div>

        {/* Today's Sleep / Log Button */}
        <div className="bg-card rounded-lg border border-border shadow-soft p-6">
          {todayEntry ? (
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
              <div>
                <h3 className="text-sm font-semibold text-foreground mb-2">Last Night's Sleep</h3>
                <div className="flex items-center gap-4">
                  <div className="flex items-center gap-2">
                    <Moon className="w-5 h-5 text-primary" />
                    <span className="text-lg font-medium text-foreground">{todayEntry.bedtime}</span>
                  </div>
                  <span className="text-muted-foreground">→</span>
                  <div className="flex items-center gap-2">
                    <Sun className="w-5 h-5 text-warning" />
                    <span className="text-lg font-medium text-foreground">{todayEntry.wakeTime}</span>
                  </div>
                  <span className={cn(
                    "text-xs font-medium px-2 py-1 rounded-full capitalize ml-2",
                    qualityOptions.find(q => q.value === todayEntry.quality)?.color
                  )}>
                    {todayEntry.hours}h • {todayEntry.quality}
                  </span>
                </div>
              </div>
              <Button variant="outline" onClick={() => startEdit(todayEntry)}>
                <Pencil className="w-4 h-4 mr-2" />
                Edit
              </Button>
            </div>
          ) : (
            <div className="text-center">
              <Moon className="w-10 h-10 text-muted-foreground mx-auto mb-3" />
              <p className="text-muted-foreground mb-4">No sleep logged for today</p>
              <Dialog open={isAddOpen} onOpenChange={setIsAddOpen}>
                <DialogTrigger asChild>
                  <Button className="gap-2" onClick={resetForm}>
                    <Plus className="w-4 h-4" />
                    Log Sleep
                  </Button>
                </DialogTrigger>
                <DialogContent className="sm:max-w-md">
                  <DialogHeader>
                    <DialogTitle>Log Sleep</DialogTitle>
                  </DialogHeader>
                  <div className="space-y-4 pt-4">
                    <div>
                      <label className="text-sm font-medium text-foreground mb-1.5 block">Date</label>
                      <Input
                        type="date"
                        value={formData.date}
                        onChange={(e) => setFormData({ ...formData, date: e.target.value })}
                      />
                    </div>
                    <div className="grid grid-cols-2 gap-4">
                      <div>
                        <label className="text-sm font-medium text-foreground mb-1.5 block">Bedtime</label>
                        <Input
                          type="time"
                          value={formData.bedtime}
                          onChange={(e) => setFormData({ ...formData, bedtime: e.target.value })}
                        />
                      </div>
                      <div>
                        <label className="text-sm font-medium text-foreground mb-1.5 block">Wake Time</label>
                        <Input
                          type="time"
                          value={formData.wakeTime}
                          onChange={(e) => setFormData({ ...formData, wakeTime: e.target.value })}
                        />
                      </div>
                    </div>
                    <div>
                      <label className="text-sm font-medium text-foreground mb-1.5 block">Quality</label>
                      <Select
                        value={formData.quality}
                        onValueChange={(v) => setFormData({ ...formData, quality: v as any })}
                      >
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          {qualityOptions.map((q) => (
                            <SelectItem key={q.value} value={q.value}>{q.label}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <p className="text-sm text-muted-foreground">
                      Total sleep: <span className="font-medium text-foreground">{calculateHours(formData.bedtime, formData.wakeTime)}h</span>
                    </p>
                    <div className="flex gap-2 pt-2">
                      <Button onClick={addEntry} className="flex-1">Save</Button>
                      <Button variant="outline" onClick={() => setIsAddOpen(false)}>Cancel</Button>
                    </div>
                  </div>
                </DialogContent>
              </Dialog>
            </div>
          )}
        </div>

        {/* Add Button (when today is logged) */}
        {todayEntry && (
          <div className="flex justify-end">
            <Dialog open={isAddOpen} onOpenChange={setIsAddOpen}>
              <DialogTrigger asChild>
                <Button className="gap-2" onClick={resetForm}>
                  <Plus className="w-4 h-4" />
                  Add Entry
                </Button>
              </DialogTrigger>
              <DialogContent className="sm:max-w-md">
                <DialogHeader>
                  <DialogTitle>Log Sleep</DialogTitle>
                </DialogHeader>
                <div className="space-y-4 pt-4">
                  <div>
                    <label className="text-sm font-medium text-foreground mb-1.5 block">Date</label>
                    <Input
                      type="date"
                      value={formData.date}
                      onChange={(e) => setFormData({ ...formData, date: e.target.value })}
                    />
                  </div>
                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <label className="text-sm font-medium text-foreground mb-1.5 block">Bedtime</label>
                      <Input
                        type="time"
                        value={formData.bedtime}
                        onChange={(e) => setFormData({ ...formData, bedtime: e.target.value })}
                      />
                    </div>
                    <div>
                      <label className="text-sm font-medium text-foreground mb-1.5 block">Wake Time</label>
                      <Input
                        type="time"
                        value={formData.wakeTime}
                        onChange={(e) => setFormData({ ...formData, wakeTime: e.target.value })}
                      />
                    </div>
                  </div>
                  <div>
                    <label className="text-sm font-medium text-foreground mb-1.5 block">Quality</label>
                    <Select
                      value={formData.quality}
                      onValueChange={(v) => setFormData({ ...formData, quality: v as any })}
                    >
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {qualityOptions.map((q) => (
                          <SelectItem key={q.value} value={q.value}>{q.label}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <p className="text-sm text-muted-foreground">
                    Total sleep: <span className="font-medium text-foreground">{calculateHours(formData.bedtime, formData.wakeTime)}h</span>
                  </p>
                  <div className="flex gap-2 pt-2">
                    <Button onClick={addEntry} className="flex-1">Save</Button>
                    <Button variant="outline" onClick={() => setIsAddOpen(false)}>Cancel</Button>
                  </div>
                </div>
              </DialogContent>
            </Dialog>
          </div>
        )}

        {/* Edit Modal */}
        <Dialog open={!!editingEntry} onOpenChange={(open) => !open && resetForm()}>
          <DialogContent className="sm:max-w-md">
            <DialogHeader>
              <DialogTitle>Edit Sleep Entry</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 pt-4">
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Date</label>
                <Input
                  type="date"
                  value={formData.date}
                  onChange={(e) => setFormData({ ...formData, date: e.target.value })}
                />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-sm font-medium text-foreground mb-1.5 block">Bedtime</label>
                  <Input
                    type="time"
                    value={formData.bedtime}
                    onChange={(e) => setFormData({ ...formData, bedtime: e.target.value })}
                  />
                </div>
                <div>
                  <label className="text-sm font-medium text-foreground mb-1.5 block">Wake Time</label>
                  <Input
                    type="time"
                    value={formData.wakeTime}
                    onChange={(e) => setFormData({ ...formData, wakeTime: e.target.value })}
                  />
                </div>
              </div>
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Quality</label>
                <Select
                  value={formData.quality}
                  onValueChange={(v) => setFormData({ ...formData, quality: v as any })}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {qualityOptions.map((q) => (
                      <SelectItem key={q.value} value={q.value}>{q.label}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <p className="text-sm text-muted-foreground">
                Total sleep: <span className="font-medium text-foreground">{calculateHours(formData.bedtime, formData.wakeTime)}h</span>
              </p>
              <div className="flex gap-2 pt-2">
                <Button onClick={updateEntry} className="flex-1">Save Changes</Button>
                <Button variant="outline" onClick={resetForm}>Cancel</Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>

        {/* Weekly Chart */}
        <div className="bg-card rounded-lg border border-border shadow-soft p-4">
          <h3 className="text-sm font-semibold text-foreground mb-4">This Week</h3>
          <div className="flex items-end justify-between gap-1 sm:gap-2 h-40">
            {entries.slice(0, 7).reverse().map((entry) => {
              const heightPercent = (entry.hours / 10) * 100;
              const isToday = entry.date === todayStr;
              return (
                <div key={entry.id} className="flex-1 flex flex-col items-center gap-1 sm:gap-2">
                  <span className="text-[10px] sm:text-xs text-muted-foreground">{entry.hours}h</span>
                  <div className="w-full bg-muted rounded-t-sm relative flex-1 flex items-end min-h-[80px]">
                    <div
                      className={cn(
                        "w-full rounded-t-sm transition-smooth",
                        entry.hours >= 8 ? "bg-success" : entry.hours >= 7 ? "bg-primary" : "bg-warning",
                        isToday && "ring-2 ring-primary ring-offset-2"
                      )}
                      style={{ height: `${heightPercent}%` }}
                    />
                  </div>
                  <span className={cn(
                    "text-[10px] sm:text-xs",
                    isToday ? "font-medium text-foreground" : "text-muted-foreground"
                  )}>
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
          <div className="divide-y divide-border max-h-80 overflow-y-auto">
            {entries.map((entry) => (
              <div key={entry.id} className="flex items-center gap-3 sm:gap-4 p-4 hover:bg-muted/30 transition-smooth group">
                <div className="w-10 h-10 rounded-lg bg-accent flex items-center justify-center flex-shrink-0">
                  <Moon className="w-5 h-5 text-accent-foreground" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-foreground">{entry.hours} hours</p>
                  <p className="text-xs text-muted-foreground">
                    {entry.bedtime} → {entry.wakeTime}
                  </p>
                </div>
                <span className={cn(
                  "text-xs font-medium px-2 py-1 rounded-full capitalize hidden sm:block",
                  qualityOptions.find(q => q.value === entry.quality)?.color
                )}>
                  {entry.quality}
                </span>
                <span className="text-xs text-muted-foreground whitespace-nowrap">
                  {new Date(entry.date).toLocaleDateString("en-US", { month: "short", day: "numeric" })}
                </span>
                <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-smooth">
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-8 w-8 text-muted-foreground hover:text-foreground"
                    onClick={() => startEdit(entry)}
                  >
                    <Pencil className="w-4 h-4" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-8 w-8 text-muted-foreground hover:text-destructive"
                    onClick={() => deleteEntry(entry.id)}
                  >
                    <Trash2 className="w-4 h-4" />
                  </Button>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </AppLayout>
  );
}
