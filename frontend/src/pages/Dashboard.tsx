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
import {
  CheckSquare,
  Target,
  Smile,
  Wallet,
  Droplets,
  Moon,
} from "lucide-react";

export default function Dashboard() {
  return (
    <AppLayout title="Dashboard" subtitle="Your daily overview">
      {/* Quick Metrics */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4 mb-6">
        <MetricCard
          icon={CheckSquare}
          label="Tasks"
          value="12"
          subtitle="5 completed"
          trend={{ value: 15, positive: true }}
        />
        <MetricCard
          icon={Target}
          label="Habits"
          value="4/6"
          subtitle="67% done"
        />
        <MetricCard
          icon={Smile}
          label="Mood"
          value="Good"
          subtitle="Better than yesterday"
          trend={{ value: 10, positive: true }}
        />
        <MetricCard
          icon={Wallet}
          label="Spent"
          value="$794"
          subtitle="This month"
          trend={{ value: 8, positive: false }}
        />
        <MetricCard
          icon={Droplets}
          label="Water"
          value="5/8"
          subtitle="Glasses today"
        />
        <MetricCard
          icon={Moon}
          label="Sleep"
          value="7.5h"
          subtitle="Last night"
          trend={{ value: 5, positive: true }}
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