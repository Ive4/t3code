import { renderToString } from "katex";
import { describe, expect, it } from "vite-plus/test";

import { harmonyMathDocument, harmonyStandaloneMath } from "./harmonyMathDocument";

describe("Harmony display math", () => {
  it.each([
    ["$$\n\\frac{1}{2}\n$$", "\\frac{1}{2}"],
    ["$$x^2$$", "x^2"],
    ["$$\nx", undefined],
    ["$x^2$", undefined],
    ["A value $$x^2$$.", undefined],
    ["`$$x^2$$`", undefined],
  ])("selects complete standalone display formulas in %j", (source, tex) => {
    expect(harmonyStandaloneMath(source)).toBe(tex);
  });

  it("typesets math without external resources and rejects invalid or oversized TeX", () => {
    const html = harmonyMathDocument(renderToString, "\\frac{1}{2}", 15, "#333333");
    expect(html).toContain("<mfrac>");
    expect(html).toContain("default-src 'none'");
    expect(harmonyMathDocument(renderToString, "\\frac{", 15, "#333333")).toBeNull();
    expect(harmonyMathDocument(renderToString, "x".repeat(4097), 15, "#333333")).toBeNull();
    expect(
      harmonyMathDocument(renderToString, "\\href{https://example.com}{x}", 15, "#333333"),
    ).toBeNull();
  });
});
