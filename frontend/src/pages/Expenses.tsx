import { useState } from "react";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Plus, Trash2, Pencil, DollarSign, ShoppingBag, Car, Utensils, Film, Home, Zap, Heart } from "lucide-react";
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
  { name: "Utilities", icon: Zap, color: "bg-purple-500" },
  { name: "Health", icon: Heart, color: "bg-pink-500" },
];

const todayStr = new Date().toISOString().split("T")[0];

const initialExpenses: Expense[] = [
  { id: "1", description: "Grocery shopping", amount: 85.50, category: "Food", date: todayStr },
  { id: "2", description: "Uber ride", amount: 24.00, category: "Transport", date: todayStr },
  { id: "3", description: "Netflix subscription", amount: 15.99, category: "Entertainment", date: "2024-12-04" },
  { id: "4", description: "New headphones", amount: 149.99, category: "Shopping", date: "2024-12-03" },
  { id: "5", description: "Restaurant dinner", amount: 68.00, category: "Food", date: "2024-12-03" },
  { id: "6", description: "Electric bill", amount: 120.00, category: "Utilities", date: "2024-12-02" },
  { id: "7", description: "Gas station", amount: 45.00, category: "Transport", date: "2024-12-01" },
  { id: "8", description: "Coffee shop", amount: 12.50, category: "Food", date: "2024-12-01" },
];

