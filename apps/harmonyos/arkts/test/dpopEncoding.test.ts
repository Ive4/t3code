import { describe, expect, it } from "vitest";
import { derToJose } from "../entry/src/main/ets/client/DpopEncoding.ts";

describe("ArkTS DPoP signature encoding", () => {
  it("strips a required DER sign byte and pads each integer to 32 bytes", () => {
    const r = `80${"11".repeat(31)}`;
    const der = Buffer.from(`3026022100${r}020101`, "hex");

    expect(Buffer.from(derToJose(der)).toString("hex")).toBe(`${r}${"00".repeat(31)}01`);
  });

  it.each([
    ["wrong sequence tag", "3106020101020102"],
    ["long-form sequence length", "308106020101020102"],
    ["truncated sequence", "30060201010201"],
    ["trailing bytes outside the sequence", "300602010102010200"],
    ["trailing bytes inside the sequence", "300702010102010200"],
    ["wrong integer tag", "3006030101020102"],
    ["long-form integer length", "300702810101020102"],
    ["empty integer", "30050200020101"],
    ["zero integer", "3006020100020101"],
    ["negative integer", "3006020180020101"],
    ["unnecessary sign byte", "30070202007f020101"],
    ["truncated integer", "3006020101020202"],
    ["integer wider than P-256", `3026022101${"11".repeat(32)}020101`],
  ])("rejects %s", (_label, der) => {
    expect(() => derToJose(Buffer.from(der, "hex"))).toThrow();
  });
});
