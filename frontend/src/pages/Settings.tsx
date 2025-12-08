import { useState, useMemo } from "react";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Separator } from "@/components/ui/separator";
import { User, Bell, Shield, Database, LogOut, Calendar, ChevronLeft, ChevronRight, Check, X, Minus } from "lucide-react";
import { cn } from "@/lib/utils";
import { Link } from "react-router-dom";

// Simulated activity data - in real app this would come from tracking data
const generateActivityData = () => {
  const now = new Date();
  const data: Record<string, { hasExpenses: boolean; hasActivity: boolean }> = {};
  
  // Generate data for the last 60 days
  for (let i = 0; i < 60; i++) {
    const date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
    const dateStr = date.toISOString().split("T")[0];
    
    // Simulate some activity patterns
    const dayOfWeek = date.getDay();
    const random = Math.random();
    
    // Weekends have less activity, some days intentionally have no expenses
    if (dayOfWeek === 0 || dayOfWeek === 6) {
      data[dateStr] = {
        hasExpenses: random > 0.4,
        hasActivity: random > 0.3
      };
    } else {
      data[dateStr] = {
        hasExpenses: random > 0.2,
        hasActivity: random > 0.1
      };
    }
  }
  
  // Today always has activity
  data[now.toISOString().split("T")[0]] = { hasExpenses: true, hasActivity: true };
  
  return data;
};

