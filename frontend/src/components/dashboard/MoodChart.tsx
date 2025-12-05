import { cn } from "@/lib/utils";

const moodData = [
  { day: "Mon", value: 4, emoji: "😊" },
  { day: "Tue", value: 3, emoji: "😐" },
  { day: "Wed", value: 5, emoji: "😄" },
  { day: "Thu", value: 4, emoji: "😊" },
  { day: "Fri", value: 2, emoji: "😔" },
  { day: "Sat", value: 4, emoji: "😊" },
  { day: "Sun", value: 5, emoji: "😄" },
];

const maxValue = 5;

export function MoodChart() {
  return (
    <div className="bg-card rounded-lg border border-border shadow-soft animate-fade-in">
      <div className="p-4 border-b border-border">
        <h3 className="text-sm font-semibold text-foreground">Weekly Mood</h3>
        <p className="text-xs text-muted-foreground mt-0.5">How you've been feeling</p>
      </div>

      <div className="p-4">
        <div className="flex items-end justify-between gap-2 h-32">
          {moodData.map((item, index) => (
            <div key={index} className="flex-1 flex flex-col items-center gap-2">
              <span className="text-lg">{item.emoji}</span>
              <div className="w-full bg-muted rounded-t-sm relative flex-1 flex items-end">
                <div
                  className="w-full bg-primary rounded-t-sm transition-smooth"
                  style={{ height: `${(item.value / maxValue) * 100}%` }}
                />
              </div>
              <span className="text-xs text-muted-foreground">{item.day}</span>
            </div>
          ))}
        </div>

        <div className="mt-4 pt-4 border-t border-border flex items-center justify-between">
          <span className="text-xs text-muted-foreground">Average mood</span>
          <span className="text-sm font-medium text-foreground">
            {(moodData.reduce((sum, d) => sum + d.value, 0) / moodData.length).toFixed(1)} / 5
          </span>
        </div>
      </div>
    </div>
  );
}
