import { useState, useEffect, useMemo } from "react";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { 
  User, 
  Camera, 
  Calendar, 
  MapPin,
  Phone,
  Briefcase,
  Globe,
  Mail,
  Edit2,
  ExternalLink,
  Wallet,
  Target,
  CheckSquare,
  Flame,
  Award
} from "lucide-react";
import { cn } from "@/lib/utils";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

import { useProfile } from "@/hooks/useProfile";
import { ProfileData, ProfileUpdatePayload } from "@/api/profile.api";

// Achievements (hardcoded for now – can be moved to backend later)
const achievements = [
  { id: "first-task", name: "First Step", description: "Complete your first task", unlocked: true, icon: "🎯" },
  { id: "week-streak", name: "Week Warrior", description: "7-day tracking streak", unlocked: true, icon: "🔥" },
  { id: "expense-50", name: "Money Tracker", description: "Log 50 expenses", unlocked: true, icon: "💰" },
  { id: "habit-30", name: "Habit Master", description: "30-day habit streak", unlocked: false, icon: "🏆" },
  { id: "task-100", name: "Centurion", description: "100 tasks completed", unlocked: true, icon: "⭐" },
  { id: "sleep-30", name: "Dream Logger", description: "Track sleep for 30 days", unlocked: false, icon: "🌙" },
  { id: "water-7", name: "Hydration Hero", description: "Hit water goal 7 days", unlocked: true, icon: "💧" },
  { id: "water-100", name: "Ocean Drinker", description: "Log 100L of water", unlocked: false, icon: "🌊" },
  { id: "expense-1000", name: "Big Spender", description: "Track $1000+ in a month", unlocked: true, icon: "💳" },
  { id: "budget-master", name: "Budget Master", description: "Stay under budget 3 months", unlocked: false, icon: "📊" },
  { id: "mood-14", name: "Mood Logger", description: "Log mood 14 days straight", unlocked: true, icon: "😊" },
  { id: "early-bird", name: "Early Bird", description: "Sleep before 10pm 7 times", unlocked: false, icon: "🐦" },
];

const getHeatmapColor = (level: number) => {
  switch (level) {
    case 0: return "bg-muted/50";
    case 1: return "bg-primary/25";
    case 2: return "bg-primary/50";
    case 3: return "bg-primary/75";
    case 4: return "bg-primary";
    default: return "bg-muted/50";
  }
};

const monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

// Backend returns raw activity counts per day (e.g. {"2026-07-04": 3}).
// Bucket those counts into 0-4 intensity levels for the heatmap coloring.
const getIntensityLevel = (count: number) => {
  if (count <= 0) return 0;
  if (count === 1) return 1;
  if (count === 2) return 2;
  if (count <= 4) return 3;
  return 4;
};

