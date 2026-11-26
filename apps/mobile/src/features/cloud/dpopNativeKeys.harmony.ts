import { TurboModuleRegistry, type TurboModule } from "react-native";

import type { NativeDpopKeys } from "./dpopNativeKeys";

interface HarmonyDpopKeys extends TurboModule {
  generateDpopKey(): Promise<number[]>;
  dpopKeyMatches(privateKey: number[], publicKey: number[]): Promise<boolean>;
  signDpop(privateKey: number[], signingInput: number[]): Promise<number[]>;
}

// P-256 signatures fit in a DER sequence with one-byte lengths. JOSE expects two 32-byte integers.
function signatureFromDer(der: readonly number[]): Uint8Array {
  const signature = new Uint8Array(64);
  if (der[0] !== 0x30 || der[1] !== der.length - 2) {
    throw new Error("Invalid ES256 signature");
  }
  let offset = 2;
  for (const outputOffset of [0, 32]) {
    const tag = der[offset++];
    const size = der[offset++];
    const first = der[offset];
    const second = der[offset + 1];
    if (
      tag !== 0x02 ||
      size === undefined ||
      size < 1 ||
      size > 33 ||
      offset + size > der.length ||
      first === undefined ||
      first >= 0x80 ||
      (first === 0 && (size === 1 || second === undefined || second < 0x80))
    ) {
      throw new Error("Invalid ES256 signature");
    }
    const bytes = der.slice(offset + (first === 0 ? 1 : 0), offset + size);
    if (bytes.length > 32) {
      throw new Error("Invalid ES256 signature");
    }
    signature.set(bytes, outputOffset + 32 - bytes.length);
    offset += size;
  }
  if (offset !== der.length) {
    throw new Error("Invalid ES256 signature");
  }
  return signature;
}

export async function nativeDpopKeys(): Promise<NativeDpopKeys> {
  const module = TurboModuleRegistry.getEnforcing<HarmonyDpopKeys>("T3Crypto");
  return {
    generateDpopKey: async () => Uint8Array.from(await module.generateDpopKey()),
    dpopKeyMatches: async (privateKey, publicKey) =>
      privateKey.length === 32 &&
      publicKey.length === 65 &&
      publicKey[0] === 0x04 &&
      (await module.dpopKeyMatches(Array.from(privateKey), Array.from(publicKey))),
    signDpop: async (privateKey, signingInput) =>
      signatureFromDer(await module.signDpop(Array.from(privateKey), Array.from(signingInput))),
  };
}
