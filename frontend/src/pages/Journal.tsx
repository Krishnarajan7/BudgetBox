import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  ChevronLeft,
  ChevronRight,
  Pin,
  Pencil,
  Trash2,
  Plus,
  Search,
  BookOpen,
  Wallet,
  CheckSquare,
  Flame,
  Loader2,
} from "lucide-react";
import { cn } from "@/lib/utils";
import {
  createNote,
  deleteJournalEntry,
  deleteNote,
  getJournalDay,
  listJournalEntries,
  listNotes,
  updateNote,
  upsertJournalEntry,
  type Note,
} from "@/api/journal.api";

// Uses local date components (not toISOString, which is UTC) so "today"
// matches the user's wall-clock date regardless of timezone offset.
function toLocalDateKey(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function parseLocalDateKey(dateKey: string): Date {
  const [year, month, day] = dateKey.split("-").map(Number);
  return new Date(year, month - 1, day);
}

function formatFriendlyDate(dateKey: string): string {
  return parseLocalDateKey(dateKey).toLocaleDateString("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
    year: "numeric",
  });
}

function formatShortDate(dateKey: string): string {
  return parseLocalDateKey(dateKey).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });
}

function formatTimestamp(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

function formatCurrency(amount: number): string {
  return amount.toLocaleString(undefined, {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 2,
  });
}

function addDays(dateKey: string, delta: number): string {
  const d = parseLocalDateKey(dateKey);
  d.setDate(d.getDate() + delta);
  return toLocalDateKey(d);
}

export default function Journal() {
  const queryClient = useQueryClient();
  const today = useMemo(() => toLocalDateKey(new Date()), []);

  const [activeTab, setActiveTab] = useState<"day" | "notes">("day");

  // ---------------------------------------------------------------------
  // My Day tab state
  // ---------------------------------------------------------------------
  const [selectedDate, setSelectedDate] = useState(today);
  const [bodyDraft, setBodyDraft] = useState("");
  const [moodNoteDraft, setMoodNoteDraft] = useState("");
  const [draftInitializedFor, setDraftInitializedFor] = useState<string | null>(null);

  const dayQuery = useQuery({
    queryKey: ["journal", "day", selectedDate],
    queryFn: () => getJournalDay(selectedDate),
  });

  // Initialize the editable draft from the fetched entry exactly once per
  // date change, so the Save button reflects genuine local edits ("dirty")
  // rather than re-syncing on every refetch.
  if (dayQuery.data && draftInitializedFor !== selectedDate) {
    setBodyDraft(dayQuery.data.entry?.body ?? "");
    setMoodNoteDraft(dayQuery.data.entry?.mood_note ?? "");
    setDraftInitializedFor(selectedDate);
  }

  const startOfRange = useMemo(() => addDays(today, -30), [today]);
  const recentEntriesQuery = useQuery({
    queryKey: ["journal", "entries", startOfRange, today],
    queryFn: () => listJournalEntries({ start_date: startOfRange, end_date: today }),
  });

  const saveEntryMutation = useMutation({
    mutationFn: () =>
      upsertJournalEntry(selectedDate, {
        body: bodyDraft,
        mood_note: moodNoteDraft.trim() ? moodNoteDraft : undefined,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["journal", "day", selectedDate] });
      queryClient.invalidateQueries({ queryKey: ["journal", "entries"] });
    },
  });

  const entry = dayQuery.data?.entry ?? null;
  const isDirty =
    bodyDraft !== (entry?.body ?? "") || moodNoteDraft !== (entry?.mood_note ?? "");

  const goToDate = (dateKey: string) => {
    setSelectedDate(dateKey);
    setDraftInitializedFor(null);
  };

  const hasAnyHistory =
    (recentEntriesQuery.data?.length ?? 0) > 0 || !!entry;

  // ---------------------------------------------------------------------
  // Notes tab state
  // ---------------------------------------------------------------------
  const [search, setSearch] = useState("");
  const [pinnedOnly, setPinnedOnly] = useState(false);
  const [isNoteDialogOpen, setIsNoteDialogOpen] = useState(false);
  const [editingNote, setEditingNote] = useState<Note | null>(null);
  const [noteForm, setNoteForm] = useState({ title: "", body: "", pinned: false });
  const [pendingDeleteId, setPendingDeleteId] = useState<number | null>(null);

  const notesQuery = useQuery({
    queryKey: ["notes", search, pinnedOnly],
    queryFn: () =>
      listNotes({
        q: search.trim() ? search.trim() : undefined,
        pinned: pinnedOnly ? true : undefined,
      }),
  });

  const invalidateNotes = () =>
    queryClient.invalidateQueries({ queryKey: ["notes"] });

  const createNoteMutation = useMutation({
    mutationFn: createNote,
    onSuccess: () => {
      invalidateNotes();
      setIsNoteDialogOpen(false);
    },
  });

  const updateNoteMutation = useMutation({
    mutationFn: (vars: { id: number; patch: { title: string; body: string; pinned: boolean } }) =>
      updateNote(vars.id, vars.patch),
    onSuccess: () => {
      invalidateNotes();
      setIsNoteDialogOpen(false);
    },
  });

  const deleteNoteMutation = useMutation({
    mutationFn: (id: number) => deleteNote(id),
    onSuccess: () => {
      invalidateNotes();
      setPendingDeleteId(null);
    },
  });

  const openNewNote = () => {
    setEditingNote(null);
    setNoteForm({ title: "", body: "", pinned: false });
    setIsNoteDialogOpen(true);
  };

  const openEditNote = (note: Note) => {
    setEditingNote(note);
    setNoteForm({ title: note.title, body: note.body, pinned: note.pinned });
    setIsNoteDialogOpen(true);
  };

  const saveNote = () => {
    if (!noteForm.title.trim() || !noteForm.body.trim()) return;
    if (editingNote) {
      updateNoteMutation.mutate({ id: editingNote.id, patch: noteForm });
    } else {
      createNoteMutation.mutate(noteForm);
    }
  };

  const notes = notesQuery.data ?? [];
  const pinnedNotes = notes.filter((n) => n.pinned);
  const otherNotes = notes.filter((n) => !n.pinned);
  const isSearching = search.trim().length > 0 || pinnedOnly;
  const isSavingNote = createNoteMutation.isPending || updateNoteMutation.isPending;

  return (
    <AppLayout title="Journal" subtitle="Your day, notes, and history in one place">
      <div className="w-full max-w-5xl mx-auto space-y-6">
        <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as "day" | "notes")}>
          <TabsList>
            <TabsTrigger value="day" className="gap-1.5">
              <BookOpen className="w-4 h-4" />
              My Day
            </TabsTrigger>
            <TabsTrigger value="notes" className="gap-1.5">
              <Pencil className="w-4 h-4" />
              Notes
            </TabsTrigger>
          </TabsList>

          {/* ------------------------------------------------------------ */}
          {/* My Day                                                       */}
          {/* ------------------------------------------------------------ */}
          <TabsContent value="day" className="space-y-6 mt-4">
            <div className="flex items-center justify-between gap-3 bg-card rounded-lg border border-border shadow-soft p-3">
              <Button
                variant="ghost"
                size="icon"
                onClick={() => goToDate(addDays(selectedDate, -1))}
                aria-label="Previous day"
              >
                <ChevronLeft className="w-4 h-4" />
              </Button>
              <div className="flex flex-col items-center">
                <Input
                  type="date"
                  value={selectedDate}
                  onChange={(e) => e.target.value && goToDate(e.target.value)}
                  className="w-auto text-center border-none shadow-none font-medium"
                />
                {selectedDate === today && (
                  <span className="text-xs text-primary font-medium">Today</span>
                )}
              </div>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => goToDate(addDays(selectedDate, 1))}
                aria-label="Next day"
              >
                <ChevronRight className="w-4 h-4" />
              </Button>
            </div>

            {!hasAnyHistory && !dayQuery.isLoading && !recentEntriesQuery.isLoading ? (
              <div className="bg-card rounded-lg border border-border shadow-soft p-12 text-center">
                <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto mb-3">
                  <BookOpen className="w-6 h-6 text-muted-foreground" />
                </div>
                <p className="text-foreground font-medium">Write your first entry</p>
                <p className="text-sm text-muted-foreground mt-1">
                  Use the editor below to capture what happened today — it'll show up here alongside your transactions, tasks, and habits.
                </p>
              </div>
            ) : null}

            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
              <div className="lg:col-span-2 space-y-6">
                {/* Editor */}
                <div className="bg-card rounded-lg border border-border shadow-soft p-4 space-y-3">
                  <div className="flex items-center justify-between">
                    <h3 className="text-sm font-semibold text-foreground">
                      Journal entry for {formatFriendlyDate(selectedDate)}
                    </h3>
                    {entry && !isDirty && (
                      <span className="text-xs text-muted-foreground">
                        Saved · {formatTimestamp(entry.updated_at)}
                      </span>
                    )}
                  </div>

                  {dayQuery.isLoading ? (
                    <Skeleton className="h-32 w-full" />
                  ) : (
                    <Textarea
                      placeholder="What happened today?"
                      value={bodyDraft}
                      onChange={(e) => setBodyDraft(e.target.value)}
                      rows={6}
                      className="resize-none"
                    />
                  )}

                  <div>
                    <label className="text-xs font-medium text-muted-foreground mb-1 block">
                      Mood note (optional)
                    </label>
                    <Input
                      placeholder="A quick note on how you felt..."
                      value={moodNoteDraft}
                      onChange={(e) => setMoodNoteDraft(e.target.value)}
                    />
                  </div>

                  <div className="flex items-center gap-3">
                    <Button
                      onClick={() => saveEntryMutation.mutate()}
                      disabled={!isDirty || saveEntryMutation.isPending}
                    >
                      {saveEntryMutation.isPending ? "Saving..." : "Save"}
                    </Button>
                    {!isDirty && entry && (
                      <span className="text-xs text-muted-foreground">No unsaved changes</span>
                    )}
                  </div>
                </div>

                {/* Connected panels */}
                <div className="space-y-3">
                  <h3 className="text-sm font-semibold text-foreground">
                    What happened on {formatFriendlyDate(selectedDate)}
                  </h3>

                  {dayQuery.isLoading ? (
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                      <Skeleton className="h-32 w-full" />
                      <Skeleton className="h-32 w-full" />
                      <Skeleton className="h-32 w-full" />
                    </div>
                  ) : (
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                      {/* Money that day */}
                      <div className="bg-card rounded-lg border border-border shadow-soft p-4">
                        <div className="flex items-center gap-2 mb-3">
                          <Wallet className="w-4 h-4 text-muted-foreground" />
                          <h4 className="text-xs font-semibold text-foreground">Money that day</h4>
                        </div>
                        {(dayQuery.data?.transactions?.length ?? 0) === 0 ? (
                          <p className="text-xs text-muted-foreground">No transactions logged</p>
                        ) : (
                          <ul className="space-y-2">
                            {dayQuery.data!.transactions.map((tx) => (
                              <li key={tx.id} className="text-xs">
                                <div className="flex items-center justify-between gap-2">
                                  <span
                                    className={cn(
                                      "font-medium",
                                      tx.type === "income" ? "text-success" : "text-destructive"
                                    )}
                                  >
                                    {tx.type === "income" ? "+" : "-"}
                                    {formatCurrency(tx.amount)}
                                  </span>
                                </div>
                                {tx.note && (
                                  <p className="text-muted-foreground truncate">{tx.note}</p>
                                )}
                              </li>
                            ))}
                          </ul>
                        )}
                      </div>

                      {/* Tasks completed */}
                      <div className="bg-card rounded-lg border border-border shadow-soft p-4">
                        <div className="flex items-center gap-2 mb-3">
                          <CheckSquare className="w-4 h-4 text-muted-foreground" />
                          <h4 className="text-xs font-semibold text-foreground">Tasks completed</h4>
                        </div>
                        {(dayQuery.data?.tasks_completed?.length ?? 0) === 0 ? (
                          <p className="text-xs text-muted-foreground">No tasks completed</p>
                        ) : (
                          <ul className="space-y-1.5">
                            {dayQuery.data!.tasks_completed.map((t) => (
                              <li key={t.id} className="text-xs text-foreground">
                                {t.title}
                              </li>
                            ))}
                          </ul>
                        )}
                      </div>

                      {/* Habits completed */}
                      <div className="bg-card rounded-lg border border-border shadow-soft p-4">
                        <div className="flex items-center gap-2 mb-3">
                          <Flame className="w-4 h-4 text-muted-foreground" />
                          <h4 className="text-xs font-semibold text-foreground">Habits completed</h4>
                        </div>
                        {(dayQuery.data?.habits_completed?.length ?? 0) === 0 ? (
                          <p className="text-xs text-muted-foreground">No habits completed</p>
                        ) : (
                          <ul className="space-y-1.5">
                            {dayQuery.data!.habits_completed.map((h) => (
                              <li key={h.id} className="text-xs text-foreground">
                                {h.name}
                              </li>
                            ))}
                          </ul>
                        )}
                      </div>
                    </div>
                  )}
                </div>
              </div>

              {/* Recent entries */}
              <div className="bg-card rounded-lg border border-border shadow-soft">
                <div className="p-4 border-b border-border">
                  <h3 className="text-sm font-semibold text-foreground">Recent entries</h3>
                  <p className="text-xs text-muted-foreground mt-0.5">Last 30 days</p>
                </div>
                {recentEntriesQuery.isLoading ? (
                  <div className="p-4 space-y-2">
                    <Skeleton className="h-10 w-full" />
                    <Skeleton className="h-10 w-full" />
                    <Skeleton className="h-10 w-full" />
                  </div>
                ) : (recentEntriesQuery.data?.length ?? 0) === 0 ? (
                  <div className="p-8 text-center">
                    <p className="text-sm text-muted-foreground">No entries yet</p>
                  </div>
                ) : (
                  <div className="divide-y divide-border max-h-[420px] overflow-auto">
                    {recentEntriesQuery.data!.map((e) => (
                      <button
                        key={e.date}
                        onClick={() => goToDate(e.date)}
                        className={cn(
                          "w-full text-left p-3 hover:bg-muted/30 transition-smooth",
                          e.date === selectedDate && "bg-accent"
                        )}
                      >
                        <div className="flex items-center justify-between gap-2">
                          <span className="text-xs font-medium text-foreground">
                            {formatShortDate(e.date)}
                          </span>
                        </div>
                        <p className="text-xs text-muted-foreground truncate mt-0.5">
                          {e.body || "(empty entry)"}
                        </p>
                      </button>
                    ))}
                  </div>
                )}
              </div>
            </div>
          </TabsContent>

          {/* ------------------------------------------------------------ */}
          {/* Notes                                                        */}
          {/* ------------------------------------------------------------ */}
          <TabsContent value="notes" className="space-y-6 mt-4">
            <div className="flex flex-col sm:flex-row gap-3 sm:items-center sm:justify-between">
              <div className="flex flex-1 items-center gap-2 max-w-sm">
                <div className="relative flex-1">
                  <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
                  <Input
                    placeholder="Search notes..."
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                    className="pl-9"
                  />
                </div>
                <Button
                  variant={pinnedOnly ? "default" : "outline"}
                  size="sm"
                  onClick={() => setPinnedOnly((v) => !v)}
                  className="gap-1.5 whitespace-nowrap"
                >
                  <Pin className="w-3.5 h-3.5" />
                  Pinned
                </Button>
              </div>
              <Button className="gap-2" onClick={openNewNote}>
                <Plus className="w-4 h-4" />
                New Note
              </Button>
            </div>

            {notesQuery.isLoading ? (
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                <Skeleton className="h-40 w-full" />
                <Skeleton className="h-40 w-full" />
                <Skeleton className="h-40 w-full" />
              </div>
            ) : notes.length === 0 ? (
              <div className="bg-card rounded-lg border border-border shadow-soft p-12 text-center">
                <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto mb-3">
                  <Pencil className="w-6 h-6 text-muted-foreground" />
                </div>
                <p className="text-foreground font-medium">
                  {isSearching ? "No notes match your search" : "No notes yet"}
                </p>
                <p className="text-sm text-muted-foreground mt-1">
                  {isSearching
                    ? "Try a different search term or clear the pinned filter."
                    : "Create your first note to get started."}
                </p>
              </div>
            ) : (
              <div className="space-y-6">
                {pinnedNotes.length > 0 && (
                  <div className="space-y-3">
                    <h4 className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">
                      Pinned
                    </h4>
                    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                      {pinnedNotes.map((note) => (
                        <NoteCard
                          key={note.id}
                          note={note}
                          onEdit={() => openEditNote(note)}
                          onDelete={() => setPendingDeleteId(note.id)}
                        />
                      ))}
                    </div>
                  </div>
                )}
                {otherNotes.length > 0 && (
                  <div className="space-y-3">
                    {pinnedNotes.length > 0 && (
                      <h4 className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">
                        All notes
                      </h4>
                    )}
                    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                      {otherNotes.map((note) => (
                        <NoteCard
                          key={note.id}
                          note={note}
                          onEdit={() => openEditNote(note)}
                          onDelete={() => setPendingDeleteId(note.id)}
                        />
                      ))}
                    </div>
                  </div>
                )}
              </div>
            )}
          </TabsContent>
        </Tabs>

        {/* Note add/edit dialog */}
        <Dialog open={isNoteDialogOpen} onOpenChange={setIsNoteDialogOpen}>
          <DialogContent className="sm:max-w-md">
            <DialogHeader>
              <DialogTitle>{editingNote ? "Edit Note" : "New Note"}</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 pt-4">
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Title</label>
                <Input
                  placeholder="Note title"
                  value={noteForm.title}
                  onChange={(e) => setNoteForm({ ...noteForm, title: e.target.value })}
                />
              </div>
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Body</label>
                <Textarea
                  placeholder="Write your note..."
                  value={noteForm.body}
                  onChange={(e) => setNoteForm({ ...noteForm, body: e.target.value })}
                  rows={5}
                  className="resize-none"
                />
              </div>
              <div className="flex items-center justify-between">
                <label className="text-sm font-medium text-foreground">Pin this note</label>
                <Switch
                  checked={noteForm.pinned}
                  onCheckedChange={(checked) => setNoteForm({ ...noteForm, pinned: checked })}
                />
              </div>
              <div className="flex gap-2 pt-2">
                <Button
                  onClick={saveNote}
                  className="flex-1"
                  disabled={isSavingNote || !noteForm.title.trim() || !noteForm.body.trim()}
                >
                  {isSavingNote ? (
                    <Loader2 className="w-4 h-4 animate-spin" />
                  ) : editingNote ? (
                    "Save Changes"
                  ) : (
                    "Add Note"
                  )}
                </Button>
                <Button variant="outline" onClick={() => setIsNoteDialogOpen(false)}>
                  Cancel
                </Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>

        {/* Delete confirmation */}
        <Dialog
          open={pendingDeleteId !== null}
          onOpenChange={(open) => !open && setPendingDeleteId(null)}
        >
          <DialogContent className="sm:max-w-sm">
            <DialogHeader>
              <DialogTitle>Delete this note?</DialogTitle>
            </DialogHeader>
            <p className="text-sm text-muted-foreground">
              This action can't be undone.
            </p>
            <div className="flex gap-2 pt-2">
              <Button
                variant="destructive"
                className="flex-1"
                disabled={deleteNoteMutation.isPending}
                onClick={() => pendingDeleteId !== null && deleteNoteMutation.mutate(pendingDeleteId)}
              >
                {deleteNoteMutation.isPending ? "Deleting..." : "Delete"}
              </Button>
              <Button variant="outline" onClick={() => setPendingDeleteId(null)}>
                Cancel
              </Button>
            </div>
          </DialogContent>
        </Dialog>
      </div>
    </AppLayout>
  );
}

function NoteCard({
  note,
  onEdit,
  onDelete,
}: {
  note: Note;
  onEdit: () => void;
  onDelete: () => void;
}) {
  return (
    <div className="bg-card rounded-lg border border-border shadow-soft p-4 flex flex-col gap-2 group">
      <div className="flex items-start justify-between gap-2">
        <h4 className="text-sm font-semibold text-foreground truncate">{note.title}</h4>
        {note.pinned && <Pin className="w-3.5 h-3.5 text-primary flex-shrink-0" />}
      </div>
      <p className="text-xs text-muted-foreground line-clamp-4 flex-1">{note.body}</p>
      <div className="flex items-center justify-between pt-1">
        <span className="text-[10px] text-muted-foreground">
          {formatTimestamp(note.updated_at)}
        </span>
        <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-smooth">
          <Button variant="ghost" size="icon" className="h-7 w-7 text-muted-foreground hover:text-foreground" onClick={onEdit}>
            <Pencil className="w-3.5 h-3.5" />
          </Button>
          <Button variant="ghost" size="icon" className="h-7 w-7 text-muted-foreground hover:text-destructive" onClick={onDelete}>
            <Trash2 className="w-3.5 h-3.5" />
          </Button>
        </div>
      </div>
    </div>
  );
}
