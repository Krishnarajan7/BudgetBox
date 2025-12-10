import { useState } from "react";
import { DonutChart, DonutChartSegment } from "@/components/ui/donut-chart";
import { motion, AnimatePresence } from "framer-motion";
import { cn } from "@/lib/utils";

interface ActivityDonutChartProps {
  className?: string;
}

const activityData: DonutChartSegment[] = [
  { value: 45, color: "hsl(var(--primary))", label: "Tasks" },
  { value: 28, color: "hsl(var(--success))", label: "Habits" },
  { value: 18, color: "hsl(var(--info))", label: "Expenses" },
  { value: 9, color: "hsl(var(--warning))", label: "Other" },
];

const totalValue = activityData.reduce((sum, d) => sum + d.value, 0);

export function ActivityDonutChart({ className }: ActivityDonutChartProps) {
  const [hoveredSegment, setHoveredSegment] = useState<string | null>(null);

  const activeSegment = activityData.find(
    (segment) => segment.label === hoveredSegment
  );
  
  const displayValue = activeSegment?.value ?? totalValue;
  const displayLabel = activeSegment?.label ?? "Total Activity";
  const displayPercentage = activeSegment 
    ? (activeSegment.value / totalValue) * 100 
    : 100;

  return (
    <div className={cn("bg-card rounded-xl border border-border shadow-soft p-5", className)}>
      <h3 className="text-sm font-semibold text-foreground mb-4">Activity Breakdown</h3>
      
      <div className="flex flex-col items-center">
        <DonutChart
          data={activityData}
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
                  {displayValue}
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
        {activityData.map((segment, index) => (
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
              <span className="text-sm text-foreground">
                {segment.label}
              </span>
            </div>
            <span className="text-sm font-medium text-muted-foreground">
              {segment.value}
            </span>
          </motion.div>
        ))}
      </div>
    </div>
  );
}