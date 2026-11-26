export interface NativeDpopKeys {
  /** A 32-byte private scalar followed by its 65-byte uncompressed public point. */
  generateDpopKey(): Promise<Uint8Array>;
  dpopKeyMatches(privateKey: Uint8Array, publicKey: Uint8Array): Promise<boolean>;
  /** ES256 over the signing input, as the raw 64-byte `r‖s` pair. */
  signDpop(privateKey: Uint8Array, signingInput: Uint8Array): Promise<Uint8Array>;
}

// Platform crypto: in Hermes, @noble/curves blocks JS for about a second on its first P-256 key.
// Imported lazily: loading `expo` at module scope breaks Node tests that import this file.
export const nativeDpopKeys = async () =>
  (await import("expo")).requireNativeModule<NativeDpopKeys>("T3NativeControls");
