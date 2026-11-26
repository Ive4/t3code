/// <reference types="node" />

import * as NodeCrypto from "node:crypto";
import { expect, it, vi } from "vite-plus/test";

import { nativeDpopKeys } from "./dpopNativeKeys.harmony";

const ecdh = NodeCrypto.createECDH("prime256v1");
const scalar = new Uint8Array(32).fill(1);
ecdh.setPrivateKey(scalar);
const point = ecdh.getPublicKey();
const jwk = {
  kty: "EC",
  crv: "P-256",
  x: point.subarray(1, 33).toString("base64url"),
  y: point.subarray(33).toString("base64url"),
};
const publicKey = NodeCrypto.createPublicKey({ format: "jwk", key: jwk });
const native = vi.hoisted(() => ({
  signDpop: vi.fn<(key: number[], input: number[]) => Promise<number[]>>(),
  dpopKeyMatches: vi.fn<(key: number[], point: number[]) => Promise<boolean>>(),
}));

vi.mock("react-native", () => ({
  TurboModuleRegistry: {
    getEnforcing: (name: string) => {
      if (name !== "T3Crypto") throw new Error("Unexpected native module");
      return native;
    },
  },
}));

it("converts the native DER signature into an interoperable ES256 signature", async () => {
  native.signDpop.mockImplementationOnce(async (key, input) => {
    const signingKey = NodeCrypto.createPrivateKey({
      format: "jwk",
      key: { ...jwk, d: Buffer.from(key).toString("base64url") },
    });
    return Array.from(NodeCrypto.sign("sha256", Uint8Array.from(input), signingKey));
  });

  const keys = await nativeDpopKeys();
  const input = new TextEncoder().encode("encoded-header.encoded-payload");
  const signature = await keys.signDpop(scalar, input);

  expect(signature).toHaveLength(64);
  expect(
    NodeCrypto.verify("sha256", input, { key: publicKey, dsaEncoding: "ieee-p1363" }, signature),
  ).toBe(true);
});

it("rejects a malformed stored scalar", async () => {
  const keys = await nativeDpopKeys();
  await expect(keys.dpopKeyMatches(new Uint8Array(31), point)).resolves.toBe(false);
});

it.each([
  { malformed: "truncated integer", der: [0x30, 4, 2, 1, 1, 2] },
  { malformed: "negative integer", der: [0x30, 6, 2, 1, 0x80, 2, 1, 1] },
  { malformed: "noncanonical padding", der: [0x30, 7, 2, 2, 0, 1, 2, 1, 1] },
])("rejects a native DER signature with $malformed", async ({ der }) => {
  native.signDpop.mockResolvedValueOnce(der);
  const keys = await nativeDpopKeys();
  await expect(keys.signDpop(scalar, Uint8Array.of(1))).rejects.toThrow("Invalid ES256 signature");
});
