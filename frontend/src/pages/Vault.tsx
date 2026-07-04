import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { useToast } from "@/hooks/use-toast";
import { cn } from "@/lib/utils";
import {
  ShieldCheck,
  Lock,
  Unlock,
  Loader2,
  AlertCircle,
  AlertTriangle,
  Plus,
  Pencil,
  Trash2,
  Eye,
  EyeOff,
  Copy,
  Download,
  Upload,
  FileText,
  Calendar as CalendarIcon,
  KeyRound,
  File as FileIcon,
  ShieldAlert,
} from "lucide-react";
import {
  getVaultConfig,
  setupVault,
  listVaultItems,
  getVaultItem,
  createVaultItem,
  updateVaultItem,
  deleteVaultItem,
  deleteVault,
  VAULT_TITLE_PLACEHOLDER,
  type VaultItemType,
  type VaultItemListResponse,
  type NotePayload,
  type DatePayload,
  type CredentialPayload,
  type FilePayload,
} from "@/api/vault.api";
import {
  createVaultSetupMaterial,
  tryUnlockVault,
  encryptJson,
  encryptBytes,
  decryptBytes,
  decryptJson,
  VAULT_KDF_ITERATIONS,
} from "@/lib/vaultCrypto";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const IDLE_LOCK_MS = 5 * 60 * 1000; // auto-lock after 5 minutes of inactivity
const MAX_FILE_BYTES = 10 * 1024 * 1024; // 10MB cap, encrypted client-side

type TabKey = "note" | "date" | "credential" | "file";

const TAB_META: Record<TabKey, { label: string; icon: typeof FileText }> = {
  note: { label: "Notes", icon: FileText },
  date: { label: "Dates", icon: CalendarIcon },
  credential: { label: "Credentials", icon: KeyRound },
  file: { label: "Files", icon: FileIcon },
};

// Decrypted, in-memory-only view of a vault item. Never persisted.
interface DecryptedItem {
  id: number;
  item_type: VaultItemType;
  title: string;
  payload: NotePayload | DatePayload | CredentialPayload | FilePayload | null;
  decryptFailed: boolean;
  has_file: boolean;
  file_size: number | null;
  created_at: string;
  updated_at: string;
}

