import type { EnvironmentId, OrchestrationV2ShellSnapshot, ThreadId } from "@t3tools/contracts";
import {
  projectThreadAwarenessV2,
  type ProjectThreadAwarenessV2Input,
} from "@t3tools/shared/agentAwareness";
import * as DateTime from "effect/DateTime";

import type { HarmonyNotificationPhases } from "../../persistence/mobile-preferences";

type Thread = ProjectThreadAwarenessV2Input["thread"] &
  Pick<
    OrchestrationV2ShellSnapshot["threads"][number],
    "projectId" | "latestRunId" | "latestRunCompletedAt" | "snoozedAt" | "snoozedUntil"
  >;

export interface HarmonyAlertShell {
  readonly generation: number;
  readonly snapshotSequence: number;
  readonly projects: ReadonlyArray<
    Pick<OrchestrationV2ShellSnapshot["projects"][number], "id" | "title">
  >;
  readonly threads: ReadonlyArray<Thread>;
}

export interface HarmonyAgentAlert {
  readonly environmentId: EnvironmentId;
  readonly threadId: ThreadId;
  readonly phase: "waiting_for_approval" | "waiting_for_input" | "completed" | "failed";
}

export const harmonyAlertPhasePreferences = {
  waiting_for_approval: "notifyOnApproval",
  waiting_for_input: "notifyOnInput",
  completed: "notifyOnCompletion",
  failed: "notifyOnFailure",
} satisfies Record<HarmonyAgentAlert["phase"], keyof HarmonyNotificationPhases>;

export function usesHarmonyLocalAgentAlerts(input: {
  readonly foreground: boolean;
  readonly pushReady: boolean;
}): boolean {
  return input.foreground || !input.pushReady;
}

function snoozedCompletion(thread: Thread): boolean {
  const completedAt = thread.latestRunCompletedAt;
  return (
    completedAt != null &&
    thread.snoozedUntil != null &&
    DateTime.isLessThan(completedAt, thread.snoozedUntil) &&
    (thread.snoozedAt == null || !DateTime.isLessThan(completedAt, thread.snoozedAt))
  );
}

export function collectHarmonyAgentAlerts(
  environmentId: EnvironmentId,
  previous: HarmonyAlertShell | undefined,
  current: HarmonyAlertShell,
  visibleThread: string | null,
  preferences?: HarmonyNotificationPhases,
): HarmonyAgentAlert[] {
  if (
    previous?.generation !== current.generation ||
    previous.snapshotSequence >= current.snapshotSequence
  )
    return [];

  const oldThreads = new Map(previous.threads.map((thread) => [thread.id, thread]));
  const projects = new Map(current.projects.map((project) => [project.id, project]));
  const alerts: HarmonyAgentAlert[] = [];
  for (const thread of current.threads) {
    const oldThread = oldThreads.get(thread.id);
    if (oldThread === thread) continue;
    const project = projects.get(thread.projectId);
    if (!project) continue;
    const state = projectThreadAwarenessV2({ environmentId, project, thread });
    if (state === null || state.deepLink === visibleThread) continue;

    const { phase } = state;
    if (
      phase !== "waiting_for_input" &&
      phase !== "waiting_for_approval" &&
      phase !== "completed" &&
      phase !== "failed"
    ) {
      continue;
    }
    if (preferences?.[harmonyAlertPhasePreferences[phase]] === false) continue;
    if (phase === "waiting_for_input" || phase === "waiting_for_approval") {
      if (oldThread?.pendingRuntimeRequest?.id !== thread.pendingRuntimeRequest?.id) {
        alerts.push({ environmentId, threadId: thread.id, phase });
      }
    } else if (oldThread !== undefined) {
      const previousPhase = projectThreadAwarenessV2({
        environmentId,
        project,
        thread: oldThread,
      })?.phase;
      if (previousPhase === phase && oldThread.latestRunId === thread.latestRunId) continue;
      if (phase === "completed" && snoozedCompletion(thread)) continue;
      alerts.push({ environmentId, threadId: thread.id, phase });
    }
  }
  return alerts;
}
