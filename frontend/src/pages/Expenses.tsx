import { useState } from "react";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Plus, TrendingUp, TrendingDown, DollarSign, ShoppingBag, Car, Utensils, Film, Home } from "lucide-react";
import { cn } from "@/lib/utils";

interface Expense {
  id: string;
  description: string;
  amount: number;
  category: string;
  date: string;
}

const categories = [
  { name: "Food", icon: Utensils, color: "bg-primary" },
  { name: "Transport", icon: Car, color: "bg-info" },
  { name: "Shopping", icon: ShoppingBag, color: "bg-warning" },
  { name: "Entertainment", icon: Film, color: "bg-destructive" },
  { name: "Housing", icon: Home, color: "bg-success" },
];

const initialExpenses: Expense[] = [
  { id: "1", description: "Grocery shopping", amount: 85.50, category: "Food", date: "2024-12-05" },
  { id: "2", description: "Uber ride", amount: 24.00, category: "Transport", date: "2024-12-05" },
  { id: "3", description: "Netflix subscription", amount: 15.99, category: "Entertainment", date: "2024-12-04" },
  { id: "4", description: "New headphones", amount: 149.99, category: "Shopping", date: "2024-12-03" },
  { id: "5", description: "Restaurant dinner", amount: 68.00, category: "Food", date: "2024-12-03" },
  { id: "6", description: "Electric bill", amount: 120.00, category: "Housing", date: "2024-12-02" },
  { id: "7", description: "Gas station", amount: 45.00, category: "Transport", date: "2024-12-01" },
  { id: "8", description: "Coffee shop", amount: 12.50, category: "Food", date: "2024-12-01" },
];

export default function Expenses() {
  const [expenses, setExpenses] = useState<Expense[]>(initialExpenses);
  const [showAdd, setShowAdd] = useState(false);
  const [newExpense, setNewExpense] = useState({ description: "", amount: "", category: "Food" });

  const addExpense = () => {
    if (!newExpense.description || !newExpense.amount) return;
    setExpenses([{
      id: Date.now().toString(),
      description: newExpense.description,
      amount: parseFloat(newExpense.amount),
      category: newExpense.category,
      date: new Date().toISOString().split("T")[0]
    }, ...expenses]);
    setNewExpense({ description: "", amount: "", category: "Food" });
    setShowAdd(false);
  };

  const totalSpent = expenses.reduce((sum, e) => sum + e.amount, 0);
  const thisWeek = expenses.filter(e => {
    const expDate = new Date(e.date);
    const weekAgo = new Date();
    weekAgo.setDate(weekAgo.getDate() - 7);
    return expDate >= weekAgo;
  }).reduce((sum, e) => sum + e.amount, 0);

  const categoryTotals = categories.map(cat => ({
    ...cat,
    total: expenses.filter(e => e.category === cat.name).reduce((sum, e) => sum + e.amount, 0)
  }));

  return (
    <AppLayout title="Expenses" subtitle="Track your spending">
      <div className="max-w-4xl space-y-6">
        {/* Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <div className="flex items-center gap-2 mb-2">
              <DollarSign className="w-4 h-4 text-muted-foreground" />
              <p className="text-xs text-muted-foreground">Total Spent</p>
            </div>
            <p className="text-2xl font-semibold text-foreground">${totalSpent.toFixed(0)}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <div className="flex items-center gap-2 mb-2">
              <TrendingDown className="w-4 h-4 text-destructive" />
              <p className="text-xs text-muted-foreground">This Week</p>
            </div>
            <p className="text-2xl font-semibold text-foreground">${thisWeek.toFixed(0)}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-2">Transactions</p>
            <p className="text-2xl font-semibold text-foreground">{expenses.length}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-2">Daily Avg</p>
            <p className="text-2xl font-semibold text-foreground">${(totalSpent / 30).toFixed(0)}</p>
          </div>
        </div>

        {/* Category Breakdown */}
        <div className="bg-card rounded-lg border border-border shadow-soft p-4">
          <h3 className="text-sm font-semibold text-foreground mb-4">By Category</h3>
          <div className="space-y-3">
            {categoryTotals.map((cat) => (
              <div key={cat.name} className="flex items-center gap-3">
                <div className={cn("w-8 h-8 rounded-md flex items-center justify-center", cat.color)}>
                  <cat.icon className="w-4 h-4 text-primary-foreground" />
                </div>
                <span className="text-sm font-medium text-foreground flex-1">{cat.name}</span>
                <div className="flex-1 h-2 bg-muted rounded-full overflow-hidden">
                  <div
                    className={cn("h-full rounded-full", cat.color)}
                    style={{ width: `${(cat.total / totalSpent) * 100}%` }}
                  />
                </div>
                <span className="text-sm font-medium text-foreground w-20 text-right">
                  ${cat.total.toFixed(0)}
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Add Expense */}
        {showAdd && (
          <div className="bg-card rounded-lg border border-border shadow-soft p-4 animate-fade-in">
            <h3 className="text-sm font-semibold text-foreground mb-4">Add Expense</h3>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-4">
              <Input
                placeholder="Description"
                value={newExpense.description}
                onChange={(e) => setNewExpense({ ...newExpense, description: e.target.value })}
              />
              <Input
                type="number"
                placeholder="Amount"
                value={newExpense.amount}
                onChange={(e) => setNewExpense({ ...newExpense, amount: e.target.value })}
              />
              <select
                value={newExpense.category}
                onChange={(e) => setNewExpense({ ...newExpense, category: e.target.value })}
                className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
              >
                {categories.map((cat) => (
                  <option key={cat.name} value={cat.name}>{cat.name}</option>
                ))}
              </select>
            </div>
            <div className="flex gap-2">
              <Button onClick={addExpense}>Save</Button>
              <Button variant="outline" onClick={() => setShowAdd(false)}>Cancel</Button>
            </div>
          </div>
        )}

        {/* Expense List */}
        <div className="bg-card rounded-lg border border-border shadow-soft">
          <div className="p-4 border-b border-border flex items-center justify-between">
            <h3 className="text-sm font-semibold text-foreground">Recent Expenses</h3>
            <Button size="sm" onClick={() => setShowAdd(true)} className="gap-2">
              <Plus className="w-4 h-4" />
              Add
            </Button>
          </div>
          <div className="divide-y divide-border">
            {expenses.map((expense) => {
              const cat = categories.find(c => c.name === expense.category);
              return (
                <div key={expense.id} className="flex items-center gap-4 p-4 hover:bg-muted/30 transition-smooth">
                  <div className={cn("w-10 h-10 rounded-md flex items-center justify-center", cat?.color || "bg-muted")}>
                    {cat && <cat.icon className="w-5 h-5 text-primary-foreground" />}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-foreground">{expense.description}</p>
                    <p className="text-xs text-muted-foreground">{expense.category}</p>
                  </div>
                  <div className="text-right">
                    <p className="text-sm font-semibold text-foreground">-${expense.amount.toFixed(2)}</p>
                    <p className="text-xs text-muted-foreground">
                      {new Date(expense.date).toLocaleDateString("en-US", { month: "short", day: "numeric" })}
                    </p>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </AppLayout>
  );
}