function formatBytes(n: number | null): string {
  if (!n && n !== 0) return "";
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

function isAxios404(err: unknown): boolean {
  return (
    typeof err === "object" &&
    err !== null &&
    "response" in err &&
    (err as { response?: { status?: number } }).response?.status === 404
  );
}

export default function Vault() {
  const queryClient = useQueryClient();
  const { toast } = useToast();

  // The derived AES key lives ONLY in component state — never written to
  // localStorage/sessionStorage/IndexedDB. Locking (manual or idle-timeout)
  // simply drops this reference; nothing to "clear" on the wire since the
  // passphrase never left the browser.
  const [vaultKey, setVaultKey] = useState<CryptoKey | null>(null);

  const configQuery = useQuery({
    queryKey: ["vault", "config"],
    queryFn: getVaultConfig,
    retry: false,
  });

  const notSetUp = configQuery.isError && isAxios404(configQuery.error);
  const isUnlocked = !!vaultKey && !!configQuery.data;

  // ---- idle auto-lock -------------------------------------------------
  const idleTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const lockVault = () => {
    setVaultKey(null);
  };

  useEffect(() => {
    if (!isUnlocked) return;

    const resetTimer = () => {
      if (idleTimer.current) clearTimeout(idleTimer.current);
      idleTimer.current = setTimeout(() => {
        lockVault();
        toast({
          title: "Vault locked",
          description: "Locked automatically after 5 minutes of inactivity.",
        });
      }, IDLE_LOCK_MS);
    };

    const activityEvents = ["mousemove", "mousedown", "keydown", "scroll", "touchstart"];
    activityEvents.forEach((ev) => window.addEventListener(ev, resetTimer));
    resetTimer();

    return () => {
      activityEvents.forEach((ev) => window.removeEventListener(ev, resetTimer));
      if (idleTimer.current) clearTimeout(idleTimer.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isUnlocked]);

  if (configQuery.isLoading) {
    return (
      <AppLayout title="Secret Vault" subtitle="Zero-knowledge encrypted storage">
        <div className="p-12 text-center">
          <Loader2 className="w-6 h-6 animate-spin mx-auto mb-3 text-muted-foreground" />
          <p className="text-muted-foreground">Loading vault...</p>
        </div>
      </AppLayout>
    );
  }

  if (configQuery.isError && !notSetUp) {
    return (
      <AppLayout title="Secret Vault" subtitle="Zero-knowledge encrypted storage">
        <div className="p-12 text-center">
          <div className="w-12 h-12 rounded-full bg-destructive/10 flex items-center justify-center mx-auto mb-3">
            <AlertCircle className="w-6 h-6 text-destructive" />
          </div>
          <p className="text-destructive font-medium">Failed to load vault</p>
          <p className="text-sm text-muted-foreground mt-1">Please try again.</p>
        </div>
      </AppLayout>
    );
  }

  if (notSetUp) {
    return <VaultSetupScreen onSetUp={(key) => setVaultKey(key)} />;
  }

  if (!isUnlocked && configQuery.data) {
    return <VaultUnlockScreen config={configQuery.data} onUnlock={(key) => setVaultKey(key)} />;
  }

  if (isUnlocked && configQuery.data) {
    return <VaultUnlockedView vaultKey={vaultKey} onLock={lockVault} />;
  }

  return null;
}

// ---------------------------------------------------------------------------
// Setup screen (first time)
// ---------------------------------------------------------------------------

function VaultSetupScreen({ onSetUp }: { onSetUp: (key: CryptoKey) => void }) {
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const [passphrase, setPassphrase] = useState("");
  const [confirm, setConfirm] = useState("");
  const [acknowledged, setAcknowledged] = useState(false);

  const setupMutation = useMutation({
    mutationFn: async () => {
      const material = await createVaultSetupMaterial(passphrase);
      const config = await setupVault({
        kdf_salt: material.kdf_salt,
        kdf_iterations: material.kdf_iterations,
        canary_ct: material.canary_ct,
        canary_iv: material.canary_iv,
      });
      return { config, key: material.key };
    },
    onSuccess: ({ config, key }) => {
      queryClient.setQueryData(["vault", "config"], config);
      onSetUp(key);
      toast({ title: "Vault created", description: "Your secret vault is ready to use." });
    },
    onError: () => {
      toast({
        title: "Setup failed",
        description: "Could not create the vault. Please try again.",
        variant: "destructive",
      });
    },
  });

  const canSubmit =
    passphrase.length >= 8 && passphrase === confirm && acknowledged && !setupMutation.isPending;

  return (
    <AppLayout title="Secret Vault" subtitle="Zero-knowledge encrypted storage">
      <div className="w-full max-w-lg mx-auto">
        <div className="bg-card rounded-lg border border-border shadow-soft p-6 sm:p-8">
          <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center mb-4">
            <ShieldCheck className="w-6 h-6 text-primary" />
          </div>
          <h2 className="text-lg font-semibold text-foreground">Create your Secret Vault</h2>
          <p className="text-sm text-muted-foreground mt-1">
            Notes, dates, credentials, and files you store here are encrypted in your browser
            before they're ever sent to the server. BudgetBox only ever stores ciphertext — it
            has no way to read your data, and no way to help you recover it.
          </p>

          <div className="mt-4 rounded-md border border-destructive/40 bg-destructive/10 p-3 flex gap-2">
            <AlertTriangle className="w-4 h-4 text-destructive flex-shrink-0 mt-0.5" />
            <p className="text-xs text-destructive-foreground">
              <span className="font-semibold">There is no password reset for the vault.</span>{" "}
              If you forget this passphrase, your vault contents are permanently and
              irrecoverably lost. This is a deliberate trade-off of zero-knowledge encryption —
              not even BudgetBox support can help.
            </p>
          </div>

          <div className="space-y-4 mt-6">
            <div>
              <Label className="mb-1.5 block">Vault passphrase</Label>
              <Input
                type="password"
                placeholder="At least 8 characters"
                value={passphrase}
                onChange={(e) => setPassphrase(e.target.value)}
                autoComplete="new-password"
              />
            </div>
            <div>
              <Label className="mb-1.5 block">Confirm passphrase</Label>
              <Input
                type="password"
                placeholder="Re-enter your passphrase"
                value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
                autoComplete="new-password"
              />
              {confirm.length > 0 && confirm !== passphrase && (
                <p className="text-xs text-destructive mt-1">Passphrases do not match.</p>
              )}
            </div>

            <label className="flex items-start gap-2 text-sm text-foreground cursor-pointer">
              <input
                type="checkbox"
                className="mt-0.5"
                checked={acknowledged}
                onChange={(e) => setAcknowledged(e.target.checked)}
              />
              <span>
                I understand that forgetting this passphrase means permanent, unrecoverable
                loss of everything stored in my vault.
              </span>
            </label>

            <Button
              className="w-full gap-2"
              disabled={!canSubmit}
              onClick={() => setupMutation.mutate()}
            >
              {setupMutation.isPending ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <ShieldCheck className="w-4 h-4" />
              )}
              Create Vault
            </Button>
          </div>
        </div>
      </div>
    </AppLayout>
  );
}

// ---------------------------------------------------------------------------
// Unlock screen (config exists, key not yet held in memory)
// ---------------------------------------------------------------------------

function VaultUnlockScreen({
  config,
  onUnlock,
}: {
  config: { kdf_salt: string; kdf_iterations: number; canary_ct: string; canary_iv: string };
  onUnlock: (key: CryptoKey) => void;
}) {
  const [passphrase, setPassphrase] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isUnlocking, setIsUnlocking] = useState(false);

  const attemptUnlock = async () => {
    if (!passphrase) return;
    setIsUnlocking(true);
    setError(null);
    try {
      const key = await tryUnlockVault(passphrase, config);
      if (!key) {
        setError("Incorrect passphrase.");
        return;
      }
      onUnlock(key);
    } catch {
      setError("Incorrect passphrase.");
    } finally {
      setIsUnlocking(false);
    }
  };

  return (
    <AppLayout title="Secret Vault" subtitle="Zero-knowledge encrypted storage">
      <div className="w-full max-w-md mx-auto">
        <div className="bg-card rounded-lg border border-border shadow-soft p-6 sm:p-8 text-center">
          <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto mb-4">
            <Lock className="w-6 h-6 text-foreground" />
          </div>
          <h2 className="text-lg font-semibold text-foreground">Vault Locked</h2>
          <p className="text-sm text-muted-foreground mt-1 mb-6">
            Enter your passphrase to decrypt your vault for this session.
          </p>

          <div className="space-y-3 text-left">
            <Input
              type="password"
              placeholder="Vault passphrase"
              value={passphrase}
              autoFocus
              onChange={(e) => {
                setPassphrase(e.target.value);
                setError(null);
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter") attemptUnlock();
              }}
            />
            {error && (
              <p className="text-xs text-destructive flex items-center gap-1">
                <AlertCircle className="w-3.5 h-3.5" /> {error}
              </p>
            )}
            <Button
              className="w-full gap-2"
              disabled={!passphrase || isUnlocking}
              onClick={attemptUnlock}
            >
              {isUnlocking ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <Unlock className="w-4 h-4" />
              )}
              Unlock
            </Button>
          </div>
        </div>
      </div>
    </AppLayout>
  );
}

