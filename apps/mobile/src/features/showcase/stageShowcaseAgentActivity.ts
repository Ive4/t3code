import { Platform } from "react-native";

import { nativeNotifications } from "../../native/notifications";
import type { AgentActivityProps } from "../../widgets/AgentActivity";
import {
  getAgentLiveActivities,
  startAgentLiveActivity,
} from "../agent-awareness/agentLiveActivity";
import { showAndroidShowcaseAgentActivity } from "../agent-awareness/androidNotifications";
import { showcaseAndroidActivityData } from "./showcaseAgentActivity";

export async function stageShowcaseAgentActivity(
  activity: AgentActivityProps,
  now: number,
): Promise<true | string> {
  const Notifications = nativeNotifications;
  if (!Notifications || (Platform.OS !== "ios" && Platform.OS !== "android")) {
    return `unsupported platform ${Platform.OS}`;
  }
  const permission = await Notifications.requestPermissionsAsync({
    ios: { allowAlert: true, allowBadge: true, allowSound: true },
  });
  if (!permission.granted) return `notification permission ${permission.status}`;
  await Notifications.dismissAllNotificationsAsync();

  if (Platform.OS === "android") {
    return (
      showAndroidShowcaseAgentActivity(showcaseAndroidActivityData(activity, now)) ||
      "native showShowcaseActivity missing"
    );
  }

  await Promise.all(getAgentLiveActivities().map((existing) => existing.end("immediate")));
  // ActivityKit needs foreground startup; the runner locks only after this scene is ready.
  // oxlint-disable-next-line t3code/no-untranslated-copy -- showcase runner failure, read by the screenshot runner
  return startAgentLiveActivity(activity) !== null || "Live Activity did not start";
}
