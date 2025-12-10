import { useState, useMemo } from "react";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { DonutChart, DonutChartSegment } from "@/components/ui/donut-chart";
import { motion, AnimatePresence } from "framer-motion";
import { 
  User, 
  Camera, 
  Trophy, 
  Flame, 
  Calendar, 
  TrendingUp,
  CheckCircle2,
  Zap,
  Award,
  Star,
  MapPin,
  Phone,
  Briefcase,
  Globe,
  Clock
} from "lucide-react";
import { cn } from "@/lib/utils";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

// Activity breakdown data for donut chart
const profileActivityData: DonutChartSegment[] = [
  { value: 156, color: "hsl(var(--primary))", label: "Tasks" },
  { value: 89, color: "hsl(var(--success))", label: "Habits" },
  { value: 234, color: "hsl(var(--info))", label: "Expenses" },
  { value: 45, color: "hsl(var(--warning))", label: "Mood Logs" },
];

// Simulated user data
const initialUserData = {
  firstName: "Alex",
  lastName: "Johnson",
  email: "alex@example.com",
  phone: "+1 (555) 123-4567",
  location: "San Francisco, CA",
  occupation: "Software Developer",
  website: "https://alexjohnson.dev",
  bio: "Passionate about productivity and personal growth. Tracking my habits and expenses to become a better version of myself.",
  timezone: "America/Los_Angeles",
  joinDate: "2024-01-15",
  avatar: null,
};

// Stats data
const statsData = {
  currentStreak: 12,
  longestStreak: 28,
  totalTasks: 156,
  totalHabits: 89,
  totalExpenses: 234,
  activeDays: 287,
  totalDays: 365,
};

// Achievements - Personal tracking badges
const achievements = [
  { id: 1, name: "First Step", description: "Complete your first task", icon: CheckCircle2, unlocked: true, date: "Jan 15", category: "tasks" },
  { id: 2, name: "Week Warrior", description: "7-day streak", icon: Flame, unlocked: true, date: "Jan 22", category: "streak" },
  { id: 3, name: "Money Tracker", description: "Log 50 expenses", icon: Award, unlocked: true, date: "Feb 10", category: "expenses" },
  { id: 4, name: "Habit Master", description: "30-day habit streak", icon: Trophy, unlocked: false, date: null, category: "habits" },
  { id: 5, name: "Centurion", description: "100 tasks completed", icon: Award, unlocked: true, date: "Mar 5", category: "tasks" },
  { id: 6, name: "Night Owl", description: "Log sleep for 30 days", icon: Clock, unlocked: false, date: null, category: "sleep" },
  { id: 7, name: "Hydration Hero", description: "Hit daily water goal 7 days in a row", icon: Zap, unlocked: true, date: "Feb 28", category: "water" },
  { id: 8, name: "Ocean Drinker", description: "Log 100 liters of water", icon: Trophy, unlocked: false, date: null, category: "water" },
  { id: 9, name: "Big Spender", description: "Track $1000+ in a month", icon: Award, unlocked: true, date: "Mar 15", category: "expenses" },
  { id: 10, name: "Budget Master", description: "Stay under budget 3 months", icon: Star, unlocked: false, date: null, category: "expenses" },
  { id: 11, name: "Mood Logger", description: "Log mood for 14 days straight", icon: TrendingUp, unlocked: true, date: "Feb 5", category: "mood" },
  { id: 12, name: "Early Bird", description: "Sleep before 10pm 7 times", icon: Clock, unlocked: false, date: null, category: "sleep" },
];

// Generate GitHub-style heatmap data (52 weeks / 12 months)
const generateYearHeatmapData = () => {
  const data: { date: Date; level: number }[] = [];
  const today = new Date();
  const oneYearAgo = new Date(today.getFullYear() - 1, today.getMonth(), today.getDate());
  
  // Start from the beginning of the week (Sunday) of one year ago
  const startDate = new Date(oneYearAgo);
  startDate.setDate(startDate.getDate() - startDate.getDay());
  
  const current = new Date(startDate);
  while (current <= today) {
    // Generate random activity level with some patterns
    const dayOfWeek = current.getDay();
    const random = Math.random();
    
    let level = 0;
    // Weekends have less activity
    if (dayOfWeek === 0 || dayOfWeek === 6) {
      if (random > 0.6) level = Math.floor(Math.random() * 3) + 1;
    } else {
      // Weekdays more active
      if (random > 0.2) level = Math.floor(Math.random() * 4) + 1;
    }
    
    data.push({ date: new Date(current), level });
    current.setDate(current.getDate() + 1);
  }
  
  return data;
};

