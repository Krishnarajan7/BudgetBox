// Client-side, zero-knowledge crypto for the Secret Vault feature.
//
// Design:
// - Key derivation: PBKDF2-SHA256(passphrase, salt, iterations) -> AES-GCM-256
//   CryptoKey. The key is marked non-extractable, so it can never be read
//   back out of WebCrypto (e.g. via devtools) once derived — only used for
//   encrypt/decrypt operations for the lifetime of the page.
// - The passphrase itself is NEVER sent to the backend, and the derived key
//   is NEVER persisted anywhere (no localStorage/sessionStorage/IndexedDB).
//   It only ever lives in JS memory (React state) for the current session.
// - AES-GCM requires a unique IV per encryption under the same key. Every
//   call to encryptJson/encryptBytes generates a fresh random 12-byte IV,
//   so IVs are never reused, even when encrypting multiple fields for the
//   same vault item (title+payload are bundled into ONE JSON blob precisely
//   so only one IV is needed per item, matching the backend's single `iv`
//   column — see vault.api.ts for the item-shape rationale).
// - The backend only ever stores ciphertext + IV + salt/iteration count. It
//   has no way to derive the key or decrypt anything; only this module
//   (holding the user's passphrase) can produce a working key.

const PBKDF2_HASH = "SHA-256";
const AES_ALGO = "AES-GCM";
const AES_KEY_LENGTH = 256;
const IV_LENGTH_BYTES = 12; // 96-bit IV, the recommended size for AES-GCM
const SALT_LENGTH_BYTES = 16;

export const VAULT_KDF_ITERATIONS = 310000;
export const VAULT_CANARY_VALUE = "budgetbox-vault";

// ---- base64 <-> bytes helpers -------------------------------------------
//
// Chunked so we don't blow the call stack on String.fromCharCode(...bytes)
// for larger buffers (e.g. files up to the 10MB cap).

const B64_CHUNK_SIZE = 0x8000;

export function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += B64_CHUNK_SIZE) {
    const chunk = bytes.subarray(i, i + B64_CHUNK_SIZE);
    binary += String.fromCharCode(...chunk);
  }
  return btoa(binary);
}

// Typed explicitly as the ArrayBuffer-backed variant (rather than bare
// `Uint8Array`, which TS's lib.dom.d.ts widens to `Uint8Array<ArrayBufferLike>`)
// so these values satisfy WebCrypto's `BufferSource` parameter types.
type Bytes = Uint8Array<ArrayBuffer>;

export function base64ToBytes(b64: string): Bytes {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function randomBytes(length: number): Bytes {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytes;
}

/** Generates a fresh random salt for PBKDF2, base64-encoded for transport/storage. */
export function generateSaltB64(): string {
  return bytesToBase64(randomBytes(SALT_LENGTH_BYTES));
}

// ---- key derivation -------------------------------------------------------

/**
 * Derives a non-extractable AES-GCM-256 CryptoKey from a passphrase using
 * PBKDF2-SHA256. `saltB64` and `iterations` come from the vault config
 * (either freshly generated during setup, or fetched from the backend on
 * unlock) so the same key can be reproduced from the same passphrase.
 */
export async function deriveKey(
  passphrase: string,
  saltB64: string,
  iterations: number
): Promise<CryptoKey> {
  const salt = base64ToBytes(saltB64);
  const passphraseKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(passphrase),
    "PBKDF2",
    false,
    ["deriveKey"]
  );

  return crypto.subtle.deriveKey(
    {
      name: "PBKDF2",
      salt,
      iterations,
      hash: PBKDF2_HASH,
    },
    passphraseKey,
    { name: AES_ALGO, length: AES_KEY_LENGTH },
    false, // non-extractable — cannot be exported back out of WebCrypto
    ["encrypt", "decrypt"]
  );
}

export interface EncryptedBlob {
  ct_b64: string;
  iv_b64: string;
}

// ---- JSON payload encryption ----------------------------------------------

