const path = require("node:path");
const { createRequire } = require("node:module");

const { build } = createRequire(path.resolve(__dirname, "../../../scripts/package.json"))(
  "esbuild",
);

async function buildTerminalDocument() {
  const result = await build({
    entryPoints: [path.resolve(__dirname, "../src/shared/terminal/page.js")],
    bundle: true,
    write: false,
    minify: true,
    target: "es2022",
    plugins: [
      {
        name: "inline-ghostty-wasm",
        setup(builder) {
          builder.onResolve({ filter: /\.wasm\?url/ }, ({ path: file, resolveDir }) => ({
            path: path.resolve(resolveDir, file.split("?")[0]),
          }));
        },
      },
    ],
    loader: { ".wasm": "dataurl" },
  });
  const script = result.outputFiles[0].text.replace(/<\/script/gi, "<\\/script");
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'wasm-unsafe-eval'; style-src 'unsafe-inline'; connect-src data:; base-uri 'none'; form-action 'none'"><style>
*{box-sizing:border-box}
[hidden]{display:none!important}
html,body,canvas{margin:0;width:100%;height:100%;overflow:hidden}
body{user-select:none}
canvas,.selection-handle{touch-action:none}
textarea{position:absolute;top:0;left:0;width:1px;height:1px;opacity:0;user-select:text}
.selection-handle{position:absolute;width:44px;height:44px;transform:translate(-50%,-50%);color:#4285c4}
.selection-handle::before,.selection-handle::after{content:"";position:absolute;background:currentColor}
.selection-handle::before{inset:14px;border-radius:50%}
.selection-handle::after{left:21px;top:6px;width:2px;height:9px}
#selection-actions{position:absolute;left:50%;transform:translateX(-50%);display:flex;max-width:100%;border-radius:8px;background:Canvas;color:CanvasText;box-shadow:0 2px 12px #0006}
#selection-actions button{min-height:44px;padding:0 12px;border:0;border-radius:inherit;color:inherit;background:transparent;font:500 14px system-ui}
#selection-actions button:active{background:#80808030}
</style></head><body>
<canvas></canvas><textarea autocapitalize="off" autocomplete="off" spellcheck="false"></textarea>
<div id="selection-start" class="selection-handle" aria-hidden="true" hidden></div>
<div id="selection-end" class="selection-handle" aria-hidden="true" hidden></div>
<div id="selection-actions" hidden><button id="selection-copy" type="button"></button><button id="selection-all" type="button"></button></div>
<script>${script}</script></body></html>`;
}
module.exports = { buildTerminalDocument };
