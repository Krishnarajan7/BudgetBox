import { cn } from "@/lib/utils";

interface Habit {
  id: string;
  name: string;
  streak: number;
  weekProgress: boolean[];
}

const mockHabits: Habit[] = [
  { id: "1", name: "Morning Exercise", streak: 12, weekProgress: [true, true, true, true, true, false, false] },
  { id: "2", name: "Read 30 mins", streak: 8, weekProgress: [true, true, false, true, true, true, false] },
  { id: "3", name: "Meditate", streak: 21, weekProgress: [true, true, true, true, true, true, true] },
  { id: "4", name: "No Sugar", streak: 5, weekProgress: [true, true, true, false, true, true, false] },
];

const days = ["M", "T", "W", "T", "F", "S", "S"];

export function HabitTracker() {
  return (
    <div className="bg-card rounded-lg border border-border shadow-soft animate-fade-in">
      <div className="p-4 border-b border-border">
        <h3 className="text-sm font-semibold text-foreground">Weekly Habits</h3>
        <p className="text-xs text-muted-foreground mt-0.5">Track your daily progress</p>
      </div>

      <div className="p-4 space-y-4">
        {mockHabits.map((habit) => (
          <div key={habit.id}>
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm font-medium text-foreground">{habit.name}</span>
              <span className="text-xs text-muted-foreground">{habit.streak} day streak</span>
            </div>

            <div className="flex gap-1.5">
              {habit.weekProgress.map((completed, index) => (
                <div key={index} className="flex-1 flex flex-col items-center gap-1">
                  <div
                    className={cn(
                      "w-full h-6 rounded-sm transition-smooth",
                      completed
                        ? "bg-primary"
                        : "bg-muted"
                    )}
                  />
                  <span className="text-[10px] text-muted-foreground">{days[index]}</span>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