const getHeatmapColor = (level: number) => {
  switch (level) {
    case 0: return "bg-muted";
    case 1: return "bg-primary/20";
    case 2: return "bg-primary/40";
    case 3: return "bg-primary/70";
    case 4: return "bg-primary";
    default: return "bg-muted";
  }
};

const monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

// Profile Activity Donut Component
function ProfileActivityDonut() {
  const [hoveredSegment, setHoveredSegment] = useState<string | null>(null);
  const totalValue = profileActivityData.reduce((sum, d) => sum + d.value, 0);

  const activeSegment = profileActivityData.find(
    (segment) => segment.label === hoveredSegment
  );
  
  const displayValue = activeSegment?.value ?? totalValue;
  const displayLabel = activeSegment?.label ?? "Total Logged";
  const displayPercentage = activeSegment 
    ? (activeSegment.value / totalValue) * 100 
    : 100;

  return (
    <div className="bg-card rounded-xl border border-border shadow-soft p-5">
      <h3 className="text-sm font-semibold text-foreground mb-4">Activity Breakdown</h3>
      
      <div className="flex flex-col items-center">
        <DonutChart
          data={profileActivityData}
          size={160}
          strokeWidth={22}
          animationDuration={1}
          animationDelayPerSegment={0.08}
          highlightOnHover={true}
          onSegmentHover={(segment) => setHoveredSegment(segment?.label ?? null)}
          centerContent={
            <AnimatePresence mode="wait">
              <motion.div
                key={displayLabel}
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.9 }}
                transition={{ duration: 0.2, ease: "circOut" }}
                className="flex flex-col items-center justify-center text-center"
              >
                <p className="text-muted-foreground text-[10px] font-medium truncate max-w-[80px]">
                  {displayLabel}
                </p>
                <p className="text-xl font-bold text-foreground">
                  {displayValue}
                </p>
                {activeSegment && (
                  <p className="text-xs font-medium text-muted-foreground">
                    {displayPercentage.toFixed(0)}%
                  </p>
                )}
              </motion.div>
            </AnimatePresence>
          }
        />
      </div>

      <div className="flex flex-col space-y-1 mt-4 pt-3 border-t border-border">
        {profileActivityData.map((segment, index) => (
          <motion.div
            key={segment.label}
            initial={{ opacity: 0, x: -10 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 1 + index * 0.1, duration: 0.3 }}
            className={cn(
              "flex items-center justify-between px-2 py-1 rounded-md transition-all duration-200 cursor-pointer",
              hoveredSegment === segment.label && "bg-muted"
            )}
            onMouseEnter={() => setHoveredSegment(segment.label)}
            onMouseLeave={() => setHoveredSegment(null)}
          >
            <div className="flex items-center gap-2">
              <span
                className="h-2 w-2 rounded-full"
                style={{ backgroundColor: segment.color }}
              />
              <span className="text-xs text-foreground">
                {segment.label}
              </span>
            </div>
            <span className="text-xs font-medium text-muted-foreground">
              {segment.value}
            </span>
          </motion.div>
        ))}
      </div>
    </div>
  );
}