// ---------------------------------------------------------------------------
// Unlocked view: tabs, list, CRUD dialogs, danger zone
// ---------------------------------------------------------------------------

function VaultUnlockedView({
  vaultKey,
  onLock,
}: {
  vaultKey: CryptoKey;
  onLock: () => void;
}) {
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const [tab, setTab] = useState<TabKey>("note");
  const [decrypted, setDecrypted] = useState<DecryptedItem[]>([]);
  const [isDecrypting, setIsDecrypting] = useState(true);

  const [editorOpen, setEditorOpen] = useState(false);
  const [editingItem, setEditingItem] = useState<DecryptedItem | null>(null);
  const [dangerOpen, setDangerOpen] = useState(false);

  const itemsQuery = useQuery({
    queryKey: ["vault", "items"],
    queryFn: () => listVaultItems(),
  });

  const invalidateItems = () => queryClient.invalidateQueries({ queryKey: ["vault", "items"] });

  // Decrypt every item's payload (which also carries its title) once the
  // list loads or changes. This is why the vault list endpoint returns
  // payload_ct/iv for every item — no per-item fetch needed.
  useEffect(() => {
    let cancelled = false;
    if (!itemsQuery.data) {
      setIsDecrypting(false);
      return;
    }
    setIsDecrypting(true);
    (async () => {
      const results = await Promise.all(
        itemsQuery.data.map(async (it: VaultItemListResponse): Promise<DecryptedItem> => {
          try {
            const payload = await decryptJson<NotePayload | DatePayload | CredentialPayload | FilePayload>(
              vaultKey,
              it.payload_ct,
              it.iv
            );
            return {
              id: it.id,
              item_type: it.item_type,
              title: payload.title || "(untitled)",
              payload,
              decryptFailed: false,
              has_file: it.has_file,
              file_size: it.file_size,
              created_at: it.created_at,
              updated_at: it.updated_at,
            };
          } catch {
            return {
              id: it.id,
              item_type: it.item_type,
              title: "(unable to decrypt)",
              payload: null,
              decryptFailed: true,
              has_file: it.has_file,
              file_size: it.file_size,
              created_at: it.created_at,
              updated_at: it.updated_at,
            };
          }
        })
      );
      if (!cancelled) {
        setDecrypted(results);
        setIsDecrypting(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [itemsQuery.data, vaultKey]);

  const deleteItemMutation = useMutation({
    mutationFn: (id: number) => deleteVaultItem(id),
    onSuccess: () => {
      invalidateItems();
      toast({ title: "Item deleted" });
    },
    onError: () => {
      toast({ title: "Couldn't delete item", description: "Please try again.", variant: "destructive" });
    },
  });

  const nukeMutation = useMutation({
    mutationFn: () => deleteVault(),
    onSuccess: () => {
      onLock();
      queryClient.invalidateQueries({ queryKey: ["vault"] });
      toast({ title: "Vault deleted", description: "All vault data has been permanently erased." });
    },
    onError: () => {
      toast({ title: "Couldn't delete vault", description: "Please try again.", variant: "destructive" });
    },
  });

  const filtered = decrypted.filter((d) => d.item_type === tab);
  const counts = useMemo(() => {
    const c: Record<TabKey, number> = { note: 0, date: 0, credential: 0, file: 0 };
    decrypted.forEach((d) => {
      c[d.item_type] += 1;
    });
    return c;
  }, [decrypted]);

  const openCreate = () => {
    setEditingItem(null);
    setEditorOpen(true);
  };

  const openEdit = (item: DecryptedItem) => {
    setEditingItem(item);
    setEditorOpen(true);
  };

  return (
    <AppLayout title="Secret Vault" subtitle="Zero-knowledge encrypted storage">
      <div className="w-full max-w-4xl mx-auto space-y-6">
        <div className="flex items-center justify-between gap-3 flex-wrap">
          <div className="flex items-center gap-2 text-sm text-success">
            <Unlock className="w-4 h-4" />
            <span>Vault unlocked for this session</span>
          </div>
          <Button variant="outline" size="sm" className="gap-2" onClick={onLock}>
            <Lock className="w-4 h-4" />
            Lock now
          </Button>
        </div>

        <div className="flex flex-col sm:flex-row gap-3 sm:items-center sm:justify-between">
          <Tabs value={tab} onValueChange={(v) => setTab(v as TabKey)}>
            <TabsList>
              {(Object.keys(TAB_META) as TabKey[]).map((key) => {
                const Icon = TAB_META[key].icon;
                return (
                  <TabsTrigger key={key} value={key} className="gap-1.5">
                    <Icon className="w-3.5 h-3.5" />
                    {TAB_META[key].label} ({counts[key]})
                  </TabsTrigger>
                );
              })}
            </TabsList>
          </Tabs>

          <Button className="gap-2" onClick={openCreate}>
            <Plus className="w-4 h-4" />
            Add {TAB_META[tab].label.replace(/s$/, "")}
          </Button>
        </div>

        <div className="bg-card rounded-lg border border-border shadow-soft">
          {itemsQuery.isLoading || isDecrypting ? (
            <div className="p-12 text-center">
              <Loader2 className="w-6 h-6 animate-spin mx-auto mb-3 text-muted-foreground" />
              <p className="text-muted-foreground">Decrypting vault...</p>
            </div>
          ) : itemsQuery.isError ? (
            <div className="p-12 text-center">
              <AlertCircle className="w-6 h-6 text-destructive mx-auto mb-3" />
              <p className="text-destructive font-medium">Failed to load vault items</p>
            </div>
          ) : filtered.length === 0 ? (
            <div className="p-12 text-center">
              <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto mb-3">
                {(() => {
                  const Icon = TAB_META[tab].icon;
                  return <Icon className="w-6 h-6 text-muted-foreground" />;
                })()}
              </div>
              <p className="text-muted-foreground">No {TAB_META[tab].label.toLowerCase()} yet</p>
            </div>
          ) : (
            <div className="divide-y divide-border">
              {filtered.map((item) => (
                <VaultItemRow
                  key={item.id}
                  item={item}
                  vaultKey={vaultKey}
                  onEdit={() => openEdit(item)}
                  onDelete={() => deleteItemMutation.mutate(item.id)}
                  deletePending={deleteItemMutation.isPending && deleteItemMutation.variables === item.id}
                />
              ))}
            </div>
          )}
        </div>

        {/* Danger zone */}
        <div className="bg-card rounded-lg border border-destructive/30 shadow-soft p-4 sm:p-6">
          <div className="flex items-center gap-2 text-destructive font-medium mb-1">
            <ShieldAlert className="w-4 h-4" />
            Danger zone
          </div>
          <p className="text-sm text-muted-foreground mb-3">
            Permanently delete this vault and everything in it. This cannot be undone.
          </p>
          <Button variant="destructive" size="sm" onClick={() => setDangerOpen(true)}>
            Delete entire vault
          </Button>
        </div>
      </div>

      {editorOpen && (
        <ItemEditorDialog
          open={editorOpen}
          onOpenChange={setEditorOpen}
          itemType={tab}
          vaultKey={vaultKey}
          editingItem={editingItem}
          onSaved={() => {
            invalidateItems();
            setEditorOpen(false);
          }}
        />
      )}

      <DeleteVaultDialog
        open={dangerOpen}
        onOpenChange={setDangerOpen}
        onConfirm={() => nukeMutation.mutate()}
        pending={nukeMutation.isPending}
      />
    </AppLayout>
  );
}

// ---------------------------------------------------------------------------
// Row renderer per item type
// ---------------------------------------------------------------------------

function VaultItemRow({
  item,
  vaultKey,
  onEdit,
  onDelete,
  deletePending,
}: {
  item: DecryptedItem;
  vaultKey: CryptoKey;
  onEdit: () => void;
  onDelete: () => void;
  deletePending: boolean;
}) {
  const { toast } = useToast();
  const [showPassword, setShowPassword] = useState(false);
  const [downloading, setDownloading] = useState(false);

  const credential = item.item_type === "credential" ? (item.payload as CredentialPayload | null) : null;
  const dateInfo = item.item_type === "date" ? (item.payload as DatePayload | null) : null;
  const note = item.item_type === "note" ? (item.payload as NotePayload | null) : null;
  const filePayload = item.item_type === "file" ? (item.payload as FilePayload | null) : null;

  const copy = async (value: string, label: string) => {
    try {
      await navigator.clipboard.writeText(value);
      toast({ title: `${label} copied to clipboard` });
    } catch {
      toast({ title: "Copy failed", variant: "destructive" });
    }
  };

  const handleDownload = async () => {
    setDownloading(true);
    try {
      const detail = await getVaultItem(item.id);
      if (!detail.file_data_b64 || !detail.file_iv) {
        throw new Error("No file data");
      }
      const plainBuf = await decryptBytes(vaultKey, detail.file_data_b64, detail.file_iv);
      const mimetype = filePayload?.mimetype || "application/octet-stream";
      const filename = filePayload?.filename || item.title || "download";
      const blob = new Blob([plainBuf], { type: mimetype });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch {
      toast({ title: "Download failed", description: "Could not decrypt file.", variant: "destructive" });
    } finally {
      setDownloading(false);
    }
  };

  return (
    <div className="flex items-start sm:items-center gap-3 p-4 hover:bg-muted/30 transition-smooth group">
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 flex-wrap">
          <span className={cn("text-sm font-medium", item.decryptFailed ? "text-destructive italic" : "text-foreground")}>
            {item.title}
          </span>
          {item.item_type === "date" && dateInfo?.recur_yearly && (
            <span className="text-xs font-medium px-2 py-0.5 rounded-full bg-primary/10 text-primary">Yearly</span>
          )}
        </div>

        {note && <p className="text-xs text-muted-foreground mt-1 line-clamp-2">{note.text}</p>}

        {dateInfo && (
          <p className="text-xs text-muted-foreground mt-1 flex items-center gap-1">
            <CalendarIcon className="w-3 h-3" />
            {dateInfo.date}
            {dateInfo.note ? ` — ${dateInfo.note}` : ""}
          </p>
        )}

        {credential && (
          <div className="flex items-center gap-3 mt-1 flex-wrap">
            <span className="text-xs text-muted-foreground">{credential.site}</span>
            <span className="text-xs text-muted-foreground">{credential.username}</span>
            <span className="flex items-center gap-1 text-xs font-mono text-foreground">
              {showPassword ? credential.password : "•".repeat(Math.min(credential.password.length || 8, 12))}
              <button
                className="text-muted-foreground hover:text-foreground"
                onClick={() => setShowPassword((s) => !s)}
                aria-label={showPassword ? "Hide password" : "Show password"}
              >
                {showPassword ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
              </button>
              <button
                className="text-muted-foreground hover:text-foreground"
                onClick={() => copy(credential.password, "Password")}
                aria-label="Copy password"
              >
                <Copy className="w-3.5 h-3.5" />
              </button>
            </span>
          </div>
        )}

        {filePayload && (
          <p className="text-xs text-muted-foreground mt-1">
            {filePayload.filename} · {formatBytes(item.file_size)}
          </p>
        )}
      </div>

      <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-smooth flex-shrink-0">
        {item.item_type === "file" && item.has_file && (
          <Button
            variant="ghost"
            size="icon"
            className="h-8 w-8 text-muted-foreground hover:text-foreground"
            onClick={handleDownload}
            disabled={downloading}
            aria-label="Download file"
          >
            {downloading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Download className="w-4 h-4" />}
          </Button>
        )}
        {item.item_type !== "file" && (
          <Button
            variant="ghost"
            size="icon"
            className="h-8 w-8 text-muted-foreground hover:text-foreground"
            onClick={onEdit}
            aria-label="Edit item"
          >
            <Pencil className="w-4 h-4" />
          </Button>
        )}
        <Button
          variant="ghost"
          size="icon"
          className="h-8 w-8 text-muted-foreground hover:text-destructive"
          onClick={onDelete}
          disabled={deletePending}
          aria-label="Delete item"
        >
          {deletePending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Trash2 className="w-4 h-4" />}
        </Button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Create / edit dialog (per item type)
// ---------------------------------------------------------------------------

function ItemEditorDialog({
  open,
  onOpenChange,
  itemType,
  vaultKey,
  editingItem,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  itemType: TabKey;
  vaultKey: CryptoKey;
  editingItem: DecryptedItem | null;
  onSaved: () => void;
}) {
  const { toast } = useToast();
  const isEditing = !!editingItem;

  // Note fields
  const [noteTitle, setNoteTitle] = useState("");
  const [noteText, setNoteText] = useState("");

  // Date fields
  const [dateTitle, setDateTitle] = useState("");
  const [dateValue, setDateValue] = useState("");
  const [recurYearly, setRecurYearly] = useState(false);
  const [dateNote, setDateNote] = useState("");

  // Credential fields
  const [credTitle, setCredTitle] = useState("");
  const [credSite, setCredSite] = useState("");
  const [credUsername, setCredUsername] = useState("");
  const [credPassword, setCredPassword] = useState("");
  const [credNote, setCredNote] = useState("");
  const [showPw, setShowPw] = useState(false);

  // File fields
  const [fileTitle, setFileTitle] = useState("");
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [fileError, setFileError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    if (editingItem) {
      const p = editingItem.payload;
      if (editingItem.item_type === "note" && p) {
        const note = p as NotePayload;
        setNoteTitle(note.title);
        setNoteText(note.text);
      } else if (editingItem.item_type === "date" && p) {
        const d = p as DatePayload;
        setDateTitle(d.title);
        setDateValue(d.date);
        setRecurYearly(d.recur_yearly);
        setDateNote(d.note);
      } else if (editingItem.item_type === "credential" && p) {
        const c = p as CredentialPayload;
        setCredTitle(c.title);
        setCredSite(c.site);
        setCredUsername(c.username);
        setCredPassword(c.password);
        setCredNote(c.note);
      }
    } else {
      setNoteTitle("");
      setNoteText("");
      setDateTitle("");
      setDateValue("");
      setRecurYearly(false);
      setDateNote("");
      setCredTitle("");
      setCredSite("");
      setCredUsername("");
      setCredPassword("");
      setCredNote("");
      setFileTitle("");
      setSelectedFile(null);
      setFileError(null);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, editingItem]);

  const saveMutation = useMutation({
    mutationFn: async () => {
      if (itemType === "file") {
        if (!editingItem) {
          if (!selectedFile) throw new Error("No file selected");
          if (selectedFile.size > MAX_FILE_BYTES) throw new Error("File too large");
          const buf = await selectedFile.arrayBuffer();
          const fileBlob = await encryptBytes(vaultKey, buf);
          const payload: FilePayload = {
            title: fileTitle.trim() || selectedFile.name,
            filename: selectedFile.name,
            mimetype: selectedFile.type || "application/octet-stream",
          };
          const payloadBlob = await encryptJson(vaultKey, payload);
          await createVaultItem({
            item_type: "file",
            title_ct: VAULT_TITLE_PLACEHOLDER,
            payload_ct: payloadBlob.ct_b64,
            iv: payloadBlob.iv_b64,
            file_data_b64: fileBlob.ct_b64,
            file_iv: fileBlob.iv_b64,
          });
        }
        return;
      }

      let payload: NotePayload | DatePayload | CredentialPayload;
      if (itemType === "note") {
        payload = { title: noteTitle.trim() || "Untitled note", text: noteText };
      } else if (itemType === "date") {
        payload = {
          title: dateTitle.trim() || "Untitled date",
          date: dateValue,
          recur_yearly: recurYearly,
          note: dateNote,
        };
      } else {
        payload = {
          title: credTitle.trim() || "Untitled credential",
          site: credSite,
          username: credUsername,
          password: credPassword,
          note: credNote,
        };
      }

      const blob = await encryptJson(vaultKey, payload);

      if (isEditing && editingItem) {
        await updateVaultItem(editingItem.id, {
          payload_ct: blob.ct_b64,
          iv: blob.iv_b64,
        });
      } else {
        await createVaultItem({
          item_type: itemType,
          title_ct: VAULT_TITLE_PLACEHOLDER,
          payload_ct: blob.ct_b64,
          iv: blob.iv_b64,
        });
      }
    },
    onSuccess: () => {
      onSaved();
      toast({ title: isEditing ? "Item updated" : "Item added" });
    },
    onError: (err: unknown) => {
      const message = err instanceof Error ? err.message : "Please try again.";
      toast({ title: "Save failed", description: message, variant: "destructive" });
    },
  });

  const onFilePicked = (f: File | null) => {
    setFileError(null);
    if (f && f.size > MAX_FILE_BYTES) {
      setFileError("File exceeds the 10MB limit.");
      setSelectedFile(null);
      return;
    }
    setSelectedFile(f);
  };

  const canSubmit = (() => {
    if (itemType === "file") return !isEditing && !!selectedFile && !fileError;
    if (itemType === "date") return !!dateValue;
    return true;
  })();

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>
            {isEditing ? "Edit" : "Add"} {TAB_META[itemType].label.replace(/s$/, "")}
          </DialogTitle>
          <DialogDescription>
            Encrypted in your browser before it's sent — BudgetBox never sees the plaintext.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 pt-2">
          {itemType === "note" && (
            <>
              <div>
                <Label className="mb-1.5 block">Title</Label>
                <Input value={noteTitle} onChange={(e) => setNoteTitle(e.target.value)} placeholder="Note title" />
              </div>
              <div>
                <Label className="mb-1.5 block">Text</Label>
                <Textarea
                  value={noteText}
                  onChange={(e) => setNoteText(e.target.value)}
                  placeholder="Write your note..."
                  rows={6}
                />
              </div>
            </>
          )}

          {itemType === "date" && (
            <>
              <div>
                <Label className="mb-1.5 block">Title</Label>
                <Input value={dateTitle} onChange={(e) => setDateTitle(e.target.value)} placeholder="e.g. Anniversary" />
              </div>
              <div className="grid grid-cols-2 gap-4 items-end">
                <div>
                  <Label className="mb-1.5 block">Date</Label>
                  <Input type="date" value={dateValue} onChange={(e) => setDateValue(e.target.value)} />
                </div>
                <div className="flex items-center gap-2 pb-2">
                  <Switch checked={recurYearly} onCheckedChange={setRecurYearly} id="recur-yearly" />
                  <Label htmlFor="recur-yearly" className="cursor-pointer">Repeats yearly</Label>
                </div>
              </div>
              <div>
                <Label className="mb-1.5 block">Note</Label>
                <Textarea value={dateNote} onChange={(e) => setDateNote(e.target.value)} rows={3} />
              </div>
            </>
          )}

          {itemType === "credential" && (
            <>
              <div>
                <Label className="mb-1.5 block">Title</Label>
                <Input value={credTitle} onChange={(e) => setCredTitle(e.target.value)} placeholder="e.g. Gmail" />
              </div>
              <div>
                <Label className="mb-1.5 block">Site / URL</Label>
                <Input value={credSite} onChange={(e) => setCredSite(e.target.value)} />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <Label className="mb-1.5 block">Username</Label>
                  <Input value={credUsername} onChange={(e) => setCredUsername(e.target.value)} />
                </div>
                <div>
                  <Label className="mb-1.5 block">Password</Label>
                  <div className="relative">
                    <Input
                      type={showPw ? "text" : "password"}
                      value={credPassword}
                      onChange={(e) => setCredPassword(e.target.value)}
                      className="pr-9"
                    />
                    <button
                      type="button"
                      className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                      onClick={() => setShowPw((s) => !s)}
                      aria-label={showPw ? "Hide password" : "Show password"}
                    >
                      {showPw ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                    </button>
                  </div>
                </div>
              </div>
              <div>
                <Label className="mb-1.5 block">Note</Label>
                <Textarea value={credNote} onChange={(e) => setCredNote(e.target.value)} rows={3} />
              </div>
            </>
          )}

          {itemType === "file" && !isEditing && (
            <>
              <div>
                <Label className="mb-1.5 block">Title (optional)</Label>
                <Input
                  value={fileTitle}
                  onChange={(e) => setFileTitle(e.target.value)}
                  placeholder="Defaults to filename"
                />
              </div>
              <div>
                <Label className="mb-1.5 block">File (max 10MB)</Label>
                <label className="flex items-center gap-2 border border-dashed border-input rounded-md p-4 cursor-pointer hover:bg-muted/30 transition-smooth">
                  <Upload className="w-4 h-4 text-muted-foreground" />
                  <span className="text-sm text-muted-foreground">
                    {selectedFile ? selectedFile.name : "Click to choose a file"}
                  </span>
                  <input
                    type="file"
                    className="hidden"
                    onChange={(e) => onFilePicked(e.target.files?.[0] ?? null)}
                  />
                </label>
                {fileError && <p className="text-xs text-destructive mt-1">{fileError}</p>}
              </div>
            </>
          )}
          {itemType === "file" && isEditing && (
            <p className="text-sm text-muted-foreground">Files cannot be edited in place — delete and re-upload.</p>
          )}
        </div>

        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button
            onClick={() => saveMutation.mutate()}
            disabled={!canSubmit || saveMutation.isPending}
            className="gap-2"
          >
            {saveMutation.isPending && <Loader2 className="w-4 h-4 animate-spin" />}
            {isEditing ? "Save Changes" : "Add"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Delete-vault danger dialog (double confirmation)
// ---------------------------------------------------------------------------

function DeleteVaultDialog({
  open,
  onOpenChange,
  onConfirm,
  pending,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onConfirm: () => void;
  pending: boolean;
}) {
  const [confirmText, setConfirmText] = useState("");

  useEffect(() => {
    if (!open) setConfirmText("");
  }, [open]);

  const canDelete = confirmText === "DELETE" && !pending;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-destructive">
            <ShieldAlert className="w-5 h-5" />
            Delete entire vault
          </DialogTitle>
          <DialogDescription>
            This permanently deletes your vault configuration and every note, date, credential,
            and file inside it. This action cannot be undone and there is no backup — because
            BudgetBox never had the ability to read your data in the first place.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-2 pt-2">
          <Label className="block text-sm">
            Type <span className="font-mono font-semibold">DELETE</span> to confirm
          </Label>
          <Input value={confirmText} onChange={(e) => setConfirmText(e.target.value)} placeholder="DELETE" />
        </div>

        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button variant="destructive" disabled={!canDelete} onClick={onConfirm} className="gap-2">
            {pending && <Loader2 className="w-4 h-4 animate-spin" />}
            Permanently delete vault
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
