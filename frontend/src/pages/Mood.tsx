import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Trash2, Pencil, Loader2, AlertCircle } from "lucide-react";
import { cn } from "@/lib/utils";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useToast } from "@/hooks/use-toast";
import {
  MoodEntry,
  deleteMoodEntry,
  listMoodEntries,
  upsertMoodEntry,
} from "@/api/wellness.api";

const moodOptions = [
  { value: 1, emoji: "😢", label: "Terrible", color: "bg-destructive/20 border-destructive/30" },
  { value: 2, emoji: "😔", label: "Bad", color: "bg-warning/20 border-warning/30" },
  { value: 3, emoji: "😐", label: "Okay", color: "bg-muted border-border" },
  { value: 4, emoji: "😊", label: "Good", color: "bg-info/20 border-info/30" },
  { value: 5, emoji: "😄", label: "Great", color: "bg-success/20 border-success/30" },
];

function formatLocalDate(d: Date): string {
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function parseLocalDate(dateStr: string): Date {
  const [year, month, day] = dateStr.split("-").map(Number);
  return new Date(year, month - 1, day);
}

function emojiFor(mood: number): string {
  return moodOptions.find((m) => m.value === mood)?.emoji || "😐";
}

export default function Mood() {
  const { toast } = useToast();
  const queryClient = useQueryClient();

  const [selectedMood, setSelectedMood] = useState<number | null>(null);
  const [note, setNote] = useState("");
  const [editingEntry, setEditingEntry] = useState<MoodEntry | null>(null);

  const todayStr = formatLocalDate(new Date());

  const {
    data: entries = [],
    isLoading,
    isError,
    refetch,
  } = useQuery({
    queryKey: ["mood"],
    queryFn: () => listMoodEntries(),
  });

  const todayEntry = entries.find((e) => e.date === todayStr);

  const upsertMutation = useMutation({
    mutationFn: (vars: { date: string; mood: number; note?: string }) =>
      upsertMoodEntry(vars.date, { mood: vars.mood, note: vars.note }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["mood"] });
      resetEdit();
    },
    onError: () => {
      toast({
        title: "Couldn't save mood",
        description: "Please try again.",
        variant: "destructive",
      });
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (date: string) => deleteMoodEntry(date),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["mood"] });
    },
    onError: () => {
      toast({
        title: "Couldn't delete entry",
        description: "Please try again.",
        variant: "destructive",
      });
    },
  });

  const logMood = () => {
    if (selectedMood === null || upsertMutation.isPending) return;
    upsertMutation.mutate({
      date: todayStr,
      mood: selectedMood,
      note: note.trim() || undefined,
    });
  };

  const updateEntry = () => {
    if (!editingEntry || selectedMood === null || upsertMutation.isPending) return;
    upsertMutation.mutate({
      date: editingEntry.date,
      mood: selectedMood,
      note: note.trim() || undefined,
    });
  };

  const startEdit = (entry: MoodEntry) => {
    setEditingEntry(entry);
    setSelectedMood(entry.mood);
    setNote(entry.note || "");
  };

  const resetEdit = () => {
    setEditingEntry(null);
    setSelectedMood(null);
    setNote("");
  };

  const avgMood = entries.length > 0
    ? (entries.reduce((sum, e) => sum + e.mood, 0) / entries.length).toFixed(1)
    : "0";

  const moodCounts = moodOptions.map(opt => ({
    ...opt,
    count: entries.filter(e => e.mood === opt.value).length
  }));
  const mostCommon = moodCounts.reduce((a, b) => a.count > b.count ? a : b, moodCounts[0]);

  return (
    <AppLayout title="Mood" subtitle="Track how you feel">
      <div className="w-full max-w-4xl mx-auto space-y-6">
        {/* Today's Mood Logger */}
        <div className="bg-card rounded-lg border border-border shadow-soft p-6">
          <h3 className="text-sm font-semibold text-foreground mb-4">
            {todayEntry ? "Update today's mood" : "How are you feeling today?"}
          </h3>

          <div className="flex flex-wrap justify-center gap-2 sm:gap-3 mb-4">
            {moodOptions.map((option) => (
              <button
                key={option.value}
                onClick={() => setSelectedMood(option.value)}
                className={cn(
                  "flex flex-col items-center gap-1.5 p-2 sm:p-3 rounded-lg transition-smooth border-2",
                  selectedMood === option.value
                    ? "border-primary bg-accent scale-105"
                    : "border-transparent hover:bg-muted"
                )}
              >
                <span className="text-2xl sm:text-3xl">{option.emoji}</span>
                <span className="text-[10px] sm:text-xs text-muted-foreground">{option.label}</span>
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

          <Button
            onClick={logMood}
            disabled={selectedMood === null || upsertMutation.isPending}
            className="w-full"
          >
            {upsertMutation.isPending && !editingEntry ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : todayEntry ? (
              "Update Mood"
            ) : (
              "Log Mood"
            )}
          </Button>
        </div>

        {/* Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 md:gap-4">
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft text-center">
            <p className="text-xs text-muted-foreground mb-1">Total Entries</p>
            <p className="text-2xl font-semibold text-foreground">{entries.length}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft text-center">
            <p className="text-xs text-muted-foreground mb-1">Average</p>
            <p className="text-2xl font-semibold text-foreground">{avgMood}/5</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft text-center">
            <p className="text-xs text-muted-foreground mb-1">Most Common</p>
            <p className="text-2xl">{mostCommon?.emoji || "—"}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft text-center">
            <p className="text-xs text-muted-foreground mb-1">Today</p>
            <p className="text-2xl">{todayEntry ? emojiFor(todayEntry.mood) : "—"}</p>
          </div>
        </div>

        {/* Mood Distribution */}
        <div className="bg-card rounded-lg border border-border shadow-soft p-4">
          <h3 className="text-sm font-semibold text-foreground mb-4">Mood Distribution</h3>
          <div className="flex items-end justify-between gap-2 h-24">
            {moodCounts.map((mood) => {
              const maxCount = Math.max(...moodCounts.map(m => m.count), 1);
              const heightPercent = (mood.count / maxCount) * 100;
              return (
                <div key={mood.value} className="flex-1 flex flex-col items-center gap-2">
                  <span className="text-xs text-muted-foreground">{mood.count}</span>
                  <div className="w-full bg-muted rounded-t-sm flex-1 flex items-end" style={{ height: '60px' }}>
                    <div
                      className={cn("w-full rounded-t-sm transition-smooth", mood.color.split(" ")[0])}
                      style={{ height: `${Math.max(heightPercent, 5)}%` }}
                    />
                  </div>
                  <span className="text-lg">{mood.emoji}</span>
                </div>
              );
            })}
          </div>
        </div>

        {/* Edit Modal */}
        <Dialog open={!!editingEntry} onOpenChange={(open) => !open && resetEdit()}>
          <DialogContent className="sm:max-w-md">
            <DialogHeader>
              <DialogTitle>Edit Mood Entry</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 pt-4">
              <div className="flex flex-wrap justify-center gap-2">
                {moodOptions.map((option) => (
                  <button
                    key={option.value}
                    onClick={() => setSelectedMood(option.value)}
                    className={cn(
                      "flex flex-col items-center gap-1.5 p-2 sm:p-3 rounded-lg transition-smooth border-2",
                      selectedMood === option.value
                        ? "border-primary bg-accent"
                        : "border-transparent hover:bg-muted"
                    )}
                  >
                    <span className="text-2xl">{option.emoji}</span>
                    <span className="text-xs text-muted-foreground">{option.label}</span>
                  </button>
                ))}
              </div>
              <Textarea
                placeholder="Add a note..."
                value={note}
                onChange={(e) => setNote(e.target.value)}
                className="resize-none"
                rows={2}
              />
              <div className="flex gap-2">
                <Button
                  onClick={updateEntry}
                  className="flex-1"
                  disabled={selectedMood === null || upsertMutation.isPending}
                >
                  {upsertMutation.isPending ? (
                    <Loader2 className="w-4 h-4 animate-spin" />
                  ) : (
                    "Save Changes"
                  )}
                </Button>
                <Button variant="outline" onClick={resetEdit}>Cancel</Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>

        {/* History */}
        <div className="bg-card rounded-lg border border-border shadow-soft">
          <div className="p-4 border-b border-border">
            <h3 className="text-sm font-semibold text-foreground">Mood History</h3>
          </div>
          {isLoading ? (
            <div className="p-12 text-center">
              <Loader2 className="w-6 h-6 text-muted-foreground animate-spin mx-auto mb-3" />
              <p className="text-muted-foreground">Loading mood history…</p>
            </div>
          ) : isError ? (
            <div className="p-12 text-center">
              <div className="w-12 h-12 rounded-full bg-destructive/10 flex items-center justify-center mx-auto mb-3">
                <AlertCircle className="w-6 h-6 text-destructive" />
              </div>
              <p className="text-muted-foreground">Couldn't load your mood history</p>
              <Button variant="outline" className="mt-4" onClick={() => refetch()}>
                Try again
              </Button>
            </div>
          ) : entries.length === 0 ? (
            <div className="p-12 text-center">
              <p className="text-muted-foreground">No entries yet</p>
            </div>
          ) : (
            <div className="divide-y divide-border">
              {entries.map((entry) => (
                <div key={entry.id} className="flex items-start sm:items-center gap-4 p-4 hover:bg-muted/30 transition-smooth group">
                  <div className={cn(
                    "w-10 h-10 rounded-lg flex items-center justify-center border",
                    moodOptions.find(m => m.value === entry.mood)?.color
                  )}>
                    <span className="text-xl">{emojiFor(entry.mood)}</span>
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-foreground">
                      {moodOptions.find(m => m.value === entry.mood)?.label}
                    </p>
                    {entry.note && (
                      <p className="text-xs text-muted-foreground truncate">{entry.note}</p>
                    )}
                  </div>
                  <span className="text-xs text-muted-foreground whitespace-nowrap">
                    {parseLocalDate(entry.date).toLocaleDateString("en-US", { month: "short", day: "numeric" })}
                  </span>
                  <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-smooth">
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 text-muted-foreground hover:text-foreground"
                      onClick={() => startEdit(entry)}
                    >
                      <Pencil className="w-4 h-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 text-muted-foreground hover:text-destructive"
                      onClick={() => deleteMutation.mutate(entry.date)}
                      disabled={deleteMutation.isPending && deleteMutation.variables === entry.date}
                    >
                      {deleteMutation.isPending && deleteMutation.variables === entry.date ? (
                        <Loader2 className="w-4 h-4 animate-spin" />
                      ) : (
                        <Trash2 className="w-4 h-4" />
                      )}
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
