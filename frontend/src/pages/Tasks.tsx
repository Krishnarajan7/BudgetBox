import { useState } from "react";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Check, Plus, Trash2, Calendar, Flag } from "lucide-react";
import { cn } from "@/lib/utils";

interface Task {
  id: string;
  title: string;
  completed: boolean;
  priority: "low" | "medium" | "high";
  dueDate?: string;
}

const initialTasks: Task[] = [
  { id: "1", title: "Review project proposal", completed: true, priority: "high", dueDate: "2024-12-05" },
  { id: "2", title: "Update documentation", completed: false, priority: "medium", dueDate: "2024-12-06" },
  { id: "3", title: "Schedule team meeting", completed: false, priority: "high", dueDate: "2024-12-05" },
  { id: "4", title: "Send weekly report", completed: false, priority: "low", dueDate: "2024-12-07" },
  { id: "5", title: "Fix navigation bug", completed: true, priority: "medium" },
  { id: "6", title: "Prepare presentation slides", completed: false, priority: "high", dueDate: "2024-12-08" },
  { id: "7", title: "Review pull requests", completed: false, priority: "medium" },
  { id: "8", title: "Update project timeline", completed: true, priority: "low" },
];

const priorityStyles = {
  low: "bg-muted text-muted-foreground",
  medium: "bg-warning/10 text-warning-foreground",
  high: "bg-destructive/10 text-destructive",
};

export default function Tasks() {
  const [tasks, setTasks] = useState<Task[]>(initialTasks);
  const [newTask, setNewTask] = useState("");
  const [filter, setFilter] = useState<"all" | "active" | "completed">("all");

  const toggleTask = (id: string) => {
    setTasks(tasks.map(t => t.id === id ? { ...t, completed: !t.completed } : t));
  };

  const deleteTask = (id: string) => {
    setTasks(tasks.filter(t => t.id !== id));
  };

  const addTask = () => {
    if (!newTask.trim()) return;
    setTasks([...tasks, {
      id: Date.now().toString(),
      title: newTask,
      completed: false,
      priority: "medium"
    }]);
    setNewTask("");
  };

  const filteredTasks = tasks.filter(t => {
    if (filter === "active") return !t.completed;
    if (filter === "completed") return t.completed;
    return true;
  });

  const completedCount = tasks.filter(t => t.completed).length;

  return (
    <AppLayout title="Tasks" subtitle="Manage your to-do list">
      <div className="max-w-3xl space-y-6">
        {/* Stats */}
        <div className="grid grid-cols-3 gap-4">
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground">Total Tasks</p>
            <p className="text-2xl font-semibold text-foreground">{tasks.length}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground">Completed</p>
            <p className="text-2xl font-semibold text-success">{completedCount}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground">Remaining</p>
            <p className="text-2xl font-semibold text-foreground">{tasks.length - completedCount}</p>
          </div>
        </div>

        {/* Add Task */}
        <div className="flex gap-2">
          <Input
            placeholder="Add a new task..."
            value={newTask}
            onChange={(e) => setNewTask(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && addTask()}
            className="flex-1"
          />
          <Button onClick={addTask} className="gap-2">
            <Plus className="w-4 h-4" />
            <span className="hidden sm:inline">Add Task</span>
          </Button>
        </div>

        {/* Filters */}
        <div className="flex gap-2">
          {(["all", "active", "completed"] as const).map((f) => (
            <Button
              key={f}
              variant={filter === f ? "default" : "outline"}
              size="sm"
              onClick={() => setFilter(f)}
              className="capitalize"
            >
              {f}
            </Button>
          ))}
        </div>

        {/* Task List */}
        <div className="bg-card rounded-lg border border-border shadow-soft divide-y divide-border">
          {filteredTasks.length === 0 ? (
            <div className="p-8 text-center text-muted-foreground">
              No tasks found
            </div>
          ) : (
            filteredTasks.map((task) => (
              <div
                key={task.id}
                className="flex items-center gap-3 p-4 hover:bg-muted/30 transition-smooth group"
              >
                <button
                  onClick={() => toggleTask(task.id)}
                  className={cn(
                    "w-5 h-5 rounded-full border-2 flex items-center justify-center transition-smooth flex-shrink-0",
                    task.completed
                      ? "bg-primary border-primary"
                      : "border-muted-foreground/30 hover:border-primary"
                  )}
                >
                  {task.completed && <Check className="w-3 h-3 text-primary-foreground" />}
                </button>

                <div className="flex-1 min-w-0">
                  <span
                    className={cn(
                      "text-sm block truncate",
                      task.completed ? "text-muted-foreground line-through" : "text-foreground"
                    )}
                  >
                    {task.title}
                  </span>
                  {task.dueDate && (
                    <span className="text-xs text-muted-foreground flex items-center gap-1 mt-0.5">
                      <Calendar className="w-3 h-3" />
                      {new Date(task.dueDate).toLocaleDateString()}
                    </span>
                  )}
                </div>

                <span
                  className={cn(
                    "text-xs font-medium px-2 py-0.5 rounded-full capitalize hidden sm:block",
                    priorityStyles[task.priority]
                  )}
                >
                  {task.priority}
                </span>

                <Button
                  variant="ghost"
                  size="icon"
                  className="h-8 w-8 opacity-0 group-hover:opacity-100 transition-smooth text-muted-foreground hover:text-destructive"
                  onClick={() => deleteTask(task.id)}
                >
                  <Trash2 className="w-4 h-4" />
                </Button>
              </div>
            ))
          )}
        </div>
      </div>
    </AppLayout>
  );
}
