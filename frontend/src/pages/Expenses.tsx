import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Plus,
  Trash2,
  Pencil,
  DollarSign,
  ShoppingBag,
  Car,
  Utensils,
  Film,
  Home,
  Zap,
  Heart,
  Tag,
  ArrowUpRight,
  ArrowDownRight,
  Receipt,
  PieChart,
  Calendar,
  Filter,
  AlertCircle,
  type LucideIcon,
} from "lucide-react";
import { cn } from "@/lib/utils";
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
  listExpenses,
  createExpense,
  updateExpense,
  deleteExpense,
  type Expense,
} from "@/api/expenses.api";
import {
  listCategories,
  createCategory,
  type Category,
} from "@/api/categories.api";
import { listWallets, createWallet } from "@/api/wallets.api";

const NEW_CATEGORY_VALUE = "__new__";

// Icon/color styling for well-known category names. Anything the user
// creates that doesn't match one of these falls back to a stable,
// hash-derived color from `fallbackColors` below.
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

// Round to exactly 2 decimal places and return a real number (never a
// string), per the "amounts as numbers with 2-decimal precision" contract.
function roundToCents(value: number): number {
  return Number(value.toFixed(2));
}

// Local (not UTC) date key, e.g. "2026-07-04". Computed fresh from a Date
// each time it's needed instead of frozen once via `toISOString()` at
// module load (which is both UTC and stale after midnight/across renders).
function toLocalDateKey(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

// Combine a "YYYY-MM-DD" date-only string (from a <input type="date">) with
// the current wall-clock time-of-day, built via local Date components so it
// represents the intended local calendar day regardless of timezone.
function buildOccurredAt(dateStr: string): string {
  const [y, m, d] = dateStr.split("-").map(Number);
  const now = new Date();
  const combined = new Date(
    y,
    (m || 1) - 1,
    d || 1,
    now.getHours(),
    now.getMinutes(),
    now.getSeconds()
  );
  return combined.toISOString();
}

const monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

interface ExpenseVM {
  id: number;
  raw: Expense;
  description: string;
  amount: number;
  categoryId: number;
  categoryName: string;
  categoryStyle: { icon: LucideIcon; color: string };
  date: Date;
  dateKey: string;
}

interface ExpenseFormState {
  description: string;
  amount: string;
  categoryValue: string; // category id as string, or NEW_CATEGORY_VALUE
  newCategoryName: string;
  date: string; // local YYYY-MM-DD
}

function makeEmptyForm(categories: Category[]): ExpenseFormState {
  return {
    description: "",
    amount: "",
    categoryValue: categories.length > 0 ? String(categories[0].id) : NEW_CATEGORY_VALUE,
    newCategoryName: "",
    date: toLocalDateKey(new Date()),
  };
}

export default function Expenses() {
  const queryClient = useQueryClient();

  const expensesQuery = useQuery({
    queryKey: ["expenses"],
    queryFn: listExpenses,
  });
  const categoriesQuery = useQuery({
    queryKey: ["categories", "expense"],
    queryFn: () => listCategories("expense"),
  });
  const walletsQuery = useQuery({
    queryKey: ["wallets"],
    queryFn: listWallets,
  });

  const categories = categoriesQuery.data ?? [];
  const wallets = walletsQuery.data ?? [];

  const createCategoryMutation = useMutation({
    mutationFn: createCategory,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["categories", "expense"] });
    },
  });
  const createWalletMutation = useMutation({
    mutationFn: createWallet,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["wallets"] });
    },
  });
  const createExpenseMutation = useMutation({
    mutationFn: createExpense,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["expenses"] });
    },
  });
  const updateExpenseMutation = useMutation({
    mutationFn: ({ id, payload }: { id: number; payload: Parameters<typeof updateExpense>[1] }) =>
      updateExpense(id, payload),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["expenses"] });
    },
  });
  const deleteExpenseMutation = useMutation({
    mutationFn: deleteExpense,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["expenses"] });
    },
  });

  const [isAddOpen, setIsAddOpen] = useState(false);
  const [editingExpense, setEditingExpense] = useState<Expense | null>(null);
  const [selectedCategory, setSelectedCategory] = useState<string>("all");
  const [formData, setFormData] = useState<ExpenseFormState>(() => makeEmptyForm([]));
  const [formError, setFormError] = useState<string | null>(null);

  const resetForm = () => {
    setFormData(makeEmptyForm(categories));
    setEditingExpense(null);
    setFormError(null);
  };

  // Ensure the user has a wallet to post expenses against. New users have
  // none, so silently create a default "Cash" wallet on first use rather
  // than blocking the add-expense flow on a wallet picker.
  const ensureWalletId = async (): Promise<number> => {
    if (wallets.length > 0) return wallets[0].id;
    const wallet = await createWalletMutation.mutateAsync({ name: "Cash", balance: 0 });
    return wallet.id;
  };

  // Resolve the category to submit: either the selected existing category,
  // or create a brand-new one on the fly from the free-text input (used
  // when the user has no categories yet, or explicitly picks "New Category").
  const resolveCategoryId = async (): Promise<number | null> => {
    if (formData.categoryValue === NEW_CATEGORY_VALUE) {
      const trimmed = formData.newCategoryName.trim();
      if (!trimmed) return null;
      const category = await createCategoryMutation.mutateAsync({
        name: trimmed,
        type: "expense",
      });
      return category.id;
    }
    const id = Number(formData.categoryValue);
    return Number.isFinite(id) ? id : null;
  };

  const handleAddExpense = async () => {
    setFormError(null);
    const amountValue = roundToCents(parseFloat(formData.amount));
    if (!formData.description.trim() || !formData.amount || Number.isNaN(amountValue)) {
      setFormError("Please provide a description and a valid amount.");
      return;
    }
    try {
      const categoryId = await resolveCategoryId();
      if (categoryId == null) {
        setFormError("Please select or name a category.");
        return;
      }
      const walletId = await ensureWalletId();
      await createExpenseMutation.mutateAsync({
        wallet_id: walletId,
        category_id: categoryId,
        amount: amountValue,
        occurred_at: buildOccurredAt(formData.date),
        note: formData.description.trim(),
      });
      resetForm();
      setIsAddOpen(false);
    } catch {
      setFormError("Could not add expense. Please try again.");
    }
  };

  const handleUpdateExpense = async () => {
    setFormError(null);
    if (!editingExpense) return;
    const amountValue = roundToCents(parseFloat(formData.amount));
    if (!formData.description.trim() || !formData.amount || Number.isNaN(amountValue)) {
      setFormError("Please provide a description and a valid amount.");
      return;
    }
    try {
      const categoryId = await resolveCategoryId();
      if (categoryId == null) {
        setFormError("Please select or name a category.");
        return;
      }
      await updateExpenseMutation.mutateAsync({
        id: editingExpense.id,
        payload: {
          amount: amountValue,
          category_id: categoryId,
          occurred_at: buildOccurredAt(formData.date),
          note: formData.description.trim(),
        },
      });
      resetForm();
    } catch {
      setFormError("Could not save changes. Please try again.");
    }
  };

  const handleDeleteExpense = (id: number) => {
    deleteExpenseMutation.mutate(id);
  };

  const startEdit = (expense: Expense) => {
    setEditingExpense(expense);
    setFormError(null);
    setFormData({
      description: expense.note ?? "",
      amount: toNumber(expense.amount).toFixed(2),
      categoryValue: String(expense.category_id),
      newCategoryName: "",
      date: toLocalDateKey(new Date(expense.occurred_at)),
    });
  };

  const categoryMap = useMemo(() => {
    const map = new Map<number, Category>();
    categories.forEach((c) => map.set(c.id, c));
    return map;
  }, [categories]);

  const expensesVM: ExpenseVM[] = useMemo(() => {
    return (expensesQuery.data ?? []).map((e) => {
      const occurred = new Date(e.occurred_at);
      const category = categoryMap.get(e.category_id);
      const categoryName = category?.name ?? "Uncategorized";
      return {
        id: e.id,
        raw: e,
        description: e.note && e.note.trim() ? e.note : "Expense",
        amount: toNumber(e.amount),
        categoryId: e.category_id,
        categoryName,
        categoryStyle: getCategoryStyle(categoryName),
        date: occurred,
        dateKey: toLocalDateKey(occurred),
      };
    });
  }, [expensesQuery.data, categoryMap]);

  // Monthly comparison data, bucketed consistently in local time.
  const monthlyData = useMemo(() => {
    const data: { month: string; year: number; monthIndex: number; total: number; count: number }[] = [];
    const now = new Date();

    for (let i = 5; i >= 0; i--) {
      const targetDate = new Date(now.getFullYear(), now.getMonth() - i, 1);
      const year = targetDate.getFullYear();
      const month = targetDate.getMonth();

      const monthExpenses = expensesVM.filter(
        (e) => e.date.getMonth() === month && e.date.getFullYear() === year
      );

      data.push({
        month: monthNames[month],
        year,
        monthIndex: month,
        total: monthExpenses.reduce((sum, e) => sum + e.amount, 0),
        count: monthExpenses.length,
      });
    }

    return data;
  }, [expensesVM]);

  const currentMonthTotal = monthlyData[monthlyData.length - 1]?.total || 0;
  const lastMonthTotal = monthlyData[monthlyData.length - 2]?.total || 0;
  const monthOverMonthChange =
    lastMonthTotal > 0 ? ((currentMonthTotal - lastMonthTotal) / lastMonthTotal) * 100 : 0;
  const maxMonthlyTotal = Math.max(...monthlyData.map((m) => m.total), 1);

  const todayKey = toLocalDateKey(new Date());
  const todayExpenses = expensesVM.filter((e) => e.dateKey === todayKey);
  const todayTotal = todayExpenses.reduce((sum, e) => sum + e.amount, 0);
  const totalSpent = expensesVM.reduce((sum, e) => sum + e.amount, 0);

  const thisWeek = expensesVM
    .filter((e) => {
      const weekAgo = new Date();
      weekAgo.setDate(weekAgo.getDate() - 7);
      return e.date >= weekAgo;
    })
    .reduce((sum, e) => sum + e.amount, 0);

  const categoryTotals = categories
    .map((cat) => ({
      ...cat,
      style: getCategoryStyle(cat.name),
      total: expensesVM.filter((e) => e.categoryId === cat.id).reduce((sum, e) => sum + e.amount, 0),
    }))
    .filter((c) => c.total > 0)
    .sort((a, b) => b.total - a.total);

  const filteredExpenses =
    selectedCategory === "all"
      ? expensesVM
      : expensesVM.filter((e) => String(e.categoryId) === selectedCategory);

  const isLoading = expensesQuery.isLoading || categoriesQuery.isLoading || walletsQuery.isLoading;
  const isError = expensesQuery.isError || categoriesQuery.isError || walletsQuery.isError;

  const handleRetry = () => {
    expensesQuery.refetch();
    categoriesQuery.refetch();
    walletsQuery.refetch();
  };

  const categorySelectFields = (
    <>
      <div>
        <label className="text-sm font-medium text-foreground mb-1.5 block">Category</label>
        <Select
          value={formData.categoryValue}
          onValueChange={(v) => setFormData({ ...formData, categoryValue: v })}
        >
          <SelectTrigger>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {categories.map((cat) => {
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
            <SelectItem value={NEW_CATEGORY_VALUE}>
              <div className="flex items-center gap-2">
                <div className="w-4 h-4 rounded flex items-center justify-center bg-muted-foreground/50">
                  <Plus className="w-2.5 h-2.5 text-white" />
                </div>
                New Category
              </div>
            </SelectItem>
          </SelectContent>
        </Select>
      </div>
      {formData.categoryValue === NEW_CATEGORY_VALUE && (
        <div>
          <label className="text-sm font-medium text-foreground mb-1.5 block">New category name</label>
          <Input
            placeholder="e.g. Groceries"
            value={formData.newCategoryName}
            onChange={(e) => setFormData({ ...formData, newCategoryName: e.target.value })}
          />
        </div>
      )}
    </>
  );

  if (isLoading) {
    return (
      <AppLayout title="Expenses" subtitle="Track and analyze spending">
        <div className="w-full max-w-6xl mx-auto space-y-6">
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
            {Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="bg-card rounded-xl border border-border p-5 shadow-soft">
                <Skeleton className="w-10 h-10 rounded-lg mb-3" />
                <Skeleton className="h-6 w-20 mb-2" />
                <Skeleton className="h-3 w-24" />
              </div>
            ))}
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div className="lg:col-span-2 space-y-6">
              <div className="bg-card rounded-xl border border-border shadow-soft p-5">
                <Skeleton className="h-48 w-full" />
              </div>
              <div className="bg-card rounded-xl border border-border shadow-soft p-5">
                <Skeleton className="h-32 w-full" />
              </div>
            </div>
            <div className="space-y-6">
              <Skeleton className="h-12 w-full rounded-xl" />
              <Skeleton className="h-64 w-full rounded-xl" />
            </div>
          </div>
        </div>
      </AppLayout>
    );
  }

  if (isError) {
    return (
      <AppLayout title="Expenses" subtitle="Track and analyze spending">
        <div className="w-full max-w-6xl mx-auto">
          <div className="bg-card rounded-xl border border-border shadow-soft p-8 text-center space-y-4">
            <div className="w-12 h-12 rounded-full bg-destructive/10 flex items-center justify-center mx-auto">
              <AlertCircle className="w-6 h-6 text-destructive" />
            </div>
            <div>
              <p className="text-sm font-medium text-foreground">Couldn't load your expenses</p>
              <p className="text-xs text-muted-foreground mt-1">Please check your connection and try again.</p>
            </div>
            <Button onClick={handleRetry}>Retry</Button>
          </div>
        </div>
      </AppLayout>
    );
  }

  return (
    <AppLayout title="Expenses" subtitle="Track and analyze spending">
      <div className="w-full max-w-6xl mx-auto space-y-6">
        {/* Header Stats */}
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="bg-card rounded-xl border border-border p-5 shadow-soft">
            <div className="flex items-center justify-between mb-3">
              <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
                <DollarSign className="w-5 h-5 text-primary" />
              </div>
              <span className="text-xs text-muted-foreground px-2 py-1 bg-muted rounded-full">Today</span>
            </div>
            <p className="text-2xl font-bold text-foreground">${todayTotal.toFixed(2)}</p>
            <p className="text-xs text-muted-foreground mt-1">{todayExpenses.length} transactions</p>
          </div>

          <div className="bg-card rounded-xl border border-border p-5 shadow-soft">
            <div className="flex items-center justify-between mb-3">
              <div className="w-10 h-10 rounded-lg bg-info/10 flex items-center justify-center">
                <Receipt className="w-5 h-5 text-info" />
              </div>
              <span className="text-xs text-muted-foreground px-2 py-1 bg-muted rounded-full">7 days</span>
            </div>
            <p className="text-2xl font-bold text-foreground">${thisWeek.toFixed(0)}</p>
            <p className="text-xs text-muted-foreground mt-1">This week</p>
          </div>

          <div className="bg-card rounded-xl border border-border p-5 shadow-soft">
            <div className="flex items-center justify-between mb-3">
              <div className="w-10 h-10 rounded-lg bg-success/10 flex items-center justify-center">
                <Calendar className="w-5 h-5 text-success" />
              </div>
              <span className="text-xs text-muted-foreground px-2 py-1 bg-muted rounded-full">Month</span>
            </div>
            <p className="text-2xl font-bold text-foreground">${currentMonthTotal.toFixed(0)}</p>
            <p className="text-xs text-muted-foreground mt-1">This month</p>
          </div>

          <div className="bg-card rounded-xl border border-border p-5 shadow-soft">
            <div className="flex items-center justify-between mb-3">
              <div
                className={cn(
                  "w-10 h-10 rounded-lg flex items-center justify-center",
                  monthOverMonthChange > 0 ? "bg-destructive/10" : "bg-success/10"
                )}
              >
                {monthOverMonthChange > 0 ? (
                  <ArrowUpRight className="w-5 h-5 text-destructive" />
                ) : (
                  <ArrowDownRight className="w-5 h-5 text-success" />
                )}
              </div>
              <span className="text-xs text-muted-foreground px-2 py-1 bg-muted rounded-full">vs Last</span>
            </div>
            <p
              className={cn(
                "text-2xl font-bold",
                monthOverMonthChange > 0 ? "text-destructive" : "text-success"
              )}
            >
              {monthOverMonthChange > 0 ? "+" : ""}
              {monthOverMonthChange.toFixed(0)}%
            </p>
            <p className="text-xs text-muted-foreground mt-1">Month over month</p>
          </div>
        </div>

        {/* Main Content Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Left Column - Charts */}
          <div className="lg:col-span-2 space-y-6">
            {/* Monthly Comparison */}
            <div className="bg-card rounded-xl border border-border shadow-soft p-5">
              <div className="flex items-center justify-between mb-6">
                <div>
                  <h3 className="text-base font-semibold text-foreground">Monthly Overview</h3>
                  <p className="text-xs text-muted-foreground">Last 6 months spending trends</p>
                </div>
                <div className="text-right">
                  <p className="text-lg font-bold text-foreground">
                    ${monthlyData.reduce((sum, m) => sum + m.total, 0).toFixed(0)}
                  </p>
                  <p className="text-xs text-muted-foreground">Total</p>
                </div>
              </div>

              <div className="flex items-end gap-3 h-48">
                {monthlyData.map((month, index) => {
                  const heightPercent = (month.total / maxMonthlyTotal) * 100;
                  const isCurrentMonth = index === monthlyData.length - 1;
                  const prevMonth = monthlyData[index - 1];
                  const change =
                    prevMonth && prevMonth.total > 0
                      ? ((month.total - prevMonth.total) / prevMonth.total) * 100
                      : 0;

                  return (
                    <div key={`${month.month}-${month.year}`} className="flex-1 flex flex-col items-center group relative">
                      {/* Tooltip */}
                      <div className="absolute -top-16 left-1/2 -translate-x-1/2 bg-foreground text-background text-xs px-3 py-2 rounded-lg opacity-0 group-hover:opacity-100 transition-smooth whitespace-nowrap z-10 shadow-lg">
                        <p className="font-semibold">${month.total.toFixed(0)}</p>
                        <p className="text-[10px] opacity-80">{month.count} transactions</p>
                        {change !== 0 && (
                          <p className={cn("text-[10px]", change > 0 ? "text-red-300" : "text-green-300")}>
                            {change > 0 ? "↑" : "↓"} {Math.abs(change).toFixed(0)}%
                          </p>
                        )}
                      </div>

                      <div className="w-full bg-muted rounded-lg relative flex-1 flex items-end overflow-hidden">
                        <div
                          className={cn(
                            "w-full rounded-lg transition-all duration-500 ease-out",
                            isCurrentMonth ? "bg-primary" : "bg-primary/40 group-hover:bg-primary/60"
                          )}
                          style={{ height: `${Math.max(heightPercent, 8)}%` }}
                        />
                      </div>
                      <div className="text-center mt-2">
                        <span
                          className={cn(
                            "text-xs block font-medium",
                            isCurrentMonth ? "text-foreground" : "text-muted-foreground"
                          )}
                        >
                          {month.month}
                        </span>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>

            {/* Category Breakdown */}
            <div className="bg-card rounded-xl border border-border shadow-soft p-5">
              <div className="flex items-center gap-2 mb-5">
                <PieChart className="w-5 h-5 text-muted-foreground" />
                <h3 className="text-base font-semibold text-foreground">Category Breakdown</h3>
              </div>

              {categoryTotals.length === 0 ? (
                <div className="py-8 text-center">
                  <p className="text-sm text-muted-foreground">No spending yet — add an expense to see a breakdown.</p>
                </div>
              ) : (
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  {/* Visual representation */}
                  <div className="flex flex-wrap gap-2 justify-center items-center py-4">
                    {categoryTotals.slice(0, 5).map((cat) => {
                      const size = Math.max(40, Math.min(80, totalSpent > 0 ? (cat.total / totalSpent) * 200 : 40));
                      return (
                        <div
                          key={cat.id}
                          className={cn(
                            "rounded-full flex items-center justify-center text-white text-xs font-medium transition-all hover:scale-110",
                            cat.style.color
                          )}
                          style={{ width: size, height: size }}
                          title={`${cat.name}: $${cat.total.toFixed(0)}`}
                        >
                          <cat.style.icon className="w-4 h-4" />
                        </div>
                      );
                    })}
                  </div>

                  {/* List */}
                  <div className="space-y-3">
                    {categoryTotals.map((cat) => (
                      <div key={cat.id} className="flex items-center gap-3">
                        <div
                          className={cn(
                            "w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0",
                            cat.style.color
                          )}
                        >
                          <cat.style.icon className="w-4 h-4 text-white" />
                        </div>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center justify-between mb-1">
                            <span className="text-sm font-medium text-foreground">{cat.name}</span>
                            <span className="text-sm font-medium text-foreground">${cat.total.toFixed(0)}</span>
                          </div>
                          <div className="h-1.5 bg-muted rounded-full overflow-hidden">
                            <div
                              className={cn("h-full rounded-full transition-all", cat.style.color)}
                              style={{ width: `${totalSpent > 0 ? (cat.total / totalSpent) * 100 : 0}%` }}
                            />
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </div>

          {/* Right Column - Transactions */}
          <div className="space-y-6">
            {/* Add Button */}
            <Dialog open={isAddOpen} onOpenChange={(open) => { setIsAddOpen(open); if (open) resetForm(); }}>
              <DialogTrigger asChild>
                <Button className="w-full gap-2 h-12" onClick={resetForm}>
                  <Plus className="w-5 h-5" />
                  Add Expense
                </Button>
              </DialogTrigger>
              <DialogContent className="sm:max-w-md">
                <DialogHeader>
                  <DialogTitle>Add Expense</DialogTitle>
                </DialogHeader>
                <div className="space-y-4 pt-4">
                  <div>
                    <label className="text-sm font-medium text-foreground mb-1.5 block">Description</label>
                    <Input
                      placeholder="What did you spend on?"
                      value={formData.description}
                      onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                    />
                  </div>
                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <label className="text-sm font-medium text-foreground mb-1.5 block">Amount</label>
                      <Input
                        type="number"
                        step="0.01"
                        placeholder="0.00"
                        value={formData.amount}
                        onChange={(e) => setFormData({ ...formData, amount: e.target.value })}
                      />
                    </div>
                    <div>
                      <label className="text-sm font-medium text-foreground mb-1.5 block">Date</label>
                      <Input
                        type="date"
                        value={formData.date}
                        onChange={(e) => setFormData({ ...formData, date: e.target.value })}
                      />
                    </div>
                  </div>
                  {categorySelectFields}
                  {formError && <p className="text-xs text-destructive">{formError}</p>}
                  <div className="flex gap-2 pt-2">
                    <Button
                      onClick={handleAddExpense}
                      className="flex-1"
                      disabled={createExpenseMutation.isPending}
                    >
                      {createExpenseMutation.isPending ? "Adding..." : "Add Expense"}
                    </Button>
                    <Button variant="outline" onClick={() => setIsAddOpen(false)}>Cancel</Button>
                  </div>
                </div>
              </DialogContent>
            </Dialog>

            {/* Today's Quick View */}
            <div className="bg-card rounded-xl border border-border shadow-soft overflow-hidden">
              <div className="p-4 border-b border-border bg-muted/30">
                <h3 className="text-sm font-semibold text-foreground">Today's Expenses</h3>
                <p className="text-xs text-muted-foreground">{todayExpenses.length} transactions • ${todayTotal.toFixed(2)}</p>
              </div>

              {todayExpenses.length === 0 ? (
                <div className="p-6 text-center">
                  <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto mb-3">
                    <Receipt className="w-6 h-6 text-muted-foreground" />
                  </div>
                  <p className="text-sm text-muted-foreground">No expenses today</p>
                </div>
              ) : (
                <div className="divide-y divide-border max-h-64 overflow-y-auto">
                  {todayExpenses.map((expense) => (
                    <div key={expense.id} className="flex items-center gap-3 p-3 hover:bg-muted/30 transition-smooth group">
                      <div
                        className={cn(
                          "w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0",
                          expense.categoryStyle.color
                        )}
                      >
                        <expense.categoryStyle.icon className="w-4 h-4 text-white" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-foreground truncate">{expense.description}</p>
                        <p className="text-xs text-muted-foreground">{expense.categoryName}</p>
                      </div>
                      <p className="text-sm font-semibold text-foreground">-${expense.amount.toFixed(2)}</p>
                      <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-smooth">
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7 text-muted-foreground hover:text-foreground"
                          onClick={() => startEdit(expense.raw)}
                        >
                          <Pencil className="w-3.5 h-3.5" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7 text-muted-foreground hover:text-destructive"
                          onClick={() => handleDeleteExpense(expense.id)}
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* All Expenses with Filter */}
            <div className="bg-card rounded-xl border border-border shadow-soft overflow-hidden">
              <div className="p-4 border-b border-border bg-muted/30 flex items-center justify-between">
                <h3 className="text-sm font-semibold text-foreground">All Expenses</h3>
                <Select value={selectedCategory} onValueChange={setSelectedCategory}>
                  <SelectTrigger className="w-32 h-8 text-xs">
                    <Filter className="w-3 h-3 mr-1" />
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All</SelectItem>
                    {categories.map((cat) => (
                      <SelectItem key={cat.id} value={String(cat.id)}>{cat.name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              {filteredExpenses.length === 0 ? (
                <div className="p-6 text-center">
                  <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto mb-3">
                    <Receipt className="w-6 h-6 text-muted-foreground" />
                  </div>
                  <p className="text-sm text-muted-foreground">No expenses yet</p>
                </div>
              ) : (
                <div className="divide-y divide-border max-h-80 overflow-y-auto">
                  {filteredExpenses.map((expense) => (
                    <div key={expense.id} className="flex items-center gap-3 p-3 hover:bg-muted/30 transition-smooth group">
                      <div
                        className={cn(
                          "w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0",
                          expense.categoryStyle.color
                        )}
                      >
                        <expense.categoryStyle.icon className="w-4 h-4 text-white" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-foreground truncate">{expense.description}</p>
                        <p className="text-xs text-muted-foreground">
                          {expense.date.toLocaleDateString("en-US", { month: "short", day: "numeric" })}
                        </p>
                      </div>
                      <p className="text-sm font-semibold text-foreground">-${expense.amount.toFixed(2)}</p>
                      <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-smooth">
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7 text-muted-foreground hover:text-foreground"
                          onClick={() => startEdit(expense.raw)}
                        >
                          <Pencil className="w-3.5 h-3.5" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7 text-muted-foreground hover:text-destructive"
                          onClick={() => handleDeleteExpense(expense.id)}
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Edit Modal */}
        <Dialog open={!!editingExpense} onOpenChange={(open) => !open && resetForm()}>
          <DialogContent className="sm:max-w-md">
            <DialogHeader>
              <DialogTitle>Edit Expense</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 pt-4">
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Description</label>
                <Input
                  placeholder="What did you spend on?"
                  value={formData.description}
                  onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-sm font-medium text-foreground mb-1.5 block">Amount</label>
                  <Input
                    type="number"
                    step="0.01"
                    placeholder="0.00"
                    value={formData.amount}
                    onChange={(e) => setFormData({ ...formData, amount: e.target.value })}
                  />
                </div>
                <div>
                  <label className="text-sm font-medium text-foreground mb-1.5 block">Date</label>
                  <Input
                    type="date"
                    value={formData.date}
                    onChange={(e) => setFormData({ ...formData, date: e.target.value })}
                  />
                </div>
              </div>
              {categorySelectFields}
              {formError && <p className="text-xs text-destructive">{formError}</p>}
              <div className="flex gap-2 pt-2">
                <Button
                  onClick={handleUpdateExpense}
                  className="flex-1"
                  disabled={updateExpenseMutation.isPending}
                >
                  {updateExpenseMutation.isPending ? "Saving..." : "Save Changes"}
                </Button>
                <Button variant="outline" onClick={resetForm}>Cancel</Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>
      </div>
    </AppLayout>
  );
}
