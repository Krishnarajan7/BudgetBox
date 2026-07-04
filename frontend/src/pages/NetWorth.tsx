import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Plus,
  Trash2,
  Pencil,
  Wallet as WalletIcon,
  Landmark,
  TrendingUp,
  TrendingDown,
  Scale,
  Home,
  Car,
  PiggyBank,
  CreditCard,
  Tag,
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
  getNetWorth,
  listAssets,
  createAsset,
  updateAsset,
  deleteAsset,
  type Asset,
  type AssetKind,
  type DecimalString,
} from "@/api/networth.api";

const CUSTOM_CATEGORY_VALUE = "__custom__";

const CATEGORY_PRESETS: { value: string; label: string; icon: LucideIcon }[] = [
  { value: "property", label: "Property", icon: Home },
  { value: "vehicle", label: "Vehicle", icon: Car },
  { value: "investment", label: "Investment", icon: TrendingUp },
  { value: "savings", label: "Savings", icon: PiggyBank },
  { value: "loan", label: "Loan", icon: Landmark },
  { value: "credit_card", label: "Credit Card", icon: CreditCard },
  { value: "other", label: "Other", icon: Tag },
];

function getCategoryIcon(category: string): LucideIcon {
  const preset = CATEGORY_PRESETS.find((c) => c.value === category.trim().toLowerCase());
  return preset?.icon ?? Tag;
}

function getCategoryLabel(category: string): string {
  const preset = CATEGORY_PRESETS.find((c) => c.value === category.trim().toLowerCase());
  if (preset) return preset.label;
  // Free-text category: title-case it for display.
  return category
    .split(/[_\s]+/)
    .filter(Boolean)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}