export default function Profile() {
  const {
    profile,
    stats,
    activity,
    loading,
    saving,
    saveProfile,
  } = useProfile();

  const [isEditing, setIsEditing] = useState(false);
  const [localProfile, setLocalProfile] = useState<ProfileData | null>(null);

  // Sync local editable copy when profile loads/changes
  useEffect(() => {
    if (profile) {
      setLocalProfile(profile);
    }
  }, [profile]);

  // Fixed heatmap: fills every day in the last year with real data or 0
  const heatmapData = useMemo(() => {
    if (!activity) return [];

    const map = new Map<string, number>(
      Object.entries(activity).map(([date, count]) => [date, getIntensityLevel(count)])
    );

    const data: { date: Date; level: number }[] = [];
    const today = new Date();
    const start = new Date();
    start.setFullYear(today.getFullYear() - 1);
    start.setDate(start.getDate() + 1); // inclusive

    for (let d = new Date(start); d <= today; d.setDate(d.getDate() + 1)) {
      const key = d.toISOString().slice(0, 10);
      data.push({
        date: new Date(d),
        level: map.get(key) ?? 0,
      });
    }

    return data;
  }, [activity]);

  const weeks = useMemo(() => {
    const result: { date: Date; level: number }[][] = [];
    let currentWeek: { date: Date; level: number }[] = [];
    
    heatmapData.forEach((day) => {
      currentWeek.push(day);
      if (currentWeek.length === 7) {
        result.push(currentWeek);
        currentWeek = [];
      }
    });
    
    if (currentWeek.length > 0) {
      result.push(currentWeek);
    }
    
    return result;
  }, [heatmapData]);

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

  if (loading) {
    return (
      <AppLayout title="Profile">
        <div className="p-10 text-center text-muted-foreground">
          Loading profile...
        </div>
      </AppLayout>
    );
  }

  if (!profile || !stats || !localProfile) return null;

  const memberSinceDate = new Date(profile.join_date);
  const memberSinceText = memberSinceDate.toLocaleDateString("en-US", {
    month: "long",
    year: "numeric"
  });

  const totalContributions = heatmapData.reduce((sum, day) => sum + (day.level > 0 ? 1 : 0), 0);
  const unlockedCount = achievements.filter(a => a.unlocked).length;

  const handleSave = async () => {
    if (!localProfile) return;
    try {
      // Only send the fields the backend's ProfileUpdate schema accepts.
      // Notably `email` is not editable server-side, so it's excluded here.
      const payload: ProfileUpdatePayload = {
        first_name: localProfile.first_name,
        last_name: localProfile.last_name,
        phone: localProfile.phone,
        location: localProfile.location,
        occupation: localProfile.occupation,
        website: localProfile.website,
        bio: localProfile.bio,
        timezone: localProfile.timezone,
        avatar_url: localProfile.avatar_url,
      };
      await saveProfile(payload);
      setIsEditing(false);
    } catch (error) {
      alert("Failed to save profile. Please try again.");
    }
  };

  return (
    <AppLayout title="Profile" subtitle="Your personal overview">
      <div className="max-w-6xl mx-auto">
        <div className="grid grid-cols-1 lg:grid-cols-4 gap-6">
          
          {/* Left Sidebar - Profile Card */}
          <div className="lg:col-span-1 space-y-4">
            {/* Avatar Card */}
            <div className="bg-card rounded-xl border border-border p-6">
              <div className="flex flex-col items-center text-center">
                <div className="relative mb-4">
                  <div className="w-32 h-32 rounded-full bg-muted border-4 border-background shadow-lg flex items-center justify-center overflow-hidden">
                    {profile.avatar_url ? (
                      <img src={profile.avatar_url} alt="Avatar" className="w-full h-full object-cover" />
                    ) : (
                      <User className="w-16 h-16 text-muted-foreground" />
                    )}
                  </div>
                  <button className="absolute bottom-1 right-1 w-8 h-8 rounded-full bg-primary text-primary-foreground flex items-center justify-center shadow-md hover:bg-primary/90 transition-colors">
                    <Camera className="w-4 h-4" />
                  </button>
                </div>

                <h2 className="text-xl font-semibold text-foreground">
                  {profile.first_name} {profile.last_name || ""}
                </h2>
                <p className="text-sm text-muted-foreground mt-1">{profile.occupation || "No occupation set"}</p>
                
                <Button 
                  variant="outline" 
                  size="sm" 
                  className="mt-4 w-full"
                  onClick={() => setIsEditing(!isEditing)}
                >
                  <Edit2 className="w-3.5 h-3.5 mr-2" />
                  Edit profile
                </Button>
              </div>
              
              {/* Contact Info */}
              <div className="mt-6 pt-6 border-t border-border space-y-3">
                <div className="flex items-center gap-3 text-sm">
                  <Mail className="w-4 h-4 text-muted-foreground flex-shrink-0" />
                  <span className="text-foreground truncate">{profile.email}</span>
                </div>
                {profile.phone && (
                  <div className="flex items-center gap-3 text-sm">
                    <Phone className="w-4 h-4 text-muted-foreground flex-shrink-0" />
                    <span className="text-foreground">{profile.phone}</span>
                  </div>
                )}
                {profile.location && (
                  <div className="flex items-center gap-3 text-sm">
                    <MapPin className="w-4 h-4 text-muted-foreground flex-shrink-0" />
                    <span className="text-foreground">{profile.location}</span>
                  </div>
                )}
                {profile.website && (
                  <div className="flex items-center gap-3 text-sm">
                    <Globe className="w-4 h-4 text-muted-foreground flex-shrink-0" />
                    <a href={profile.website} target="_blank" rel="noopener noreferrer" className="text-primary hover:underline flex items-center gap-1">
                      Website <ExternalLink className="w-3 h-3" />
                    </a>
                  </div>
                )}
                <div className="flex items-center gap-3 text-sm">
                  <Calendar className="w-4 h-4 text-muted-foreground flex-shrink-0" />
                  <span className="text-muted-foreground">Joined {memberSinceText}</span>
                </div>
              </div>
              
              {profile.bio && (
                <div className="mt-6 pt-6 border-t border-border">
                  <p className="text-sm text-muted-foreground leading-relaxed">{profile.bio}</p>
                </div>
              )}
            </div>

            {/* Achievements Summary */}
            <div className="bg-card rounded-xl border border-border p-4">
              <div className="flex items-center justify-between mb-3">
                <h3 className="text-sm font-medium text-foreground">Achievements</h3>
                <span className="text-xs text-muted-foreground">{unlockedCount}/{achievements.length}</span>
              </div>
              <div className="flex flex-wrap gap-1.5">
                {achievements.slice(0, 8).map((achievement) => (
                  <div
                    key={achievement.id}
                    className={cn(
                      "w-8 h-8 rounded-md flex items-center justify-center text-base border transition-all cursor-default",
                      achievement.unlocked 
                        ? "bg-secondary/50 border-border hover:scale-110" 
                        : "bg-muted/30 border-transparent opacity-40 grayscale"
                    )}
                    title={`${achievement.name}: ${achievement.description}`}
                  >
                    {achievement.icon}
                  </div>
                ))}
                {achievements.length > 8 && (
                  <div className="w-8 h-8 rounded-md flex items-center justify-center text-xs text-muted-foreground bg-muted/30 border border-transparent">
                    +{achievements.length - 8}
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* Main Content */}
          <div className="lg:col-span-3 space-y-6">
            
            {/* Edit Profile Form */}
            {isEditing && (
              <div className="bg-card rounded-xl border border-border p-6">
                <h3 className="text-lg font-semibold text-foreground mb-6">Edit Profile</h3>
                <div className="space-y-6">
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div className="space-y-2">
                      <Label htmlFor="firstName">First Name</Label>
                      <Input
                        id="firstName"
                        value={localProfile.first_name || ""}
                        onChange={(e) => setLocalProfile({ ...localProfile, first_name: e.target.value })}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="lastName">Last Name</Label>
                      <Input
                        id="lastName"
                        value={localProfile.last_name || ""}
                        onChange={(e) => setLocalProfile({ ...localProfile, last_name: e.target.value })}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="email">Email</Label>
                      <Input
                        id="email"
                        type="email"
                        value={localProfile.email || ""}
                        disabled
                        title="Email cannot be changed here"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="phone">Phone</Label>
                      <Input 
                        id="phone" 
                        type="tel"
                        value={localProfile.phone || ""}
                        onChange={(e) => setLocalProfile({ ...localProfile, phone: e.target.value })}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="location">Location</Label>
                      <Input 
                        id="location" 
                        value={localProfile.location || ""}
                        onChange={(e) => setLocalProfile({ ...localProfile, location: e.target.value })}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="occupation">Occupation</Label>
                      <Input 
                        id="occupation" 
                        value={localProfile.occupation || ""}
                        onChange={(e) => setLocalProfile({ ...localProfile, occupation: e.target.value })}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="website">Website</Label>
                      <Input 
                        id="website" 
                        type="url"
                        value={localProfile.website || ""}
                        onChange={(e) => setLocalProfile({ ...localProfile, website: e.target.value })}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="timezone">Timezone</Label>
                      <Select 
                        value={localProfile.timezone || ""} 
                        onValueChange={(v) => setLocalProfile({ ...localProfile, timezone: v })}
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
                        rows={3}
                        value={localProfile.bio || ""}
                        onChange={(e) => setLocalProfile({ ...localProfile, bio: e.target.value })}
                      />
                    </div>
                  </div>
                  <div className="flex gap-3 pt-2">
                    <Button onClick={handleSave} disabled={saving}>
                      {saving ? "Saving..." : "Save changes"}
                    </Button>
                    <Button variant="outline" onClick={() => setIsEditing(false)}>Cancel</Button>
                  </div>
                </div>
              </div>
            )}

            {/* Contribution Graph */}
            <div className="bg-card rounded-xl border border-border p-6">
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 mb-4">
                <h3 className="text-sm font-medium text-foreground">
                  {totalContributions} contributions in the last year
                </h3>
                <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <span>Less</span>
                  {[0, 1, 2, 3, 4].map((level) => (
                    <div key={level} className={cn("w-2.5 h-2.5 rounded-sm", getHeatmapColor(level))} />
                  ))}
                  <span>More</span>
                </div>
              </div>
              
              <div className="overflow-x-auto">
                <div className="inline-block min-w-full">
                  <div className="flex mb-1.5 ml-7">
                    {monthLabels.map((label, index) => (
                      <div 
                        key={index} 
                        className="text-[10px] text-muted-foreground"
                        style={{ 
                          position: 'relative',
                          left: `${label.weekIndex * 11}px`,
                          marginRight: index < monthLabels.length - 1 
                            ? `${(monthLabels[index + 1]?.weekIndex - label.weekIndex - 1) * 11}px` 
                            : 0
                        }}
                      >
                        {label.month}
                      </div>
                    ))}
                  </div>
                  
                  <div className="flex gap-[3px]">
                    <div className="flex flex-col gap-[3px] mr-1">
                      {dayNames.map((day, index) => (
                        <div 
                          key={day} 
                          className={cn(
                            "h-2.5 text-[9px] text-muted-foreground flex items-center",
                            index % 2 === 1 ? "opacity-100" : "opacity-0"
                          )}
                        >
                          {day.slice(0, 3)}
                        </div>
                      ))}
                    </div>
                    
                    {weeks.map((week, weekIndex) => (
                      <div key={weekIndex} className="flex flex-col gap-[3px]">
                        {week.map((day, dayIndex) => (
                          <div
                            key={dayIndex}
                            className={cn(
                              "w-2.5 h-2.5 rounded-sm transition-all hover:ring-1 hover:ring-foreground/30",
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

            {/* Stats Overview */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
              <StatCard
                icon={Flame}
                label="Task Streak"
                value={stats.task_streak.current_streak}
                subLabel={`Best: ${stats.task_streak.longest_streak}`}
                color="text-orange-500"
                bgColor="bg-orange-500/10"
              />
              <StatCard
                icon={Award}
                label="Habit Streak"
                value={stats.habit_streak.current_streak}
                subLabel={`Best: ${stats.habit_streak.longest_streak}`}
                color="text-primary"
                bgColor="bg-primary/10"
              />
              <StatCard icon={CheckSquare} label="Tasks Done" value={stats.total_tasks_completed} color="text-green-500" bgColor="bg-green-500/10" />
              <StatCard icon={Target} label="Habits Done" value={stats.total_habits_completed} color="text-blue-500" bgColor="bg-blue-500/10" />
            </div>

            {/* All Achievements */}
            <div className="bg-card rounded-xl border border-border p-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-sm font-medium text-foreground">All Achievements</h3>
                <span className="text-xs text-muted-foreground px-2 py-1 bg-muted rounded-full">
                  {unlockedCount} of {achievements.length} unlocked
                </span>
              </div>
              
              <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
                {achievements.map((achievement) => (
                  <div
                    key={achievement.id}
                    className={cn(
                      "relative p-4 rounded-lg border text-center transition-all",
                      achievement.unlocked 
                        ? "bg-card border-border hover:border-primary/50 hover:shadow-sm" 
                        : "bg-muted/20 border-transparent opacity-50"
                    )}
                  >
                    <div className={cn(
                      "text-2xl mb-2",
                      !achievement.unlocked && "grayscale"
                    )}>
                      {achievement.icon}
                    </div>
                    <p className="text-xs font-medium text-foreground truncate">{achievement.name}</p>
                    <p className="text-[10px] text-muted-foreground mt-0.5 line-clamp-2">{achievement.description}</p>
                  </div>
                ))}
              </div>
            </div>

            {/* Activity Summary */}
            {/* Mood/water/sleep cards removed: backend does not expose those
                counters (see app/profile/stats_service.py) — showing them
                would just be fake data. */}
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
              <MiniStatCard icon={CheckSquare} label="Tasks Done" value={stats.total_tasks_completed} />
              <MiniStatCard icon={Target} label="Habits Done" value={stats.total_habits_completed} />
              <MiniStatCard
                icon={Wallet}
                label="Expenses"
                value={`$${stats.total_expenses.toLocaleString(undefined, { maximumFractionDigits: 2 })}`}
              />
            </div>
          </div>
        </div>
      </div>
    </AppLayout>
  );
}

function StatCard({ icon: Icon, label, value, subLabel, color, bgColor }: {
  icon: any;
  label: string;
  value: number | string;
  subLabel?: string;
  color: string;
  bgColor: string;
}) {
  return (
    <div className="bg-card rounded-xl border border-border p-4">
      <div className={cn("w-9 h-9 rounded-lg flex items-center justify-center mb-3", bgColor)}>
        <Icon className={cn("w-4.5 h-4.5", color)} />
      </div>
      <p className="text-2xl font-semibold text-foreground">{value}</p>
      <p className="text-xs text-muted-foreground mt-0.5">{label}</p>
      {subLabel && (
        <p className="text-[10px] text-muted-foreground/70 mt-0.5">{subLabel}</p>
      )}
    </div>
  );
}

function MiniStatCard({ icon: Icon, label, value }: {
  icon: any;
  label: string;
  value: number | string;
}) {
  return (
    <div className="bg-card rounded-lg border border-border p-3 flex items-center gap-3">
      <div className="w-8 h-8 rounded-md bg-muted/50 flex items-center justify-center flex-shrink-0">
        <Icon className="w-4 h-4 text-muted-foreground" />
      </div>
      <div className="min-w-0">
        <p className="text-lg font-semibold text-foreground">{value}</p>
        <p className="text-[10px] text-muted-foreground truncate">{label}</p>
      </div>
    </div>
  );
}