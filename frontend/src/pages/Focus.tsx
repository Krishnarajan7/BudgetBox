import { useEffect, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { format } from "date-fns";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useToast } from "@/hooks/use-toast";
import { cn } from "@/lib/utils";
import {
  Play,
  Pause,
  RotateCcw,
  Flame,
  Clock,
  CalendarDays,
  Trash2,
  Loader2,
  AlertCircle,
  Coffee,
  Brain,
} from "lucide-react";
import {
  createFocusSession,
  deleteFocusSession,
  getFocusStats,
  listFocusSessions,
  type FocusKind,
} from "@/api/focus.api";

type Phase = FocusKind;
type Status = "idle" | "running" | "paused";
type PresetKey = "25-5" | "50-10" | "custom";

interface Preset {
  key: PresetKey;
  label: string;
  workMin: number;
  breakMin: number;
}

const PRESETS: Preset[] = [
  { key: "25-5", label: "25 / 5", workMin: 25, breakMin: 5 },
  { key: "50-10", label: "50 / 10", workMin: 50, breakMin: 10 },
  { key: "custom", label: "Custom", workMin: 0, breakMin: 0 },
];

const RING_RADIUS = 88;
const RING_CIRCUMFERENCE = 2 * Math.PI * RING_RADIUS;
const DEFAULT_TITLE = typeof document !== "undefined" ? document.title : "BudgetBox";

function formatClock(totalSec: number): string {
  const safe = Math.max(0, totalSec);
  const m = Math.floor(safe / 60);
  const s = safe % 60;
  return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

// Two short sine-wave beeps via the Web Audio API - no asset files needed.
// Failures (e.g. autoplay restrictions) are swallowed since the chime is a
// nice-to-have, not core to logging a session.
function playChime() {
  try {
    const AudioCtxCtor =
      window.AudioContext || (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AudioCtxCtor) return;
    const ctx = new AudioCtxCtor();
    const now = ctx.currentTime;

    [0, 0.22].forEach((offset, i) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = "sine";
      osc.frequency.value = i === 0 ? 880 : 1046.5;
      gain.gain.setValueAtTime(0.0001, now + offset);
      gain.gain.exponentialRampToValueAtTime(0.2, now + offset + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + offset + 0.2);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(now + offset);
      osc.stop(now + offset + 0.25);
    });

    window.setTimeout(() => {
      ctx.close().catch(() => undefined);
    }, 800);
  } catch {
    // Ignore - chime is best-effort.
  }
}

