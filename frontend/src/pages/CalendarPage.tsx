import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  addDays,
  addMonths,
  eachDayOfInterval,
  endOfMonth,
  endOfWeek,
  startOfMonth,
  startOfWeek,
  subMonths,
} from "date-fns";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  ChevronLeft,
  ChevronRight,
  Plus,
  Pencil,
  Trash2,
  Loader2,
  AlertCircle,
  Cake,
  Heart,
  Bell,
  Star,
  CalendarDays,
  Clock,
  CheckCircle2,
  Circle,
  CalendarPlus,
} from "lucide-react";
import {
  createEvent,
  deleteEvent,
  getCalendarMonth,
  listEvents,
  updateEvent,
  type EventKind,
  type EventResponse,
} from "@/api/calendar.api";

// Uses local date components (not toISOString, which is UTC) so calendar
// day keys match the user's wall-clock date regardless of timezone offset.
// Mirrors the equivalent helper in Tasks.tsx.
function toLocalDateString(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

// Parses a plain "YYYY-MM-DD" string (as returned by the backend) into a
// local Date at midnight. Never use `new Date("YYYY-MM-DD")` directly - that
// parses as UTC midnight and can shift the displayed day in negative-offset
// timezones.
function parseLocalDateString(value: string): Date {
  const [year, month, day] = value.split("-").map(Number);
  return new Date(year, (month ?? 1) - 1, day ?? 1);
}

function toMonthString(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

function formatMonthLabel(date: Date): string {
  return date.toLocaleDateString("en-US", { month: "long", year: "numeric" });
}

function formatDayLabel(dateStr: string): string {
  return parseLocalDateString(dateStr).toLocaleDateString("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
    year: "numeric",
  });
}

function formatShortDate(dateStr: string): string {
  return parseLocalDateString(dateStr).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });
}

const WEEKDAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

const KIND_META: Record<
  EventKind,
  { label: string; dot: string; text: string; icon: typeof CalendarDays }
> = {
  event: { label: "Event", dot: "bg-primary", text: "text-primary", icon: CalendarDays },
  birthday: { label: "Birthday", dot: "bg-pink-500", text: "text-pink-500", icon: Cake },
  anniversary: { label: "Anniversary", dot: "bg-purple-500", text: "text-purple-500", icon: Heart },
  reminder: { label: "Reminder", dot: "bg-amber-500", text: "text-amber-500", icon: Bell },
  important_date: { label: "Important date", dot: "bg-teal-500", text: "text-teal-500", icon: Star },
};

const EVENT_KIND_OPTIONS: EventKind[] = [
  "event",
  "birthday",
  "anniversary",
  "reminder",
  "important_date",
];

// Human phrasing for the backend's `years_since` field, which is only
// populated for birthday/anniversary occurrences (see
// backend/app/calendar_events/service.py::RECUR_YEARS_SINCE_KINDS).
function yearsSincePhrase(kind: EventKind, yearsSince: number | null): string | null {
  if (yearsSince === null || yearsSince === undefined) return null;
  if (kind === "birthday") return `Turns ${yearsSince}`;
  if (kind === "anniversary") return `${yearsSince} ${yearsSince === 1 ? "year" : "years"}`;
  return `${yearsSince} ${yearsSince === 1 ? "year" : "years"} since`;
}

interface EventFormState {
  title: string;
  date: string;
  time: string;
  kind: EventKind;
  recur_yearly: boolean;
  note: string;
}

function emptyForm(date: string): EventFormState {
  return { title: "", date, time: "", kind: "event", recur_yearly: false, note: "" };
}

