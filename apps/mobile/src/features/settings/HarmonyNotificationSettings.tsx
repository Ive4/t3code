import { useAtom, useAtomValue } from "@effect/atom-react";
import { runAtomCommand } from "@t3tools/client-runtime/state/runtime";
import { AsyncResult } from "effect/reactivity";
import { msg, useGT, useMessages } from "gt-react-native";
import { useState } from "react";

import * as Dialog from "../../components/ui/Dialog";
import { ScreenScrollView } from "../../components/ui/ScreenScrollView";
import type { HarmonyNotificationPhases } from "../../persistence/mobile-preferences";
import { appAtomRegistry } from "../../state/atom-registry";
import { mobilePreferencesAtom, saveMobilePreferences } from "../../state/preferences";
import {
  harmonyAgentNotificationPermissionAtom,
  harmonyAgentNotifications,
  harmonyPushConfigured,
  harmonyPushRegistrationStateAtom,
  refreshHuaweiPushAccount,
} from "../agent-awareness/harmonyAgentNotifications";
import { SettingsRow } from "./components/SettingsRow";
import { SettingsScreen } from "./components/SettingsScreen";
import { SettingsSection } from "./components/SettingsSection";
import { SettingsSwitchRow } from "./components/SettingsSwitchRow";

const phaseLabels = [
  ["notifyOnApproval", msg("Approval needed")],
  ["notifyOnInput", msg("User input needed")],
  ["notifyOnCompletion", msg("Agent work completed")],
  ["notifyOnFailure", msg("Agent work failed")],
] as const satisfies ReadonlyArray<readonly [keyof HarmonyNotificationPhases, string]>;

export function HarmonyNotificationSettings() {
  const gt = useGT();
  const m = useMessages();
  const [enabled, setEnabled] = useAtom(harmonyAgentNotificationPermissionAtom);
  const [opening, setOpening] = useState(false);
  const [saving, setSaving] = useState(false);
  const preferencesResult = useAtomValue(mobilePreferencesAtom);
  const preferences = AsyncResult.isSuccess(preferencesResult)
    ? preferencesResult.value
    : undefined;
  const optedIn = preferences?.harmonyBackgroundNotificationsEnabled === true;
  const { ready, pending, session, error } = useAtomValue(harmonyPushRegistrationStateAtom);
  const signedIn = session === "signedIn";

  async function openSettings() {
    if (harmonyAgentNotifications === null || opening) return;
    setOpening(true);
    try {
      setEnabled(await harmonyAgentNotifications.openSettings());
    } catch {
      Dialog.alert(gt("Couldn't open Settings"));
    } finally {
      setOpening(false);
    }
  }

  async function savePreference(patch: Parameters<typeof saveMobilePreferences.run>[1]) {
    setSaving(true);
    try {
      const result = await runAtomCommand(appAtomRegistry, saveMobilePreferences, patch);
      if (result._tag === "Failure") Dialog.alert(gt("Could not save preferences"));
    } finally {
      setSaving(false);
    }
  }

  const backgroundStatus =
    session === "checking" || pending || saving
      ? gt("Checking")
      : !signedIn
        ? gt("Sign in to your Huawei Account")
        : error !== null
          ? gt("Notifications unavailable")
          : !optedIn
            ? undefined
            : enabled === false
              ? gt("Notifications disabled")
              : ready.size > 0
                ? gt("Enabled")
                : gt("Notifications unavailable");

  return (
    <SettingsScreen title={gt("Notifications")}>
      <ScreenScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerClassName="px-5 pt-4"
      >
        <SettingsSection
          footer={
            harmonyPushConfigured
              ? gt(
                  "Background notifications are available from paired environments configured to send them.",
                )
              : gt("Agent alerts arrive while this app is running and connected to an environment.")
          }
        >
          <SettingsRow
            icon="bell.badge"
            label={gt("Device Notifications")}
            value={
              enabled === null
                ? gt("Checking")
                : enabled
                  ? gt("Enabled")
                  : gt("Notifications disabled")
            }
            disabled={enabled === null || opening}
            onPress={() => void openSettings()}
          />
          {harmonyPushConfigured && (
            <SettingsSwitchRow
              label={gt("Background notifications")}
              subtitle={backgroundStatus}
              value={optedIn}
              disabled={
                saving || (!optedIn && !signedIn) || !AsyncResult.isSuccess(preferencesResult)
              }
              onValueChange={(value) =>
                void savePreference({ harmonyBackgroundNotificationsEnabled: value })
              }
            />
          )}
          {harmonyPushConfigured && !signedIn && (
            <SettingsRow
              icon="person.crop.circle"
              label={gt("Huawei Account")}
              target="SettingsHuaweiAccount"
            />
          )}
          {harmonyPushConfigured && signedIn && error !== null && (
            <SettingsRow
              icon="arrow.clockwise"
              label={gt("Try again")}
              disabled={pending}
              onPress={() => void refreshHuaweiPushAccount()}
            />
          )}
        </SettingsSection>
        <SettingsSection title={gt("Agent alerts")}>
          {phaseLabels.map(([key, label]) => (
            <SettingsSwitchRow
              key={key}
              label={m(label)}
              value={preferences?.harmonyNotificationPhases?.[key] !== false}
              disabled={saving || !AsyncResult.isSuccess(preferencesResult)}
              onValueChange={(value) =>
                void savePreference({
                  transform: (current) => ({
                    harmonyNotificationPhases: {
                      ...current.harmonyNotificationPhases,
                      [key]: value,
                    },
                  }),
                })
              }
            />
          ))}
        </SettingsSection>
      </ScreenScrollView>
    </SettingsScreen>
  );
}
