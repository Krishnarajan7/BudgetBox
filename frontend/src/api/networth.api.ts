import api from "./axios";

export type AssetKind = "asset" | "liability";

// Backend serializes Decimal fields as strings (e.g. "12.50") to preserve
// precision, so callers must parse this before doing arithmetic/display.
export type DecimalString = string | number;

export interface Asset {
  id: number;
  name: string;
  kind: AssetKind;
  category: string;
  value: DecimalString;
  note?: string | null;
}

export interface AssetCreatePayload {
  name: string;
  kind: AssetKind;
  category: string;
  value: number;
  note?: string | null;
}

export interface AssetUpdatePayload {
  name?: string;
  kind?: AssetKind;
  category?: string;
  value?: number;
  note?: string | null;
}

export interface WalletBreakdown {
  id: number;
  name: string;
  balance: DecimalString;
}

export interface AssetBreakdown {
  id: number;
  name: string;
  category: string;
  value: DecimalString;
}

export interface NetWorthBreakdown {
  wallets: WalletBreakdown[];
  assets: AssetBreakdown[];
  liabilities: AssetBreakdown[];
}

export interface NetWorthResponse {
  wallets_total: DecimalString;
  assets_total: DecimalString;
  liabilities_total: DecimalString;
  net_worth: DecimalString;
  breakdown: NetWorthBreakdown;
}

export const getNetWorth = async (): Promise<NetWorthResponse> => {
  const res = await api.get<NetWorthResponse>("/networth");
  return res.data;
};

export const listAssets = async (): Promise<Asset[]> => {
  const res = await api.get<Asset[]>("/assets");
  return res.data;
};

export const createAsset = async (
  payload: AssetCreatePayload
): Promise<Asset> => {
  const res = await api.post<Asset>("/assets", payload);
  return res.data;
};

export const updateAsset = async (
  id: number,
  payload: AssetUpdatePayload
): Promise<Asset> => {
  const res = await api.patch<Asset>(`/assets/${id}`, payload);
  return res.data;
};

export const deleteAsset = async (id: number): Promise<void> => {
  await api.delete(`/assets/${id}`);
};
