import { useState } from "react";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Separator } from "@/components/ui/separator";
import { 
  Bell, 
  Shield, 
  Database, 
  LogOut, 
  Palette, 
  Globe, 
  Smartphone,
  Clock,
  HelpCircle,
  MessageSquare,
  ChevronRight
} from "lucide-react";
import { Link } from "react-router-dom";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

export default function Settings() {
  const [notifications, setNotifications] = useState({
    dailyReminders: true,
    weeklySummary: true,
    budgetAlerts: false,
    achievements: true,
  });

  return (
    <AppLayout title="Settings" subtitle="Customize your experience">
      <div className="w-full max-w-3xl mx-auto space-y-6">
        {/* Preferences Section */}
        <section className="bg-card rounded-xl border border-border shadow-soft overflow-hidden">
          <div className="p-4 border-b border-border flex items-center gap-3 bg-muted/30">
            <Palette className="w-5 h-5 text-muted-foreground" />
            <h2 className="text-sm font-semibold text-foreground">Preferences</h2>
          </div>
          <div className="p-4 space-y-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <Globe className="w-4 h-4 text-muted-foreground" />
                <div>
                  <p className="text-sm font-medium text-foreground">Language</p>
                  <p className="text-xs text-muted-foreground">Select your preferred language</p>
                </div>
              </div>
              <Select defaultValue="en">
                <SelectTrigger className="w-32">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="en">English</SelectItem>
                  <SelectItem value="es">Spanish</SelectItem>
                  <SelectItem value="fr">French</SelectItem>
                  <SelectItem value="de">German</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <Separator />
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <Clock className="w-4 h-4 text-muted-foreground" />
                <div>
                  <p className="text-sm font-medium text-foreground">Time Format</p>
                  <p className="text-xs text-muted-foreground">Choose 12-hour or 24-hour</p>
                </div>
              </div>
              <Select defaultValue="12h">
                <SelectTrigger className="w-32">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="12h">12-hour</SelectItem>
                  <SelectItem value="24h">24-hour</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <Separator />
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <Smartphone className="w-4 h-4 text-muted-foreground" />
                <div>
                  <p className="text-sm font-medium text-foreground">Compact Mode</p>
                  <p className="text-xs text-muted-foreground">Show more content on screen</p>
                </div>
              </div>
              <Switch />
            </div>
          </div>
        </section>

        {/* Notifications Section */}
        <section className="bg-card rounded-xl border border-border shadow-soft overflow-hidden">
          <div className="p-4 border-b border-border flex items-center gap-3 bg-muted/30">
            <Bell className="w-5 h-5 text-muted-foreground" />
            <h2 className="text-sm font-semibold text-foreground">Notifications</h2>
          </div>
          <div className="p-4 space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-foreground">Daily Reminders</p>
                <p className="text-xs text-muted-foreground">Get reminded to log your habits</p>
              </div>
              <Switch 
                checked={notifications.dailyReminders}
                onCheckedChange={(checked) => setNotifications({ ...notifications, dailyReminders: checked })}
              />
            </div>
            <Separator />
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-foreground">Weekly Summary</p>
                <p className="text-xs text-muted-foreground">Receive weekly progress report</p>
              </div>
              <Switch 
                checked={notifications.weeklySummary}
                onCheckedChange={(checked) => setNotifications({ ...notifications, weeklySummary: checked })}
              />
            </div>
            <Separator />
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-foreground">Budget Alerts</p>
                <p className="text-xs text-muted-foreground">Notify when exceeding budget</p>
              </div>
              <Switch 
                checked={notifications.budgetAlerts}
                onCheckedChange={(checked) => setNotifications({ ...notifications, budgetAlerts: checked })}
              />
            </div>
            <Separator />
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-foreground">Achievement Unlocks</p>
                <p className="text-xs text-muted-foreground">Celebrate your milestones</p>
              </div>
              <Switch 
                checked={notifications.achievements}
                onCheckedChange={(checked) => setNotifications({ ...notifications, achievements: checked })}
              />
            </div>
          </div>
        </section>

        {/* Privacy Section */}
        <section className="bg-card rounded-xl border border-border shadow-soft overflow-hidden">
          <div className="p-4 border-b border-border flex items-center gap-3 bg-muted/30">
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
                <p className="text-sm font-medium text-foreground">Change Password</p>
                <p className="text-xs text-muted-foreground">Update your account password</p>
              </div>
              <Button variant="outline" size="sm">Change</Button>
            </div>
          </div>
        </section>

        {/* Data Section */}
        <section className="bg-card rounded-xl border border-border shadow-soft overflow-hidden">
          <div className="p-4 border-b border-border flex items-center gap-3 bg-muted/30">
            <Database className="w-5 h-5 text-muted-foreground" />
            <h2 className="text-sm font-semibold text-foreground">Data Management</h2>
          </div>
          <div className="p-4 space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-foreground">Export Data</p>
                <p className="text-xs text-muted-foreground">Download all your tracking data</p>
              </div>
              <Button variant="outline" size="sm">Export</Button>
            </div>
            <Separator />
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-foreground text-destructive">Clear All Data</p>
                <p className="text-xs text-muted-foreground">Permanently delete all tracked data</p>
              </div>
              <Button variant="destructive" size="sm">Clear</Button>
            </div>
          </div>
        </section>

        {/* Support Section */}
        <section className="bg-card rounded-xl border border-border shadow-soft overflow-hidden">
          <div className="p-4 border-b border-border flex items-center gap-3 bg-muted/30">
            <HelpCircle className="w-5 h-5 text-muted-foreground" />
            <h2 className="text-sm font-semibold text-foreground">Support</h2>
          </div>
          <div className="divide-y divide-border">
            <button className="w-full flex items-center justify-between p-4 hover:bg-muted/30 transition-smooth text-left">
              <div className="flex items-center gap-3">
                <MessageSquare className="w-4 h-4 text-muted-foreground" />
                <span className="text-sm font-medium text-foreground">Send Feedback</span>
              </div>
              <ChevronRight className="w-4 h-4 text-muted-foreground" />
            </button>
            <button className="w-full flex items-center justify-between p-4 hover:bg-muted/30 transition-smooth text-left">
              <div className="flex items-center gap-3">
                <HelpCircle className="w-4 h-4 text-muted-foreground" />
                <span className="text-sm font-medium text-foreground">Help Center</span>
              </div>
              <ChevronRight className="w-4 h-4 text-muted-foreground" />
            </button>
          </div>
        </section>

        {/* Version */}
        <div className="text-center text-xs text-muted-foreground">
          BudgetBox v1.0.0
        </div>

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