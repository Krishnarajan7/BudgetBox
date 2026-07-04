import api from "./axios";

export interface Wallet {
  id: number;
  name: string;
  // Backend serializes Decimal fields as strings (e.g. "12.50") to preserve
  // precision, so callers must parse this before doing arithmetic/display.
  balance: string | number;
}

export interface WalletCreatePayload {
  name: string;
  balance?: number;
}

export interface WalletUpdatePayload {
  name?: string;
  balance?: number;
}

export const listWallets = async (): Promise<Wallet[]> => {
  const res = await api.get<Wallet[]>("/wallets");
  return res.data;
};

export const createWallet = async (
  payload: WalletCreatePayload
): Promise<Wallet> => {
  const res = await api.post<Wallet>("/wallets", payload);
  return res.data;
};

export const updateWallet = async (
  id: number,
  payload: WalletUpdatePayload
): Promise<Wallet> => {
  const res = await api.patch<Wallet>(`/wallets/${id}`, payload);
  return res.data;
};

export const deleteWallet = async (id: number): Promise<void> => {
  await api.delete(`/wallets/${id}`);
};
