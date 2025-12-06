import { useState } from "react";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Droplets, Plus, Minus, Target, TrendingUp, Trash2, Pencil } from "lucide-react";
import { cn } from "@/lib/utils";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

interface WaterEntry {
  id: string;
  date: string;
  glasses: number;
}

const GOAL = 8;
const todayStr = new Date().toISOString().split("T")[0];

const initialHistory: WaterEntry[] = [
  { id: "1", date: todayStr, glasses: 5 },
  { id: "2", date: "2024-12-04", glasses: 8 },
  { id: "3", date: "2024-12-03", glasses: 6 },
  { id: "4", date: "2024-12-02", glasses: 7 },
  { id: "5", date: "2024-12-01", glasses: 8 },
  { id: "6", date: "2024-11-30", glasses: 5 },
  { id: "7", date: "2024-11-29", glasses: 9 },
];

export default function Water() {
  const [history, setHistory] = useState<WaterEntry[]>(initialHistory);
  const [editingEntry, setEditingEntry] = useState<WaterEntry | null>(null);
  const [editGlasses, setEditGlasses] = useState(0);
  const [goal, setGoal] = useState(GOAL);
  const [isGoalOpen, setIsGoalOpen] = useState(false);
  const [tempGoal, setTempGoal] = useState(GOAL.toString());

  const todayEntry = history.find(e => e.date === todayStr);
  const glasses = todayEntry?.glasses || 0;

  const updateToday = (newGlasses: number) => {
    const value = Math.max(0, newGlasses);
    if (todayEntry) {
      setHistory(history.map(e => e.date === todayStr ? { ...e, glasses: value } : e));
    } else {
      setHistory([{ id: Date.now().toString(), date: todayStr, glasses: value }, ...history]);
    }
  };

  const updateEntry = () => {
    if (!editingEntry) return;
    setHistory(history.map(e => e.id === editingEntry.id ? { ...e, glasses: editGlasses } : e));
    setEditingEntry(null);
  };

  const deleteEntry = (id: string) => {
    setHistory(history.filter(e => e.id !== id));
  };

  const startEdit = (entry: WaterEntry) => {
    setEditingEntry(entry);
    setEditGlasses(entry.glasses);
  };

  const updateGoal = () => {
    const newGoal = parseInt(tempGoal) || GOAL;
    setGoal(Math.max(1, newGoal));
    setIsGoalOpen(false);
  };

  const progress = Math.min((glasses / goal) * 100, 100);
  const avgIntake = history.length > 0 
    ? (history.reduce((sum, e) => sum + e.glasses, 0) / history.length).toFixed(1) 
    : "0";
  const daysMetGoal = history.filter(e => e.glasses >= goal).length;

  return (
    <AppLayout title="Water" subtitle="Stay hydrated">
      <div className="max-w-3xl space-y-6">
        {/* Main Tracker */}
        <div className="bg-card rounded-lg border border-border shadow-soft p-6 sm:p-8">
          <div className="flex flex-col items-center">
            <h3 className="text-sm font-semibold text-muted-foreground mb-6">Today's Intake</h3>
            
            <div className="relative w-40 h-40 sm:w-48 sm:h-48 mb-6">
              <svg className="w-full h-full -rotate-90">
                <circle
                  cx="50%"
                  cy="50%"
                  r="45%"
                  stroke="hsl(var(--muted))"
                  strokeWidth="12"
                  fill="none"
                />
                <circle
                  cx="50%"
                  cy="50%"
                  r="45%"
                  stroke="hsl(var(--primary))"
                  strokeWidth="12"
                  fill="none"
                  strokeLinecap="round"
                  strokeDasharray={`${progress * 2.83} 283`}
                  className="transition-all duration-500"
                />
              </svg>
              <div className="absolute inset-0 flex flex-col items-center justify-center">
                <Droplets className="w-6 h-6 sm:w-8 sm:h-8 text-primary mb-2" />
                <span className="text-3xl sm:text-4xl font-bold text-foreground">{glasses}</span>
                <span className="text-xs sm:text-sm text-muted-foreground">of {goal} glasses</span>
              </div>
            </div>

            <div className="flex items-center gap-4 sm:gap-6">
              <Button
                variant="outline"
                size="lg"
                className="h-12 w-12 sm:h-14 sm:w-14 rounded-full"
                onClick={() => updateToday(glasses - 1)}
                disabled={glasses === 0}
              >
                <Minus className="w-5 h-5 sm:w-6 sm:h-6" />
              </Button>

              <Button
                size="lg"
                className="h-12 w-12 sm:h-14 sm:w-14 rounded-full"
                onClick={() => updateToday(glasses + 1)}
              >
                <Plus className="w-5 h-5 sm:w-6 sm:h-6" />
              </Button>
            </div>

            {glasses >= goal && (
              <p className="mt-4 text-sm text-success font-medium">
                Goal achieved! Great job staying hydrated.
              </p>
            )}
          </div>
        </div>

        {/* Quick Add */}
        <div className="bg-card rounded-lg border border-border shadow-soft p-4">
          <h3 className="text-sm font-semibold text-foreground mb-3">Quick Add</h3>
          <div className="grid grid-cols-4 gap-2">
            {[1, 2, 3, 4].map((amount) => (
              <Button
                key={amount}
                variant="outline"
                onClick={() => updateToday(glasses + amount)}
              >
                +{amount}
              </Button>
            ))}
          </div>
        </div>

        {/* Stats */}
        <div className="grid grid-cols-3 gap-3 sm:gap-4">
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <button 
              onClick={() => { setTempGoal(goal.toString()); setIsGoalOpen(true); }}
              className="w-full text-left hover:bg-muted/30 -m-2 p-2 rounded-md transition-smooth"
            >
              <Target className="w-5 h-5 text-muted-foreground mx-auto mb-2" />
              <p className="text-xs text-muted-foreground text-center">Daily Goal</p>
              <p className="text-lg sm:text-xl font-semibold text-foreground text-center">{goal} glasses</p>
            </button>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft text-center">
            <TrendingUp className="w-5 h-5 text-muted-foreground mx-auto mb-2" />
            <p className="text-xs text-muted-foreground">Avg. Intake</p>
            <p className="text-lg sm:text-xl font-semibold text-foreground">{avgIntake}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft text-center">
            <Droplets className="w-5 h-5 text-muted-foreground mx-auto mb-2" />
            <p className="text-xs text-muted-foreground">Goals Met</p>
            <p className="text-lg sm:text-xl font-semibold text-success">{daysMetGoal}/{history.length}</p>
          </div>
        </div>

        {/* Goal Edit Dialog */}
        <Dialog open={isGoalOpen} onOpenChange={setIsGoalOpen}>
          <DialogContent className="sm:max-w-sm">
            <DialogHeader>
              <DialogTitle>Set Daily Goal</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 pt-4">
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Glasses per day</label>
                <Input
                  type="number"
                  min="1"
                  value={tempGoal}
                  onChange={(e) => setTempGoal(e.target.value)}
                />
              </div>
              <div className="flex gap-2">
                <Button onClick={updateGoal} className="flex-1">Save</Button>
                <Button variant="outline" onClick={() => setIsGoalOpen(false)}>Cancel</Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>

        {/* Edit Entry Dialog */}
        <Dialog open={!!editingEntry} onOpenChange={(open) => !open && setEditingEntry(null)}>
          <DialogContent className="sm:max-w-sm">
            <DialogHeader>
              <DialogTitle>Edit Entry</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 pt-4">
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Glasses</label>
                <div className="flex items-center gap-4">
                  <Button
                    variant="outline"
                    size="icon"
                    onClick={() => setEditGlasses(Math.max(0, editGlasses - 1))}
                  >
                    <Minus className="w-4 h-4" />
                  </Button>
                  <span className="text-2xl font-bold text-foreground w-12 text-center">{editGlasses}</span>
                  <Button
                    variant="outline"
                    size="icon"
                    onClick={() => setEditGlasses(editGlasses + 1)}
                  >
                    <Plus className="w-4 h-4" />
                  </Button>
                </div>
              </div>
              <div className="flex gap-2">
                <Button onClick={updateEntry} className="flex-1">Save</Button>
                <Button variant="outline" onClick={() => setEditingEntry(null)}>Cancel</Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>

        {/* Weekly Progress */}
        <div className="bg-card rounded-lg border border-border shadow-soft p-4">
          <h3 className="text-sm font-semibold text-foreground mb-4">This Week</h3>
          <div className="flex items-end justify-between gap-1 sm:gap-2 h-32">
            {history.slice(0, 7).reverse().map((entry, index) => {
              const dayProgress = (entry.glasses / goal) * 100;
              const isToday = entry.date === todayStr;
              return (
                <div key={entry.id} className="flex-1 flex flex-col items-center gap-1 sm:gap-2">
                  <span className="text-[10px] sm:text-xs text-muted-foreground">{entry.glasses}</span>
                  <div className="w-full bg-muted rounded-t-sm relative flex-1 flex items-end min-h-[60px]">
                    <div
                      className={cn(
                        "w-full rounded-t-sm transition-smooth",
                        entry.glasses >= goal ? "bg-success" : "bg-primary",
                        isToday && "ring-2 ring-primary ring-offset-2"
                      )}
                      style={{ height: `${Math.min(dayProgress, 100)}%` }}
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

        {/* History */}
        <div className="bg-card rounded-lg border border-border shadow-soft">
          <div className="p-4 border-b border-border">
            <h3 className="text-sm font-semibold text-foreground">History</h3>
          </div>
          <div className="divide-y divide-border max-h-64 overflow-y-auto">
            {history.map((entry) => (
              <div key={entry.id} className="flex items-center gap-4 p-4 hover:bg-muted/30 transition-smooth group">
                <div className={cn(
                  "w-10 h-10 rounded-lg flex items-center justify-center",
                  entry.glasses >= goal ? "bg-success/20" : "bg-primary/20"
                )}>
                  <Droplets className={cn(
                    "w-5 h-5",
                    entry.glasses >= goal ? "text-success" : "text-primary"
                  )} />
                </div>
                <div className="flex-1">
                  <p className="text-sm font-medium text-foreground">{entry.glasses} glasses</p>
                  <p className="text-xs text-muted-foreground">
                    {entry.glasses >= goal ? "Goal met!" : `${goal - entry.glasses} more to go`}
                  </p>
                </div>
                <span className="text-xs text-muted-foreground">
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