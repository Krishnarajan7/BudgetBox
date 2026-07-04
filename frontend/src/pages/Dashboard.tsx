import { useQueries, useQuery } from "@tanstack/react-query";
import { AppLayout } from "@/components/layout/AppLayout";
import { MetricCard } from "@/components/dashboard/MetricCard";
import { TaskList } from "@/components/dashboard/TaskList";
import { HabitTracker } from "@/components/dashboard/HabitTracker";
import { MoodChart } from "@/components/dashboard/MoodChart";
import { WaterTracker } from "@/components/dashboard/WaterTracker";
import { SleepTracker } from "@/components/dashboard/SleepTracker";
import { ExpensesSummary } from "@/components/dashboard/ExpensesSummary";
import { ActivityDonutChart } from "@/components/dashboard/ActivityDonutChart";
import { DashboardCalendar } from "@/components/dashboard/DashboardCalendar";
import { DashboardAlerts } from "@/components/dashboard/DashboardAlerts";
import {
  CheckSquare,
  Target,
  Smile,
  Wallet,
  Droplets,
  Moon,
} from "lucide-react";
import { listTasks } from "@/api/tasks.api";
import { getHabitToday, listHabits } from "@/api/habits.api";
import {
  addLocalDays,
  dashboardKeys,
  getDashboardSummary,
  getMonthComparison,
  isSameLocalDay,
  listMoodEntries,
  listSleepEntries,
  listWaterLogs,
  toLocalDateString,
} from "@/api/dashboard.api";

const MOOD_LABELS: Record<number, string> = {
  1: "Terrible",
  2: "Bad",
  3: "Okay",
  4: "Good",
  5: "Great",
};

export default function Dashboard() {
  const now = new Date();
  const today = toLocalDateString(now);
  const weekAgo = toLocalDateString(addLocalDays(now, -6));
  const yesterday = toLocalDateString(addLocalDays(now, -1));

  // --- Analytics (spend metric + month-over-month trend) ---------------
  const { data: summary } = useQuery({
    queryKey: dashboardKeys.summary,
    queryFn: getDashboardSummary,
  });

  const { data: monthComparison } = useQuery({
    queryKey: dashboardKeys.monthComparison,
    queryFn: getMonthComparison,
  });

  // --- Tasks -------------------------------------------------------------
  const { data: tasks } = useQuery({
    queryKey: ["tasks"],
    queryFn: listTasks,
  });

  const dueTodayCount = (tasks ?? []).filter((t) =>
    isSameLocalDay(t.due_at, today)
  ).length;
  const completedTodayCount = (tasks ?? []).filter(
    (t) => t.completed && isSameLocalDay(t.completed_at, today)
  ).length;

  // --- Habits --------------------------------------------------------------
  const { data: habits } = useQuery({
    queryKey: ["habits"],
    queryFn: listHabits,
  });
  const activeHabits = (habits ?? []).filter((h) => h.is_active);

  const habitTodayQueries = useQueries({
    queries: activeHabits.map((habit) => ({
      queryKey: ["habit-today", habit.id],
      queryFn: () => getHabitToday(habit.id),
    })),
  });
  const habitsDoneToday = habitTodayQueries.filter((q) => q.data?.completed).length;

  // --- Water (today) ------------------------------------------------------
  const { data: waterLogs } = useQuery({
    queryKey: dashboardKeys.water(today, today),
    queryFn: () => listWaterLogs(today, today),
  });
  const todayWater = waterLogs?.[0];
  const waterGlasses = todayWater?.glasses ?? 0;
  const waterGoal = todayWater?.goal ?? 8;

  // --- Sleep (last 7 days, for "last night" + trend vs the prior night) --
  const { data: sleepEntries } = useQuery({
    queryKey: dashboardKeys.sleep(weekAgo, today),
    queryFn: () => listSleepEntries(weekAgo, today),
  });
  const lastNight = sleepEntries?.find((e) => e.date === today);
  const nightBefore = sleepEntries?.find((e) => e.date === yesterday);
  const sleepTrend =
    lastNight && nightBefore && Number(nightBefore.hours) > 0
      ? {
          value: Math.round(
            Math.abs(
              ((Number(lastNight.hours) - Number(nightBefore.hours)) /
                Number(nightBefore.hours)) *
                100
            )
          ),
          positive: Number(lastNight.hours) >= Number(nightBefore.hours),
        }
      : undefined;

  // --- Mood (last 7 days, for today's mood + trend vs yesterday) ---------
  const { data: moodEntries } = useQuery({
    queryKey: dashboardKeys.mood(weekAgo, today),
    queryFn: () => listMoodEntries(weekAgo, today),
  });
  const todayMood = moodEntries?.find((e) => e.date === today);
  const yesterdayMood = moodEntries?.find((e) => e.date === yesterday);
  const moodTrend =
    todayMood && yesterdayMood
      ? {
          value: Math.round(Math.abs(((todayMood.mood - yesterdayMood.mood) / 5) * 100)),
          positive: todayMood.mood >= yesterdayMood.mood,
        }
      : undefined;

  // --- Spend trend vs previous month --------------------------------------
  const previousExpense = monthComparison?.previous_month.expense ?? 0;
  const expenseDiff = monthComparison?.difference.expense ?? 0;
  const spendTrend =
    monthComparison && previousExpense > 0
      ? {
          value: Math.round(Math.abs((expenseDiff / previousExpense) * 100)),
          positive: expenseDiff <= 0,
        }
      : undefined;

  return (
    <AppLayout title="Dashboard" subtitle="Your daily overview">
      <DashboardAlerts />

      {/* Quick Metrics */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4 mb-6">
        <MetricCard
          icon={CheckSquare}
          label="Tasks"
          value={dueTodayCount}
          subtitle={`${completedTodayCount} completed today`}
        />
        <MetricCard
          icon={Target}
          label="Habits"
          value={`${habitsDoneToday}/${activeHabits.length}`}
          subtitle={
            activeHabits.length > 0
              ? `${Math.round((habitsDoneToday / activeHabits.length) * 100)}% done`
              : "No habits yet"
          }
        />
        <MetricCard
          icon={Smile}
          label="Mood"
          value={todayMood ? MOOD_LABELS[todayMood.mood] ?? todayMood.mood : "—"}
          subtitle={todayMood ? "Today's mood" : "No entry today"}
          trend={moodTrend}
        />
        <MetricCard
          icon={Wallet}
          label="Spent"
          value={`$${(summary?.monthly.expense ?? 0).toFixed(0)}`}
          subtitle="This month"
          trend={spendTrend}
        />
        <MetricCard
          icon={Droplets}
          label="Water"
          value={`${waterGlasses}/${waterGoal}`}
          subtitle="Glasses today"
        />
        <MetricCard
          icon={Moon}
          label="Sleep"
          value={lastNight ? `${Number(lastNight.hours)}h` : "—"}
          subtitle="Last night"
          trend={sleepTrend}
        />
      </div>

      {/* Main Content Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 pb-6">
        {/* Left Column */}
        <div className="lg:col-span-2 space-y-6">
          <TaskList />
          <HabitTracker />
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <MoodChart />
            <WaterTracker />
          </div>
        </div>

        {/* Right Column */}
        <div className="space-y-6">
          <DashboardCalendar />
          <ActivityDonutChart />
          <SleepTracker />
          <ExpensesSummary />
        </div>
      </div>
    </AppLayout>
  );
}
