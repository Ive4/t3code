import { Platform, TurboModuleRegistry, type TurboModule } from "react-native";

interface AgentNotificationsBridge extends TurboModule {
  isEnabled(): Promise<boolean>;
  openSettings(): Promise<boolean>;
  getPushToken(): Promise<string>;
  isHuaweiAccountAvailable?(): Promise<boolean>;
  signInHuaweiAccount?(): Promise<string | null>;
  observePushToken(): Promise<void>;
  deletePushToken(): Promise<void>;
  publish(title: string, text: string, environmentId: string, threadId: string): Promise<void>;
  takePendingLink(): Promise<{ readonly environmentId: string; readonly threadId: string } | null>;
}

export function getHarmonyAgentNotifications(): AgentNotificationsBridge | null {
  return String(Platform.OS) === "harmony"
    ? (TurboModuleRegistry.get<AgentNotificationsBridge>("T3AgentNotifications") ?? null)
    : null;
}
