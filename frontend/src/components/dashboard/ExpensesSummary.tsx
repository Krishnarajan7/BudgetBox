import { TrendingUp, TrendingDown } from "lucide-react";
import { cn } from "@/lib/utils";

const categories = [
  { name: "Food & Dining", amount: 245.50, budget: 300, color: "bg-primary" },
  { name: "Transportation", amount: 89.00, budget: 150, color: "bg-info" },
  { name: "Entertainment", amount: 120.00, budget: 100, color: "bg-warning" },
  { name: "Shopping", amount: 340.00, budget: 200, color: "bg-destructive" },
];

export function ExpensesSummary() {
  const totalSpent = categories.reduce((sum, cat) => sum + cat.amount, 0);
  const totalBudget = categories.reduce((sum, cat) => sum + cat.budget, 0);

  return (
    <div className="bg-card rounded-lg border border-border shadow-soft animate-fade-in">
      <div className="p-4 border-b border-border">
        <h3 className="text-sm font-semibold text-foreground">Monthly Expenses</h3>
        <p className="text-xs text-muted-foreground mt-0.5">Budget overview</p>
      </div>

      <div className="p-4">
        <div className="flex items-baseline gap-2 mb-4">
          <span className="text-2xl font-semibold text-foreground">
            ${totalSpent.toFixed(0)}
          </span>
          <span className="text-sm text-muted-foreground">
            of ${totalBudget} budget
          </span>
        </div>

        <div className="space-y-3">
          {categories.map((category, index) => {
            const percentage = (category.amount / category.budget) * 100;
            const overBudget = percentage > 100;

            return (
              <div key={index}>
                <div className="flex items-center justify-between mb-1">
                  <span className="text-xs font-medium text-foreground">
                    {category.name}
                  </span>
                  <div className="flex items-center gap-1">
                    <span className="text-xs text-muted-foreground">
                      ${category.amount.toFixed(0)}
                    </span>
                    {overBudget && (
                      <TrendingUp className="w-3 h-3 text-destructive" />
                    )}
                  </div>
                </div>
                <div className="h-2 bg-muted rounded-full overflow-hidden">
                  <div
                    className={cn(
                      "h-full rounded-full transition-smooth",
                      overBudget ? "bg-destructive" : category.color
                    )}
                    style={{ width: `${Math.min(percentage, 100)}%` }}
                  />
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
