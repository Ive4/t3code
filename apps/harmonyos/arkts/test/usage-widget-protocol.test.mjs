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
  DEFAULT_USAGE_WIDGET_TITLE,
  DEFAULT_USAGE_WIDGET_TTL_MS,
  formatUsageWidgetSnapshot,
  isUsageWidgetExpired,
} = await import(new URL("UsageWidgetProtocol.ets", client).href);
NodeTest.after(() => loader.deregister());

NodeTest.test("formats usage widget snapshot from rows with clamping and defaults", () => {
  const snapshot = formatUsageWidgetSnapshot({
    title: "  AI Quotas  ",
    asOf: " 12:00 ",
    nowMs: 1_000_000,
    rows: [
      { label: "  Codex · 5h  ", remaining: 74.6 },
      { label: "   ", remaining: 50 },
      { label: "Claude · Weekly", remaining: -10 },
      { label: "Grok", remaining: 140 },
      { label: "Cursor", remaining: 25 },
      { label: "Extra", remaining: 10 },
    ],
  });

  NodeAssert.deepEqual(snapshot, {
    title: "AI Quotas",
    message: "",
    asOf: "12:00",
    rows: [
      { label: "Codex · 5h", remaining: 75 },
      { label: "Claude · Weekly", remaining: 0 },
      { label: "Grok", remaining: 100 },
      { label: "Cursor", remaining: 25 },
    ],
    expiresAtMs: 1_000_000 + DEFAULT_USAGE_WIDGET_TTL_MS,
  });
});

NodeTest.test(
  "formats usage widget snapshot from accounts and uses earliest reset deadline",
  () => {
    const nowMs = Date.parse("2026-11-26T10:00:00.000Z");
    const earlierReset = "2026-11-26T10:12:00.000Z";
    const laterReset = "2026-11-26T11:00:00.000Z";
    const snapshot = formatUsageWidgetSnapshot({
      nowMs,
      asOf: "10:00",
      accounts: [
        {
          id: "codex-1",
          driver: "codex",
          name: "Codex",
          checkedAt: "2026-11-26T10:00:00.000Z",
          zeroSpendCap: false,
          windows: [
            {
              id: "w1",
              kind: "primary",
              label: "5h",
              remainingPercent: 82,
              resetsAt: earlierReset,
            },
            {
              id: "w2",
              kind: "secondary",
              label: "Weekly",
              remainingPercent: 60,
              resetsAt: laterReset,
            },
          ],
        },
        {
          id: "claude-1",
          driver: "claude",
          name: "Claude",
          checkedAt: "2026-11-26T10:00:00.000Z",
          zeroSpendCap: false,
          unavailable: "unsupported",
          windows: [
            {
              id: "w3",
              kind: "primary",
              label: "Ignored",
              remainingPercent: 10,
            },
          ],
        },
      ],
    });

    NodeAssert.deepEqual(snapshot, {
      title: DEFAULT_USAGE_WIDGET_TITLE,
      message: "",
      asOf: "10:00",
      rows: [
        { label: "Codex · 5h", remaining: 82 },
        { label: "Codex · Weekly", remaining: 60 },
      ],
      expiresAtMs: Date.parse(earlierReset),
    });
  },
);

NodeTest.test("formats empty snapshot with fallback message and clears asOf", () => {
  const snapshot = formatUsageWidgetSnapshot({
    asOf: "10:00",
    emptyMessage: "Sign in to view quotas",
    nowMs: 5_000,
    ttlMs: 60_000,
    rows: [],
  });

  NodeAssert.deepEqual(snapshot, {
    title: DEFAULT_USAGE_WIDGET_TITLE,
    message: "Sign in to view quotas",
    asOf: "",
    rows: [],
    expiresAtMs: 65_000,
  });
});

NodeTest.test("checks snapshot expiration against nowMs", () => {
  const snapshot = formatUsageWidgetSnapshot({
    nowMs: 1_000,
    expiresAtMs: 5_000,
    rows: [{ label: "Codex", remaining: 80 }],
  });

  NodeAssert.equal(isUsageWidgetExpired(snapshot, 4_999), false);
  NodeAssert.equal(isUsageWidgetExpired(snapshot, 5_000), true);
  NodeAssert.equal(isUsageWidgetExpired(snapshot, 6_000), true);
  NodeAssert.equal(isUsageWidgetExpired(null, 1_000), true);
  NodeAssert.equal(isUsageWidgetExpired(snapshot, Number.NaN), true);
});
