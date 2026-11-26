import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import {
  ScheduledTaskDeleteInput,
  ScheduledTaskRunNowInput,
  ScheduledTaskSetEnabledInput,
  ScheduledTaskUpsertInput,
  WS_METHODS,
} from "@t3tools/contracts";
import * as Schema from "effect/Schema";

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

const {
  buildScheduledTaskDeleteRequest,
  buildScheduledTaskRunNowRequest,
  buildScheduledTaskSetEnabledRequest,
  buildScheduledTaskUpsertRequest,
  readScheduledTasksSnapshot,
} = await import(new URL("ScheduledTasksProtocol.ets", client).href);

const decodeUpsert = Schema.decodeUnknownSync(ScheduledTaskUpsertInput);
const decodeSetEnabled = Schema.decodeUnknownSync(ScheduledTaskSetEnabledInput);
const decodeDelete = Schema.decodeUnknownSync(ScheduledTaskDeleteInput);
const decodeRunNow = Schema.decodeUnknownSync(ScheduledTaskRunNowInput);

NodeTest.test("reads scheduled tasks snapshot and skips malformed entries", () => {
  NodeAssert.deepEqual(readScheduledTasksSnapshot(null), []);
  NodeAssert.deepEqual(readScheduledTasksSnapshot({}), []);

  const tasks = readScheduledTasksSnapshot({
    tasks: [
      {
        id: "task-1",
        title: "Daily summary",
        prompt: "Summarize repo activity",
        enabled: true,
        schedule: { type: "fixed_time", timeOfDay: "09:30", weekdays: [1, 3, 5] },
        projectId: "proj-1",
        threadId: null,
        threadMode: "new_thread",
        workspaceStrategy: { type: "root" },
        modelSelection: { provider: "codex", model: "gpt-5.4" },
        runtimeMode: "approval-required",
        interactionMode: "default",
        createdAt: "2026-11-25T10:00:00.000Z",
        updatedAt: "2026-11-25T10:00:00.000Z",
        nextRunAt: "2026-11-27T09:30:00.000Z",
        lastRunAt: "2026-11-25T09:30:00.000Z",
        lastRunStatus: "succeeded",
        lastRunError: null,
        runCount: 3,
      },
      {
        id: "",
        title: "Invalid",
        prompt: "Missing id",
        enabled: true,
        schedule: { type: "interval", everyMs: 60000 },
        projectId: "proj-1",
        modelSelection: { provider: "codex", model: "gpt-5.4" },
      },
    ],
  });

  NodeAssert.equal(tasks.length, 1);
  NodeAssert.deepEqual(tasks[0], {
    id: "task-1",
    title: "Daily summary",
    prompt: "Summarize repo activity",
    enabled: true,
    schedule: { type: "fixed_time", timeOfDay: "09:30", weekdays: [1, 3, 5] },
    projectId: "proj-1",
    threadId: null,
    threadMode: "new_thread",
    workspaceStrategy: { type: "root" },
    modelSelection: { instanceId: "codex", model: "gpt-5.4" },
    runtimeMode: "approval-required",
    interactionMode: "default",
    createdAt: "2026-11-25T10:00:00.000Z",
    updatedAt: "2026-11-25T10:00:00.000Z",
    nextRunAt: "2026-11-27T09:30:00.000Z",
    lastRunAt: "2026-11-25T09:30:00.000Z",
    lastRunStatus: "succeeded",
    lastRunError: null,
    runCount: 3,
  });
});

NodeTest.test("builds scheduledTasks.* RPC requests matching contracts", () => {
  const upsert = buildScheduledTaskUpsertRequest({
    title: "Hourly check",
    prompt: "Check CI status",
    enabled: true,
    schedule: { type: "interval", everyMs: 3600000 },
    projectId: "proj-1",
    modelSelection: { instanceId: "codex", model: "gpt-5.4" },
  });
  NodeAssert.equal(upsert.method, WS_METHODS.scheduledTasksUpsert);
  const decodedUpsert = decodeUpsert(upsert.params);
  NodeAssert.equal(decodedUpsert.title, "Hourly check");
  NodeAssert.equal(decodedUpsert.prompt, "Check CI status");
  NodeAssert.equal(decodedUpsert.enabled, true);

  const setEnabled = buildScheduledTaskSetEnabledRequest("task-1", false);
  NodeAssert.equal(setEnabled.method, WS_METHODS.scheduledTasksSetEnabled);
  NodeAssert.deepEqual(decodeSetEnabled(setEnabled.params), { id: "task-1", enabled: false });

  const del = buildScheduledTaskDeleteRequest("task-1");
  NodeAssert.equal(del.method, WS_METHODS.scheduledTasksDelete);
  NodeAssert.deepEqual(decodeDelete(del.params), { id: "task-1" });

  const runNow = buildScheduledTaskRunNowRequest("task-1");
  NodeAssert.equal(runNow.method, WS_METHODS.scheduledTasksRunNow);
  NodeAssert.deepEqual(decodeRunNow(runNow.params), { id: "task-1" });

  NodeAssert.throws(() => buildScheduledTaskSetEnabledRequest(" ", true));
  NodeAssert.throws(() => buildScheduledTaskDeleteRequest(""));
  NodeAssert.throws(() => buildScheduledTaskRunNowRequest(""));
  NodeAssert.throws(() =>
    buildScheduledTaskUpsertRequest({
      title: "",
      prompt: "Check CI",
      enabled: true,
      schedule: { type: "interval", everyMs: 60000 },
      projectId: "proj-1",
      modelSelection: { instanceId: "codex", model: "gpt-5.4" },
    }),
  );
});
