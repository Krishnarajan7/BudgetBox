import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { Check, AlertCircle, ListChecks } from "lucide-react";
import { cn } from "@/lib/utils";
import { Skeleton } from "@/components/ui/skeleton";
import { listTasks, type TaskResponse } from "@/api/tasks.api";
import { toLocalDateString, isSameLocalDay } from "@/api/dashboard.api";

const priorityStyles: Record<string, string> = {
  low: "bg-muted text-muted-foreground",
  medium: "bg-warning/10 text-warning-foreground",
  high: "bg-destructive/10 text-destructive",
};

// Read-only preview of the Tasks page — same "tasks" query cache, so
// whatever is edited on /tasks is reflected here without an extra fetch.
export function TaskList() {
  const {
    data: tasks,
    isLoading,
    isError,
  } = useQuery({
    queryKey: ["tasks"],
    queryFn: listTasks,
  });

  const today = toLocalDateString();

  const sorted = (tasks ?? [])
    .slice()
    .sort((a, b) => {
      if (a.completed !== b.completed) return a.completed ? 1 : -1;
      const aTime = a.due_at ? new Date(a.due_at).getTime() : Infinity;
      const bTime = b.due_at ? new Date(b.due_at).getTime() : Infinity;
      return aTime - bTime;
    });

  const preview = sorted.slice(0, 5);
  const completedCount = (tasks ?? []).filter((t) => t.completed).length;
  const dueTodayCount = (tasks ?? []).filter((t) =>
    isSameLocalDay(t.due_at, today)
  ).length;

  return (
    <div className="bg-card rounded-lg border border-border shadow-soft animate-fade-in">
      <div className="p-4 border-b border-border flex items-center justify-between">
        <div>
          <h3 className="text-sm font-semibold text-foreground">Today's Tasks</h3>
          <p className="text-xs text-muted-foreground mt-0.5">
            {isLoading
              ? "Loading…"
              : `${completedCount} of ${(tasks ?? []).length} completed · ${dueTodayCount} due today`}
          </p>
        </div>
        <Link to="/tasks" className="text-xs font-medium text-primary hover:underline">
          View all
        </Link>
      </div>

      {isLoading ? (
        <div className="p-4 space-y-3">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-10 w-full" />
          ))}
        </div>
      ) : isError ? (
        <div className="p-8 text-center">
          <AlertCircle className="w-6 h-6 text-destructive mx-auto mb-2" />
          <p className="text-sm text-muted-foreground">Couldn't load tasks</p>
        </div>
      ) : preview.length === 0 ? (
        <div className="p-8 text-center">
          <ListChecks className="w-6 h-6 text-muted-foreground mx-auto mb-2" />
          <p className="text-sm text-muted-foreground">No tasks yet</p>
          <Link to="/tasks" className="text-xs text-primary hover:underline">
            Add your first task
          </Link>
        </div>
      ) : (
        <div className="divide-y divide-border">
          {preview.map((task: TaskResponse) => (
            <div
              key={task.id}
              className="flex items-center gap-3 p-4 hover:bg-muted/50 transition-smooth"
            >
              <div
                className={cn(
                  "w-5 h-5 rounded-full border-2 flex items-center justify-center flex-shrink-0",
                  task.completed
                    ? "bg-primary border-primary"
                    : "border-muted-foreground/30"
                )}
              >
                {task.completed && <Check className="w-3 h-3 text-primary-foreground" />}
              </div>

              <span
                className={cn(
                  "flex-1 text-sm truncate",
                  task.completed
                    ? "text-muted-foreground line-through"
                    : "text-foreground"
                )}
              >
                {task.title}
              </span>

              <span
                className={cn(
                  "text-xs font-medium px-2 py-0.5 rounded-full capitalize flex-shrink-0",
                  priorityStyles[task.priority] ?? priorityStyles.low
                )}
              >
                {task.priority}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