/** Encrypts an arbitrary JSON-serializable object under a fresh random IV. */
export async function encryptJson(key: CryptoKey, obj: unknown): Promise<EncryptedBlob> {
  const iv = randomBytes(IV_LENGTH_BYTES);
  const plaintext = new TextEncoder().encode(JSON.stringify(obj));
  const ciphertext = await crypto.subtle.encrypt({ name: AES_ALGO, iv }, key, plaintext);
  return {
    ct_b64: bytesToBase64(new Uint8Array(ciphertext)),
    iv_b64: bytesToBase64(iv),
  };
}

/** Decrypts and JSON-parses a blob produced by encryptJson. Throws on wrong key/tampered data. */
export async function decryptJson<T = unknown>(
  key: CryptoKey,
  ctB64: string,
  ivB64: string
): Promise<T> {
  const iv = base64ToBytes(ivB64);
  const ciphertext = base64ToBytes(ctB64);
  const plaintext = await crypto.subtle.decrypt({ name: AES_ALGO, iv }, key, ciphertext);
  return JSON.parse(new TextDecoder().decode(plaintext)) as T;
}

// ---- raw byte (file) encryption -------------------------------------------

/** Encrypts a raw ArrayBuffer (e.g. file contents) under a fresh random IV. */
export async function encryptBytes(key: CryptoKey, data: ArrayBuffer): Promise<EncryptedBlob> {
  const iv = randomBytes(IV_LENGTH_BYTES);
  const ciphertext = await crypto.subtle.encrypt({ name: AES_ALGO, iv }, key, data);
  return {
    ct_b64: bytesToBase64(new Uint8Array(ciphertext)),
    iv_b64: bytesToBase64(iv),
  };
}

/** Decrypts a blob produced by encryptBytes back into a raw ArrayBuffer. */
export async function decryptBytes(
  key: CryptoKey,
  ctB64: string,
  ivB64: string
): Promise<ArrayBuffer> {
  const iv = base64ToBytes(ivB64);
  const ciphertext = base64ToBytes(ctB64);
  return crypto.subtle.decrypt({ name: AES_ALGO, iv }, key, ciphertext);
}

// ---- setup / unlock helpers ------------------------------------------------

export interface VaultSetupMaterial {
  kdf_salt: string;
  kdf_iterations: number;
  canary_ct: string;
  canary_iv: string;
  key: CryptoKey;
}

/**
 * Builds everything needed to POST /vault/setup: a fresh salt, the fixed
 * iteration count, the derived key, and an encrypted "canary" value. The
 * canary lets us later verify a passphrase is correct (by attempting to
 * decrypt it) without the backend ever seeing the passphrase or key.
 */
export async function createVaultSetupMaterial(passphrase: string): Promise<VaultSetupMaterial> {
  const kdf_salt = generateSaltB64();
  const kdf_iterations = VAULT_KDF_ITERATIONS;
  const key = await deriveKey(passphrase, kdf_salt, kdf_iterations);
  const canary = await encryptJson(key, { v: VAULT_CANARY_VALUE });
  return {
    kdf_salt,
    kdf_iterations,
    canary_ct: canary.ct_b64,
    canary_iv: canary.iv_b64,
    key,
  };
}

/**
 * Attempts to unlock the vault: derives a key from the given passphrase and
 * the stored KDF params, then tries to decrypt the stored canary. Returns
 * the derived key on success (proving the passphrase is correct), or null
 * if decryption fails (wrong passphrase) or the canary value doesn't match.
 */
export async function tryUnlockVault(
  passphrase: string,
  config: { kdf_salt: string; kdf_iterations: number; canary_ct: string; canary_iv: string }
): Promise<CryptoKey | null> {
  try {
    const key = await deriveKey(passphrase, config.kdf_salt, config.kdf_iterations);
    const canary = await decryptJson<{ v: string }>(key, config.canary_ct, config.canary_iv);
    if (canary?.v !== VAULT_CANARY_VALUE) return null;
    return key;
  } catch {
    // AES-GCM decrypt fails (auth tag mismatch) when the derived key is wrong.
    return null;
  }
}
