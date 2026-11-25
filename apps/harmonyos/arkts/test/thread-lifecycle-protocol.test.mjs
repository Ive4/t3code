import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import { ORCHESTRATION_V2_WS_METHODS, OrchestrationV2RpcSchemas } from "@t3tools/contracts";
import * as Schema from "effect/Schema";

const decodeArchivedSnapshot = Schema.decodeUnknownSync(
  OrchestrationV2RpcSchemas.getArchivedShellSnapshot.input,
);

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
NodeTest.after(() => loader.deregister());

const { readThreads } = await import(new URL("T3Protocol.ets", client).href);
const protocol = () => import(new URL("ThreadLifecycleProtocol.ets", client).href);
const completedAt = "2026-11-24T12:00:00.000Z";
const now = Date.parse("2026-11-24T13:00:00.000Z");
const wakeAt = "2026-11-24T14:00:00.000Z";
const closedThread = {
  id: "task",
  title: "测试会话",
  status: "completed",
  latestRunCompletedAt: completedAt,
};

NodeTest.test("keeps lifecycle state on projected shells and discards deleted rows", () => {
  const threads = readThreads({
    projects: [{ id: "project", title: "Projects", workspaceRoot: "/projects" }],
    threads: [
      {
        ...closedThread,
        projectId: "project",
        archivedAt: null,
        settledOverride: "active",
        pinnedAt: completedAt,
        pinOrderKey: "m",
        snoozedUntil: null,
        lastVisitedAt: null,
      },
      { ...closedThread, id: "deleted", deletedAt: completedAt },
      { ...closedThread, id: "legacy", latestRunCompletedAt: null },
    ],
  });
  NodeAssert.deepEqual(
    threads.map((thread) => [
      thread.id,
      thread.projectTitle,
      thread.archivedAt,
      thread.settledOverride,
      thread.pinnedAt,
      thread.pinOrderKey,
      thread.snoozedUntil,
      thread.lastVisitedAt,
      thread.latestRunCompletedAt,
    ]),
    [
      ["task", "Projects", null, "active", completedAt, "m", null, null, completedAt],
      ["legacy", undefined, undefined, undefined, undefined, undefined, undefined, undefined, null],
    ],
  );
});

NodeTest.test("sends lifecycle actions using the protocol-2 command schemas", async () => {
  const { archivedThreadSnapshotRequest, threadLifecycleRequest, threadVisitRequest } =
    await protocol();
  const decode = Schema.decodeUnknownSync(
    Schema.toCodecJson(OrchestrationV2RpcSchemas.dispatchCommand.input),
  );
  for (const [action, type, value, fields] of [
    ["rename", "thread.metadata.update", "  新标题  ", { title: "新标题" }],
    ["pin", "thread.pin", undefined, {}],
    ["unpin", "thread.unpin", undefined, {}],
    ["mark-unread", "thread.mark-unread", undefined, {}],
    ["settle", "thread.settle", undefined, {}],
    ["unsettle", "thread.unsettle", undefined, { reason: "user" }],
    ["snooze", "thread.snooze", wakeAt, { snoozedUntil: wakeAt }],
    ["unsnooze", "thread.unsnooze", undefined, { reason: "user" }],
    ["archive", "thread.archive", undefined, {}],
    ["unarchive", "thread.unarchive", undefined, {}],
    ["delete", "thread.delete", undefined, {}],
  ]) {
    const request = threadLifecycleRequest("command", "task", action, value);
    NodeAssert.equal(request.tag, ORCHESTRATION_V2_WS_METHODS.dispatchCommand);
    NodeAssert.deepEqual(decode(request.payload), {
      type,
      commandId: "command",
      threadId: "task",
      ...fields,
    });
  }
  const visit = threadVisitRequest("command", "task", completedAt);
  NodeAssert.equal(visit.tag, ORCHESTRATION_V2_WS_METHODS.dispatchCommand);
  NodeAssert.deepEqual(decode(visit.payload), {
    type: "thread.visit",
    commandId: "command",
    threadId: "task",
    visitedAt: completedAt,
    opened: true,
  });
  const archived = archivedThreadSnapshotRequest();
  NodeAssert.equal(archived.tag, ORCHESTRATION_V2_WS_METHODS.getArchivedShellSnapshot);
  NodeAssert.deepEqual(decodeArchivedSnapshot(archived.payload), {});
  NodeAssert.throws(() => threadLifecycleRequest("command", "task", "rename", "  "));
  NodeAssert.throws(() => threadLifecycleRequest("command", "task", "snooze", "tomorrow"));
});

