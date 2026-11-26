import {
  EnvironmentId,
  ProjectId,
  ProviderInstanceId,
  RunId,
  RuntimeRequestId,
  ThreadId,
} from "@t3tools/contracts";
import * as DateTime from "effect/DateTime";
import { expect, it } from "vite-plus/test";

import {
  collectHarmonyAgentAlerts,
  usesHarmonyLocalAgentAlerts,
  type HarmonyAlertShell,
} from "./harmonyAgentAlerts";

const environmentId = EnvironmentId.make("environment-one");
const threadId = ThreadId.make("thread-one");
const projectId = ProjectId.make("project-one");
const now = DateTime.makeUnsafe("2026-11-24T01:00:00Z");
const before = DateTime.makeUnsafe("2026-11-24T00:59:00Z");
const after = DateTime.makeUnsafe("2026-11-24T01:01:00Z");
const running: HarmonyAlertShell["threads"][number] = {
  id: threadId,
  title: "Private thread title",
  projectId,
  status: "running",
  modelSelection: { instanceId: ProviderInstanceId.make("codex"), model: "gpt-5.4" },
  lineage: { rootThreadId: threadId, parentThreadId: null, relationshipToParent: null },
  latestRunId: RunId.make("run-one"),
  latestRunCompletedAt: null,
  pendingRuntimeRequest: null,
  settledOverride: null,
  updatedAt: now,
};

const waiting = (requestId: string) => ({
  ...running,
  pendingRuntimeRequest: {
    id: RuntimeRequestId.make(requestId),
    kind: "user_input" as const,
    createdAt: now,
  },
});

const shell = (
  thread: HarmonyAlertShell["threads"][number],
  snapshotSequence: number,
  generation = 1,
): HarmonyAlertShell => ({
  projects: [{ id: projectId, title: "Private project title" }],
  threads: [thread],
  snapshotSequence,
  generation,
});

it("uses local alerts in the foreground and for hosts without working background push", () => {
  expect(usesHarmonyLocalAgentAlerts({ foreground: false, pushReady: true })).toBe(false);
  expect(usesHarmonyLocalAgentAlerts({ foreground: true, pushReady: true })).toBe(true);
  expect(usesHarmonyLocalAgentAlerts({ foreground: false, pushReady: false })).toBe(true);
});

it("only announces live transitions and never includes thread or project titles", () => {
  const first = shell(waiting("request-one"), 10);
  const refresh = shell(waiting("request-one"), 11);
  const newRequest = shell(waiting("request-two"), 12);

  expect(collectHarmonyAgentAlerts(environmentId, undefined, first, null)).toEqual([]);
  expect(collectHarmonyAgentAlerts(environmentId, first, refresh, null)).toEqual([]);
  expect(
    collectHarmonyAgentAlerts(environmentId, first, shell(waiting("request-two"), 12, 2), null),
  ).toEqual([]);
  expect(collectHarmonyAgentAlerts(environmentId, refresh, newRequest, null)).toEqual([
    { environmentId, threadId, phase: "waiting_for_input" },
  ]);
  expect(
    collectHarmonyAgentAlerts(environmentId, refresh, newRequest, null, { notifyOnInput: false }),
  ).toEqual([]);
  expect(
    collectHarmonyAgentAlerts(
      environmentId,
      refresh,
      newRequest,
      `/threads/${environmentId}/${threadId}`,
    ),
  ).toEqual([]);
  expect(
    collectHarmonyAgentAlerts(
      EnvironmentId.make("other-environment"),
      refresh,
      newRequest,
      `/threads/${environmentId}/${threadId}`,
    ),
  ).toHaveLength(1);
});

it("respects snoozed completion, manual stop and newer runs ending in the same phase", () => {
  const completed = { ...running, status: "completed" as const, latestRunCompletedAt: now };
  const previous = shell(running, 10);
  expect(
    collectHarmonyAgentAlerts(
      environmentId,
      previous,
      shell({ ...completed, snoozedAt: before, snoozedUntil: after }, 11),
      null,
    ),
  ).toEqual([]);
  expect(
    collectHarmonyAgentAlerts(
      environmentId,
      previous,
      shell({ ...completed, latestRunStopRequested: true }, 11),
      null,
    ),
  ).toEqual([]);
  expect(
    collectHarmonyAgentAlerts(
      environmentId,
      shell(completed, 11),
      shell({ ...completed, latestRunId: RunId.make("run-two") }, 12),
      null,
    ),
  ).toEqual([{ environmentId, threadId, phase: "completed" }]);
});