export default function CalendarPage() {
  const queryClient = useQueryClient();

  const today = useMemo(() => new Date(), []);
  const todayKey = toLocalDateString(today);

  const [monthCursor, setMonthCursor] = useState<Date>(
    () => new Date(today.getFullYear(), today.getMonth(), 1)
  );
  const monthKey = toMonthString(monthCursor);

  const [selectedDay, setSelectedDay] = useState<string | null>(null);
  const [isFormOpen, setIsFormOpen] = useState(false);
  const [editingEvent, setEditingEvent] = useState<EventResponse | null>(null);
  const [formData, setFormData] = useState<EventFormState>(emptyForm(todayKey));

  const {
    data: calendarData,
    isLoading: isCalendarLoading,
    isError: isCalendarError,
    error: calendarError,
  } = useQuery({
    queryKey: ["calendar", monthKey],
    queryFn: () => getCalendarMonth(monthKey),
  });

  const upcomingRange = useMemo(() => {
    const end = addDays(today, 29);
    return { start: todayKey, end: toLocalDateString(end) };
  }, [today, todayKey]);

  const { data: upcomingEvents, isLoading: isUpcomingLoading } = useQuery({
    queryKey: ["events", "upcoming", upcomingRange.start, upcomingRange.end],
    queryFn: () => listEvents(upcomingRange.start, upcomingRange.end),
  });

  const invalidateAll = () => {
    queryClient.invalidateQueries({ queryKey: ["calendar"] });
    queryClient.invalidateQueries({ queryKey: ["events"] });
  };

  const createMutation = useMutation({
    mutationFn: createEvent,
    onSuccess: invalidateAll,
  });

  const updateMutation = useMutation({
    mutationFn: (vars: { id: number; payload: Parameters<typeof updateEvent>[1] }) =>
      updateEvent(vars.id, vars.payload),
    onSuccess: invalidateAll,
  });

  const deleteMutation = useMutation({
    mutationFn: (id: number) => deleteEvent(id),
    onSuccess: invalidateAll,
  });

  // Grid of days: full weeks spanning the month, so the layout is always a
  // clean set of 7-day rows (matches the shadcn calendar's outside-days
  // convention).
  const gridDays = useMemo(() => {
    const start = startOfWeek(startOfMonth(monthCursor));
    const end = endOfWeek(endOfMonth(monthCursor));
    return eachDayOfInterval({ start, end });
  }, [monthCursor]);

  const goToMonth = (offset: number) => {
    setMonthCursor((prev) => (offset > 0 ? addMonths(prev, 1) : subMonths(prev, 1)));
  };

  const goToToday = () => {
    setMonthCursor(new Date(today.getFullYear(), today.getMonth(), 1));
  };

  const selectDay = (date: Date) => {
    const key = toLocalDateString(date);
    const dayMonthKey = toMonthString(date);
    if (dayMonthKey !== monthKey) {
      setMonthCursor(new Date(date.getFullYear(), date.getMonth(), 1));
    }
    setSelectedDay(key);
  };

  const closeSheet = () => setSelectedDay(null);

  const resetForm = (date?: string) => {
    setFormData(emptyForm(date ?? selectedDay ?? todayKey));
    setEditingEvent(null);
  };

  const openAddDialog = (date?: string) => {
    resetForm(date);
    setIsFormOpen(true);
  };

  const openEditDialog = (event: EventResponse) => {
    setEditingEvent(event);
    setFormData({
      title: event.title,
      // Edit the anchor date, not `occurs_on` - for a yearly-recurring
      // event occurs_on may be a future/computed occurrence, while `date`
      // is the actual row the PATCH updates.
      date: event.date,
      time: event.time ?? "",
      kind: event.kind,
      recur_yearly: event.recur_yearly,
      note: event.note ?? "",
    });
    setIsFormOpen(true);
  };

  const closeForm = () => {
    setIsFormOpen(false);
    resetForm();
  };

  const submitForm = () => {
    if (!formData.title.trim() || !formData.date) return;

    const payload = {
      title: formData.title.trim(),
      date: formData.date,
      time: formData.time || undefined,
      kind: formData.kind,
      note: formData.note.trim() || undefined,
      recur_yearly: formData.recur_yearly,
    };

    if (editingEvent) {
      updateMutation.mutate({ id: editingEvent.id, payload });
    } else {
      createMutation.mutate(payload);
    }
    closeForm();
  };

  const handleDelete = (id: number) => {
    deleteMutation.mutate(id);
  };

  const dayMap = calendarData?.days ?? {};
  const selectedDayData = selectedDay ? dayMap[selectedDay] : undefined;
  const isSheetOpen = selectedDay !== null;

  const sortedUpcoming = useMemo(() => {
    return [...(upcomingEvents ?? [])].sort((a, b) => (a.occurs_on < b.occurs_on ? -1 : 1));
  }, [upcomingEvents]);

  return (
    <AppLayout title="Calendar" subtitle="Events, birthdays, reminders and important dates">
      <div className="w-full max-w-6xl mx-auto space-y-6">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Month grid */}
          <div className="lg:col-span-2 bg-card rounded-lg border border-border shadow-soft p-4">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-2">
                <Button variant="outline" size="icon" className="h-8 w-8" onClick={() => goToMonth(-1)}>
                  <ChevronLeft className="w-4 h-4" />
                </Button>
                <Button variant="outline" size="icon" className="h-8 w-8" onClick={() => goToMonth(1)}>
                  <ChevronRight className="w-4 h-4" />
                </Button>
                <Button variant="ghost" size="sm" onClick={goToToday}>
                  Today
                </Button>
              </div>
              <h2 className="text-base sm:text-lg font-semibold text-foreground">
                {formatMonthLabel(monthCursor)}
              </h2>
              <Button className="gap-2" size="sm" onClick={() => openAddDialog(todayKey)}>
                <Plus className="w-4 h-4" />
                <span className="hidden sm:inline">Add Event</span>
              </Button>
            </div>

            {isCalendarLoading ? (
              <div className="p-12 text-center">
                <Loader2 className="w-6 h-6 animate-spin mx-auto mb-3 text-muted-foreground" />
                <p className="text-muted-foreground">Loading calendar...</p>
              </div>
            ) : isCalendarError ? (
              <div className="p-12 text-center">
                <div className="w-12 h-12 rounded-full bg-destructive/10 flex items-center justify-center mx-auto mb-3">
                  <AlertCircle className="w-6 h-6 text-destructive" />
                </div>
                <p className="text-destructive font-medium">Failed to load calendar</p>
                <p className="text-sm text-muted-foreground mt-1">
                  {calendarError instanceof Error ? calendarError.message : "Please try again."}
                </p>
              </div>
            ) : (
              <>
                <div className="grid grid-cols-7 gap-1 mb-1">
                  {WEEKDAY_LABELS.map((label) => (
                    <div
                      key={label}
                      className="flex items-center justify-center h-8 text-xs font-medium text-muted-foreground"
                    >
                      {label}
                    </div>
                  ))}
                </div>
                <div className="grid grid-cols-7 gap-1">
                  {gridDays.map((date) => {
                    const key = toLocalDateString(date);
                    const inMonth = toMonthString(date) === monthKey;
                    const isToday = key === todayKey;
                    const dayData = dayMap[key];
                    const events = dayData?.events ?? [];
                    const tasks = dayData?.tasks_due ?? [];
                    const visibleEvents = events.slice(0, 3);
                    const overflow = events.length - visibleEvents.length;

                    return (
                      <button
                        key={key}
                        onClick={() => selectDay(date)}
                        className={cn(
                          "min-h-[4.5rem] sm:min-h-[5.5rem] rounded-lg border border-transparent p-1.5 text-left transition-smooth hover:border-border hover:bg-muted/40 flex flex-col gap-1",
                          !inMonth && "opacity-40",
                          isToday && "border-primary/60 bg-primary/5"
                        )}
                      >
                        <span
                          className={cn(
                            "text-xs font-medium inline-flex items-center justify-center w-5 h-5 rounded-full",
                            isToday
                              ? "bg-primary text-primary-foreground"
                              : "text-foreground"
                          )}
                        >
                          {date.getDate()}
                        </span>
                        <div className="flex flex-wrap gap-0.5">
                          {visibleEvents.map((ev) => (
                            <span
                              key={ev.id}
                              title={ev.title}
                              className={cn("w-1.5 h-1.5 rounded-full", KIND_META[ev.kind]?.dot ?? "bg-primary")}
                            />
                          ))}
                          {overflow > 0 && (
                            <span className="text-[10px] leading-none text-muted-foreground">
                              +{overflow}
                            </span>
                          )}
                        </div>
                        {tasks.length > 0 && (
                          <span className="text-[10px] leading-none text-muted-foreground inline-flex items-center gap-0.5 mt-auto">
                            <CheckCircle2 className="w-2.5 h-2.5" />
                            {tasks.length}
                          </span>
                        )}
                      </button>
                    );
                  })}
                </div>
              </>
            )}
          </div>

          {/* Upcoming list */}
          <div className="bg-card rounded-lg border border-border shadow-soft p-4 flex flex-col">
            <h3 className="text-sm font-semibold text-foreground mb-3">Next 30 Days</h3>
            {isUpcomingLoading ? (
              <div className="p-6 text-center">
                <Loader2 className="w-5 h-5 animate-spin mx-auto text-muted-foreground" />
              </div>
            ) : sortedUpcoming.length === 0 ? (
              <p className="text-sm text-muted-foreground py-6 text-center">
                Nothing coming up. Add an event to get started.
              </p>
            ) : (
              <div className="space-y-1 overflow-y-auto max-h-[26rem] pr-1">
                {sortedUpcoming.map((ev) => {
                  const meta = KIND_META[ev.kind] ?? KIND_META.event;
                  const Icon = meta.icon;
                  const phrase = yearsSincePhrase(ev.kind, ev.years_since);
                  return (
                    <div
                      key={`${ev.id}-${ev.occurs_on}`}
                      className="flex items-start gap-2 p-2 rounded-md hover:bg-muted/30 transition-smooth group"
                    >
                      <Icon className={cn("w-4 h-4 mt-0.5 flex-shrink-0", meta.text)} />
                      <div className="flex-1 min-w-0">
                        <p className="text-sm text-foreground truncate">{ev.title}</p>
                        <p className="text-xs text-muted-foreground">
                          {formatShortDate(ev.occurs_on)}
                          {ev.time ? ` · ${ev.time}` : ""}
                          {phrase ? ` · ${phrase}` : ""}
                        </p>
                      </div>
                      <div className="flex gap-0.5 opacity-0 group-hover:opacity-100 transition-smooth">
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7 text-muted-foreground hover:text-foreground"
                          onClick={() => openEditDialog(ev)}
                        >
                          <Pencil className="w-3.5 h-3.5" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7 text-muted-foreground hover:text-destructive"
                          onClick={() => handleDelete(ev.id)}
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </Button>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Day detail side panel */}
      <Sheet open={isSheetOpen} onOpenChange={(open) => !open && closeSheet()}>
        <SheetContent side="right" className="w-full sm:max-w-md overflow-y-auto">
          <SheetHeader>
            <SheetTitle>{selectedDay ? formatDayLabel(selectedDay) : ""}</SheetTitle>
          </SheetHeader>

          <div className="mt-4 space-y-6">
            <Button
              className="w-full gap-2"
              variant="outline"
              onClick={() => selectedDay && openAddDialog(selectedDay)}
            >
              <CalendarPlus className="w-4 h-4" />
              Add event for this day
            </Button>

            <div>
              <h4 className="text-sm font-semibold text-foreground mb-2">Events</h4>
              {!selectedDayData || selectedDayData.events.length === 0 ? (
                <p className="text-sm text-muted-foreground">No events on this day.</p>
              ) : (
                <div className="space-y-2">
                  {selectedDayData.events.map((ev) => {
                    const meta = KIND_META[ev.kind] ?? KIND_META.event;
                    const Icon = meta.icon;
                    const phrase = yearsSincePhrase(ev.kind, ev.years_since);
                    return (
                      <div
                        key={ev.id}
                        className="flex items-start gap-2 p-2.5 rounded-md border border-border"
                      >
                        <Icon className={cn("w-4 h-4 mt-0.5 flex-shrink-0", meta.text)} />
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium text-foreground">{ev.title}</p>
                          <p className="text-xs text-muted-foreground flex items-center gap-1 flex-wrap">
                            <span>{meta.label}</span>
                            {ev.time && (
                              <span className="inline-flex items-center gap-0.5">
                                <Clock className="w-3 h-3" />
                                {ev.time}
                              </span>
                            )}
                            {phrase && <span className="font-medium text-foreground/80">{phrase}</span>}
                            {ev.recur_yearly && <span>· repeats yearly</span>}
                          </p>
                          {ev.note && (
                            <p className="text-xs text-muted-foreground mt-1">{ev.note}</p>
                          )}
                        </div>
                        <div className="flex gap-0.5">
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7 text-muted-foreground hover:text-foreground"
                            onClick={() => openEditDialog(ev)}
                          >
                            <Pencil className="w-3.5 h-3.5" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7 text-muted-foreground hover:text-destructive"
                            onClick={() => handleDelete(ev.id)}
                          >
                            <Trash2 className="w-3.5 h-3.5" />
                          </Button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>

            <div>
              <h4 className="text-sm font-semibold text-foreground mb-2">Tasks Due</h4>
              {!selectedDayData || selectedDayData.tasks_due.length === 0 ? (
                <p className="text-sm text-muted-foreground">No tasks due on this day.</p>
              ) : (
                <div className="space-y-2">
                  {selectedDayData.tasks_due.map((task) => (
                    <div
                      key={task.id}
                      className="flex items-center gap-2 p-2.5 rounded-md border border-border"
                    >
                      {task.completed ? (
                        <CheckCircle2 className="w-4 h-4 text-success flex-shrink-0" />
                      ) : (
                        <Circle className="w-4 h-4 text-muted-foreground flex-shrink-0" />
                      )}
                      <span
                        className={cn(
                          "text-sm flex-1 min-w-0 truncate",
                          task.completed ? "text-muted-foreground line-through" : "text-foreground"
                        )}
                      >
                        {task.title}
                      </span>
                      <span className="text-xs text-muted-foreground capitalize">{task.priority}</span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </SheetContent>
      </Sheet>

      {/* Add / Edit event dialog */}
      <Dialog open={isFormOpen} onOpenChange={(open) => !open && closeForm()}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{editingEvent ? "Edit Event" : "Add Event"}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 pt-2">
            <div>
              <Label className="text-sm font-medium text-foreground mb-1.5 block">Title</Label>
              <Input
                placeholder="What's the occasion?"
                value={formData.title}
                onChange={(e) => setFormData({ ...formData, title: e.target.value })}
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <Label className="text-sm font-medium text-foreground mb-1.5 block">Date</Label>
                <Input
                  type="date"
                  value={formData.date}
                  onChange={(e) => setFormData({ ...formData, date: e.target.value })}
                />
              </div>
              <div>
                <Label className="text-sm font-medium text-foreground mb-1.5 block">Time (optional)</Label>
                <Input
                  type="time"
                  value={formData.time}
                  onChange={(e) => setFormData({ ...formData, time: e.target.value })}
                />
              </div>
            </div>

            <div>
              <Label className="text-sm font-medium text-foreground mb-1.5 block">Kind</Label>
              <Select
                value={formData.kind}
                onValueChange={(v) => setFormData({ ...formData, kind: v as EventKind })}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {EVENT_KIND_OPTIONS.map((k) => (
                    <SelectItem key={k} value={k}>
                      {KIND_META[k].label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="flex items-center justify-between rounded-md border border-border p-3">
              <div>
                <Label className="text-sm font-medium text-foreground">Repeats yearly</Label>
                <p className="text-xs text-muted-foreground">
                  Recurs every year on this month and day (e.g. birthdays).
                </p>
              </div>
              <Switch
                checked={formData.recur_yearly}
                onCheckedChange={(checked) => setFormData({ ...formData, recur_yearly: checked })}
              />
            </div>

            <div>
              <Label className="text-sm font-medium text-foreground mb-1.5 block">Note (optional)</Label>
              <Textarea
                placeholder="Any extra details..."
                value={formData.note}
                onChange={(e) => setFormData({ ...formData, note: e.target.value })}
              />
            </div>

            <div className="flex gap-2 pt-2">
              <Button
                onClick={submitForm}
                className="flex-1"
                disabled={createMutation.isPending || updateMutation.isPending}
              >
                {createMutation.isPending || updateMutation.isPending
                  ? "Saving..."
                  : editingEvent
                  ? "Save Changes"
                  : "Add Event"}
              </Button>
              <Button variant="outline" onClick={closeForm}>
                Cancel
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </AppLayout>
  );
}
