import { describe, expect, it } from "vite-plus/test";

import { parseMarkdownDocument } from "../lib/markdownDocument";
import { harmonyFenceIsClosed, highlightHarmonyCode } from "./harmonyCodeBlock";

describe("Harmony code blocks", () => {
  it.each([
    ["```mermaid\nflowchart LR\n```", true],
    ["> ````mermaid\n> flowchart LR\n> ````", true],
    ["- ~~~mermaid\n  flowchart LR\n  ~~~~", true],
    ["```mermaid\nflowchart LR\n", false],
    ["```mermaid\nflowchart LR\n``", false],
    ["```mermaid\nflowchart LR\n    ```", false],
    ["```mermaid\nflowchart LR\n~~~", false],
  ])("detects a closing fence in %j", (source, closed) => {
    const root = parseMarkdownDocument(source);
    const block = root.children[0];
    const node =
      block?.type === "blockquote"
        ? block.children[0]
        : block?.type === "list"
          ? block.children[0]?.children[0]
          : block;
    if (node?.type !== "code") throw new Error("Missing fenced block");
    expect(harmonyFenceIsClosed(source, node)).toBe(closed);
  });

  it("applies colors while preserving source, including multidimensional syntax and line endings", () => {
    const code = 'const print = (s: string) => `hello ${s}`;\r\nprint("你好");\n';
    const dark = highlightHarmonyCode(code, "ts", "dark");
    expect(dark?.map((token) => token.content).join("")).toBe(code);
    expect(dark?.find((token) => token.content === "const")?.color).toMatch(/^#/);
    expect(highlightHarmonyCode(code, "ts", "light")).not.toEqual(dark);
  });

  it("leaves unknown languages and large input in plain text", () => {
    expect(highlightHarmonyCode("const x = 5;", "unknown", "light")).toBeNull();
    expect(highlightHarmonyCode("x".repeat(32_769), "js", "light")).toBeNull();
  });
});
