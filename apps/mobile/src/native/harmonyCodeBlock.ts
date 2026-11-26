import type { Code } from "mdast";
import Prism from "prismjs";
import "prismjs/components/prism-bash";
import "prismjs/components/prism-c";
import "prismjs/components/prism-cpp";
import "prismjs/components/prism-csharp";
import "prismjs/components/prism-diff";
import "prismjs/components/prism-go";
import "prismjs/components/prism-java";
import "prismjs/components/prism-json";
import "prismjs/components/prism-kotlin";
import "prismjs/components/prism-lua";
import "prismjs/components/prism-markdown";
import "prismjs/components/prism-python";
import "prismjs/components/prism-ruby";
import "prismjs/components/prism-rust";
import "prismjs/components/prism-sql";
import "prismjs/components/prism-swift";
import "prismjs/components/prism-toml";
import "prismjs/components/prism-typescript";
import "prismjs/components/prism-jsx";
import "prismjs/components/prism-tsx";
import "prismjs/components/prism-yaml";

export function harmonyFenceIsClosed(source: string, node: Code): boolean {
  const { start, end } = node.position ?? {};
  if (start?.offset === undefined || end?.offset === undefined || start.line === end.line) {
    return false;
  }
  const block = source.slice(start.offset, end.offset);
  const open = /^(`{3,}|~{3,})/.exec(block)?.[1];
  const close = /(?:\r\n?|\n)[\t >]*(`{3,}|~{3,})[\t ]*$/.exec(block)?.[1];
  return Boolean(
    open &&
    close &&
    open[0] === close[0] &&
    close.length >= open.length &&
    // An apparent closing fence can be indented as part of the code instead.
    (node.value === "" || node.value.split(/\r\n?|\n/).length < end.line - start.line),
  );
}

type Scheme = "light" | "dark";
type Token = {
  readonly start: number;
  readonly content: string;
  readonly color: string | undefined;
};

const colors = new Map<string, readonly [string, string]>([
  ["comment", ["#6e7781", "#8b949e"]],
  ["function", ["#8250df", "#d2a8ff"]],
  ["keyword", ["#cf222e", "#ff7b72"]],
  ["operator", ["#cf222e", "#ff7b72"]],
  ["string", ["#0a3069", "#a5d6ff"]],
  ["number", ["#0550ae", "#79c0ff"]],
  ["boolean", ["#0550ae", "#79c0ff"]],
  ["property", ["#0550ae", "#79c0ff"]],
  ["tag", ["#116329", "#7ee787"]],
  ["attr-name", ["#0550ae", "#79c0ff"]],
  ["attr-value", ["#0a3069", "#a5d6ff"]],
  ["class-name", ["#953800", "#ffa657"]],
]);

const aliases = new Map([
  ["shell", "bash"],
  ["shellscript", "bash"],
  ["zsh", "bash"],
  ["golang", "go"],
]);

export function highlightHarmonyCode(
  code: string,
  fence: string,
  scheme: Scheme,
): readonly Token[] | null {
  if (code.length > 32_768 || /[^\r\n]{1001}/.test(code)) return null;
  const name = fence.toLowerCase();
  const language = aliases.get(name) ?? name;
  const grammar = Object.hasOwn(Prism.languages, language) && Prism.languages[language];
  if (!grammar || typeof grammar !== "object") return null;
  const tokens: Token[] = [];
  let offset = 0;
  function append(token: string | Prism.Token, inheritedColor?: string) {
    if (typeof token === "string") {
      if (token) {
        tokens.push({ start: offset, content: token, color: inheritedColor });
        offset += token.length;
      }
      return;
    }
    const color = colors.get(token.type)?.[scheme === "dark" ? 1 : 0] ?? inheritedColor;
    if (Array.isArray(token.content)) {
      token.content.forEach((child) => append(child, color));
    } else {
      append(token.content, color);
    }
  }
  try {
    Prism.tokenize(code, grammar).forEach((token) => append(token));
    return tokens.length <= 2_000 ? tokens : null;
  } catch {
    return null;
  }
}
