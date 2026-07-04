import { useMemo, useState } from "react";
import axios from "axios";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { useToast } from "@/hooks/use-toast";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  ChevronLeft,
  ChevronRight,
  Plus,
  Pencil,
  Trash2,
  Loader2,
  AlertCircle,
  Wallet,
  PiggyBank,
  TrendingDown,
  ShoppingBag,
  Car,
  Utensils,
  Film,
  Home,
  Zap,
  Heart,
  Tag,
  type LucideIcon,
} from "lucide-react";
import {
  listBudgets,
  createBudget,
  updateBudget,
  deleteBudget,
  type Budget,
} from "@/api/budgets.api";
import { listCategories, type Category } from "@/api/categories.api";

// Icon/color styling for well-known category names, mirroring the scheme
// used on the Expenses page so budget cards feel like the same system.
// Anything the user names that doesn't match falls back to a stable,
// hash-derived color.
const defaultCategoryStyles: Record<string, { icon: LucideIcon; color: string }> = {
  food: { icon: Utensils, color: "bg-emerald-500" },
  transport: { icon: Car, color: "bg-blue-500" },
  shopping: { icon: ShoppingBag, color: "bg-amber-500" },
  entertainment: { icon: Film, color: "bg-rose-500" },
  housing: { icon: Home, color: "bg-violet-500" },
  utilities: { icon: Zap, color: "bg-cyan-500" },
  health: { icon: Heart, color: "bg-pink-500" },
};

const fallbackColors = [
  "bg-slate-500",
  "bg-indigo-500",
  "bg-teal-500",
  "bg-orange-500",
  "bg-fuchsia-500",
  "bg-lime-600",
];

function hashString(value: string): number {
  let hash = 0;
  for (let i = 0; i < value.length; i++) {
    hash = (hash * 31 + value.charCodeAt(i)) >>> 0;
  }
  return hash;
}

function getCategoryStyle(name: string): { icon: LucideIcon; color: string } {
  const key = name.trim().toLowerCase();
  if (defaultCategoryStyles[key]) return defaultCategoryStyles[key];
  return {
    icon: Tag,
    color: fallbackColors[hashString(key) % fallbackColors.length],
  };
}