export default function Settings() {
  const [currentMonth, setCurrentMonth] = useState(new Date());
  const activityData = useMemo(() => generateActivityData(), []);

  // Calendar logic
  const calendarDays = useMemo(() => {
    const year = currentMonth.getFullYear();
    const month = currentMonth.getMonth();
    
    const firstDay = new Date(year, month, 1);
    const lastDay = new Date(year, month + 1, 0);
    
    const startPadding = firstDay.getDay();
    const days: { date: Date; dateStr: string; inMonth: boolean }[] = [];
    
    // Previous month padding
    for (let i = startPadding - 1; i >= 0; i--) {
      const d = new Date(year, month, -i);
      days.push({ date: d, dateStr: d.toISOString().split("T")[0], inMonth: false });
    }
    
    // Current month
    for (let i = 1; i <= lastDay.getDate(); i++) {
      const d = new Date(year, month, i);
      days.push({ date: d, dateStr: d.toISOString().split("T")[0], inMonth: true });
    }
    
    // Next month padding
    const remaining = 42 - days.length;
    for (let i = 1; i <= remaining; i++) {
      const d = new Date(year, month + 1, i);
      days.push({ date: d, dateStr: d.toISOString().split("T")[0], inMonth: false });
    }
    
    return days;
  }, [currentMonth]);

  const navigateMonth = (direction: number) => {
    setCurrentMonth(new Date(currentMonth.getFullYear(), currentMonth.getMonth() + direction, 1));
  };

  // Calculate stats for the visible month
  const monthStats = useMemo(() => {
    const year = currentMonth.getFullYear();
    const month = currentMonth.getMonth();
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    
    let daysWithExpenses = 0;
    let daysWithActivity = 0;
    let daysMissed = 0;
    let noExpenseDays = 0;
    
    const today = new Date();
    
    for (let i = 1; i <= daysInMonth; i++) {
      const d = new Date(year, month, i);
      const dateStr = d.toISOString().split("T")[0];
      const data = activityData[dateStr];
      
      // Only count past days and today
      if (d <= today) {
        if (data?.hasExpenses) {
          daysWithExpenses++;
        } else {
          noExpenseDays++;
        }
        
        if (data?.hasActivity) {
          daysWithActivity++;
        } else {
          daysMissed++;
        }
      }
    }
    
    return { daysWithExpenses, daysWithActivity, daysMissed, noExpenseDays, daysInMonth };
  }, [currentMonth, activityData]);

  const todayStr = new Date().toISOString().split("T")[0];

  return (
    <AppLayout title="Settings" subtitle="Manage your preferences">
      <div className="w-full max-w-3xl mx-auto space-y-6">
        {/* Activity Calendar */}
        <section className="bg-card rounded-lg border border-border shadow-soft animate-fade-in">
          <div className="p-4 border-b border-border flex items-center gap-3">
            <Calendar className="w-5 h-5 text-muted-foreground" />
            <h2 className="text-sm font-semibold text-foreground">Activity Tracker</h2>
          </div>
          <div className="p-4">
            {/* Month Navigation */}
            <div className="flex items-center justify-between mb-4">
              <Button variant="ghost" size="icon" onClick={() => navigateMonth(-1)}>
                <ChevronLeft className="w-4 h-4" />
              </Button>
              <h3 className="text-sm font-semibold text-foreground">
                {currentMonth.toLocaleDateString("en-US", { month: "long", year: "numeric" })}
              </h3>
              <Button 
                variant="ghost" 
                size="icon" 
                onClick={() => navigateMonth(1)}
                disabled={currentMonth.getMonth() === new Date().getMonth() && currentMonth.getFullYear() === new Date().getFullYear()}
              >
                <ChevronRight className="w-4 h-4" />
              </Button>
            </div>

            {/* Stats Summary */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
              <div className="bg-success/10 rounded-lg p-3 text-center">
                <p className="text-lg font-semibold text-success">{monthStats.daysWithExpenses}</p>
                <p className="text-xs text-muted-foreground">Days with expenses</p>
              </div>
              <div className="bg-muted rounded-lg p-3 text-center">
                <p className="text-lg font-semibold text-muted-foreground">{monthStats.noExpenseDays}</p>
                <p className="text-xs text-muted-foreground">No expense days</p>
              </div>
              <div className="bg-primary/10 rounded-lg p-3 text-center">
                <p className="text-lg font-semibold text-primary">{monthStats.daysWithActivity}</p>
                <p className="text-xs text-muted-foreground">Active days</p>
              </div>
              <div className="bg-destructive/10 rounded-lg p-3 text-center">
                <p className="text-lg font-semibold text-destructive">{monthStats.daysMissed}</p>
                <p className="text-xs text-muted-foreground">Missed days</p>
              </div>
            </div>

            {/* Calendar Grid */}
            <div className="grid grid-cols-7 gap-1">
              {["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].map(day => (
                <div key={day} className="text-center text-xs font-medium text-muted-foreground py-2">
                  {day}
                </div>
              ))}
              
              {calendarDays.map((day, index) => {
                const data = activityData[day.dateStr];
                const isToday = day.dateStr === todayStr;
                const isFuture = day.date > new Date();
                
                let bgColor = "bg-transparent";
                let icon = null;
                
                if (!isFuture && day.inMonth) {
                  if (data?.hasExpenses && data?.hasActivity) {
                    bgColor = "bg-success/20";
                    icon = <Check className="w-3 h-3 text-success" />;
                  } else if (data?.hasActivity && !data?.hasExpenses) {
                    bgColor = "bg-muted";
                    icon = <Minus className="w-3 h-3 text-muted-foreground" />;
                  } else {
                    bgColor = "bg-destructive/10";
                    icon = <X className="w-3 h-3 text-destructive/60" />;
                  }
                }
                
                return (
                  <div
                    key={index}
                    className={cn(
                      "aspect-square flex flex-col items-center justify-center rounded-md text-xs relative",
                      day.inMonth ? "text-foreground" : "text-muted-foreground/40",
                      bgColor,
                      isToday && "ring-2 ring-primary ring-offset-1 ring-offset-card"
                    )}
                  >
                    <span className={cn(isToday && "font-bold")}>{day.date.getDate()}</span>
                    {icon && <div className="absolute bottom-0.5">{icon}</div>}
                  </div>
                );
              })}
            </div>

            {/* Legend */}
            <div className="flex flex-wrap items-center justify-center gap-4 mt-4 pt-4 border-t border-border">
              <div className="flex items-center gap-2">
                <div className="w-4 h-4 rounded bg-success/20 flex items-center justify-center">
                  <Check className="w-2.5 h-2.5 text-success" />
                </div>
                <span className="text-xs text-muted-foreground">Expenses logged</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-4 h-4 rounded bg-muted flex items-center justify-center">
                  <Minus className="w-2.5 h-2.5 text-muted-foreground" />
                </div>
                <span className="text-xs text-muted-foreground">No expenses (active)</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-4 h-4 rounded bg-destructive/10 flex items-center justify-center">
                  <X className="w-2.5 h-2.5 text-destructive/60" />
                </div>
                <span className="text-xs text-muted-foreground">Missed</span>
              </div>
            </div>
          </div>
        </section>

        {/* Profile Section */}
        <section className="bg-card rounded-lg border border-border shadow-soft animate-fade-in">
          <div className="p-4 border-b border-border flex items-center gap-3">
            <User className="w-5 h-5 text-muted-foreground" />
            <h2 className="text-sm font-semibold text-foreground">Profile</h2>
          </div>
          <div className="p-4 space-y-4">
            <div className="flex items-center gap-4">
              <div className="w-16 h-16 rounded-full bg-muted flex items-center justify-center">
                <User className="w-8 h-8 text-muted-foreground" />
              </div>
              <div>
                <Button variant="outline" size="sm">Change Photo</Button>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="firstName">First Name</Label>
                <Input id="firstName" defaultValue="Alex" />
              </div>
              <div className="space-y-2">
                <Label htmlFor="lastName">Last Name</Label>
                <Input id="lastName" defaultValue="Johnson" />
              </div>
            </div>
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input id="email" type="email" defaultValue="alex@example.com" />
            </div>
          </div>
        </section>

        {/* Notifications Section */}
        <section className="bg-card rounded-lg border border-border shadow-soft animate-fade-in">
          <div className="p-4 border-b border-border flex items-center gap-3">
            <Bell className="w-5 h-5 text-muted-foreground" />
            <h2 className="text-sm font-semibold text-foreground">Notifications</h2>
          </div>
          <div className="p-4 space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-foreground">Daily Reminders</p>
                <p className="text-xs text-muted-foreground">Get reminded to log your habits</p>
              </div>
              <Switch defaultChecked />
            </div>
            <Separator />
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-foreground">Weekly Summary</p>
                <p className="text-xs text-muted-foreground">Receive weekly progress report</p>
              </div>
              <Switch defaultChecked />
            </div>
            <Separator />
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-foreground">Budget Alerts</p>
                <p className="text-xs text-muted-foreground">Notify when exceeding budget</p>
              </div>
              <Switch />
            </div>
          </div>
        </section>

        {/* Privacy Section */}
        <section className="bg-card rounded-lg border border-border shadow-soft animate-fade-in">
          <div className="p-4 border-b border-border flex items-center gap-3">
            <Shield className="w-5 h-5 text-muted-foreground" />
            <h2 className="text-sm font-semibold text-foreground">Privacy & Security</h2>
          </div>
          <div className="p-4 space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-foreground">Two-Factor Authentication</p>
                <p className="text-xs text-muted-foreground">Add an extra layer of security</p>
              </div>
              <Button variant="outline" size="sm">Enable</Button>
            </div>
            <Separator />
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-foreground">Data Export</p>
                <p className="text-xs text-muted-foreground">Download all your data</p>
              </div>
              <Button variant="outline" size="sm">Export</Button>
            </div>
          </div>
        </section>

        {/* Data Section */}
        <section className="bg-card rounded-lg border border-border shadow-soft animate-fade-in">
          <div className="p-4 border-b border-border flex items-center gap-3">
            <Database className="w-5 h-5 text-muted-foreground" />
            <h2 className="text-sm font-semibold text-foreground">Data Management</h2>
          </div>
          <div className="p-4 space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-foreground">Clear All Data</p>
                <p className="text-xs text-muted-foreground">Permanently delete all tracked data</p>
              </div>
              <Button variant="destructive" size="sm">Clear</Button>
            </div>
          </div>
        </section>

        {/* Logout */}
        <Link to="/auth">
          <Button variant="outline" className="w-full gap-2">
            <LogOut className="w-4 h-4" />
            Sign Out
          </Button>
        </Link>
      </div>
    </AppLayout>
  );
}
