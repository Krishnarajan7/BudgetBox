import { useState } from "react";
import { useMutation, useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Plus, Flame, Check, Trash2, Loader2, AlertCircle, Pencil } from "lucide-react";
import { cn } from "@/lib/utils";
import { useToast } from "@/hooks/use-toast";
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
import {
  Habit,
  HabitInsights,
  createHabit,
  deleteHabit,
  getHabitInsights,
  getHabitToday,
  listHabits,
  patchHabitToday,
  updateHabit,
} from "@/api/habits.api";

const colorOptions = [
  { value: "bg-primary", label: "Teal" },
  { value: "bg-info", label: "Blue" },
  { value: "bg-success", label: "Green" },
  { value: "bg-warning", label: "Orange" },
  { value: "bg-destructive", label: "Red" },
];

// The backend does not store a color for a habit (see app/habits/schemas.py
// HabitResponse: id/name/is_active only). Color is a purely cosmetic,
// client-side preference, persisted in localStorage so it survives a
// refresh without pretending the backend returned it.
const COLOR_STORAGE_KEY = "budgetbox.habitColors";

function loadHabitColors(): Record<number, string> {
  try {
    const raw = localStorage.getItem(COLOR_STORAGE_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

function saveHabitColor(habitId: number, color: string) {
  const colors = loadHabitColors();
  colors[habitId] = color;
  try {
    localStorage.setItem(COLOR_STORAGE_KEY, JSON.stringify(colors));
  } catch {
    // ignore quota / privacy-mode errors — color is purely cosmetic
  }
}

function removeHabitColor(habitId: number) {
  const colors = loadHabitColors();
  delete colors[habitId];
  try {
    localStorage.setItem(COLOR_STORAGE_KEY, JSON.stringify(colors));
  } catch {
    // ignore
  }
}

export default function Habits() {
  const { toast } = useToast();
  const queryClient = useQueryClient();

  const [isAddOpen, setIsAddOpen] = useState(false);
  const [formData, setFormData] = useState({ name: "", color: "bg-primary" });

  const resetForm = () => setFormData({ name: "", color: "bg-primary" });

  const [editingHabit, setEditingHabit] = useState<Habit | null>(null);
  const [editName, setEditName] = useState("");

  const {
    data: habits = [],
    isLoading: habitsLoading,
    isError: habitsError,
    refetch: refetchHabits,
  } = useQuery({
    queryKey: ["habits"],
    queryFn: listHabits,
  });

  // Per-habit streak / weekly insights, sourced from GET /habits/{id}/insights.
  const insightsQueries = useQueries({
    queries: habits.map((habit) => ({
      queryKey: ["habit-insights", habit.id],
      queryFn: () => getHabitInsights(habit.id),
      enabled: !!habit.id,
    })),
  });

  // Today's completion status, sourced from GET /habits/{id}/logs/today —
  // a pure read that never creates a log row as a side effect.
  const todayQueries = useQueries({
    queries: habits.map((habit) => ({
      queryKey: ["habit-today", habit.id],
      queryFn: () => getHabitToday(habit.id),
      enabled: !!habit.id,
    })),
  });

  const createMutation = useMutation({
    mutationFn: (vars: { name: string; color: string }) => createHabit(vars.name),
    onSuccess: (created, vars) => {
      saveHabitColor(created.id, vars.color);
      queryClient.invalidateQueries({ queryKey: ["habits"] });
      resetForm();
      setIsAddOpen(false);
    },
    onError: () => {
      toast({
        title: "Couldn't add habit",
        description: "Please try again.",
        variant: "destructive",
      });
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (habitId: number) => deleteHabit(habitId),
    onSuccess: (_data, habitId) => {
      removeHabitColor(habitId);
      queryClient.invalidateQueries({ queryKey: ["habits"] });
      queryClient.removeQueries({ queryKey: ["habit-insights", habitId] });
      queryClient.removeQueries({ queryKey: ["habit-today", habitId] });
    },
    onError: () => {
      toast({
        title: "Couldn't delete habit",
        description: "Please try again.",
        variant: "destructive",
      });
    },
  });

  const toggleTodayMutation = useMutation({
    mutationFn: (vars: { habitId: number; completed: boolean }) =>
      patchHabitToday(vars.habitId, { completed: vars.completed }),
    onSuccess: (_log, vars) => {
      queryClient.invalidateQueries({ queryKey: ["habit-today", vars.habitId] });
      queryClient.invalidateQueries({ queryKey: ["habit-insights", vars.habitId] });
    },
    onError: () => {
      toast({
        title: "Couldn't update today's log",
        description: "Please try again.",
        variant: "destructive",
      });
    },
  });

  const renameMutation = useMutation({
    mutationFn: (vars: { habitId: number; name: string }) =>
      updateHabit(vars.habitId, { name: vars.name }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["habits"] });
      setEditingHabit(null);
      setEditName("");
    },
    onError: () => {
      toast({
        title: "Couldn't rename habit",
        description: "Please try again.",
        variant: "destructive",
      });
    },
  });

  const openEditDialog = (habit: Habit) => {
    setEditingHabit(habit);
    setEditName(habit.name);
  };

  const saveRename = () => {
    if (!editingHabit || !editName.trim() || renameMutation.isPending) return;
    renameMutation.mutate({ habitId: editingHabit.id, name: editName.trim() });
  };

  const addHabit = () => {
    if (!formData.name.trim() || createMutation.isPending) return;
    createMutation.mutate({ name: formData.name.trim(), color: formData.color });
  };

  const habitColors = loadHabitColors();

  const doneTodayCount = todayQueries.filter((q) => q.data?.completed).length;
  const completionRate =
    habits.length > 0 ? Math.round((doneTodayCount / habits.length) * 100) : 0;
  const bestStreak = insightsQueries.reduce((max, q) => {
    const current = q.data?.streak.current_streak ?? 0;
    return current > max ? current : max;
  }, 0);

  return (
    <AppLayout title="Habits" subtitle="Build better routines">
      <div className="w-full max-w-5xl mx-auto space-y-6">
        {/* Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 md:gap-4">
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-1">Total Habits</p>
            <p className="text-2xl font-semibold text-foreground">{habits.length}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-1">Done Today</p>
            <p className="text-2xl font-semibold text-success">
              {doneTodayCount}/{habits.length}
            </p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-1">Completion</p>
            <p className="text-2xl font-semibold text-foreground">{completionRate}%</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft flex items-center gap-2">
            <div>
              <p className="text-xs text-muted-foreground mb-1">Best Streak</p>
              <p className="text-2xl font-semibold text-foreground">{bestStreak}</p>
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
                  <Button
                    onClick={addHabit}
                    className="flex-1"
                    disabled={createMutation.isPending || !formData.name.trim()}
                  >
                    {createMutation.isPending ? (
                      <Loader2 className="w-4 h-4 animate-spin" />
                    ) : (
                      "Add Habit"
                    )}
                  </Button>
                  <Button variant="outline" onClick={() => setIsAddOpen(false)}>
                    Cancel
                  </Button>
                </div>
              </div>
            </DialogContent>
          </Dialog>
        </div>

        {/* Edit Habit Dialog */}
        <Dialog
          open={!!editingHabit}
          onOpenChange={(open) => {
            if (!open) {
              setEditingHabit(null);
              setEditName("");
            }
          }}
        >
          <DialogContent className="sm:max-w-md">
            <DialogHeader>
              <DialogTitle>Edit Habit</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 pt-4">
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Habit Name</label>
                <Input
                  placeholder="e.g., Morning Exercise"
                  value={editName}
                  onChange={(e) => setEditName(e.target.value)}
                />
              </div>
              <div className="flex gap-2 pt-2">
                <Button
                  onClick={saveRename}
                  className="flex-1"
                  disabled={renameMutation.isPending || !editName.trim()}
                >
                  {renameMutation.isPending ? (
                    <Loader2 className="w-4 h-4 animate-spin" />
                  ) : (
                    "Save"
                  )}
                </Button>
                <Button variant="outline" onClick={() => setEditingHabit(null)}>
                  Cancel
                </Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>

        {/* Habits List */}
        {habitsLoading ? (
          <div className="bg-card rounded-lg border border-border shadow-soft p-12 text-center">
            <Loader2 className="w-6 h-6 text-muted-foreground animate-spin mx-auto mb-3" />
            <p className="text-muted-foreground">Loading habits…</p>
          </div>
        ) : habitsError ? (
          <div className="bg-card rounded-lg border border-border shadow-soft p-12 text-center">
            <div className="w-12 h-12 rounded-full bg-destructive/10 flex items-center justify-center mx-auto mb-3">
              <AlertCircle className="w-6 h-6 text-destructive" />
            </div>
            <p className="text-muted-foreground">Couldn't load your habits</p>
            <Button variant="outline" className="mt-4" onClick={() => refetchHabits()}>
              Try again
            </Button>
          </div>
        ) : habits.length === 0 ? (
          <div className="bg-card rounded-lg border border-border shadow-soft p-12 text-center">
            <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto mb-3">
              <Flame className="w-6 h-6 text-muted-foreground" />
            </div>
            <p className="text-muted-foreground">No habits yet</p>
            <p className="text-sm text-muted-foreground mt-1">Start building your routine</p>
          </div>
        ) : (
          <div className="grid gap-4">
            {habits.map((habit, index) => {
              const color = habitColors[habit.id] ?? "bg-primary";
              const insightsQuery = insightsQueries[index];
              const todayQuery = todayQueries[index];
              const insights: HabitInsights | undefined = insightsQuery?.data;
              const completedToday = todayQuery?.data?.completed ?? false;
              const isTogglePending =
                toggleTodayMutation.isPending &&
                toggleTodayMutation.variables?.habitId === habit.id;
              const detailsLoading = insightsQuery?.isLoading || todayQuery?.isLoading;
              const detailsErrored = insightsQuery?.isError || todayQuery?.isError;

              return (
                <div
                  key={habit.id}
                  className="bg-card rounded-lg border border-border shadow-soft p-4 group"
                >
                  <div className="flex items-center justify-between mb-4">
                    <div className="flex items-center gap-3">
                      <div className={cn("w-3 h-3 rounded-full", color)} />
                      <h3 className="font-medium text-foreground">{habit.name}</h3>
                    </div>
                    <div className="flex items-center gap-3">
                      <div className="flex items-center gap-2 text-sm text-muted-foreground">
                        <Flame className="w-4 h-4 text-warning" />
                        <span>
                          {detailsLoading
                            ? "…"
                            : `${insights?.streak.current_streak ?? 0} day${
                                insights?.streak.current_streak === 1 ? "" : "s"
                              }`}
                        </span>
                      </div>
                      <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-smooth">
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-8 w-8 text-muted-foreground hover:text-foreground"
                          onClick={() => openEditDialog(habit)}
                        >
                          <Pencil className="w-4 h-4" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-8 w-8 text-muted-foreground hover:text-destructive"
                          onClick={() => deleteMutation.mutate(habit.id)}
                          disabled={deleteMutation.isPending && deleteMutation.variables === habit.id}
                        >
                          {deleteMutation.isPending && deleteMutation.variables === habit.id ? (
                            <Loader2 className="w-4 h-4 animate-spin" />
                          ) : (
                            <Trash2 className="w-4 h-4" />
                          )}
                        </Button>
                      </div>
                    </div>
                  </div>

                  {detailsErrored ? (
                    <p className="text-sm text-muted-foreground">
                      Couldn't load today's status.
                    </p>
                  ) : (
                    <div className="flex flex-col sm:flex-row sm:items-center gap-4">
                      <button
                        onClick={() =>
                          !isTogglePending &&
                          !detailsLoading &&
                          toggleTodayMutation.mutate({
                            habitId: habit.id,
                            completed: !completedToday,
                          })
                        }
                        disabled={isTogglePending || detailsLoading}
                        className={cn(
                          "flex items-center gap-2 px-3 py-2 rounded-md ring-2 ring-primary ring-offset-2 ring-offset-card transition-smooth self-start",
                          detailsLoading && "opacity-60"
                        )}
                      >
                        <div
                          className={cn(
                            "w-7 h-7 rounded-md flex items-center justify-center transition-smooth",
                            completedToday ? color : "bg-muted"
                          )}
                        >
                          {isTogglePending ? (
                            <Loader2 className="w-4 h-4 animate-spin text-muted-foreground" />
                          ) : (
                            completedToday && <Check className="w-4 h-4 text-primary-foreground" />
                          )}
                        </div>
                        <span className="text-sm font-medium text-foreground">
                          {completedToday ? "Done today" : "Mark today done"}
                        </span>
                      </button>

                      {insights && (
                        <div className="flex-1 min-w-[160px]">
                          <div className="flex items-center justify-between text-xs text-muted-foreground mb-1">
                            <span>This week: {insights.weekly.completed_days}/7</span>
                            <span className="capitalize">{insights.momentum}</span>
                          </div>
                          <div className="h-1.5 rounded-full bg-muted overflow-hidden">
                            <div
                              className={cn("h-full rounded-full", color)}
                              style={{ width: `${insights.weekly.score}%` }}
                            />
                          </div>
                        </div>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </AppLayout>
  );
}