// Safely coerce a value that may arrive as a numeric string (e.g. a
// serialized Decimal) or a number into a JS number for display/math.
function toNumber(value: number | string | null | undefined): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  if (typeof value === "string") {
    const parsed = parseFloat(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function pad2(n: number): string {
  return String(n).padStart(2, "0");
}

// "YYYY-MM" for a first-of-month Date, in local time (months are calendar
// concepts, not instants, so this deliberately avoids any UTC conversion).
function toMonthKey(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}`;
}

function monthLabel(d: Date): string {
  return d.toLocaleDateString("en-US", { month: "long", year: "numeric" });
}

function startOfMonth(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), 1);
}

// Progress-bar color state, per the product spec: safe under 80%, warning
// from 80% up to (not including) 100%, over at/above 100%.
function progressState(percentUsed: number): "safe" | "warning" | "over" {
  if (percentUsed >= 100) return "over";
  if (percentUsed >= 80) return "warning";
  return "safe";
}

const progressBarColor: Record<ReturnType<typeof progressState>, string> = {
  safe: "bg-success",
  warning: "bg-warning",
  over: "bg-destructive",
};

const progressTextColor: Record<ReturnType<typeof progressState>, string> = {
  safe: "text-success",
  warning: "text-warning",
  over: "text-destructive",
};

interface BudgetFormState {
  categoryId: string;
  limit: string;
}

function emptyForm(): BudgetFormState {
  return { categoryId: "", limit: "" };
}

export default function Budgets() {
  const { toast } = useToast();
  const queryClient = useQueryClient();

  const [monthDate, setMonthDate] = useState<Date>(() => startOfMonth(new Date()));
  const monthKey = toMonthKey(monthDate);

  const goPrevMonth = () =>
    setMonthDate((d) => new Date(d.getFullYear(), d.getMonth() - 1, 1));
  const goNextMonth = () =>
    setMonthDate((d) => new Date(d.getFullYear(), d.getMonth() + 1, 1));
  const goCurrentMonth = () => setMonthDate(startOfMonth(new Date()));

  const budgetsQuery = useQuery({
    queryKey: ["budgets", monthKey],
    queryFn: () => listBudgets(monthKey),
  });
  const categoriesQuery = useQuery({
    queryKey: ["categories", "expense"],
    queryFn: () => listCategories("expense"),
  });

  const budgets = budgetsQuery.data ?? [];
  const categories = categoriesQuery.data ?? [];

  // Categories that don't already have a budget this month — the only
  // sensible choices for the "Add Budget" form, since the backend rejects
  // duplicates for the same category+month with a 409.
  const budgetedCategoryIds = useMemo(
    () => new Set(budgets.map((b) => b.category_id)),
    [budgets]
  );
  const availableCategories = useMemo(
    () => categories.filter((c) => !budgetedCategoryIds.has(c.id)),
    [categories, budgetedCategoryIds]
  );

  const [isAddOpen, setIsAddOpen] = useState(false);
  const [addForm, setAddForm] = useState<BudgetFormState>(() => emptyForm());
  const [addError, setAddError] = useState<string | null>(null);

  const [editingBudget, setEditingBudget] = useState<Budget | null>(null);
  const [editLimit, setEditLimit] = useState("");
  const [editError, setEditError] = useState<string | null>(null);

  const resetAddForm = (list: Category[] = availableCategories) => {
    setAddForm({ categoryId: list.length > 0 ? String(list[0].id) : "", limit: "" });
    setAddError(null);
  };

  // Friendly, 409-aware error message extraction shared by create/update.
  const describeError = (error: unknown, fallback: string): string => {
    if (axios.isAxiosError(error)) {
      if (error.response?.status === 409) {
        return "A budget already exists for that category this month.";
      }
      const detail = (error.response?.data as { detail?: unknown } | undefined)?.detail;
      if (typeof detail === "string") return detail;
    }
    return fallback;
  };

  const createMutation = useMutation({
    mutationFn: createBudget,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["budgets", monthKey] });
      setIsAddOpen(false);
      resetAddForm();
      toast({ title: "Budget created" });
    },
    onError: (error) => {
      const message = describeError(error, "Could not create budget. Please try again.");
      setAddError(message);
      toast({ title: "Couldn't create budget", description: message, variant: "destructive" });
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, limit }: { id: number; limit: number }) => updateBudget(id, { limit }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["budgets", monthKey] });
      setEditingBudget(null);
      setEditLimit("");
      setEditError(null);
      toast({ title: "Budget updated" });
    },
    onError: (error) => {
      const message = describeError(error, "Could not update budget. Please try again.");
      setEditError(message);
      toast({ title: "Couldn't update budget", description: message, variant: "destructive" });
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deleteBudget,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["budgets", monthKey] });
      toast({ title: "Budget deleted" });
    },
    onError: () => {
      toast({
        title: "Couldn't delete budget",
        description: "Please try again.",
        variant: "destructive",
      });
    },
  });

  const handleOpenAdd = (open: boolean) => {
    setIsAddOpen(open);
    if (open) resetAddForm();
  };

  const handleAddBudget = () => {
    setAddError(null);
    const limitValue = parseFloat(addForm.limit);
    const categoryId = Number(addForm.categoryId);
    if (!addForm.categoryId || !Number.isFinite(categoryId)) {
      setAddError("Please select a category.");
      return;
    }
    if (!addForm.limit || !Number.isFinite(limitValue) || limitValue <= 0) {
      setAddError("Please enter a limit greater than 0.");
      return;
    }
    createMutation.mutate({ category_id: categoryId, month: monthKey, limit: limitValue });
  };

  const openEdit = (budget: Budget) => {
    setEditingBudget(budget);
    setEditLimit(String(budget.limit));
    setEditError(null);
  };

  const handleSaveEdit = () => {
    if (!editingBudget) return;
    setEditError(null);
    const limitValue = parseFloat(editLimit);
    if (!editLimit || !Number.isFinite(limitValue) || limitValue <= 0) {
      setEditError("Please enter a limit greater than 0.");
      return;
    }
    updateMutation.mutate({ id: editingBudget.id, limit: limitValue });
  };

  const handleDelete = (id: number) => {
    deleteMutation.mutate(id);
  };

  const totals = useMemo(() => {
    const totalBudgeted = budgets.reduce((sum, b) => sum + toNumber(b.limit), 0);
    const totalSpent = budgets.reduce((sum, b) => sum + toNumber(b.spent), 0);
    const totalRemaining = totalBudgeted - totalSpent;
    return { totalBudgeted, totalSpent, totalRemaining };
  }, [budgets]);

  const isLoading = budgetsQuery.isLoading || categoriesQuery.isLoading;
  const isError = budgetsQuery.isError || categoriesQuery.isError;

  const handleRetry = () => {
    budgetsQuery.refetch();
    categoriesQuery.refetch();
  };

  const monthNav = (
    <div className="flex items-center gap-2">
      <Button variant="outline" size="icon" onClick={goPrevMonth} aria-label="Previous month">
        <ChevronLeft className="w-4 h-4" />
      </Button>
      <button
        type="button"
        onClick={goCurrentMonth}
        className="text-lg font-semibold text-foreground min-w-[11rem] text-center hover:text-primary transition-smooth"
        title="Jump to current month"
      >
        {monthLabel(monthDate)}
      </button>
      <Button variant="outline" size="icon" onClick={goNextMonth} aria-label="Next month">
        <ChevronRight className="w-4 h-4" />
      </Button>
    </div>
  );

  if (isLoading) {
    return (
      <AppLayout title="Budgets" subtitle="Plan and track spending limits">
        <div className="w-full max-w-5xl mx-auto space-y-6">
          <div className="grid grid-cols-2 lg:grid-cols-3 gap-4">
            {Array.from({ length: 3 }).map((_, i) => (
              <div key={i} className="bg-card rounded-xl border border-border p-5 shadow-soft">
                <Skeleton className="w-10 h-10 rounded-lg mb-3" />
                <Skeleton className="h-6 w-20 mb-2" />
                <Skeleton className="h-3 w-24" />
              </div>
            ))}
          </div>
          <div className="grid gap-4">
            {Array.from({ length: 3 }).map((_, i) => (
              <div key={i} className="bg-card rounded-lg border border-border shadow-soft p-4">
                <Skeleton className="h-5 w-40 mb-3" />
                <Skeleton className="h-2 w-full mb-2" />
                <Skeleton className="h-3 w-32" />
              </div>
            ))}
          </div>
        </div>
      </AppLayout>
    );
  }

  if (isError) {
    return (
      <AppLayout title="Budgets" subtitle="Plan and track spending limits">
        <div className="w-full max-w-5xl mx-auto">
          <div className="bg-card rounded-xl border border-border shadow-soft p-8 text-center space-y-4">
            <div className="w-12 h-12 rounded-full bg-destructive/10 flex items-center justify-center mx-auto">
              <AlertCircle className="w-6 h-6 text-destructive" />
            </div>
            <div>
              <p className="text-sm font-medium text-foreground">Couldn't load your budgets</p>
              <p className="text-xs text-muted-foreground mt-1">Please check your connection and try again.</p>
            </div>
            <Button onClick={handleRetry}>Retry</Button>
          </div>
        </div>
      </AppLayout>
    );
  }

  const noCategoriesYet = categories.length === 0;

  return (
    <AppLayout title="Budgets" subtitle="Plan and track spending limits">
      <div className="w-full max-w-5xl mx-auto space-y-6">
        {/* Month navigation + add */}
        <div className="flex items-center justify-between flex-wrap gap-3">
          {monthNav}
          <Dialog open={isAddOpen} onOpenChange={handleOpenAdd}>
            <DialogTrigger asChild>
              <Button className="gap-2" disabled={noCategoriesYet}>
                <Plus className="w-4 h-4" />
                Add Budget
              </Button>
            </DialogTrigger>
            <DialogContent className="sm:max-w-md">
              <DialogHeader>
                <DialogTitle>Add Budget for {monthLabel(monthDate)}</DialogTitle>
              </DialogHeader>
              <div className="space-y-4 pt-4">
                <div>
                  <label className="text-sm font-medium text-foreground mb-1.5 block">Category</label>
                  {availableCategories.length === 0 ? (
                    <p className="text-xs text-muted-foreground">
                      Every expense category already has a budget for this month.
                    </p>
                  ) : (
                    <Select
                      value={addForm.categoryId}
                      onValueChange={(v) => setAddForm({ ...addForm, categoryId: v })}
                    >
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {availableCategories.map((cat) => {
                          const style = getCategoryStyle(cat.name);
                          return (
                            <SelectItem key={cat.id} value={String(cat.id)}>
                              <div className="flex items-center gap-2">
                                <div className={cn("w-4 h-4 rounded flex items-center justify-center", style.color)}>
                                  <style.icon className="w-2.5 h-2.5 text-white" />
                                </div>
                                {cat.name}
                              </div>
                            </SelectItem>
                          );
                        })}
                      </SelectContent>
                    </Select>
                  )}
                </div>
                <div>
                  <label className="text-sm font-medium text-foreground mb-1.5 block">Monthly limit</label>
                  <Input
                    type="number"
                    step="0.01"
                    min="0.01"
                    placeholder="0.00"
                    value={addForm.limit}
                    onChange={(e) => setAddForm({ ...addForm, limit: e.target.value })}
                  />
                </div>
                {addError && <p className="text-xs text-destructive">{addError}</p>}
                <div className="flex gap-2 pt-2">
                  <Button
                    onClick={handleAddBudget}
                    className="flex-1"
                    disabled={createMutation.isPending || availableCategories.length === 0}
                  >
                    {createMutation.isPending ? (
                      <Loader2 className="w-4 h-4 animate-spin" />
                    ) : (
                      "Add Budget"
                    )}
                  </Button>
                  <Button variant="outline" onClick={() => setIsAddOpen(false)}>
                    Cancel
                  </Button>
                </div>
              </div>
            </DialogContent>
          </Dialog>
        </div>

        {/* No expense categories at all yet */}
        {noCategoriesYet && (
          <div className="bg-card rounded-xl border border-border shadow-soft p-8 text-center space-y-3">
            <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto">
              <PiggyBank className="w-6 h-6 text-muted-foreground" />
            </div>
            <div>
              <p className="text-sm font-medium text-foreground">No expense categories yet</p>
              <p className="text-xs text-muted-foreground mt-1">
                Budgets are set per category. Add an expense first to create a category, then come back here.
              </p>
            </div>
            <Button asChild variant="outline">
              <Link to="/expenses">Go to Expenses</Link>
            </Button>
          </div>
        )}

        {/* Summary */}
        {!noCategoriesYet && (
          <div className="grid grid-cols-2 lg:grid-cols-3 gap-4">
            <div className="bg-card rounded-xl border border-border p-5 shadow-soft">
              <div className="flex items-center justify-between mb-3">
                <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
                  <Wallet className="w-5 h-5 text-primary" />
                </div>
              </div>
              <p className="text-2xl font-bold text-foreground">${totals.totalBudgeted.toFixed(2)}</p>
              <p className="text-xs text-muted-foreground mt-1">Total budgeted</p>
            </div>
            <div className="bg-card rounded-xl border border-border p-5 shadow-soft">
              <div className="flex items-center justify-between mb-3">
                <div className="w-10 h-10 rounded-lg bg-info/10 flex items-center justify-center">
                  <TrendingDown className="w-5 h-5 text-info" />
                </div>
              </div>
              <p className="text-2xl font-bold text-foreground">${totals.totalSpent.toFixed(2)}</p>
              <p className="text-xs text-muted-foreground mt-1">Spent this month</p>
            </div>
            <div className="bg-card rounded-xl border border-border p-5 shadow-soft col-span-2 lg:col-span-1">
              <div className="flex items-center justify-between mb-3">
                <div
                  className={cn(
                    "w-10 h-10 rounded-lg flex items-center justify-center",
                    totals.totalRemaining < 0 ? "bg-destructive/10" : "bg-success/10"
                  )}
                >
                  <PiggyBank
                    className={cn("w-5 h-5", totals.totalRemaining < 0 ? "text-destructive" : "text-success")}
                  />
                </div>
              </div>
              <p
                className={cn(
                  "text-2xl font-bold",
                  totals.totalRemaining < 0 ? "text-destructive" : "text-foreground"
                )}
              >
                ${totals.totalRemaining.toFixed(2)}
              </p>
              <p className="text-xs text-muted-foreground mt-1">Remaining</p>
            </div>
          </div>
        )}

        {/* Budgets list */}
        {!noCategoriesYet && (
          budgets.length === 0 ? (
            <div className="bg-card rounded-xl border border-border shadow-soft p-8 text-center space-y-2">
              <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto">
                <PiggyBank className="w-6 h-6 text-muted-foreground" />
              </div>
              <p className="text-sm font-medium text-foreground">No budgets for {monthLabel(monthDate)}</p>
              <p className="text-xs text-muted-foreground">Add a budget to start tracking a category's spending limit.</p>
            </div>
          ) : (
            <div className="grid gap-4">
              {budgets.map((budget) => {
                const style = getCategoryStyle(budget.category_name);
                const percent = toNumber(budget.percent_used);
                const state = progressState(percent);
                const clampedWidth = Math.min(Math.max(percent, 0), 100);
                const limit = toNumber(budget.limit);
                const spent = toNumber(budget.spent);
                const remaining = toNumber(budget.remaining);

                return (
                  <div
                    key={budget.id}
                    className="bg-card rounded-lg border border-border shadow-soft p-4 group"
                  >
                    <div className="flex items-center justify-between mb-3">
                      <div className="flex items-center gap-3 min-w-0">
                        <div className={cn("w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0", style.color)}>
                          <style.icon className="w-5 h-5 text-white" />
                        </div>
                        <div className="min-w-0">
                          <h3 className="font-medium text-foreground truncate">{budget.category_name}</h3>
                          <p className="text-xs text-muted-foreground">
                            ${spent.toFixed(2)} of ${limit.toFixed(2)}
                          </p>
                        </div>
                      </div>
                      <div className="flex items-center gap-3 flex-shrink-0">
                        <span className={cn("text-sm font-semibold", progressTextColor[state])}>
                          {percent.toFixed(0)}%
                        </span>
                        <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-smooth">
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7 text-muted-foreground hover:text-foreground"
                            onClick={() => openEdit(budget)}
                            aria-label="Edit limit"
                          >
                            <Pencil className="w-3.5 h-3.5" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7 text-muted-foreground hover:text-destructive"
                            onClick={() => handleDelete(budget.id)}
                            disabled={deleteMutation.isPending && deleteMutation.variables === budget.id}
                            aria-label="Delete budget"
                          >
                            <Trash2 className="w-3.5 h-3.5" />
                          </Button>
                        </div>
                      </div>
                    </div>

                    <div className="h-2 bg-muted rounded-full overflow-hidden mb-2">
                      <div
                        className={cn("h-full rounded-full transition-all", progressBarColor[state])}
                        style={{ width: `${clampedWidth}%` }}
                      />
                    </div>

                    <div className="flex items-center justify-between text-xs">
                      <span className="text-muted-foreground">
                        {remaining >= 0
                          ? `$${remaining.toFixed(2)} remaining`
                          : `$${Math.abs(remaining).toFixed(2)} over budget`}
                      </span>
                      {state === "over" && (
                        <span className="text-destructive font-medium">Over budget</span>
                      )}
                      {state === "warning" && (
                        <span className="text-warning font-medium">Nearing limit</span>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          )
        )}

        {/* Edit limit dialog */}
        <Dialog
          open={!!editingBudget}
          onOpenChange={(open) => {
            if (!open) {
              setEditingBudget(null);
              setEditLimit("");
              setEditError(null);
            }
          }}
        >
          <DialogContent className="sm:max-w-md">
            <DialogHeader>
              <DialogTitle>Edit Budget{editingBudget ? ` — ${editingBudget.category_name}` : ""}</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 pt-4">
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Monthly limit</label>
                <Input
                  type="number"
                  step="0.01"
                  min="0.01"
                  placeholder="0.00"
                  value={editLimit}
                  onChange={(e) => setEditLimit(e.target.value)}
                />
              </div>
              {editError && <p className="text-xs text-destructive">{editError}</p>}
              <div className="flex gap-2 pt-2">
                <Button
                  onClick={handleSaveEdit}
                  className="flex-1"
                  disabled={updateMutation.isPending}
                >
                  {updateMutation.isPending ? (
                    <Loader2 className="w-4 h-4 animate-spin" />
                  ) : (
                    "Save Changes"
                  )}
                </Button>
                <Button variant="outline" onClick={() => setEditingBudget(null)}>
                  Cancel
                </Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>
      </div>
    </AppLayout>
  );
}
