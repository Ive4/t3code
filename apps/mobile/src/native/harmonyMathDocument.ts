import { markdownMathRanges } from "@t3tools/shared/markdownMath";

export function harmonyStandaloneMath(source: string): string | undefined {
  const trimmed = source.trim();
  if (trimmed.length > 4_128) return;
  if (!/^\$\$(?:[^\r\n]+|[\s\S]*\r?\n[\t ]*)\$\$$/.test(trimmed)) return;
  const formula = markdownMathRanges(trimmed)[0];
  if (formula?.display && formula.start === 0 && formula.end === trimmed.length) {
    return formula.tex;
  }
}

export function harmonyMathDocument(
  renderToString: typeof import("katex").renderToString,
  tex: string,
  fontSize: number,
  color: string,
): string | null {
  if (!tex.trim() || tex.length > 4_096) return null;
  try {
    let untrustedCommand = false;
    const math = renderToString(tex, {
      output: "mathml",
      displayMode: true,
      throwOnError: true,
      trust: () => {
        untrustedCommand = true;
        return false;
      },
      maxExpand: 100,
      maxSize: 12,
    });
    if (untrustedCommand || math.length > 32_768) return null;
    const foreground = /^[#\sa-zA-Z0-9%.,()/+-]+$/.test(color) ? color : "inherit";
    return `<!doctype html><html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<style>html,body{margin:0;background:transparent}body{color:${foreground};font-size:${Math.min(96, Math.max(8, fontSize))}px}main{width:max-content;min-width:100%;padding:6px 0;box-sizing:border-box;text-align:center}</style>
</head><body><main>${math}</main></body></html>`;
  } catch {
    return null;
  }
}
