import { useState } from "react";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Plus, Flame, Check } from "lucide-react";
import { cn } from "@/lib/utils";

interface Habit {
  id: string;
  name: string;
  streak: number;
  weekProgress: boolean[];
  color: string;
}

const initialHabits: Habit[] = [
  { id: "1", name: "Morning Exercise", streak: 12, weekProgress: [true, true, true, true, true, false, false], color: "bg-primary" },
  { id: "2", name: "Read 30 mins", streak: 8, weekProgress: [true, true, false, true, true, true, false], color: "bg-info" },
  { id: "3", name: "Meditate", streak: 21, weekProgress: [true, true, true, true, true, true, true], color: "bg-success" },
  { id: "4", name: "No Sugar", streak: 5, weekProgress: [true, true, true, false, true, true, false], color: "bg-warning" },
  { id: "5", name: "Drink Water", streak: 15, weekProgress: [true, true, true, true, true, true, false], color: "bg-info" },
  { id: "6", name: "Practice Guitar", streak: 3, weekProgress: [false, true, true, true, false, false, false], color: "bg-destructive" },
];

const days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const today = new Date().getDay();
const todayIndex = today === 0 ? 6 : today - 1;

export default function Habits() {
  const [habits, setHabits] = useState<Habit[]>(initialHabits);

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

  const totalCompleted = habits.filter(h => h.weekProgress[todayIndex]).length;
  const longestStreak = Math.max(...habits.map(h => h.streak));

  return (
    <AppLayout title="Habits" subtitle="Build better routines">
      <div className="max-w-4xl space-y-6">
        {/* Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground">Total Habits</p>
            <p className="text-2xl font-semibold text-foreground">{habits.length}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground">Done Today</p>
            <p className="text-2xl font-semibold text-success">{totalCompleted}/{habits.length}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground">Completion Rate</p>
            <p className="text-2xl font-semibold text-foreground">{Math.round((totalCompleted / habits.length) * 100)}%</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft flex items-center gap-2">
            <div>
              <p className="text-xs text-muted-foreground">Longest Streak</p>
              <p className="text-2xl font-semibold text-foreground">{longestStreak}</p>
            </div>
            <Flame className="w-6 h-6 text-warning ml-auto" />
          </div>
        </div>

        {/* Habits Grid */}
        <div className="grid gap-4">
          {habits.map((habit) => (
            <div
              key={habit.id}
              className="bg-card rounded-lg border border-border shadow-soft p-4 animate-fade-in"
            >
              <div className="flex items-center justify-between mb-4">
                <div className="flex items-center gap-3">
                  <div className={cn("w-3 h-3 rounded-full", habit.color)} />
                  <h3 className="font-medium text-foreground">{habit.name}</h3>
                </div>
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                  <Flame className="w-4 h-4 text-warning" />
                  <span>{habit.streak} day streak</span>
                </div>
              </div>

              <div className="grid grid-cols-7 gap-2">
                {habit.weekProgress.map((completed, index) => (
                  <button
                    key={index}
                    onClick={() => index === todayIndex && toggleToday(habit.id)}
                    disabled={index !== todayIndex}
                    className={cn(
                      "flex flex-col items-center gap-1 p-2 rounded-md transition-smooth",
                      index === todayIndex && "ring-2 ring-primary ring-offset-2 ring-offset-card",
                      index !== todayIndex && "opacity-60"
                    )}
                  >
                    <div
                      className={cn(
                        "w-8 h-8 rounded-md flex items-center justify-center transition-smooth",
                        completed ? habit.color : "bg-muted"
                      )}
                    >
                      {completed && <Check className="w-4 h-4 text-primary-foreground" />}
                    </div>
                    <span className={cn(
                      "text-xs",
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

        <Button className="w-full gap-2">
          <Plus className="w-4 h-4" />
          Add New Habit
        </Button>
      </div>
    </AppLayout>
  );
}
