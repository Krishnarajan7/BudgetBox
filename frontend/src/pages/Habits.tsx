import { useState } from "react";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Plus, Flame, Check, Trash2, Pencil, X } from "lucide-react";
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

interface Habit {
  id: string;
  name: string;
  streak: number;
  weekProgress: boolean[];
  color: string;
}

const colorOptions = [
  { value: "bg-primary", label: "Teal" },
  { value: "bg-info", label: "Blue" },
  { value: "bg-success", label: "Green" },
  { value: "bg-warning", label: "Orange" },
  { value: "bg-destructive", label: "Red" },
];

const initialHabits: Habit[] = [
  { id: "1", name: "Morning Exercise", streak: 12, weekProgress: [true, true, true, true, true, false, false], color: "bg-primary" },
  { id: "2", name: "Read 30 mins", streak: 8, weekProgress: [true, true, false, true, true, true, false], color: "bg-info" },
  { id: "3", name: "Meditate", streak: 21, weekProgress: [true, true, true, true, true, true, true], color: "bg-success" },
  { id: "4", name: "No Sugar", streak: 5, weekProgress: [true, true, true, false, true, true, false], color: "bg-warning" },
];

const days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const today = new Date().getDay();
const todayIndex = today === 0 ? 6 : today - 1;

export default function Habits() {
  const [habits, setHabits] = useState<Habit[]>(initialHabits);
  const [isAddOpen, setIsAddOpen] = useState(false);
  const [editingHabit, setEditingHabit] = useState<Habit | null>(null);
  const [formData, setFormData] = useState({
    name: "",
    color: "bg-primary",
  });

  const resetForm = () => {
    setFormData({ name: "", color: "bg-primary" });
    setEditingHabit(null);
  };

  const toggleToday = (habitId: string) => {
    setHabits(habits.map(h => {
      if (h.id === habitId) {
        const newProgress = [...h.weekProgress];
        newProgress[todayIndex] = !newProgress[todayIndex];
        return {
          ...h,
          weekProgress: newProgress,
          streak: newProgress[todayIndex] ? h.streak + 1 : Math.max(0, h.streak - 1)
        };
      }
      return h;
    }));
  };

  const addHabit = () => {
    if (!formData.name.trim()) return;
    setHabits([...habits, {
      id: Date.now().toString(),
      name: formData.name,
      streak: 0,
      weekProgress: [false, false, false, false, false, false, false],
      color: formData.color,
    }]);
    resetForm();
    setIsAddOpen(false);
  };

  const updateHabit = () => {
    if (!editingHabit || !formData.name.trim()) return;
    setHabits(habits.map(h => h.id === editingHabit.id ? {
      ...h,
      name: formData.name,
      color: formData.color,
    } : h));
    resetForm();
  };

  const deleteHabit = (id: string) => {
    setHabits(habits.filter(h => h.id !== id));
  };

  const startEdit = (habit: Habit) => {
    setEditingHabit(habit);
    setFormData({ name: habit.name, color: habit.color });
  };

  const totalCompleted = habits.filter(h => h.weekProgress[todayIndex]).length;
  const longestStreak = habits.length > 0 ? Math.max(...habits.map(h => h.streak)) : 0;
  const completionRate = habits.length > 0 ? Math.round((totalCompleted / habits.length) * 100) : 0;

  return (
    <AppLayout title="Habits" subtitle="Build better routines">
      <div className="max-w-4xl space-y-6">
        {/* Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 md:gap-4">
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-1">Total Habits</p>
            <p className="text-2xl font-semibold text-foreground">{habits.length}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-1">Done Today</p>
            <p className="text-2xl font-semibold text-success">{totalCompleted}/{habits.length}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-1">Completion</p>
            <p className="text-2xl font-semibold text-foreground">{completionRate}%</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft flex items-center gap-2">
            <div>
              <p className="text-xs text-muted-foreground mb-1">Best Streak</p>
              <p className="text-2xl font-semibold text-foreground">{longestStreak}</p>
            </div>
            <Flame className="w-6 h-6 text-warning ml-auto" />
          </div>
        </div>

        {/* Add Button */}
        <div className="flex justify-end">
          <Dialog open={isAddOpen} onOpenChange={setIsAddOpen}>
            <DialogTrigger asChild>
              <Button className="gap-2" onClick={resetForm}>
                <Plus className="w-4 h-4" />
                Add Habit
              </Button>
            </DialogTrigger>
            <DialogContent className="sm:max-w-md">
              <DialogHeader>
                <DialogTitle>Add New Habit</DialogTitle>
              </DialogHeader>
              <div className="space-y-4 pt-4">
                <div>
                  <label className="text-sm font-medium text-foreground mb-1.5 block">Habit Name</label>
                  <Input
                    placeholder="e.g., Morning Exercise"
                    value={formData.name}
                    onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  />
                </div>
                <div>
                  <label className="text-sm font-medium text-foreground mb-1.5 block">Color</label>
                  <Select
                    value={formData.color}
                    onValueChange={(v) => setFormData({ ...formData, color: v })}
                  >
                    <SelectTrigger>
                      <div className="flex items-center gap-2">
                        <div className={cn("w-4 h-4 rounded-full", formData.color)} />
                        <SelectValue />
                      </div>
                    </SelectTrigger>
                    <SelectContent>
                      {colorOptions.map((color) => (
                        <SelectItem key={color.value} value={color.value}>
                          <div className="flex items-center gap-2">
                            <div className={cn("w-4 h-4 rounded-full", color.value)} />
                            {color.label}
                          </div>
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="flex gap-2 pt-2">
                  <Button onClick={addHabit} className="flex-1">Add Habit</Button>
                  <Button variant="outline" onClick={() => setIsAddOpen(false)}>Cancel</Button>
                </div>
              </div>
            </DialogContent>
          </Dialog>
        </div>

        {/* Edit Modal */}
        <Dialog open={!!editingHabit} onOpenChange={(open) => !open && resetForm()}>
          <DialogContent className="sm:max-w-md">
            <DialogHeader>
              <DialogTitle>Edit Habit</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 pt-4">
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Habit Name</label>
                <Input
                  placeholder="e.g., Morning Exercise"
                  value={formData.name}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                />
              </div>
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Color</label>
                <Select
                  value={formData.color}
                  onValueChange={(v) => setFormData({ ...formData, color: v })}
                >
                  <SelectTrigger>
                    <div className="flex items-center gap-2">
                      <div className={cn("w-4 h-4 rounded-full", formData.color)} />
                      <SelectValue />
                    </div>
                  </SelectTrigger>
                  <SelectContent>
                    {colorOptions.map((color) => (
                      <SelectItem key={color.value} value={color.value}>
                        <div className="flex items-center gap-2">
                          <div className={cn("w-4 h-4 rounded-full", color.value)} />
                          {color.label}
                        </div>
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="flex gap-2 pt-2">
                <Button onClick={updateHabit} className="flex-1">Save Changes</Button>
                <Button variant="outline" onClick={resetForm}>Cancel</Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>

        {/* Habits Grid */}
        {habits.length === 0 ? (
          <div className="bg-card rounded-lg border border-border shadow-soft p-12 text-center">
            <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto mb-3">
              <Flame className="w-6 h-6 text-muted-foreground" />
            </div>
            <p className="text-muted-foreground">No habits yet</p>
            <p className="text-sm text-muted-foreground mt-1">Start building your routine</p>
          </div>
        ) : (
          <div className="grid gap-4">
            {habits.map((habit) => (
              <div
                key={habit.id}
                className="bg-card rounded-lg border border-border shadow-soft p-4 group"
              >
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-3">
                    <div className={cn("w-3 h-3 rounded-full", habit.color)} />
                    <h3 className="font-medium text-foreground">{habit.name}</h3>
                  </div>
                  <div className="flex items-center gap-3">
                    <div className="flex items-center gap-2 text-sm text-muted-foreground">
                      <Flame className="w-4 h-4 text-warning" />
                      <span>{habit.streak} days</span>
                    </div>
                    <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-smooth">
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8 text-muted-foreground hover:text-foreground"
                        onClick={() => startEdit(habit)}
                      >
                        <Pencil className="w-4 h-4" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8 text-muted-foreground hover:text-destructive"
                        onClick={() => deleteHabit(habit.id)}
                      >
                        <Trash2 className="w-4 h-4" />
                      </Button>
                    </div>
                  </div>
                </div>

                <div className="grid grid-cols-7 gap-1 sm:gap-2">
                  {habit.weekProgress.map((completed, index) => (
                    <button
                      key={index}
                      onClick={() => index === todayIndex && toggleToday(habit.id)}
                      disabled={index !== todayIndex}
                      className={cn(
                        "flex flex-col items-center gap-1 p-1.5 sm:p-2 rounded-md transition-smooth",
                        index === todayIndex && "ring-2 ring-primary ring-offset-2 ring-offset-card",
                        index !== todayIndex && "opacity-60"
                      )}
                    >
                      <div
                        className={cn(
                          "w-7 h-7 sm:w-8 sm:h-8 rounded-md flex items-center justify-center transition-smooth",
                          completed ? habit.color : "bg-muted"
                        )}
                      >
                        {completed && <Check className="w-3 h-3 sm:w-4 sm:h-4 text-primary-foreground" />}
                      </div>
                      <span className={cn(
                        "text-[10px] sm:text-xs",
                        index === todayIndex ? "font-medium text-foreground" : "text-muted-foreground"
                      )}>
                        {days[index]}
                      </span>
                    </button>
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </AppLayout>
  );
}