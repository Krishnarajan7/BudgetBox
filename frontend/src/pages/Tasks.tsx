import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Check, Plus, Trash2, Calendar, Pencil, Loader2, AlertCircle } from "lucide-react";
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
import {
  completeTask,
  createTask,
  deleteTask,
  listTasks,
  patchTaskLogToday,
  updateTask as updateTaskApi,
  type TaskResponse,
} from "@/api/tasks.api";

type Priority = "low" | "medium" | "high";

// UI-level task shape, derived directly from the backend's TaskResponse
// (`completed` and `priority` are now returned by GET /tasks).
interface Task {
  id: number;
  title: string;
  completed: boolean;
  priority: Priority;
  dueDate?: string;
}

const priorityStyles: Record<Priority, string> = {
  low: "bg-muted text-muted-foreground",
  medium: "bg-warning/10 text-warning-foreground",
  high: "bg-destructive/10 text-destructive",
};

const priorityDot: Record<Priority, string> = {
  low: "bg-muted-foreground",
  medium: "bg-warning",
  high: "bg-destructive",
};

// Uses local date components (not toISOString, which is UTC) so "today"
// matches the user's wall-clock date regardless of timezone offset.
function toLocalDateString(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

// Converts an ISO due_at timestamp from the backend into a plain
// YYYY-MM-DD string using local date parts, for the <input type="date">
// and for same-day comparisons against "today".
function isoToLocalDateString(iso: string | null): string | undefined {
  if (!iso) return undefined;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return undefined;
  return toLocalDateString(d);
}

export default function Tasks() {
  const queryClient = useQueryClient();

  const {
    data: rawTasks,
    isLoading,
    isError,
    error,
  } = useQuery({
    queryKey: ["tasks"],
    queryFn: listTasks,
  });

  const tasks: Task[] = useMemo(() => {
    return (rawTasks ?? []).map((t: TaskResponse) => ({
      id: t.id,
      title: t.title,
      completed: t.completed,
      priority: t.priority,
      dueDate: isoToLocalDateString(t.due_at),
    }));
  }, [rawTasks]);

  const [filter, setFilter] = useState<"all" | "active" | "completed">("all");
  const [isAddOpen, setIsAddOpen] = useState(false);
  const [editingTask, setEditingTask] = useState<Task | null>(null);
  const [formData, setFormData] = useState({
    title: "",
    priority: "medium" as Priority,
    dueDate: "",
  });

  const resetForm = () => {
    setFormData({ title: "", priority: "medium", dueDate: "" });
    setEditingTask(null);
  };

  const invalidateTasks = () =>
    queryClient.invalidateQueries({ queryKey: ["tasks"] });

  const createMutation = useMutation({
    mutationFn: (vars: {
      title: string;
      due_at?: string | null;
      priority: Priority;
    }) =>
      createTask({
        title: vars.title,
        due_at: vars.due_at,
        priority: vars.priority,
      }),
    onSuccess: () => {
      invalidateTasks();
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: number) => deleteTask(id),
    onSuccess: () => {
      invalidateTasks();
    },
  });

  // Edits update the existing task in place via PATCH /tasks/{task_id},
  // preserving its id and log history.
  const editMutation = useMutation({
    mutationFn: (vars: {
      id: number;
      title: string;
      due_at?: string | null;
      priority: Priority;
    }) =>
      updateTaskApi(vars.id, {
        title: vars.title,
        due_at: vars.due_at,
        priority: vars.priority,
      }),
    onSuccess: () => {
      invalidateTasks();
    },
  });

  // Toggling complete/incomplete. Completing twice is safe server-side
  // (complete_task_for_today just returns the existing log), but
  // un-completing requires the logs/today PATCH endpoint since /complete
  // has no way to express "not completed".
  const toggleMutation = useMutation({
    mutationFn: (vars: { id: number; nextCompleted: boolean }) =>
      vars.nextCompleted
        ? completeTask(vars.id)
        : patchTaskLogToday(vars.id, false),
    onSuccess: () => {
      invalidateTasks();
    },
  });

  const toggleTask = (task: Task) => {
    if (toggleMutation.isPending && toggleMutation.variables?.id === task.id) return;
    toggleMutation.mutate({ id: task.id, nextCompleted: !task.completed });
  };

  const handleDeleteTask = (id: number) => {
    deleteMutation.mutate(id);
  };

  const addTask = () => {
    if (!formData.title.trim()) return;
    createMutation.mutate({
      title: formData.title,
      due_at: formData.dueDate || null,
      priority: formData.priority,
    });
    resetForm();
    setIsAddOpen(false);
  };

  const updateTask = () => {
    if (!editingTask || !formData.title.trim()) return;
    editMutation.mutate({
      id: editingTask.id,
      title: formData.title,
      due_at: formData.dueDate || null,
      priority: formData.priority,
    });
    resetForm();
  };

  const startEdit = (task: Task) => {
    setEditingTask(task);
    setFormData({
      title: task.title,
      priority: task.priority,
      dueDate: task.dueDate || "",
    });
  };

  const filteredTasks = tasks.filter((t) => {
    if (filter === "active") return !t.completed;
    if (filter === "completed") return t.completed;
    return true;
  });

  const completedCount = tasks.filter((t) => t.completed).length;
  const today = toLocalDateString(new Date());
  const todayTasks = tasks.filter((t) => t.dueDate === today);

  return (
    <AppLayout title="Tasks" subtitle="Manage your to-do list">
      <div className="w-full max-w-5xl mx-auto space-y-6">
        {/* Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 md:gap-4">
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-1">Total Tasks</p>
            <p className="text-2xl font-semibold text-foreground">{tasks.length}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-1">Completed</p>
            <p className="text-2xl font-semibold text-success">{completedCount}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-1">Remaining</p>
            <p className="text-2xl font-semibold text-foreground">{tasks.length - completedCount}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-1">Due Today</p>
            <p className="text-2xl font-semibold text-primary">{todayTasks.length}</p>
          </div>
        </div>

        {/* Actions Bar */}
        <div className="flex flex-col sm:flex-row gap-3 sm:items-center sm:justify-between">
          <div className="flex gap-2 overflow-x-auto pb-1">
            {(["all", "active", "completed"] as const).map((f) => (
              <Button
                key={f}
                variant={filter === f ? "default" : "outline"}
                size="sm"
                onClick={() => setFilter(f)}
                className="capitalize whitespace-nowrap"
              >
                {f} {f === "all" && `(${tasks.length})`}
              </Button>
            ))}
          </div>

          <Dialog open={isAddOpen} onOpenChange={setIsAddOpen}>
            <DialogTrigger asChild>
              <Button className="gap-2" onClick={() => resetForm()}>
                <Plus className="w-4 h-4" />
                Add Task
              </Button>
            </DialogTrigger>
            <DialogContent className="sm:max-w-md">
              <DialogHeader>
                <DialogTitle>Add New Task</DialogTitle>
              </DialogHeader>
              <div className="space-y-4 pt-4">
                <div>
                  <label className="text-sm font-medium text-foreground mb-1.5 block">Title</label>
                  <Input
                    placeholder="What needs to be done?"
                    value={formData.title}
                    onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                  />
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="text-sm font-medium text-foreground mb-1.5 block">Priority</label>
                    <Select
                      value={formData.priority}
                      onValueChange={(v) => setFormData({ ...formData, priority: v as Priority })}
                    >
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="low">Low</SelectItem>
                        <SelectItem value="medium">Medium</SelectItem>
                        <SelectItem value="high">High</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  <div>
                    <label className="text-sm font-medium text-foreground mb-1.5 block">Due Date</label>
                    <Input
                      type="date"
                      value={formData.dueDate}
                      onChange={(e) => setFormData({ ...formData, dueDate: e.target.value })}
                    />
                  </div>
                </div>
                <div className="flex gap-2 pt-2">
                  <Button
                    onClick={addTask}
                    className="flex-1"
                    disabled={createMutation.isPending}
                  >
                    {createMutation.isPending ? "Adding..." : "Add Task"}
                  </Button>
                  <Button variant="outline" onClick={() => setIsAddOpen(false)}>Cancel</Button>
                </div>
              </div>
            </DialogContent>
          </Dialog>
        </div>

        {/* Edit Modal */}
        <Dialog open={!!editingTask} onOpenChange={(open) => !open && resetForm()}>
          <DialogContent className="sm:max-w-md">
            <DialogHeader>
              <DialogTitle>Edit Task</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 pt-4">
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Title</label>
                <Input
                  placeholder="What needs to be done?"
                  value={formData.title}
                  onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-sm font-medium text-foreground mb-1.5 block">Priority</label>
                  <Select
                    value={formData.priority}
                    onValueChange={(v) => setFormData({ ...formData, priority: v as Priority })}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="low">Low</SelectItem>
                      <SelectItem value="medium">Medium</SelectItem>
                      <SelectItem value="high">High</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <label className="text-sm font-medium text-foreground mb-1.5 block">Due Date</label>
                  <Input
                    type="date"
                    value={formData.dueDate}
                    onChange={(e) => setFormData({ ...formData, dueDate: e.target.value })}
                  />
                </div>
              </div>
              <div className="flex gap-2 pt-2">
                <Button
                  onClick={updateTask}
                  className="flex-1"
                  disabled={editMutation.isPending}
                >
                  {editMutation.isPending ? "Saving..." : "Save Changes"}
                </Button>
                <Button variant="outline" onClick={resetForm}>Cancel</Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>

        {/* Task List */}
        <div className="bg-card rounded-lg border border-border shadow-soft">
          {isLoading ? (
            <div className="p-12 text-center">
              <Loader2 className="w-6 h-6 animate-spin mx-auto mb-3 text-muted-foreground" />
              <p className="text-muted-foreground">Loading tasks...</p>
            </div>
          ) : isError ? (
            <div className="p-12 text-center">
              <div className="w-12 h-12 rounded-full bg-destructive/10 flex items-center justify-center mx-auto mb-3">
                <AlertCircle className="w-6 h-6 text-destructive" />
              </div>
              <p className="text-destructive font-medium">Failed to load tasks</p>
              <p className="text-sm text-muted-foreground mt-1">
                {error instanceof Error ? error.message : "Please try again."}
              </p>
            </div>
          ) : filteredTasks.length === 0 ? (
            <div className="p-12 text-center">
              <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto mb-3">
                <Check className="w-6 h-6 text-muted-foreground" />
              </div>
              <p className="text-muted-foreground">No tasks found</p>
              <p className="text-sm text-muted-foreground mt-1">Add a new task to get started</p>
            </div>
          ) : (
            <div className="divide-y divide-border">
              {filteredTasks.map((task) => (
                <div
                  key={task.id}
                  className="flex items-start sm:items-center gap-3 p-4 hover:bg-muted/30 transition-smooth group"
                >
                  <button
                    onClick={() => toggleTask(task)}
                    disabled={toggleMutation.isPending && toggleMutation.variables?.id === task.id}
                    className={cn(
                      "w-5 h-5 rounded-full border-2 flex items-center justify-center transition-smooth flex-shrink-0 mt-0.5 sm:mt-0",
                      task.completed
                        ? "bg-primary border-primary"
                        : "border-muted-foreground/30 hover:border-primary"
                    )}
                  >
                    {task.completed && <Check className="w-3 h-3 text-primary-foreground" />}
                  </button>

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span
                        className={cn(
                          "text-sm",
                          task.completed ? "text-muted-foreground line-through" : "text-foreground"
                        )}
                      >
                        {task.title}
                      </span>
                      <span className={cn("w-2 h-2 rounded-full", priorityDot[task.priority])} />
                    </div>
                    {task.dueDate && (
                      <span className="text-xs text-muted-foreground flex items-center gap-1 mt-1">
                        <Calendar className="w-3 h-3" />
                        {new Date(task.dueDate).toLocaleDateString("en-US", { month: "short", day: "numeric" })}
                      </span>
                    )}
                  </div>

                  <span
                    className={cn(
                      "text-xs font-medium px-2 py-0.5 rounded-full capitalize hidden md:block",
                      priorityStyles[task.priority]
                    )}
                  >
                    {task.priority}
                  </span>

                  <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-smooth">
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 text-muted-foreground hover:text-foreground"
                      onClick={() => startEdit(task)}
                    >
                      <Pencil className="w-4 h-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 text-muted-foreground hover:text-destructive"
                      onClick={() => handleDeleteTask(task.id)}
                    >
                      <Trash2 className="w-4 h-4" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </AppLayout>
  );
}
