import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Separator } from "@/components/ui/separator";
import { User, Bell, Shield, Palette, Database, LogOut } from "lucide-react";

export default function Settings() {
  return (
    <AppLayout title="Settings" subtitle="Manage your preferences">
      <div className="max-w-2xl space-y-6">
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
        <Button variant="outline" className="w-full gap-2">
          <LogOut className="w-4 h-4" />
          Sign Out
        </Button>
      </div>
    </AppLayout>
  );
}
