import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { AlertCircle, Wallet } from "lucide-react";
import { dashboardKeys, getDashboardSummary } from "@/api/dashboard.api";
import { Skeleton } from "@/components/ui/skeleton";

const barColors = ["bg-primary", "bg-info", "bg-warning", "bg-success", "bg-destructive"];

export function ExpensesSummary() {
  const { data, isLoading, isError } = useQuery({
    queryKey: dashboardKeys.summary,
    queryFn: getDashboardSummary,
  });

  const monthlyExpense = data?.monthly.expense ?? 0;
  const weeklyExpense = data?.weekly.expense ?? 0;
  const topCategories = data?.top_categories ?? [];
  const maxAmount = topCategories.reduce((max, c) => Math.max(max, c.amount), 0);

  return (
    <div className="bg-card rounded-lg border border-border shadow-soft animate-fade-in">
      <div className="p-4 border-b border-border flex items-center justify-between">
        <div>
          <h3 className="text-sm font-semibold text-foreground">Expenses</h3>
          <p className="text-xs text-muted-foreground mt-0.5">This month's spending</p>
        </div>
        <Link to="/expenses" className="text-xs font-medium text-primary hover:underline">
          View all
        </Link>
      </div>

      <div className="p-4">
        {isLoading ? (
          <div className="space-y-3">
            <Skeleton className="h-8 w-32" />
            <Skeleton className="h-2 w-full" />
            <Skeleton className="h-2 w-full" />
            <Skeleton className="h-2 w-full" />
          </div>
        ) : isError ? (
          <div className="text-center py-4">
            <AlertCircle className="w-6 h-6 text-destructive mx-auto mb-2" />
            <p className="text-sm text-muted-foreground">Couldn't load expenses</p>
          </div>
        ) : (
          <>
            <div className="flex items-baseline gap-2 mb-1">
              <span className="text-2xl font-semibold text-foreground">
                ${monthlyExpense.toFixed(0)}
              </span>
              <span className="text-sm text-muted-foreground">spent this month</span>
            </div>
            <p className="text-xs text-muted-foreground mb-4">
              ${weeklyExpense.toFixed(0)} in the last 7 days
            </p>

            {topCategories.length === 0 ? (
              <div className="text-center py-4">
                <Wallet className="w-6 h-6 text-muted-foreground mx-auto mb-2" />
                <p className="text-sm text-muted-foreground">No expenses recorded yet</p>
                <Link to="/expenses" className="text-xs text-primary hover:underline">
                  Add your first expense
                </Link>
              </div>
            ) : (
              <div className="space-y-3">
                <p className="text-xs font-medium text-muted-foreground">
                  Top categories (all time)
                </p>
                {topCategories.map((category, index) => {
                  const percentage =
                    maxAmount > 0 ? (category.amount / maxAmount) * 100 : 0;
                  return (
                    <div key={category.category}>
                      <div className="flex items-center justify-between mb-1">
                        <span className="text-xs font-medium text-foreground truncate">
                          {category.category}
                        </span>
                        <span className="text-xs text-muted-foreground flex-shrink-0">
                          ${category.amount.toFixed(0)}
                        </span>
                      </div>
                      <div className="h-2 bg-muted rounded-full overflow-hidden">
                        <div
                          className={`h-full rounded-full transition-smooth ${
                            barColors[index % barColors.length]
                          }`}
                          style={{ width: `${Math.max(percentage, 2)}%` }}
                        />
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
