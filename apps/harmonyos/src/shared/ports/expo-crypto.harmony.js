import { TurboModuleRegistry } from "react-native";

const module = TurboModuleRegistry.getEnforcing("T3Crypto");

export const CryptoDigestAlgorithm = {
  SHA1: "SHA-1",
  SHA256: "SHA-256",
  SHA384: "SHA-384",
  SHA512: "SHA-512",
  MD2: "MD2",
  MD4: "MD4",
  MD5: "MD5",
};
export const CryptoEncoding = { HEX: "hex", BASE64: "base64" };

export function randomUUID() {
  return module.randomUUID();
}

export function getRandomBytes(length) {
  if (
    typeof length !== "number" ||
    !Number.isFinite(length) ||
    Math.floor(length) < 0 ||
    Math.floor(length) > 1024
  ) {
    throw new TypeError("Random byte length must be between 0 and 1024");
  }
  return Uint8Array.from(module.randomBytes(Math.floor(length)));
}

export async function getRandomBytesAsync(length) {
  return getRandomBytes(length);
}

export function getRandomValues(array) {
  const bytes = new Uint8Array(array.buffer, array.byteOffset, array.byteLength);
  bytes.set(module.randomBytes(bytes.length));
  return array;
}

export async function digest(algorithm, input) {
  const bytes = ArrayBuffer.isView(input)
    ? new Uint8Array(input.buffer, input.byteOffset, input.byteLength)
    : new Uint8Array(input);
  return Uint8Array.from(await module.digestBytes(algorithm, Array.from(bytes))).buffer;
}

export async function digestStringAsync(algorithm, text, { encoding = CryptoEncoding.HEX } = {}) {
  const bytes = await module.digestText(algorithm, text);
  if (encoding === CryptoEncoding.BASE64) return btoa(String.fromCharCode(...bytes));
  if (encoding !== CryptoEncoding.HEX) throw new TypeError("Unsupported digest encoding");
  return bytes.map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