export default function Profile() {
  const [profile, setProfile] = useState(initialUserData);
  const [isEditing, setIsEditing] = useState(false);

  const heatmapData = useMemo(() => generateYearHeatmapData(), []);

  // Group heatmap data by weeks
  const weeks = useMemo(() => {
    const result: { date: Date; level: number }[][] = [];
    let currentWeek: { date: Date; level: number }[] = [];
    
    heatmapData.forEach((day, index) => {
      currentWeek.push(day);
      if (currentWeek.length === 7) {
        result.push(currentWeek);
        currentWeek = [];
      }
    });
    
    // Add remaining days
    if (currentWeek.length > 0) {
      result.push(currentWeek);
    }
    
    return result;
  }, [heatmapData]);

  // Get month labels for the heatmap
  const monthLabels = useMemo(() => {
    const labels: { month: string; weekIndex: number }[] = [];
    let lastMonth = -1;
    
    weeks.forEach((week, weekIndex) => {
      const firstDay = week[0];
      if (firstDay && firstDay.date.getMonth() !== lastMonth) {
        lastMonth = firstDay.date.getMonth();
        labels.push({ month: monthNames[lastMonth], weekIndex });
      }
    });
    
    return labels;
  }, [weeks]);

  const memberSince = new Date(profile.joinDate).toLocaleDateString("en-US", { 
    month: "long", 
    year: "numeric" 
  });

  const completionRate = ((statsData.activeDays / statsData.totalDays) * 100).toFixed(0);

  // Count total contributions
  const totalContributions = heatmapData.reduce((sum, day) => sum + (day.level > 0 ? 1 : 0), 0);

  const handleSave = () => {
    setIsEditing(false);
    // In real app, this would save to backend
  };

  return (
    <AppLayout title="Profile" subtitle="Your personal overview">
      <div className="w-full max-w-5xl mx-auto space-y-6">
        {/* Profile Header */}
        <div className="bg-card rounded-xl border border-border shadow-soft overflow-hidden">
          {/* Banner */}
          <div className="h-24 bg-gradient-to-r from-primary/20 via-primary/10 to-transparent" />
          
          <div className="px-6 pb-6">
            {/* Avatar & Basic Info */}
            <div className="flex flex-col sm:flex-row gap-4 -mt-12">
              <div className="relative">
                <div className="w-24 h-24 rounded-full bg-card border-4 border-card flex items-center justify-center shadow-soft">
                  {profile.avatar ? (
                    <img src={profile.avatar} alt="Avatar" className="w-full h-full rounded-full object-cover" />
                  ) : (
                    <div className="w-full h-full rounded-full bg-muted flex items-center justify-center">
                      <User className="w-10 h-10 text-muted-foreground" />
                    </div>
                  )}
                </div>
                <button className="absolute bottom-0 right-0 w-8 h-8 rounded-full bg-primary text-primary-foreground flex items-center justify-center shadow-soft hover:bg-primary/90 transition-smooth">
                  <Camera className="w-4 h-4" />
                </button>
              </div>
              
              <div className="flex-1 sm:pt-14">
                <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
                  <div>
                    <h2 className="text-xl font-semibold text-foreground">
                      {profile.firstName} {profile.lastName}
                    </h2>
                    <p className="text-sm text-muted-foreground">{profile.email}</p>
                    <div className="flex flex-wrap items-center gap-3 mt-2 text-xs text-muted-foreground">
                      {profile.location && (
                        <span className="flex items-center gap-1">
                          <MapPin className="w-3 h-3" />
                          {profile.location}
                        </span>
                      )}
                      {profile.occupation && (
                        <span className="flex items-center gap-1">
                          <Briefcase className="w-3 h-3" />
                          {profile.occupation}
                        </span>
                      )}
                      <span className="flex items-center gap-1">
                        <Calendar className="w-3 h-3" />
                        Member since {memberSince}
                      </span>
                    </div>
                    {profile.bio && !isEditing && (
                      <p className="text-sm text-muted-foreground mt-3 max-w-lg">{profile.bio}</p>
                    )}
                  </div>
                  <Button 
                    variant={isEditing ? "default" : "outline"} 
                    size="sm"
                    onClick={isEditing ? handleSave : () => setIsEditing(true)}
                  >
                    {isEditing ? "Save Changes" : "Edit Profile"}
                  </Button>
                </div>
              </div>
            </div>

            {/* Editable Fields */}
            {isEditing && (
              <div className="mt-6 pt-6 border-t border-border space-y-6">
                {/* Basic Info */}
                <div>
                  <h4 className="text-sm font-medium text-foreground mb-4">Basic Information</h4>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div className="space-y-2">
                      <Label htmlFor="firstName">First Name</Label>
                      <Input 
                        id="firstName" 
                        value={profile.firstName}
                        onChange={(e) => setProfile({ ...profile, firstName: e.target.value })}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="lastName">Last Name</Label>
                      <Input 
                        id="lastName" 
                        value={profile.lastName}
                        onChange={(e) => setProfile({ ...profile, lastName: e.target.value })}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="email">Email</Label>
                      <Input 
                        id="email" 
                        type="email"
                        value={profile.email}
                        onChange={(e) => setProfile({ ...profile, email: e.target.value })}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="phone">Phone</Label>
                      <Input 
                        id="phone" 
                        type="tel"
                        placeholder="+1 (555) 123-4567"
                        value={profile.phone}
                        onChange={(e) => setProfile({ ...profile, phone: e.target.value })}
                      />
                    </div>
                  </div>
                </div>

                {/* Additional Info */}
                <div>
                  <h4 className="text-sm font-medium text-foreground mb-4">Additional Details</h4>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div className="space-y-2">
                      <Label htmlFor="location">Location</Label>
                      <Input 
                        id="location" 
                        placeholder="City, Country"
                        value={profile.location}
                        onChange={(e) => setProfile({ ...profile, location: e.target.value })}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="occupation">Occupation</Label>
                      <Input 
                        id="occupation" 
                        placeholder="Your job title"
                        value={profile.occupation}
                        onChange={(e) => setProfile({ ...profile, occupation: e.target.value })}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="website">Website</Label>
                      <Input 
                        id="website" 
                        type="url"
                        placeholder="https://yourwebsite.com"
                        value={profile.website}
                        onChange={(e) => setProfile({ ...profile, website: e.target.value })}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="timezone">Timezone</Label>
                      <Select 
                        value={profile.timezone} 
                        onValueChange={(v) => setProfile({ ...profile, timezone: v })}
                      >
                        <SelectTrigger id="timezone">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="America/New_York">Eastern Time (ET)</SelectItem>
                          <SelectItem value="America/Chicago">Central Time (CT)</SelectItem>
                          <SelectItem value="America/Denver">Mountain Time (MT)</SelectItem>
                          <SelectItem value="America/Los_Angeles">Pacific Time (PT)</SelectItem>
                          <SelectItem value="Europe/London">London (GMT)</SelectItem>
                          <SelectItem value="Europe/Paris">Paris (CET)</SelectItem>
                          <SelectItem value="Asia/Tokyo">Tokyo (JST)</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                    <div className="sm:col-span-2 space-y-2">
                      <Label htmlFor="bio">Bio</Label>
                      <Textarea 
                        id="bio" 
                        placeholder="Tell us a little about yourself..."
                        rows={3}
                        value={profile.bio}
                        onChange={(e) => setProfile({ ...profile, bio: e.target.value })}
                      />
                    </div>
                  </div>
                </div>

                <div className="flex gap-2 pt-2">
                  <Button onClick={handleSave}>Save Changes</Button>
                  <Button variant="outline" onClick={() => setIsEditing(false)}>Cancel</Button>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Stats Cards */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
          <div className="bg-card rounded-xl border border-border p-4 shadow-soft text-center">
            <div className="w-10 h-10 rounded-full bg-orange-100 dark:bg-orange-900/20 flex items-center justify-center mx-auto mb-2">
              <Flame className="w-5 h-5 text-orange-500" />
            </div>
            <p className="text-2xl font-bold text-foreground">{statsData.currentStreak}</p>
            <p className="text-xs text-muted-foreground">Day Streak</p>
          </div>
          
          <div className="bg-card rounded-xl border border-border p-4 shadow-soft text-center">
            <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center mx-auto mb-2">
              <Zap className="w-5 h-5 text-primary" />
            </div>
            <p className="text-2xl font-bold text-foreground">{statsData.longestStreak}</p>
            <p className="text-xs text-muted-foreground">Best Streak</p>
          </div>
          
          <div className="bg-card rounded-xl border border-border p-4 shadow-soft text-center">
            <div className="w-10 h-10 rounded-full bg-success/10 flex items-center justify-center mx-auto mb-2">
              <CheckCircle2 className="w-5 h-5 text-success" />
            </div>
            <p className="text-2xl font-bold text-foreground">{statsData.totalTasks}</p>
            <p className="text-xs text-muted-foreground">Tasks Done</p>
          </div>
          
          <div className="bg-card rounded-xl border border-border p-4 shadow-soft text-center">
            <div className="w-10 h-10 rounded-full bg-info/10 flex items-center justify-center mx-auto mb-2">
              <TrendingUp className="w-5 h-5 text-info" />
            </div>
            <p className="text-2xl font-bold text-foreground">{completionRate}%</p>
            <p className="text-xs text-muted-foreground">Active Rate</p>
          </div>
        </div>

        {/* GitHub-style Activity Heatmap (12 months) */}
        <div className="bg-card rounded-xl border border-border shadow-soft p-5">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-4">
            <div>
              <h3 className="text-sm font-semibold text-foreground">{totalContributions} contributions in the last year</h3>
              <p className="text-xs text-muted-foreground">Your tracking activity across all features</p>
            </div>
            <div className="flex items-center gap-1 text-xs text-muted-foreground">
              <span>Less</span>
              {[0, 1, 2, 3, 4].map((level) => (
                <div key={level} className={cn("w-[10px] h-[10px] rounded-sm", getHeatmapColor(level))} />
              ))}
              <span>More</span>
            </div>
          </div>
          
          {/* Month labels */}
          <div className="overflow-x-auto pb-2">
            <div className="inline-block min-w-full">
              {/* Month labels row */}
              <div className="flex mb-1 ml-8">
                {monthLabels.map((label, index) => (
                  <div 
                    key={index} 
                    className="text-[10px] text-muted-foreground"
                    style={{ 
                      position: 'relative',
                      left: `${label.weekIndex * 12}px`,
                      marginRight: index < monthLabels.length - 1 
                        ? `${(monthLabels[index + 1]?.weekIndex - label.weekIndex - 1) * 12}px` 
                        : 0
                    }}
                  >
                    {label.month}
                  </div>
                ))}
              </div>
              
              {/* Heatmap grid */}
              <div className="flex gap-[2px]">
                {/* Day labels */}
                <div className="flex flex-col gap-[2px] mr-1">
                  {dayNames.map((day, index) => (
                    <div 
                      key={day} 
                      className={cn(
                        "h-[10px] text-[9px] text-muted-foreground flex items-center",
                        index % 2 === 1 ? "opacity-100" : "opacity-0"
                      )}
                    >
                      {day.slice(0, 3)}
                    </div>
                  ))}
                </div>
                
                {/* Weeks */}
                {weeks.map((week, weekIndex) => (
                  <div key={weekIndex} className="flex flex-col gap-[2px]">
                    {week.map((day, dayIndex) => (
                      <div
                        key={dayIndex}
                        className={cn(
                          "w-[10px] h-[10px] rounded-sm transition-all hover:ring-1 hover:ring-foreground/20",
                          getHeatmapColor(day.level)
                        )}
                        title={`${day.date.toLocaleDateString("en-US", { 
                          weekday: 'long', 
                          month: 'short', 
                          day: 'numeric',
                          year: 'numeric'
                        })}: ${day.level > 0 ? `${day.level} activities` : 'No activity'}`}
                      />
                    ))}
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Achievements */}
        <div className="bg-card rounded-xl border border-border shadow-soft p-5">
          <div className="flex items-center gap-2 mb-4">
            <Trophy className="w-5 h-5 text-warning" />
            <h3 className="text-sm font-semibold text-foreground">Achievements</h3>
            <span className="ml-auto text-xs text-muted-foreground">
              {achievements.filter(a => a.unlocked).length}/{achievements.length} unlocked
            </span>
          </div>
          
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {achievements.map((achievement) => (
              <div
                key={achievement.id}
                className={cn(
                  "flex items-center gap-3 p-3 rounded-lg border transition-all",
                  achievement.unlocked
                    ? "bg-card border-border hover:border-primary/30"
                    : "bg-muted/30 border-transparent opacity-60"
                )}
              >
                <div className={cn(
                  "w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0",
                  achievement.unlocked ? "bg-warning/10" : "bg-muted"
                )}>
                  <achievement.icon className={cn(
                    "w-5 h-5",
                    achievement.unlocked ? "text-warning" : "text-muted-foreground"
                  )} />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="text-sm font-medium text-foreground truncate">{achievement.name}</p>
                    {achievement.unlocked && <Star className="w-3 h-3 text-warning fill-warning" />}
                  </div>
                  <p className="text-xs text-muted-foreground truncate">{achievement.description}</p>
                  {achievement.date && (
                    <p className="text-[10px] text-muted-foreground mt-0.5">Earned {achievement.date}</p>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Activity Breakdown Donut Chart + Quick Stats */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Donut Chart */}
          <ProfileActivityDonut />
          
          {/* Quick Stats Grid */}
          <div className="lg:col-span-2 grid grid-cols-2 sm:grid-cols-4 gap-4">
            <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
              <p className="text-xs text-muted-foreground mb-1">Total Habits</p>
              <p className="text-xl font-semibold text-foreground">{statsData.totalHabits}</p>
            </div>
            <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
              <p className="text-xs text-muted-foreground mb-1">Expenses Logged</p>
              <p className="text-xl font-semibold text-foreground">{statsData.totalExpenses}</p>
            </div>
            <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
              <p className="text-xs text-muted-foreground mb-1">Active Days</p>
              <p className="text-xl font-semibold text-foreground">{statsData.activeDays}/{statsData.totalDays}</p>
            </div>
            <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
              <p className="text-xs text-muted-foreground mb-1">This Month</p>
              <p className="text-xl font-semibold text-success">+23%</p>
            </div>
          </div>
        </div>
      </div>
    </AppLayout>
  );
}