export default function Expenses() {
  const [expenses, setExpenses] = useState<Expense[]>(initialExpenses);
  const [isAddOpen, setIsAddOpen] = useState(false);
  const [editingExpense, setEditingExpense] = useState<Expense | null>(null);
  const [formData, setFormData] = useState({
    description: "",
    amount: "",
    category: "Food",
    date: todayStr,
  });

  const resetForm = () => {
    setFormData({ description: "", amount: "", category: "Food", date: todayStr });
    setEditingExpense(null);
  };

  const addExpense = () => {
    if (!formData.description.trim() || !formData.amount) return;
    setExpenses([{
      id: Date.now().toString(),
      description: formData.description,
      amount: parseFloat(formData.amount),
      category: formData.category,
      date: formData.date
    }, ...expenses]);
    resetForm();
    setIsAddOpen(false);
  };

  const updateExpense = () => {
    if (!editingExpense || !formData.description.trim() || !formData.amount) return;
    setExpenses(expenses.map(e => e.id === editingExpense.id ? {
      ...e,
      description: formData.description,
      amount: parseFloat(formData.amount),
      category: formData.category,
      date: formData.date,
    } : e));
    resetForm();
  };

  const deleteExpense = (id: string) => {
    setExpenses(expenses.filter(e => e.id !== id));
  };

  const startEdit = (expense: Expense) => {
    setEditingExpense(expense);
    setFormData({
      description: expense.description,
      amount: expense.amount.toString(),
      category: expense.category,
      date: expense.date,
    });
  };

  const todayExpenses = expenses.filter(e => e.date === todayStr);
  const todayTotal = todayExpenses.reduce((sum, e) => sum + e.amount, 0);
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
  })).filter(c => c.total > 0).sort((a, b) => b.total - a.total);

  return (
    <AppLayout title="Expenses" subtitle="Track your spending">
      <div className="max-w-4xl space-y-6">
        {/* Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 md:gap-4">
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <div className="flex items-center gap-2 mb-1">
              <DollarSign className="w-4 h-4 text-muted-foreground" />
              <p className="text-xs text-muted-foreground">Today</p>
            </div>
            <p className="text-2xl font-semibold text-foreground">${todayTotal.toFixed(2)}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-1">This Week</p>
            <p className="text-2xl font-semibold text-foreground">${thisWeek.toFixed(0)}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-1">Total Spent</p>
            <p className="text-2xl font-semibold text-foreground">${totalSpent.toFixed(0)}</p>
          </div>
          <div className="bg-card rounded-lg border border-border p-4 shadow-soft">
            <p className="text-xs text-muted-foreground mb-1">Transactions</p>
            <p className="text-2xl font-semibold text-foreground">{expenses.length}</p>
          </div>
        </div>

        {/* Today's Expenses */}
        <div className="bg-card rounded-lg border border-border shadow-soft">
          <div className="p-4 border-b border-border flex flex-col sm:flex-row sm:items-center justify-between gap-3">
            <div>
              <h3 className="text-sm font-semibold text-foreground">Today's Expenses</h3>
              <p className="text-xs text-muted-foreground">{todayExpenses.length} transactions</p>
            </div>
            <Dialog open={isAddOpen} onOpenChange={setIsAddOpen}>
              <DialogTrigger asChild>
                <Button size="sm" className="gap-2" onClick={resetForm}>
                  <Plus className="w-4 h-4" />
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
                  <div>
                    <label className="text-sm font-medium text-foreground mb-1.5 block">Category</label>
                    <Select
                      value={formData.category}
                      onValueChange={(v) => setFormData({ ...formData, category: v })}
                    >
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {categories.map((cat) => (
                          <SelectItem key={cat.name} value={cat.name}>
                            <div className="flex items-center gap-2">
                              <div className={cn("w-4 h-4 rounded flex items-center justify-center", cat.color)}>
                                <cat.icon className="w-2.5 h-2.5 text-primary-foreground" />
                              </div>
                              {cat.name}
                            </div>
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="flex gap-2 pt-2">
                    <Button onClick={addExpense} className="flex-1">Add Expense</Button>
                    <Button variant="outline" onClick={() => setIsAddOpen(false)}>Cancel</Button>
                  </div>
                </div>
              </DialogContent>
            </Dialog>
          </div>
          {todayExpenses.length === 0 ? (
            <div className="p-8 text-center">
              <p className="text-muted-foreground">No expenses today</p>
              <p className="text-sm text-muted-foreground mt-1">Add your first expense</p>
            </div>
          ) : (
            <div className="divide-y divide-border">
              {todayExpenses.map((expense) => {
                const cat = categories.find(c => c.name === expense.category);
                return (
                  <div key={expense.id} className="flex items-center gap-3 sm:gap-4 p-4 hover:bg-muted/30 transition-smooth group">
                    <div className={cn("w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0", cat?.color || "bg-muted")}>
                      {cat && <cat.icon className="w-5 h-5 text-primary-foreground" />}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-foreground truncate">{expense.description}</p>
                      <p className="text-xs text-muted-foreground">{expense.category}</p>
                    </div>
                    <p className="text-sm font-semibold text-foreground whitespace-nowrap">-${expense.amount.toFixed(2)}</p>
                    <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-smooth">
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8 text-muted-foreground hover:text-foreground"
                        onClick={() => startEdit(expense)}
                      >
                        <Pencil className="w-4 h-4" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8 text-muted-foreground hover:text-destructive"
                        onClick={() => deleteExpense(expense.id)}
                      >
                        <Trash2 className="w-4 h-4" />
                      </Button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
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
              <div>
                <label className="text-sm font-medium text-foreground mb-1.5 block">Category</label>
                <Select
                  value={formData.category}
                  onValueChange={(v) => setFormData({ ...formData, category: v })}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {categories.map((cat) => (
                      <SelectItem key={cat.name} value={cat.name}>
                        <div className="flex items-center gap-2">
                          <div className={cn("w-4 h-4 rounded flex items-center justify-center", cat.color)}>
                            <cat.icon className="w-2.5 h-2.5 text-primary-foreground" />
                          </div>
                          {cat.name}
                        </div>
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="flex gap-2 pt-2">
                <Button onClick={updateExpense} className="flex-1">Save Changes</Button>
                <Button variant="outline" onClick={resetForm}>Cancel</Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>

        {/* Category Breakdown */}
        <div className="bg-card rounded-lg border border-border shadow-soft p-4">
          <h3 className="text-sm font-semibold text-foreground mb-4">Spending by Category</h3>
          <div className="space-y-3">
            {categoryTotals.map((cat) => (
              <div key={cat.name} className="flex items-center gap-3">
                <div className={cn("w-8 h-8 rounded-md flex items-center justify-center flex-shrink-0", cat.color)}>
                  <cat.icon className="w-4 h-4 text-primary-foreground" />
                </div>
                <span className="text-sm font-medium text-foreground w-24">{cat.name}</span>
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

        {/* All Expenses */}
        <div className="bg-card rounded-lg border border-border shadow-soft">
          <div className="p-4 border-b border-border">
            <h3 className="text-sm font-semibold text-foreground">All Expenses</h3>
          </div>
          <div className="divide-y divide-border max-h-96 overflow-y-auto">
            {expenses.map((expense) => {
              const cat = categories.find(c => c.name === expense.category);
              return (
                <div key={expense.id} className="flex items-center gap-3 sm:gap-4 p-4 hover:bg-muted/30 transition-smooth group">
                  <div className={cn("w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0", cat?.color || "bg-muted")}>
                    {cat && <cat.icon className="w-5 h-5 text-primary-foreground" />}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-foreground truncate">{expense.description}</p>
                    <p className="text-xs text-muted-foreground">{expense.category}</p>
                  </div>
                  <div className="text-right">
                    <p className="text-sm font-semibold text-foreground">-${expense.amount.toFixed(2)}</p>
                    <p className="text-xs text-muted-foreground">
                      {new Date(expense.date).toLocaleDateString("en-US", { month: "short", day: "numeric" })}
                    </p>
                  </div>
                  <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-smooth">
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 text-muted-foreground hover:text-foreground"
                      onClick={() => startEdit(expense)}
                    >
                      <Pencil className="w-4 h-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 text-muted-foreground hover:text-destructive"
                      onClick={() => deleteExpense(expense.id)}
                    >
                      <Trash2 className="w-4 h-4" />
                    </Button>
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
