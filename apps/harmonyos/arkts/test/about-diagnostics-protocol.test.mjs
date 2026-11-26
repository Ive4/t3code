import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";

const client = new URL("../entry/src/main/ets/client/", import.meta.url);
const loader = NodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith("./") && context.parentURL?.startsWith(client.href)) {
      return nextResolve(`${specifier}.ets`, context);
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (!url.startsWith(client.href) || !url.endsWith(".ets")) return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(new URL(url), "utf8")),
    };
  },
});

const { defaultOpenSourceLicenses, formatDiagnosticsReport } = await import(
  new URL("AboutDiagnosticsProtocol.ets", client).href
);
loader.deregister();

NodeTest.test("formats diagnostics report with and without crash entries", () => {
  const emptyReport = formatDiagnosticsReport("1.2.3", 2, []);
  NodeAssert.match(emptyReport, /App Version: 1\.2\.3/);
  NodeAssert.match(emptyReport, /Environments: 2/);
  NodeAssert.match(emptyReport, /Recent Crashes \(0\):/);
  NodeAssert.match(emptyReport, /\nNone$/);

  const populatedReport = formatDiagnosticsReport(" 1.2.4 ", -3, [
    {
      id: "c-101",
      timestamp: "2026-11-26T10:00:00Z",
      summary: "WebSocket reconnect failed",
      stackPreview: "at T3Socket.connect (T3Socket.ets:42)",
    },
    {
      id: "c-102",
      timestamp: "2026-11-26T11:00:00Z",
      summary: "Parser panic",
      stackPreview: "",
    },
  ]);
  NodeAssert.match(populatedReport, /App Version: 1\.2\.4/);
  NodeAssert.match(populatedReport, /Environments: 0/);
  NodeAssert.match(populatedReport, /Recent Crashes \(2\):/);
  NodeAssert.match(populatedReport, /- \[c-101\] 2026-11-26T10:00:00Z: WebSocket reconnect failed/);
  NodeAssert.match(populatedReport, /Stack: at T3Socket\.connect \(T3Socket\.ets:42\)/);
  NodeAssert.match(populatedReport, /- \[c-102\] 2026-11-26T11:00:00Z: Parser panic/);
});

NodeTest.test(
  "provides default open source licenses including ArkUI, Ghostty VT, and Effect",
  () => {
    const licenses = defaultOpenSourceLicenses();
    NodeAssert.ok(licenses.length >= 3);
    const names = licenses.map((item) => item.name);
    NodeAssert.ok(names.includes("ArkUI"));
    NodeAssert.ok(names.includes("Ghostty VT"));
    NodeAssert.ok(names.includes("Effect"));

    for (const item of licenses) {
      NodeAssert.ok(item.name.trim().length > 0);
      NodeAssert.ok(item.license.trim().length > 0);
      NodeAssert.ok(item.repository.startsWith("https://"));
    }
  },
);
