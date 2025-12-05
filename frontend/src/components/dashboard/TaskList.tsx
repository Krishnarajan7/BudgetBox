import { Check, Circle } from "lucide-react";
import { cn } from "@/lib/utils";

interface Task {
  id: string;
  title: string;
  completed: boolean;
  priority: "low" | "medium" | "high";
}

const mockTasks: Task[] = [
  { id: "1", title: "Review project proposal", completed: true, priority: "high" },
  { id: "2", title: "Update documentation", completed: false, priority: "medium" },
  { id: "3", title: "Schedule team meeting", completed: false, priority: "high" },
  { id: "4", title: "Send weekly report", completed: false, priority: "low" },
  { id: "5", title: "Fix navigation bug", completed: true, priority: "medium" },
];

const priorityStyles = {
  low: "bg-muted text-muted-foreground",
  medium: "bg-warning/10 text-warning-foreground",
  high: "bg-destructive/10 text-destructive",
};

export function TaskList() {
  return (
    <div className="bg-card rounded-lg border border-border shadow-soft animate-fade-in">
      <div className="p-4 border-b border-border">
        <h3 className="text-sm font-semibold text-foreground">Today's Tasks</h3>
        <p className="text-xs text-muted-foreground mt-0.5">
          {mockTasks.filter((t) => t.completed).length} of {mockTasks.length} completed
        </p>
      </div>

      <div className="divide-y divide-border">
        {mockTasks.map((task) => (
          <div
            key={task.id}
            className="flex items-center gap-3 p-4 hover:bg-muted/50 transition-smooth"
          >
            <button
              className={cn(
                "w-5 h-5 rounded-full border-2 flex items-center justify-center transition-smooth",
                task.completed
                  ? "bg-primary border-primary"
                  : "border-muted-foreground/30 hover:border-primary"
              )}
            >
              {task.completed && <Check className="w-3 h-3 text-primary-foreground" />}
            </button>

            <span
              className={cn(
                "flex-1 text-sm",
                task.completed
                  ? "text-muted-foreground line-through"
                  : "text-foreground"
              )}
            >
              {task.title}
            </span>

            <span
              className={cn(
                "text-xs font-medium px-2 py-0.5 rounded-full capitalize",
                priorityStyles[task.priority]
              )}
            >
              {task.priority}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