NodeTest.test("offers only scoped, state-appropriate transitions", async () => {
  const { availableThreadLifecycleActions, threadLifecycleState } = await protocol();
  const actions = (thread, canOperate = true) =>
    availableThreadLifecycleActions(thread, canOperate, now);
  NodeAssert.deepEqual(actions(closedThread, false), []);
  NodeAssert.deepEqual(actions({ ...closedThread, archivedAt: completedAt }), [
    "unarchive",
    "delete",
  ]);
  NodeAssert.deepEqual(actions({ ...closedThread, snoozedAt: completedAt, snoozedUntil: wakeAt }), [
    "rename",
    "mark-unread",
    "unsnooze",
    "archive",
    "delete",
  ]);
  NodeAssert.deepEqual(actions({ ...closedThread, settledOverride: "settled" }), [
    "rename",
    "mark-unread",
    "pin",
    "unsettle",
    "archive",
    "delete",
  ]);
  NodeAssert.deepEqual(actions({ ...closedThread, pinnedAt: completedAt, status: "running" }), [
    "rename",
    "mark-unread",
    "unpin",
    "settle",
    "snooze",
    "delete",
  ]);
  NodeAssert.equal(
    actions({ ...closedThread, latestRunCompletedAt: undefined }).includes("mark-unread"),
    false,
  );
  NodeAssert.equal(
    threadLifecycleState({ ...closedThread, snoozedUntil: wakeAt }, Date.parse(wakeAt)),
    "active",
  );
  NodeAssert.equal(
    threadLifecycleState(
      {
        ...closedThread,
        snoozedAt: completedAt,
        snoozedUntil: wakeAt,
        pendingRuntimeRequest: { kind: "user_input", createdAt: completedAt },
      },
      now,
    ),
    "snoozed",
  );
  NodeAssert.equal(
    threadLifecycleState(
      {
        ...closedThread,
        snoozedAt: completedAt,
        snoozedUntil: wakeAt,
        pendingRuntimeRequest: { kind: "user_input", createdAt: "2026-11-24T12:30:00.000Z" },
      },
      now,
    ),
    "active",
  );
  NodeAssert.equal(
    actions({
      ...closedThread,
      latestUserMessageAt: "2026-11-24T12:59:59.000Z",
    }).includes("snooze"),
    false,
  );
});

NodeTest.test(
  "uses the server visit watermark to surface and clear unread completion",
  async () => {
    const { threadHasUnread } = await protocol();
    NodeAssert.equal(threadHasUnread(closedThread), false);
    NodeAssert.equal(threadHasUnread({ ...closedThread, lastVisitedAt: null }), true);
    NodeAssert.equal(
      threadHasUnread({ ...closedThread, lastVisitedAt: "2026-11-24T11:59:59.999Z" }),
      true,
    );
    NodeAssert.equal(threadHasUnread({ ...closedThread, lastVisitedAt: completedAt }), false);
    NodeAssert.equal(
      threadHasUnread({ ...closedThread, status: "failed", lastVisitedAt: null }),
      false,
    );
  },
);

NodeTest.test(
  "keeps snooze choices upcoming and calendar-correct in the device time zone",
  async () => {
    const { threadSnoozePresets, customThreadSnooze } = await protocol();
    const evening = new Date(2026, 10, 29, 19, 30); // Sunday
    const presets = threadSnoozePresets(evening);
    NodeAssert.deepEqual(
      presets.map((preset) => preset.wakeAt),
      [
        new Date(2026, 10, 29, 20, 30).toISOString(),
        new Date(2026, 10, 29, 22, 30).toISOString(),
        new Date(2026, 10, 30, 9).toISOString(),
      ],
    );
    const labels = {
      oneHour: "In 1 hour",
      threeHours: "In 3 hours",
      thisEvening: "This evening",
      tomorrow: "Tomorrow",
      nextMonday: "Next Monday",
    };
    NodeAssert.deepEqual(threadSnoozePresets(evening, labels), [
      { ...presets[0], label: labels.oneHour },
      { ...presets[1], label: labels.threeHours },
      { ...presets[2], label: labels.tomorrow },
    ]);
    NodeAssert.equal(
      customThreadSnooze("50", evening.getTime()),
      new Date(2026, 10, 29, 20, 20).toISOString(),
    );
    for (const amount of ["", "0", "-5", "50 min", "99999999999999999999"]) {
      NodeAssert.equal(customThreadSnooze(amount, evening.getTime()), undefined);
    }
  },
);
