import { useState } from "react";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";

interface MoodEntry {
  id: string;
  date: string;
  mood: number;
  emoji: string;
  note?: string;
}

const moodOptions = [
  { value: 1, emoji: "😢", label: "Terrible", color: "bg-destructive/20" },
  { value: 2, emoji: "😔", label: "Bad", color: "bg-warning/20" },
  { value: 3, emoji: "😐", label: "Okay", color: "bg-muted" },
  { value: 4, emoji: "😊", label: "Good", color: "bg-info/20" },
  { value: 5, emoji: "😄", label: "Great", color: "bg-success/20" },
];

const initialEntries: MoodEntry[] = [
  { id: "1", date: "2024-12-05", mood: 4, emoji: "😊", note: "Had a productive day at work" },
  { id: "2", date: "2024-12-04", mood: 3, emoji: "😐", note: "Feeling a bit tired" },
  { id: "3", date: "2024-12-03", mood: 5, emoji: "😄", note: "Great workout session!" },
  { id: "4", date: "2024-12-02", mood: 4, emoji: "😊" },
  { id: "5", date: "2024-12-01", mood: 2, emoji: "😔", note: "Stressful deadline" },
  { id: "6", date: "2024-11-30", mood: 4, emoji: "😊", note: "Weekend relaxation" },
  { id: "7", date: "2024-11-29", mood: 5, emoji: "😄" },
];

export default function Mood() {
  const [entries, setEntries] = useState<MoodEntry[]>(initialEntries);
  const [selectedMood, setSelectedMood] = useState<number | null>(null);
  const [note, setNote] = useState("");

  const logMood = () => {
    if (selectedMood === null) return;
    const moodOption = moodOptions.find(m => m.value === selectedMood);
    const newEntry: MoodEntry = {
      id: Date.now().toString(),
      date: new Date().toISOString().split("T")[0],
      mood: selectedMood,
      emoji: moodOption?.emoji || "😐",
      note: note || undefined
    };
    setEntries([newEntry, ...entries]);
    setSelectedMood(null);
    setNote("");
  };

  const avgMood = (entries.reduce((sum, e) => sum + e.mood, 0) / entries.length).toFixed(1);
  const todayEntry = entries.find(e => e.date === new Date().toISOString().split("T")[0]);

  return (
    <AppLayout title="Mood" subtitle="Track how you feel">
      <div className="max-w-2xl space-y-6">
        {/* Today's Mood Logger */}
        <div className="bg-card rounded-lg border border-border shadow-soft p-6 animate-fade-in">
          <h3 className="text-sm font-semibold text-foreground mb-4">
            {todayEntry ? "Today's mood logged" : "How are you feeling today?"}
          </h3>

          {!todayEntry ? (
            <>
              <div className="flex justify-between gap-2 mb-4">
                {moodOptions.map((option) => (
                  <button
                    key={option.value}
                    onClick={() => setSelectedMood(option.value)}
                    className={cn(
                      "flex-1 flex flex-col items-center gap-2 p-3 rounded-lg transition-smooth border-2",
                      selectedMood === option.value
                        ? "border-primary bg-accent"
                        : "border-transparent hover:bg-muted"
                    )}
                  >
                    <span className="text-3xl">{option.emoji}</span>
                    <span className="text-xs text-muted-foreground">{option.label}</span>
                  </button>
                ))}
              </div>

              <Textarea
                placeholder="Add a note about your day (optional)..."
                value={note}
                onChange={(e) => setNote(e.target.value)}
                className="mb-4 resize-none"
                rows={2}
              />

              <Button onClick={logMood} disabled={selectedMood === null} className="w-full">
                Log Mood
              </Button>
            </>
          ) : (
            <div className="flex items-center gap-4 p-4 bg-accent/50 rounded-lg">
              <span className="text-4xl">{todayEntry.emoji}</span>
              <div>
                <p className="font-medium text-foreground">
                  {moodOptions.find(m => m.value === todayEntry.mood)?.label}
                </p>
                {todayEntry.note && (
                  <p className="text-sm text-muted-foreground">{todayEntry.note}</p>
                )}
              </div>
            </div>
          )}
        </div>

        {/* Stats */}
        <div className="grid grid-cols-3 gap-4">
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft text-center">
            <p className="text-xs text-muted-foreground">Entries</p>
            <p className="text-2xl font-semibold text-foreground">{entries.length}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft text-center">
            <p className="text-xs text-muted-foreground">Average</p>
            <p className="text-2xl font-semibold text-foreground">{avgMood}/5</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft text-center">
            <p className="text-xs text-muted-foreground">Most Common</p>
            <p className="text-2xl">😊</p>
          </div>
        </div>

        {/* History */}
        <div className="bg-card rounded-lg border border-border shadow-soft">
          <div className="p-4 border-b border-border">
            <h3 className="text-sm font-semibold text-foreground">Mood History</h3>
          </div>
          <div className="divide-y divide-border">
            {entries.map((entry) => (
              <div key={entry.id} className="flex items-center gap-4 p-4 hover:bg-muted/30 transition-smooth">
                <span className="text-2xl">{entry.emoji}</span>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-foreground">
                    {moodOptions.find(m => m.value === entry.mood)?.label}
                  </p>
                  {entry.note && (
                    <p className="text-xs text-muted-foreground truncate">{entry.note}</p>
                  )}
                </div>
                <span className="text-xs text-muted-foreground">
                  {new Date(entry.date).toLocaleDateString("en-US", { month: "short", day: "numeric" })}
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </AppLayout>
  );
}