// Safely coerce a value that may arrive as a numeric string (e.g. a
// serialized Decimal) or a number into a JS number for display/math.
function toNumber(value: DecimalString | null | undefined): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  if (typeof value === "string") {
    const parsed = parseFloat(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function formatMoney(value: number): string {
  const sign = value < 0 ? "-" : "";
  return `${sign}$${Math.abs(value).toFixed(2)}`;
}

interface AssetFormState {
  name: string;
  categoryValue: string; // preset value, or CUSTOM_CATEGORY_VALUE
  customCategory: string;
  value: string;
  note: string;
}

function makeEmptyForm(): AssetFormState {
  return {
    name: "",
    categoryValue: CATEGORY_PRESETS[0].value,
    customCategory: "",
    value: "",
    note: "",
  };
}

function formStateFromAsset(asset: Asset): AssetFormState {
  const isPreset = CATEGORY_PRESETS.some((c) => c.value === asset.category);
  return {
    name: asset.name,
    categoryValue: isPreset ? asset.category : CUSTOM_CATEGORY_VALUE,
    customCategory: isPreset ? "" : asset.category,
    value: toNumber(asset.value).toFixed(2),
    note: asset.note ?? "",
  };
}

const kindCopy: Record<AssetKind, { title: string; addLabel: string; empty: string }> = {
  asset: {
    title: "Assets",
    addLabel: "Add Asset",
    empty: "Add what you own — property, vehicles, investments, savings — to see your full net worth.",
  },
  liability: {
    title: "Liabilities",
    addLabel: "Add Liability",
    empty: "Add what you owe — loans, credit cards — for a more accurate net worth picture.",
  },
};

export default function NetWorth() {
  const queryClient = useQueryClient();

  const networthQuery = useQuery({
    queryKey: ["networth"],
    queryFn: getNetWorth,
  });
  const assetsQuery = useQuery({
    queryKey: ["assets"],
    queryFn: listAssets,
  });

  const invalidateAll = () => {
    queryClient.invalidateQueries({ queryKey: ["networth"] });
    queryClient.invalidateQueries({ queryKey: ["assets"] });
  };

  const createAssetMutation = useMutation({
    mutationFn: createAsset,
    onSuccess: invalidateAll,
  });
  const updateAssetMutation = useMutation({
    mutationFn: ({ id, payload }: { id: number; payload: Parameters<typeof updateAsset>[1] }) =>
      updateAsset(id, payload),
    onSuccess: invalidateAll,
  });
  const deleteAssetMutation = useMutation({
    mutationFn: deleteAsset,
    onSuccess: invalidateAll,
  });

  const [addDialogKind, setAddDialogKind] = useState<AssetKind | null>(null);
  const [editingAsset, setEditingAsset] = useState<Asset | null>(null);
  const [formData, setFormData] = useState<AssetFormState>(() => makeEmptyForm());
  const [formError, setFormError] = useState<string | null>(null);

  const openAddDialog = (kind: AssetKind) => {
    setFormData(makeEmptyForm());
    setFormError(null);
    setAddDialogKind(kind);
  };

  const closeAddDialog = () => {
    setAddDialogKind(null);
    setFormError(null);
  };

  const startEdit = (asset: Asset) => {
    setEditingAsset(asset);
    setFormData(formStateFromAsset(asset));
    setFormError(null);
  };

  const closeEditDialog = () => {
    setEditingAsset(null);
    setFormError(null);
  };

  const resolveCategory = (): string | null => {
    if (formData.categoryValue === CUSTOM_CATEGORY_VALUE) {
      const trimmed = formData.customCategory.trim();
      return trimmed ? trimmed : null;
    }
    return formData.categoryValue;
  };

  const handleAdd = async () => {
    if (!addDialogKind) return;
    setFormError(null);
    const value = parseFloat(formData.value);
    const category = resolveCategory();
    if (!formData.name.trim()) {
      setFormError("Please provide a name.");
      return;
    }
    if (!category) {
      setFormError("Please select or name a category.");
      return;
    }
    if (!formData.value || Number.isNaN(value) || value <= 0) {
      setFormError("Please provide a value greater than 0.");
      return;
    }
    try {
      await createAssetMutation.mutateAsync({
        name: formData.name.trim(),
        kind: addDialogKind,
        category,
        value: Number(value.toFixed(2)),
        note: formData.note.trim() ? formData.note.trim() : undefined,
      });
      closeAddDialog();
    } catch {
      setFormError("Could not save. Please try again.");
    }
  };

  const handleUpdate = async () => {
    if (!editingAsset) return;
    setFormError(null);
    const value = parseFloat(formData.value);
    const category = resolveCategory();
    if (!formData.name.trim()) {
      setFormError("Please provide a name.");
      return;
    }
    if (!category) {
      setFormError("Please select or name a category.");
      return;
    }
    if (!formData.value || Number.isNaN(value) || value <= 0) {
      setFormError("Please provide a value greater than 0.");
      return;
    }
    try {
      await updateAssetMutation.mutateAsync({
        id: editingAsset.id,
        payload: {
          name: formData.name.trim(),
          category,
          value: Number(value.toFixed(2)),
          note: formData.note.trim() ? formData.note.trim() : null,
        },
      });
      closeEditDialog();
    } catch {
      setFormError("Could not save changes. Please try again.");
    }
  };

  const handleDelete = (id: number) => {
    deleteAssetMutation.mutate(id);
  };

  const assets = assetsQuery.data ?? [];
  const assetItems = useMemo(() => assets.filter((a) => a.kind === "asset"), [assets]);
  const liabilityItems = useMemo(() => assets.filter((a) => a.kind === "liability"), [assets]);

  const wallets = networthQuery.data?.breakdown.wallets ?? [];
  const walletsTotal = toNumber(networthQuery.data?.wallets_total);
  const assetsTotal = toNumber(networthQuery.data?.assets_total);
  const liabilitiesTotal = toNumber(networthQuery.data?.liabilities_total);
  const netWorth = toNumber(networthQuery.data?.net_worth);

  const isLoading = networthQuery.isLoading || assetsQuery.isLoading;
  const isError = networthQuery.isError || assetsQuery.isError;

  const handleRetry = () => {
    networthQuery.refetch();
    assetsQuery.refetch();
  };

  const categoryFields = (
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
            {CATEGORY_PRESETS.map((preset) => (
              <SelectItem key={preset.value} value={preset.value}>
                <div className="flex items-center gap-2">
                  <preset.icon className="w-3.5 h-3.5 text-muted-foreground" />
                  {preset.label}
                </div>
              </SelectItem>
            ))}
            <SelectItem value={CUSTOM_CATEGORY_VALUE}>
              <div className="flex items-center gap-2">
                <Plus className="w-3.5 h-3.5 text-muted-foreground" />
                Custom
              </div>
            </SelectItem>
          </SelectContent>
        </Select>
      </div>
      {formData.categoryValue === CUSTOM_CATEGORY_VALUE && (
        <div>
          <label className="text-sm font-medium text-foreground mb-1.5 block">Custom category</label>
          <Input
            placeholder="e.g. Jewelry"
            value={formData.customCategory}
            onChange={(e) => setFormData({ ...formData, customCategory: e.target.value })}
          />
        </div>
      )}
    </>
  );

  const formFields = (
    <div className="space-y-4 pt-4">
      <div>
        <label className="text-sm font-medium text-foreground mb-1.5 block">Name</label>
        <Input
          placeholder="e.g. Family Home"
          value={formData.name}
          onChange={(e) => setFormData({ ...formData, name: e.target.value })}
        />
      </div>
      {categoryFields}
      <div>
        <label className="text-sm font-medium text-foreground mb-1.5 block">Value</label>
        <Input
          type="number"
          step="0.01"
          placeholder="0.00"
          value={formData.value}
          onChange={(e) => setFormData({ ...formData, value: e.target.value })}
        />
      </div>
      <div>
        <label className="text-sm font-medium text-foreground mb-1.5 block">Note (optional)</label>
        <Textarea
          placeholder="Any extra detail..."
          value={formData.note}
          onChange={(e) => setFormData({ ...formData, note: e.target.value })}
        />
      </div>
      {formError && <p className="text-xs text-destructive">{formError}</p>}
    </div>
  );

  if (isLoading) {
    return (
      <AppLayout title="Net Worth" subtitle="What you own, minus what you owe">
        <div className="w-full max-w-6xl mx-auto space-y-6">
          <div className="bg-card rounded-xl border border-border p-8 shadow-soft">
            <Skeleton className="h-4 w-32 mb-3" />
            <Skeleton className="h-10 w-64 mb-4" />
            <div className="flex gap-3">
              <Skeleton className="h-8 w-28 rounded-full" />
              <Skeleton className="h-8 w-28 rounded-full" />
              <Skeleton className="h-8 w-28 rounded-full" />
            </div>
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            {Array.from({ length: 3 }).map((_, i) => (
              <div key={i} className="bg-card rounded-xl border border-border shadow-soft p-5">
                <Skeleton className="h-5 w-24 mb-4" />
                <Skeleton className="h-32 w-full" />
              </div>
            ))}
          </div>
        </div>
      </AppLayout>
    );
  }

  if (isError) {
    return (
      <AppLayout title="Net Worth" subtitle="What you own, minus what you owe">
        <div className="w-full max-w-6xl mx-auto">
          <div className="bg-card rounded-xl border border-border shadow-soft p-8 text-center space-y-4">
            <div className="w-12 h-12 rounded-full bg-destructive/10 flex items-center justify-center mx-auto">
              <AlertCircle className="w-6 h-6 text-destructive" />
            </div>
            <div>
              <p className="text-sm font-medium text-foreground">Couldn't load your net worth</p>
              <p className="text-xs text-muted-foreground mt-1">Please check your connection and try again.</p>
            </div>
            <Button onClick={handleRetry}>Retry</Button>
          </div>
        </div>
      </AppLayout>
    );
  }

  return (
    <AppLayout title="Net Worth" subtitle="What you own, minus what you owe">
      <div className="w-full max-w-6xl mx-auto space-y-6">
        {/* Hero Stat */}
        <div className="bg-card rounded-xl border border-border p-8 shadow-soft">
          <div className="flex items-center gap-2 mb-2">
            <div className="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center">
              <Scale className="w-4 h-4 text-primary" />
            </div>
            <span className="text-sm font-medium text-muted-foreground">Net Worth</span>
          </div>
          <p
            className={cn(
              "text-4xl font-bold",
              netWorth >= 0 ? "text-foreground" : "text-destructive"
            )}
          >
            {formatMoney(netWorth)}
          </p>
          <div className="flex flex-wrap gap-2 mt-5">
            <span className="inline-flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-full bg-info/10 text-info">
              <WalletIcon className="w-3.5 h-3.5" />
              Cash &amp; Wallets {formatMoney(walletsTotal)}
            </span>
            <span className="inline-flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-full bg-success/10 text-success">
              <TrendingUp className="w-3.5 h-3.5" />
              Assets +{formatMoney(assetsTotal)}
            </span>
            <span className="inline-flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-full bg-destructive/10 text-destructive">
              <TrendingDown className="w-3.5 h-3.5" />
              Liabilities -{formatMoney(liabilitiesTotal)}
            </span>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Wallets (read-only) */}
          <div className="bg-card rounded-xl border border-border shadow-soft overflow-hidden">
            <div className="p-4 border-b border-border bg-muted/30 flex items-center justify-between">
              <div>
                <h3 className="text-sm font-semibold text-foreground">Wallets</h3>
                <p className="text-xs text-muted-foreground">{wallets.length} wallet{wallets.length === 1 ? "" : "s"}</p>
              </div>
              <span className="text-sm font-semibold text-foreground">{formatMoney(walletsTotal)}</span>
            </div>
            {wallets.length === 0 ? (
              <div className="p-6 text-center">
                <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto mb-3">
                  <WalletIcon className="w-6 h-6 text-muted-foreground" />
                </div>
                <p className="text-sm text-muted-foreground">
                  No wallets yet — add an expense or income entry to create one.
                </p>
              </div>
            ) : (
              <div className="divide-y divide-border max-h-80 overflow-y-auto">
                {wallets.map((wallet) => (
                  <div key={wallet.id} className="flex items-center gap-3 p-3">
                    <div className="w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0 bg-info/10">
                      <WalletIcon className="w-4 h-4 text-info" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-foreground truncate">{wallet.name}</p>
                    </div>
                    <p className="text-sm font-semibold text-foreground">{formatMoney(toNumber(wallet.balance))}</p>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Assets */}
          <div className="bg-card rounded-xl border border-border shadow-soft overflow-hidden">
            <div className="p-4 border-b border-border bg-muted/30 flex items-center justify-between">
              <div>
                <h3 className="text-sm font-semibold text-foreground">Assets</h3>
                <p className="text-xs text-muted-foreground">{assetItems.length} item{assetItems.length === 1 ? "" : "s"}</p>
              </div>
              <span className="text-sm font-semibold text-foreground">{formatMoney(assetsTotal)}</span>
            </div>

            <div className="p-3 border-b border-border">
              <Dialog
                open={addDialogKind === "asset"}
                onOpenChange={(open) => (open ? openAddDialog("asset") : closeAddDialog())}
              >
                <DialogTrigger asChild>
                  <Button className="w-full gap-2" variant="outline" onClick={() => openAddDialog("asset")}>
                    <Plus className="w-4 h-4" />
                    {kindCopy.asset.addLabel}
                  </Button>
                </DialogTrigger>
                <DialogContent className="sm:max-w-md">
                  <DialogHeader>
                    <DialogTitle>{kindCopy.asset.addLabel}</DialogTitle>
                  </DialogHeader>
                  {formFields}
                  <div className="flex gap-2 pt-2">
                    <Button onClick={handleAdd} className="flex-1" disabled={createAssetMutation.isPending}>
                      {createAssetMutation.isPending ? "Adding..." : kindCopy.asset.addLabel}
                    </Button>
                    <Button variant="outline" onClick={closeAddDialog}>Cancel</Button>
                  </div>
                </DialogContent>
              </Dialog>
            </div>

            {assetItems.length === 0 ? (
              <div className="p-6 text-center">
                <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto mb-3">
                  <TrendingUp className="w-6 h-6 text-muted-foreground" />
                </div>
                <p className="text-sm text-muted-foreground">{kindCopy.asset.empty}</p>
              </div>
            ) : (
              <div className="divide-y divide-border max-h-80 overflow-y-auto">
                {assetItems.map((asset) => {
                  const Icon = getCategoryIcon(asset.category);
                  return (
                    <div key={asset.id} className="flex items-center gap-3 p-3 hover:bg-muted/30 transition-smooth group">
                      <div className="w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0 bg-success/10">
                        <Icon className="w-4 h-4 text-success" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-foreground truncate">{asset.name}</p>
                        <p className="text-xs text-muted-foreground">{getCategoryLabel(asset.category)}</p>
                      </div>
                      <p className="text-sm font-semibold text-foreground">{formatMoney(toNumber(asset.value))}</p>
                      <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-smooth">
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7 text-muted-foreground hover:text-foreground"
                          onClick={() => startEdit(asset)}
                        >
                          <Pencil className="w-3.5 h-3.5" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7 text-muted-foreground hover:text-destructive"
                          onClick={() => handleDelete(asset.id)}
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </Button>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Liabilities */}
          <div className="bg-card rounded-xl border border-border shadow-soft overflow-hidden">
            <div className="p-4 border-b border-border bg-muted/30 flex items-center justify-between">
              <div>
                <h3 className="text-sm font-semibold text-foreground">Liabilities</h3>
                <p className="text-xs text-muted-foreground">{liabilityItems.length} item{liabilityItems.length === 1 ? "" : "s"}</p>
              </div>
              <span className="text-sm font-semibold text-foreground">{formatMoney(liabilitiesTotal)}</span>
            </div>

            <div className="p-3 border-b border-border">
              <Dialog
                open={addDialogKind === "liability"}
                onOpenChange={(open) => (open ? openAddDialog("liability") : closeAddDialog())}
              >
                <DialogTrigger asChild>
                  <Button className="w-full gap-2" variant="outline" onClick={() => openAddDialog("liability")}>
                    <Plus className="w-4 h-4" />
                    {kindCopy.liability.addLabel}
                  </Button>
                </DialogTrigger>
                <DialogContent className="sm:max-w-md">
                  <DialogHeader>
                    <DialogTitle>{kindCopy.liability.addLabel}</DialogTitle>
                  </DialogHeader>
                  {formFields}
                  <div className="flex gap-2 pt-2">
                    <Button onClick={handleAdd} className="flex-1" disabled={createAssetMutation.isPending}>
                      {createAssetMutation.isPending ? "Adding..." : kindCopy.liability.addLabel}
                    </Button>
                    <Button variant="outline" onClick={closeAddDialog}>Cancel</Button>
                  </div>
                </DialogContent>
              </Dialog>
            </div>

            {liabilityItems.length === 0 ? (
              <div className="p-6 text-center">
                <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto mb-3">
                  <TrendingDown className="w-6 h-6 text-muted-foreground" />
                </div>
                <p className="text-sm text-muted-foreground">{kindCopy.liability.empty}</p>
              </div>
            ) : (
              <div className="divide-y divide-border max-h-80 overflow-y-auto">
                {liabilityItems.map((liability) => {
                  const Icon = getCategoryIcon(liability.category);
                  return (
                    <div key={liability.id} className="flex items-center gap-3 p-3 hover:bg-muted/30 transition-smooth group">
                      <div className="w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0 bg-destructive/10">
                        <Icon className="w-4 h-4 text-destructive" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-foreground truncate">{liability.name}</p>
                        <p className="text-xs text-muted-foreground">{getCategoryLabel(liability.category)}</p>
                      </div>
                      <p className="text-sm font-semibold text-foreground">{formatMoney(toNumber(liability.value))}</p>
                      <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-smooth">
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7 text-muted-foreground hover:text-foreground"
                          onClick={() => startEdit(liability)}
                        >
                          <Pencil className="w-3.5 h-3.5" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7 text-muted-foreground hover:text-destructive"
                          onClick={() => handleDelete(liability.id)}
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </Button>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </div>

        {/* Edit Modal */}
        <Dialog open={!!editingAsset} onOpenChange={(open) => !open && closeEditDialog()}>
          <DialogContent className="sm:max-w-md">
            <DialogHeader>
              <DialogTitle>Edit {editingAsset ? kindCopy[editingAsset.kind].title.replace(/s$/, "") : ""}</DialogTitle>
            </DialogHeader>
            {formFields}
            <div className="flex gap-2 pt-2">
              <Button onClick={handleUpdate} className="flex-1" disabled={updateAssetMutation.isPending}>
                {updateAssetMutation.isPending ? "Saving..." : "Save Changes"}
              </Button>
              <Button variant="outline" onClick={closeEditDialog}>Cancel</Button>
            </div>
          </DialogContent>
        </Dialog>
      </div>
    </AppLayout>
  );
}
