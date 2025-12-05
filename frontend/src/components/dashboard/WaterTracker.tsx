import { Droplets, Plus, Minus } from "lucide-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

const GOAL = 8;

export function WaterTracker() {
  const [glasses, setGlasses] = useState(5);

  const progress = Math.min((glasses / GOAL) * 100, 100);

  return (
    <div className="bg-card rounded-lg border border-border shadow-soft animate-fade-in">
      <div className="p-4 border-b border-border">
        <h3 className="text-sm font-semibold text-foreground">Water Intake</h3>
        <p className="text-xs text-muted-foreground mt-0.5">Daily hydration goal</p>
      </div>

      <div className="p-4">
        <div className="flex items-center justify-center gap-6">
          <Button
            variant="outline"
            size="icon"
            className="h-8 w-8"
            onClick={() => setGlasses(Math.max(0, glasses - 1))}
            disabled={glasses === 0}
          >
            <Minus className="w-4 h-4" />
          </Button>

          <div className="relative w-24 h-24">
            <svg className="w-full h-full -rotate-90">
              <circle
                cx="48"
                cy="48"
                r="40"
                stroke="hsl(var(--muted))"
                strokeWidth="8"
                fill="none"
              />
              <circle
                cx="48"
                cy="48"
                r="40"
                stroke="hsl(var(--primary))"
                strokeWidth="8"
                fill="none"
                strokeLinecap="round"
                strokeDasharray={`${progress * 2.51} 251`}
                className="transition-all duration-300"
              />
            </svg>
            <div className="absolute inset-0 flex flex-col items-center justify-center">
              <Droplets className="w-5 h-5 text-primary mb-1" />
              <span className="text-lg font-semibold text-foreground">{glasses}</span>
              <span className="text-[10px] text-muted-foreground">of {GOAL}</span>
            </div>
          </div>

          <Button
            variant="outline"
            size="icon"
            className="h-8 w-8"
            onClick={() => setGlasses(glasses + 1)}
          >
            <Plus className="w-4 h-4" />
          </Button>
        </div>

        <div className="mt-4 pt-4 border-t border-border">
          <div className="flex items-center justify-between text-xs">
            <span className="text-muted-foreground">Progress</span>
            <span className={cn(
              "font-medium",
              glasses >= GOAL ? "text-success" : "text-foreground"
            )}>
              {Math.round(progress)}%
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}
