import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { AlertCircle, PieChart as PieChartIcon } from "lucide-react";
import { DonutChart, DonutChartSegment } from "@/components/ui/donut-chart";
import { motion, AnimatePresence } from "framer-motion";
import { cn } from "@/lib/utils";
import { dashboardKeys, getDashboardSummary } from "@/api/dashboard.api";
import { Skeleton } from "@/components/ui/skeleton";

interface ActivityDonutChartProps {
  className?: string;
}

// hsl(var(--x)) tokens defined in index.css, cycled across categories.
const SEGMENT_COLORS = [
  "hsl(var(--primary))",
  "hsl(var(--info))",
  "hsl(var(--warning))",
  "hsl(var(--success))",
  "hsl(var(--destructive))",
];

// Repurposed from a fabricated "Activity Breakdown" (Tasks/Habits/Expenses/
// Other made-up percentages) into a real breakdown of spend by category,
// sourced from GET /analytics/dashboard's top_categories. That endpoint
// aggregates all-time expense totals per category (not month-scoped), so
// this is labeled "all time" rather than implying it's this month's split.
export function ActivityDonutChart({ className }: ActivityDonutChartProps) {
  const [hoveredSegment, setHoveredSegment] = useState<string | null>(null);

  const { data, isLoading, isError } = useQuery({
    queryKey: dashboardKeys.summary,
    queryFn: getDashboardSummary,
  });

  const topCategories = data?.top_categories ?? [];
  const segments: DonutChartSegment[] = topCategories.map((c, i) => ({
    value: c.amount,
    color: SEGMENT_COLORS[i % SEGMENT_COLORS.length],
    label: c.category,
  }));

  const totalValue = segments.reduce((sum, d) => sum + d.value, 0);
  const activeSegment = segments.find((s) => s.label === hoveredSegment);
  const displayValue = activeSegment?.value ?? totalValue;
  const displayLabel = activeSegment?.label ?? "All Categories";
  const displayPercentage = activeSegment && totalValue > 0
    ? (activeSegment.value / totalValue) * 100
    : 100;

  return (
    <div className={cn("bg-card rounded-xl border border-border shadow-soft p-5", className)}>
      <h3 className="text-sm font-semibold text-foreground mb-4">
        Top Categories <span className="text-xs font-normal text-muted-foreground">(all time)</span>
      </h3>

      {isLoading ? (
        <div className="flex flex-col items-center gap-4">
          <Skeleton className="w-[180px] h-[180px] rounded-full" />
        </div>
      ) : isError ? (
        <div className="text-center py-8">
          <AlertCircle className="w-6 h-6 text-destructive mx-auto mb-2" />
          <p className="text-sm text-muted-foreground">Couldn't load category data</p>
        </div>
      ) : segments.length === 0 ? (
        <div className="text-center py-8">
          <PieChartIcon className="w-6 h-6 text-muted-foreground mx-auto mb-2" />
          <p className="text-sm text-muted-foreground">No expenses recorded yet</p>
        </div>
      ) : (
        <>
          <div className="flex flex-col items-center">
            <DonutChart
              data={segments}
              size={180}
              strokeWidth={24}
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
                    <p className="text-muted-foreground text-xs font-medium truncate max-w-[100px]">
                      {displayLabel}
                    </p>
                    <p className="text-2xl font-bold text-foreground">
                      ${displayValue.toFixed(0)}
                    </p>
                    {activeSegment && (
                      <p className="text-sm font-medium text-muted-foreground">
                        {displayPercentage.toFixed(0)}%
                      </p>
                    )}
                  </motion.div>
                </AnimatePresence>
              }
            />
          </div>

          <div className="flex flex-col space-y-1.5 mt-4 pt-4 border-t border-border">
            {segments.map((segment, index) => (
              <motion.div
                key={segment.label}
                initial={{ opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 1 + index * 0.1, duration: 0.3 }}
                className={cn(
                  "flex items-center justify-between px-2 py-1.5 rounded-md transition-all duration-200 cursor-pointer",
                  hoveredSegment === segment.label && "bg-muted"
                )}
                onMouseEnter={() => setHoveredSegment(segment.label)}
                onMouseLeave={() => setHoveredSegment(null)}
              >
                <div className="flex items-center gap-2">
                  <span
                    className="h-2.5 w-2.5 rounded-full"
                    style={{ backgroundColor: segment.color }}
                  />
                  <span className="text-sm text-foreground truncate max-w-[120px]">
                    {segment.label}
                  </span>
                </div>
                <span className="text-sm font-medium text-muted-foreground">
                  ${segment.value.toFixed(0)}
                </span>
              </motion.div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
