import api from "./axios";

// Mirrors backend app/vault/schemas.py + router.py. The backend is a
// zero-knowledge blind store: every field it sees is ciphertext (or, for
// title_ct, an inert placeholder — see the note on VaultItemCreatePayload
// below). It never receives a passphrase or derived key.

export type VaultItemType = "note" | "date" | "credential" | "file";

export interface VaultConfigResponse {
  id: number;
  kdf_salt: string;
  kdf_iterations: number;
  canary_ct: string;
  canary_iv: string;
  created_at: string;
}

export interface VaultSetupPayload {
  kdf_salt: string;
  kdf_iterations: number;
  canary_ct: string;
  canary_iv: string;
}

// The backend schema (VaultItemCreate) has exactly ONE `iv` field per item,
// shared between title and payload. AES-GCM must never reuse an IV under
// the same key, so we can't encrypt title and payload separately with two
// IVs into one slot. Instead: the real title lives INSIDE the encrypted
// payload JSON (see NotePayload/DatePayload/etc. below), and `title_ct` is
// set to a fixed, non-reversible placeholder string. Titles for list views
// are recovered by decrypting each item's payload_ct client-side after
// unlock (see Vault.tsx) — the list endpoint conveniently already includes
// payload_ct + iv for every item, so no extra per-item fetch is needed.
export const VAULT_TITLE_PLACEHOLDER = "enc";

export interface VaultItemCreatePayload {
  item_type: VaultItemType;
  title_ct: string;
  payload_ct: string;
  iv: string;
  file_data_b64?: string | null;
  file_iv?: string | null;
}

export interface VaultItemUpdatePayload {
  title_ct?: string;
  payload_ct?: string;
  iv?: string;
  file_data_b64?: string | null;
  file_iv?: string | null;
}

export interface VaultItemListResponse {
  id: number;
  item_type: VaultItemType;
  title_ct: string;
  payload_ct: string;
  iv: string;
  has_file: boolean;
  file_size: number | null;
  created_at: string;
  updated_at: string;
}

export interface VaultItemDetailResponse extends VaultItemListResponse {
  file_data_b64: string | null;
  file_iv: string | null;
}

// Backend error code returned as the `code` field of the 404 detail payload
// from GET /vault/config when the user hasn't run setup yet.
export const VAULT_NOT_SETUP_CODE = "VAULT_NOT_SETUP";

export const getVaultConfig = async (): Promise<VaultConfigResponse> => {
  const res = await api.get<VaultConfigResponse>("/vault/config");
  return res.data;
};

export const setupVault = async (
  payload: VaultSetupPayload
): Promise<VaultConfigResponse> => {
  const res = await api.post<VaultConfigResponse>("/vault/setup", payload);
  return res.data;
};

export const listVaultItems = async (
  itemType?: VaultItemType
): Promise<VaultItemListResponse[]> => {
  const res = await api.get<VaultItemListResponse[]>("/vault/items", {
    params: itemType ? { item_type: itemType } : undefined,
  });
  return res.data;
};

export const getVaultItem = async (
  itemId: number
): Promise<VaultItemDetailResponse> => {
  const res = await api.get<VaultItemDetailResponse>(`/vault/items/${itemId}`);
  return res.data;
};

export const createVaultItem = async (
  payload: VaultItemCreatePayload
): Promise<VaultItemDetailResponse> => {
  const res = await api.post<VaultItemDetailResponse>("/vault/items", payload);
  return res.data;
};

export const updateVaultItem = async (
  itemId: number,
  payload: VaultItemUpdatePayload
): Promise<VaultItemDetailResponse> => {
  const res = await api.patch<VaultItemDetailResponse>(
    `/vault/items/${itemId}`,
    payload
  );
  return res.data;
};

export const deleteVaultItem = async (itemId: number): Promise<void> => {
  await api.delete(`/vault/items/${itemId}`);
};

// Nukes the entire vault (config + all items) for the current user.
export const deleteVault = async (): Promise<void> => {
  await api.delete("/vault");
};

// ---- decrypted payload shapes (client-side only, never sent as-is) -------
// These are the JSON objects encrypted into payload_ct for each item type.

export interface NotePayload {
  title: string;
  text: string;
}

export interface DatePayload {
  title: string;
  date: string; // YYYY-MM-DD
  recur_yearly: boolean;
  note: string;
}

export interface CredentialPayload {
  title: string;
  site: string;
  username: string;
  password: string;
  note: string;
}

export interface FilePayload {
  title: string;
  filename: string;
  mimetype: string;
}

export type VaultItemPayload = NotePayload | DatePayload | CredentialPayload | FilePayload;
