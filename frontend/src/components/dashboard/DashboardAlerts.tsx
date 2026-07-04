import { useQuery } from "@tanstack/react-query";
import { AlertTriangle, Info, CheckCircle2, OctagonAlert } from "lucide-react";
import { cn } from "@/lib/utils";
import { dashboardKeys, getDashboardSummary, type DashboardAlert } from "@/api/dashboard.api";

// Surfaces the budget/spending alerts computed server-side in
// app/analytics/alerts.py::expense_alerts (budget-limit warnings + spend-vs-
// average comparisons). Renders nothing when there are no alerts — this is
// not a widget that needs an empty state, it just disappears.
const ALERT_STYLES: Record<
  DashboardAlert["type"],
  { icon: typeof AlertTriangle; className: string }
> = {
  danger: { icon: OctagonAlert, className: "bg-destructive/10 text-destructive border-destructive/20" },
  warning: { icon: AlertTriangle, className: "bg-warning/10 text-warning-foreground border-warning/20" },
  info: { icon: Info, className: "bg-info/10 text-info border-info/20" },
  success: { icon: CheckCircle2, className: "bg-success/10 text-success border-success/20" },
};

export function DashboardAlerts() {
  const { data } = useQuery({
    queryKey: dashboardKeys.summary,
    queryFn: getDashboardSummary,
  });

  const alerts = data?.alerts ?? [];
  if (alerts.length === 0) return null;

  return (
    <div className="space-y-2 mb-6 animate-fade-in">
      {alerts.map((alert, index) => {
        const style = ALERT_STYLES[alert.type] ?? ALERT_STYLES.info;
        const Icon = style.icon;
        return (
          <div
            key={index}
            className={cn(
              "flex items-center gap-2.5 rounded-lg border px-4 py-2.5 text-sm",
              style.className
            )}
          >
            <Icon className="w-4 h-4 flex-shrink-0" />
            <span>{alert.message}</span>
          </div>
        );
      })}
    </div>
  );
}
