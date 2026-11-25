import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";

const source = new URL("../entry/src/main/ets/", import.meta.url);
const loader = NodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    return nextResolve(
      specifier.startsWith(".") && context.parentURL?.startsWith(source.href)
        ? specifier + ".ets"
        : specifier,
      context,
    );
  },
  load(url, context, nextLoad) {
    if (!url.startsWith(source.href) || !url.endsWith(".ets")) return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(new URL(url), "utf8")),
    };
  },
});
NodeTest.after(() => loader.deregister());

const model = () => import(new URL("pages/WorkspaceThreadListModel.ets", source).href);
const now = Date.parse("2026-11-24T12:30:00Z");
const recent = "2026-11-24T12:25:00Z";
const older = "2026-11-24T10:00:00Z";
const thread = (id, extra = {}) => ({ id, title: id, updatedAt: recent, ...extra });

NodeTest.test(
  "puts pinned chats first and keeps attention above the collapsible status shelves",
  async () => {
    const { workspaceThreadListEntries } = await model();
    const input = [
      thread("settled", { settledOverride: "settled" }),
      thread("recent"),
      thread("snoozed", { snoozedAt: older, snoozedUntil: "2026-11-24T13:00:00Z" }),
      thread("unread", { status: "completed", latestRunCompletedAt: recent, lastVisitedAt: null }),
      thread("working", { activityRunStatus: "running" }),
      thread("attention", { pendingRuntimeRequest: { kind: "user_input", createdAt: recent } }),
      thread("pinned", { pinnedAt: older, activityRunStatus: "running" }),
      thread("archived", { archivedAt: recent }),
    ];
    const entries = workspaceThreadListEntries(input, now, false, ["snoozed"]);
    NodeAssert.deepEqual(
      entries.map((entry) => [entry.kind, entry.thread?.id ?? entry.section, entry.count]),
      [
        ["thread", "pinned", 0],
        ["section", "attention", 1],
        ["thread", "attention", 0],
        ["shelf", "working", 1],
        ["section", "unread", 1],
        ["thread", "unread", 0],
        ["section", "recent", 1],
        ["thread", "recent", 0],
        ["shelf", "snoozed", 1],
        ["thread", "snoozed", 0],
        ["shelf", "settled", 1],
      ],
    );
  },
);

NodeTest.test(
  "shows every search match in its input order even if its shelf is closed",
  async () => {
    const { workspaceThreadListEntries } = await model();
    const matched = [
      thread("same", { environmentKey: "relay:west", settledOverride: "settled" }),
      thread("same", { environmentKey: "relay:east", activityRunStatus: "running" }),
    ];
    const entries = workspaceThreadListEntries(matched, now, true, []);
    NodeAssert.deepEqual(
      entries.map((entry) => entry.thread),
      matched,
    );
    NodeAssert.equal(new Set(entries.map((entry) => entry.key)).size, 2);
  },
);

NodeTest.test(
  "shows unread failures and completed snoozes as attention without resurrecting seen events",
  async () => {
    const { workspaceThreadRowStatus } = await model();
    NodeAssert.equal(
      workspaceThreadRowStatus(
        thread("failed", { status: "failed", latestRunCompletedAt: recent, lastVisitedAt: older }),
        now,
      ),
      "failed",
    );
    NodeAssert.equal(
      workspaceThreadRowStatus(
        thread("failed", { status: "failed", latestRunCompletedAt: older, lastVisitedAt: recent }),
        now,
      ),
      "ready",
    );
    NodeAssert.equal(
      workspaceThreadRowStatus(
        thread("woke", { snoozedAt: older, snoozedUntil: recent, lastVisitedAt: null }),
        now,
      ),
      "woke",
    );
    NodeAssert.equal(
      workspaceThreadRowStatus(
        thread("woke", { snoozedAt: older, snoozedUntil: older, lastVisitedAt: recent }),
        now,
      ),
      "ready",
    );
  },
);

NodeTest.test("switches compact time labels between Chinese and English", async () => {
  const { workspaceThreadTimeLabel } = await model();
  NodeAssert.equal(workspaceThreadTimeLabel(thread("recent"), "en", now), "5m");
  NodeAssert.equal(workspaceThreadTimeLabel(thread("recent"), "zh", now), "5分");
  NodeAssert.equal(workspaceThreadTimeLabel({ id: "undated", title: "undated" }, "en", now), "");
});
