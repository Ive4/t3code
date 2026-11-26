import { useAtomValue } from "@effect/atom-react";
import { useGT } from "gt-react-native";
import { useState } from "react";

import * as Dialog from "../../components/ui/Dialog";
import { ScreenScrollView } from "../../components/ui/ScreenScrollView";
import {
  harmonyPushRegistrationStateAtom,
  huaweiPushAccountAvailableAtom,
  refreshHuaweiPushAccount,
  signInHuaweiPushAccount,
  signOutHuaweiPushAccount,
} from "../agent-awareness/harmonyAgentNotifications";
import { SettingsRow } from "./components/SettingsRow";
import { SettingsScreen } from "./components/SettingsScreen";
import { SettingsSection } from "./components/SettingsSection";

export function SettingsHuaweiAccountRouteScreen() {
  const gt = useGT();
  const available = useAtomValue(huaweiPushAccountAvailableAtom);
  const { session, pending, error } = useAtomValue(harmonyPushRegistrationStateAtom);
  const [busy, setBusy] = useState(false);
  const signedIn = session === "signedIn";

  async function changeSession() {
    setBusy(true);
    try {
      if (signedIn) await signOutHuaweiPushAccount();
      else await signInHuaweiPushAccount();
    } catch {
      Dialog.alert(signedIn ? gt("Couldn't sign out of Huawei") : gt("Couldn't sign in to Huawei"));
    } finally {
      setBusy(false);
    }
  }

  const status =
    !signedIn && available === false
      ? gt("Notifications unavailable")
      : (!signedIn && available === null) ||
          pending ||
          busy ||
          (session === "checking" && error === null)
        ? gt("Checking")
        : error === "session"
          ? gt("Couldn't reach the notification service")
          : session === "expired"
            ? gt("Session expired. Sign in again.")
            : signedIn
              ? gt("Signed in")
              : undefined;

  return (
    <SettingsScreen title={gt("Huawei Account")}>
      <ScreenScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerClassName="px-5 pt-4"
      >
        <SettingsSection
          footer={gt(
            "Sign in with your phone's Huawei Account to receive background notifications.",
          )}
        >
          <SettingsRow
            icon="person.crop.circle"
            label={signedIn ? gt("Sign out") : gt("Sign in to your Huawei Account")}
            value={status}
            valuePosition="below"
            disabled={
              (!signedIn && available !== true) || busy || pending || session === "checking"
            }
            onPress={() => void changeSession()}
          />
          {(signedIn || available) && error === "session" && (
            <SettingsRow
              icon="arrow.clockwise"
              label={gt("Try again")}
              disabled={pending}
              onPress={() => void refreshHuaweiPushAccount()}
            />
          )}
        </SettingsSection>
      </ScreenScrollView>
    </SettingsScreen>
  );
}
