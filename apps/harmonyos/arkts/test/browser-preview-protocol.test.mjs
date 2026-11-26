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

const { buildBrowserCommandPayload, normalizeBrowserPreviewUrl, selectBrowserPreviewTab } =
  await import(new URL("BrowserPreviewProtocol.ets", client).href);
loader.deregister();

NodeTest.test("normalizeBrowserPreviewUrl normalizes valid http/https and bare hosts", () => {
  NodeAssert.equal(
    normalizeBrowserPreviewUrl("  https://example.com/path?q=1#top  "),
    "https://example.com/path?q=1#top",
  );
  NodeAssert.equal(
    normalizeBrowserPreviewUrl("HTTP://example.com:8080/health"),
    "http://example.com:8080/health",
  );
  NodeAssert.equal(normalizeBrowserPreviewUrl("example.com"), "https://example.com");
  NodeAssert.equal(
    normalizeBrowserPreviewUrl("docs.t3.codes/guide"),
    "https://docs.t3.codes/guide",
  );
  NodeAssert.equal(normalizeBrowserPreviewUrl("localhost:5173"), "http://localhost:5173");
  NodeAssert.equal(normalizeBrowserPreviewUrl("LOCALHOST/app"), "http://LOCALHOST/app");
  NodeAssert.equal(normalizeBrowserPreviewUrl("127.0.0.1:3000/api"), "http://127.0.0.1:3000/api");
  NodeAssert.equal(normalizeBrowserPreviewUrl("127.0.0.1"), "http://127.0.0.1");
});

NodeTest.test(
  "normalizeBrowserPreviewUrl rejects unsafe schemes, empty values, and control chars",
  () => {
    for (const invalid of [
      "",
      "   ",
      "javascript:alert(1)",
      "JAVASCRIPT:alert(1)",
      "javascript:123",
      "data:text/html,<script>alert(1)</script>",
      "file:///etc/passwd",
      "ftp://example.com/file",
      "mailto:user@example.com",
      "about:blank",
      "ws://localhost:8080",
      "https://",
      "http:///only-path",
      "/relative/path",
      "example.com/with space",
      "https://example.com/\npath",
      "https://example.com/\rpath",
      "https://example.com/\u0000",
      "https://example.com/\u007f",
    ]) {
      NodeAssert.equal(
        normalizeBrowserPreviewUrl(invalid),
        null,
        `expected null for ${JSON.stringify(invalid)}`,
      );
    }
  },
);

NodeTest.test("selectBrowserPreviewTab updates selectedTabId only for existing tabs", () => {
  const tabs = [
    {
      tabId: "tab_1",
      title: "Home",
      url: "https://example.com",
      loading: false,
      canGoBack: false,
      canGoForward: false,
    },
    {
      tabId: "tab_2",
      title: "Docs",
      url: "https://example.com/docs",
      loading: true,
      canGoBack: true,
      canGoForward: false,
    },
  ];
  const initial = {
    tabs,
    selectedTabId: "tab_1",
    streaming: true,
    canControl: true,
    error: null,
  };

  const selected = selectBrowserPreviewTab(initial, "tab_2");
  NodeAssert.notEqual(selected, initial);
  NodeAssert.equal(selected.selectedTabId, "tab_2");
  NodeAssert.equal(selected.tabs, tabs);
  NodeAssert.equal(selected.streaming, true);
  NodeAssert.equal(selected.canControl, true);
  NodeAssert.equal(selected.error, null);

  NodeAssert.equal(selectBrowserPreviewTab(selected, "tab_2"), selected);
  NodeAssert.equal(selectBrowserPreviewTab(initial, "missing_tab"), initial);
  NodeAssert.equal(selectBrowserPreviewTab(initial, ""), initial);
});

NodeTest.test(
  "buildBrowserCommandPayload serializes supported commands and rejects invalid inputs",
  () => {
    NodeAssert.deepEqual(
      JSON.parse(buildBrowserCommandPayload({ type: "navigate", url: "localhost:5173/preview" })),
      { type: "navigate", url: "http://localhost:5173/preview" },
    );
    NodeAssert.deepEqual(
      JSON.parse(buildBrowserCommandPayload({ type: "navigate", url: "https://t3.codes" })),
      { type: "navigate", url: "https://t3.codes" },
    );
    NodeAssert.deepEqual(JSON.parse(buildBrowserCommandPayload({ type: "reload" })), {
      type: "reload",
    });
    NodeAssert.deepEqual(JSON.parse(buildBrowserCommandPayload({ type: "history", delta: -1 })), {
      type: "history",
      delta: -1,
    });
    NodeAssert.deepEqual(
      JSON.parse(buildBrowserCommandPayload({ type: "text", text: "hello world" })),
      {
        type: "text",
        text: "hello world",
      },
    );

    NodeAssert.throws(() =>
      buildBrowserCommandPayload({ type: "navigate", url: "javascript:alert(1)" }),
    );
    NodeAssert.throws(() => buildBrowserCommandPayload({ type: "history", delta: Number.NaN }));
  },
);