export default function Focus() {
  const { toast } = useToast();
  const queryClient = useQueryClient();

  const [presetKey, setPresetKey] = useState<PresetKey>("25-5");
  const [customWorkMin, setCustomWorkMin] = useState(25);
  const [customBreakMin, setCustomBreakMin] = useState(5);
  const [label, setLabel] = useState("");

  const [phase, setPhase] = useState<Phase>("work");
  const [status, setStatus] = useState<Status>("idle");
  const [remainingSec, setRemainingSec] = useState(25 * 60);
  const [totalSec, setTotalSec] = useState(25 * 60);

  const activePreset = PRESETS.find((p) => p.key === presetKey) ?? PRESETS[0];
  const workMinutes = presetKey === "custom" ? customWorkMin : activePreset.workMin;
  const breakMinutes = presetKey === "custom" ? customBreakMin : activePreset.breakMin;

  // Refs mirror the values the ticking interval needs, so the interval
  // itself never has to be torn down/recreated on every render (label
  // keystrokes, preset switches, etc.) - it just reads the latest ref.
  const phaseRef = useRef<Phase>("work");
  const labelRef = useRef("");
  const settingsRef = useRef({ workMinutes, breakMinutes });
  const endAtRef = useRef<number | null>(null); // epoch ms the running phase ends at
  const remainingMsAtPauseRef = useRef<number>(0);
  const plannedSecRef = useRef(workMinutes * 60);
  const sessionStartRef = useRef<Date | null>(null);
  const tickRef = useRef<number | null>(null);

  useEffect(() => {
    labelRef.current = label;
  }, [label]);

  useEffect(() => {
    settingsRef.current = { workMinutes, breakMinutes };
  }, [workMinutes, breakMinutes]);

  // While idle, keep the display in sync with the selected preset.
  useEffect(() => {
    if (status === "idle") {
      setPhase("work");
      phaseRef.current = "work";
      setRemainingSec(workMinutes * 60);
      setTotalSec(workMinutes * 60);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [workMinutes, status]);

  const statsQuery = useQuery({
    queryKey: ["focus", "stats"],
    queryFn: getFocusStats,
  });

  const sessionsQuery = useQuery({
    queryKey: ["focus", "sessions"],
    queryFn: () => listFocusSessions(),
  });

  const logMutation = useMutation({
    mutationFn: createFocusSession,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["focus", "stats"] });
      queryClient.invalidateQueries({ queryKey: ["focus", "sessions"] });
    },
    onError: () => {
      toast({
        title: "Couldn't save focus session",
        description: "Please try again.",
        variant: "destructive",
      });
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: number) => deleteFocusSession(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["focus", "stats"] });
      queryClient.invalidateQueries({ queryKey: ["focus", "sessions"] });
    },
    onError: () => {
      toast({
        title: "Couldn't delete session",
        description: "Please try again.",
        variant: "destructive",
      });
    },
  });

  function logSession(kind: Phase, durationMin: number, completed: boolean) {
    const startedAt = sessionStartRef.current ?? new Date();
    const roundedDuration = Math.max(1, Math.round(durationMin));
    logMutation.mutate({
      started_at: startedAt.toISOString(),
      duration_min: roundedDuration,
      kind,
      label: kind === "work" && labelRef.current.trim() ? labelRef.current.trim() : null,
      completed,
    });
  }

  function beginPhase(nextPhase: Phase) {
    const minutes = nextPhase === "work" ? settingsRef.current.workMinutes : settingsRef.current.breakMinutes;
    const totalMs = Math.max(1, minutes) * 60 * 1000;

    phaseRef.current = nextPhase;
    plannedSecRef.current = Math.round(totalMs / 1000);
    sessionStartRef.current = new Date();
    endAtRef.current = Date.now() + totalMs;

    setPhase(nextPhase);
    setRemainingSec(Math.round(totalMs / 1000));
    setTotalSec(Math.round(totalMs / 1000));
    setStatus("running");
  }

  function handlePhaseComplete() {
    const finishedPhase = phaseRef.current;
    const plannedMin = plannedSecRef.current / 60;
    logSession(finishedPhase, plannedMin, true);
    playChime();

    if (finishedPhase === "work") {
      // Auto-switch straight into a break.
      beginPhase("break");
    } else {
      // Back to idle, ready for the next work round.
      endAtRef.current = null;
      sessionStartRef.current = null;
      setStatus("idle");
    }
  }

  // The single source of truth for "how much time is left" is an absolute
  // end timestamp, not an accumulating counter - so the countdown stays
  // correct even if the tab is backgrounded/throttled or the laptop sleeps.
  useEffect(() => {
    if (status !== "running") return;

    const id = window.setInterval(() => {
      if (endAtRef.current == null) return;
      const msLeft = endAtRef.current - Date.now();
      const secLeft = Math.max(0, Math.ceil(msLeft / 1000));
      setRemainingSec(secLeft);
      if (msLeft <= 0) {
        handlePhaseComplete();
      }
    }, 250);
    tickRef.current = id;

    return () => window.clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status]);

  // Tab-title countdown.
  useEffect(() => {
    if (status === "running") {
      const phaseLabel = phase === "work" ? "Focus" : "Break";
      document.title = `${formatClock(remainingSec)} - ${phaseLabel} | BudgetBox`;
    } else {
      document.title = DEFAULT_TITLE;
    }
    return () => {
      document.title = DEFAULT_TITLE;
    };
  }, [status, phase, remainingSec]);

  function handleStart() {
    if (status === "paused") {
      const remainingMs = remainingMsAtPauseRef.current;
      endAtRef.current = Date.now() + remainingMs;
      setStatus("running");
      return;
    }
    beginPhase("work");
  }

  function handlePause() {
    if (status !== "running" || endAtRef.current == null) return;
    remainingMsAtPauseRef.current = Math.max(0, endAtRef.current - Date.now());
    endAtRef.current = null;
    setStatus("paused");
  }

  function handleReset() {
    if (status === "idle") return;

    const confirmed = window.confirm(
      "Stop this focus session now? It will be logged as incomplete."
    );
    if (!confirmed) return;

    const elapsedSec = Math.max(0, plannedSecRef.current - remainingSec);
    if (elapsedSec >= 60) {
      logSession(phaseRef.current, elapsedSec / 60, false);
    }

    endAtRef.current = null;
    sessionStartRef.current = null;
    phaseRef.current = "work";
    setPhase("work");
    setStatus("idle");
    setRemainingSec(settingsRef.current.workMinutes * 60);
    setTotalSec(settingsRef.current.workMinutes * 60);
  }

  const progress = totalSec > 0 ? 1 - remainingSec / totalSec : 0;
  const ringOffset = RING_CIRCUMFERENCE * (1 - Math.min(1, Math.max(0, progress)));

  const stats = statsQuery.data;
  const sessions = sessionsQuery.data ?? [];

  return (
    <AppLayout title="Focus" subtitle="Pomodoro sessions to help you stay in flow">
      <div className="w-full max-w-5xl mx-auto space-y-6">
        {/* Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 md:gap-4">
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-1">Focus Today</p>
            <p className="text-2xl font-semibold text-foreground">
              {stats ? `${stats.today_minutes}m` : "--"}
            </p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-1">This Week</p>
            <p className="text-2xl font-semibold text-foreground">
              {stats ? `${stats.week_minutes}m` : "--"}
            </p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-1">Sessions Today</p>
            <p className="text-2xl font-semibold text-foreground">
              {stats ? stats.today_sessions : "--"}
            </p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-1 flex items-center gap-1">
              <Flame className="w-3.5 h-3.5" /> Day Streak
            </p>
            <p className="text-2xl font-semibold text-primary">
              {stats ? stats.current_streak_days : "--"}
            </p>
          </div>
        </div>

        {/* Timer */}
        <div className="bg-card rounded-lg border border-border shadow-soft p-6 flex flex-col items-center">
          {/* Presets */}
          <div className="flex flex-wrap gap-2 justify-center mb-6">
            {PRESETS.map((preset) => (
              <Button
                key={preset.key}
                variant={presetKey === preset.key ? "default" : "outline"}
                size="sm"
                disabled={status !== "idle"}
                onClick={() => setPresetKey(preset.key)}
              >
                {preset.label}
              </Button>
            ))}
          </div>

          {presetKey === "custom" && (
            <div className="flex items-center gap-4 mb-6">
              <div className="flex items-center gap-2">
                <label className="text-xs text-muted-foreground">Work (min)</label>
                <Input
                  type="number"
                  min={1}
                  max={180}
                  value={customWorkMin}
                  disabled={status !== "idle"}
                  onChange={(e) => setCustomWorkMin(Math.max(1, Number(e.target.value) || 1))}
                  className="w-20"
                />
              </div>
              <div className="flex items-center gap-2">
                <label className="text-xs text-muted-foreground">Break (min)</label>
                <Input
                  type="number"
                  min={1}
                  max={60}
                  value={customBreakMin}
                  disabled={status !== "idle"}
                  onChange={(e) => setCustomBreakMin(Math.max(1, Number(e.target.value) || 1))}
                  className="w-20"
                />
              </div>
            </div>
          )}

          {/* Ring */}
          <div className="relative w-56 h-56 flex items-center justify-center">
            <svg viewBox="0 0 200 200" className="w-full h-full -rotate-90">
              <circle
                cx="100"
                cy="100"
                r={RING_RADIUS}
                fill="none"
                strokeWidth="12"
                className="stroke-muted"
              />
              <circle
                cx="100"
                cy="100"
                r={RING_RADIUS}
                fill="none"
                strokeWidth="12"
                strokeLinecap="round"
                strokeDasharray={RING_CIRCUMFERENCE}
                strokeDashoffset={ringOffset}
                className={cn(
                  "transition-[stroke-dashoffset] duration-300 ease-linear",
                  phase === "work" ? "stroke-primary" : "stroke-success"
                )}
              />
            </svg>
            <div className="absolute inset-0 flex flex-col items-center justify-center">
              <span className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground uppercase tracking-wide">
                {phase === "work" ? (
                  <>
                    <Brain className="w-3.5 h-3.5" /> Focus
                  </>
                ) : (
                  <>
                    <Coffee className="w-3.5 h-3.5" /> Break
                  </>
                )}
              </span>
              <span className="text-4xl font-semibold text-foreground tabular-nums mt-1">
                {formatClock(remainingSec)}
              </span>
            </div>
          </div>

          {/* Label input */}
          <div className="w-full max-w-xs mt-6">
            <Input
              placeholder="What are you focusing on? (optional)"
              value={label}
              onChange={(e) => setLabel(e.target.value)}
              disabled={status === "running" && phase === "break"}
            />
          </div>

          {/* Controls */}
          <div className="flex gap-3 mt-6">
            {status === "running" ? (
              <Button onClick={handlePause} className="gap-2">
                <Pause className="w-4 h-4" /> Pause
              </Button>
            ) : (
              <Button onClick={handleStart} className="gap-2">
                <Play className="w-4 h-4" /> {status === "paused" ? "Resume" : "Start"}
              </Button>
            )}
            <Button
              variant="outline"
              onClick={handleReset}
              disabled={status === "idle"}
              className="gap-2"
            >
              <RotateCcw className="w-4 h-4" /> Reset
            </Button>
          </div>
        </div>

        {/* Recent sessions */}
        <div className="bg-card rounded-lg border border-border shadow-soft">
          <div className="p-4 border-b border-border">
            <h3 className="text-sm font-medium text-foreground">Recent Sessions</h3>
          </div>

          {sessionsQuery.isLoading ? (
            <div className="p-12 text-center">
              <Loader2 className="w-6 h-6 animate-spin mx-auto mb-3 text-muted-foreground" />
              <p className="text-muted-foreground">Loading sessions...</p>
            </div>
          ) : sessionsQuery.isError ? (
            <div className="p-12 text-center">
              <div className="w-12 h-12 rounded-full bg-destructive/10 flex items-center justify-center mx-auto mb-3">
                <AlertCircle className="w-6 h-6 text-destructive" />
              </div>
              <p className="text-destructive font-medium">Failed to load sessions</p>
            </div>
          ) : sessions.length === 0 ? (
            <div className="p-12 text-center">
              <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto mb-3">
                <Clock className="w-6 h-6 text-muted-foreground" />
              </div>
              <p className="text-muted-foreground">No focus sessions yet</p>
              <p className="text-sm text-muted-foreground mt-1">Start a timer above to log your first one</p>
            </div>
          ) : (
            <div className="divide-y divide-border">
              {sessions.slice(0, 15).map((session) => (
                <div
                  key={session.id}
                  className="flex items-center gap-3 p-4 hover:bg-muted/30 transition-smooth group"
                >
                  <div
                    className={cn(
                      "w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0",
                      session.kind === "work" ? "bg-primary/10 text-primary" : "bg-success/10 text-success"
                    )}
                  >
                    {session.kind === "work" ? <Brain className="w-4 h-4" /> : <Coffee className="w-4 h-4" />}
                  </div>

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="text-sm text-foreground capitalize">{session.kind}</span>
                      <span className="text-xs text-muted-foreground">{session.duration_min} min</span>
                      {!session.completed && (
                        <span className="text-xs font-medium px-2 py-0.5 rounded-full bg-warning/10 text-warning-foreground">
                          Incomplete
                        </span>
                      )}
                    </div>
                    {session.label && (
                      <p className="text-xs text-muted-foreground mt-0.5 truncate">{session.label}</p>
                    )}
                    <span className="text-xs text-muted-foreground flex items-center gap-1 mt-1">
                      <CalendarDays className="w-3 h-3" />
                      {format(new Date(session.started_at), "MMM d, h:mm a")}
                    </span>
                  </div>

                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-8 w-8 text-muted-foreground hover:text-destructive opacity-0 group-hover:opacity-100 transition-smooth"
                    disabled={deleteMutation.isPending && deleteMutation.variables === session.id}
                    onClick={() => deleteMutation.mutate(session.id)}
                  >
                    <Trash2 className="w-4 h-4" />
                  </Button>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </AppLayout>
  );
}
