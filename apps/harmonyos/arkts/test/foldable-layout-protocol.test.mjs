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

const {
  MAX_SIDEBAR_WIDTH_VP,
  MIN_SIDEBAR_WIDTH_VP,
  SPLIT_BREAKPOINT_VP,
  resolveSidebarWidthVp,
  resolveWorkspaceLayoutMode,
} = await import(new URL("FoldableLayoutProtocol.ets", client).href);
loader.deregister();

NodeTest.test("resolves compact vs split layout mode from window metrics and fold posture", () => {
  NodeAssert.equal(
    resolveWorkspaceLayoutMode({ widthVp: 390, heightVp: 844, foldPosture: "unknown" }),
    "compact",
  );
  NodeAssert.equal(
    resolveWorkspaceLayoutMode({
      widthVp: SPLIT_BREAKPOINT_VP - 1,
      heightVp: 800,
      foldPosture: "flat",
    }),
    "compact",
  );
  NodeAssert.equal(
    resolveWorkspaceLayoutMode({
      widthVp: SPLIT_BREAKPOINT_VP,
      heightVp: 800,
      foldPosture: "flat",
    }),
    "split",
  );
  NodeAssert.equal(
    resolveWorkspaceLayoutMode({ widthVp: 760, heightVp: 720, foldPosture: "half-folded" }),
    "split",
  );
  NodeAssert.equal(
    resolveWorkspaceLayoutMode({ widthVp: 640, heightVp: 800, foldPosture: "folded" }),
    "compact",
  );
  NodeAssert.equal(
    resolveWorkspaceLayoutMode({ widthVp: 0, heightVp: 800, foldPosture: "flat" }),
    "compact",
  );
});

NodeTest.test("computes sidebar width as ~34% of window width clamped to [280, 360]", () => {
  NodeAssert.equal(resolveSidebarWidthVp(600), MIN_SIDEBAR_WIDTH_VP);
  NodeAssert.equal(resolveSidebarWidthVp(900), 306);
  NodeAssert.equal(resolveSidebarWidthVp(1000), 340);
  NodeAssert.equal(resolveSidebarWidthVp(1200), MAX_SIDEBAR_WIDTH_VP);
  NodeAssert.equal(resolveSidebarWidthVp(-50), MIN_SIDEBAR_WIDTH_VP);
  NodeAssert.equal(resolveSidebarWidthVp(Number.NaN), MIN_SIDEBAR_WIDTH_VP);
});
