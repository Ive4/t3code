import { enabledEnvironmentIds } from "@t3tools/client-runtime/state/connections";
import { sessionDeniesScope } from "@t3tools/client-runtime/state/session";
import { AuthOrchestrationReadScope, type EnvironmentId } from "@t3tools/contracts";
import * as Option from "effect/Option";
import { AsyncResult, Atom } from "effect/reactivity";
import { deleteItemAsync, getItemAsync, setItemAsync } from "expo-secure-store";
import { msg } from "gt-react-native";
import { AppState, DeviceEventEmitter } from "react-native";

import { environmentCatalog } from "../../connection/catalog";
import { m } from "../../i18n/messages";
import { subscribeAppActive } from "../../lib/appState";
import { makePermissionStatusAtom } from "../../lib/permissionStatusAtom";
import { appAtomRegistry } from "../../state/atom-registry";
import { mobilePreferencesAtom } from "../../state/preferences";
import { environmentSession, sessionHasScope } from "../../state/session";
import { environmentShell } from "../../state/shell";
import { getHarmonyPushPublicUrl } from "../cloud/publicConfig";
import {
  collectHarmonyAgentAlerts,
  usesHarmonyLocalAgentAlerts,
  type HarmonyAgentAlert,
  type HarmonyAlertShell,
} from "./harmonyAgentAlerts";
import { encodeThreadDeepLink } from "./notificationPayload";
import { getHarmonyAgentNotifications } from "./harmonyAgentNotificationBridge";
import {
  createHarmonyPushRegistration,
  createHarmonyPushService,
  initialHarmonyPushRegistrationState,
  normalizeHarmonyPushOrigin,
} from "./harmonyPushRegistration";

export const harmonyAgentNotifications = getHarmonyAgentNotifications();

export const harmonyAgentNotificationPermissionAtom = makePermissionStatusAtom<boolean | null>({
  label: "harmony:agent-notification-permission",
  initial: null,
  read: async () => harmonyAgentNotifications?.isEnabled().catch(() => false) ?? false,
});

const registrationInputsAtom = Atom.make((get) => {
  const result = get(mobilePreferencesAtom);
  const catalog = get(environmentCatalog.catalogValueAtom);
  const environments = new Map<EnvironmentId, boolean | undefined>();
  for (const id of enabledEnvironmentIds(catalog)) {
    const session = get(environmentSession.sessionStateAtom(id));
    const scope = AuthOrchestrationReadScope;
    environments.set(
      id,
      sessionHasScope(session, scope)
        ? true
        : sessionDeniesScope(session, scope)
          ? false
          : undefined,
    );
  }
  return {
    environments: catalog.isReady ? environments : undefined,
    permission: get(harmonyAgentNotificationPermissionAtom),
    preferences: AsyncResult.isSuccess(result)
      ? {
          enabled: result.value.harmonyBackgroundNotificationsEnabled === true,
          phases: result.value.harmonyNotificationPhases,
        }
      : undefined,
  };
}).pipe(Atom.withLabel("harmony:push-registration-inputs"));

export const harmonyPushRegistrationStateAtom = Atom.make(initialHarmonyPushRegistrationState).pipe(
  Atom.keepAlive,
  Atom.withLabel("harmony:push-registration-state"),
);

const origin = normalizeHarmonyPushOrigin(getHarmonyPushPublicUrl());
const native = harmonyAgentNotifications;
const sessionStorageKey = "t3.harmony.push.session";
const harmonyPushRegistration =
  origin && native?.getPushToken && native.signInHuaweiAccount
    ? createHarmonyPushRegistration({
        service: createHarmonyPushService(origin),
        read: () => getItemAsync(sessionStorageKey),
        write: (value) =>
          value === null
            ? deleteItemAsync(sessionStorageKey)
            : setItemAsync(sessionStorageKey, value),
        native: {
          getPushToken: native.getPushToken.bind(native),
          signInHuaweiAccount: native.signInHuaweiAccount.bind(native),
        },
        onChange: (state) => appAtomRegistry.set(harmonyPushRegistrationStateAtom, state),
      })
    : null;

export const harmonyPushConfigured = harmonyPushRegistration !== null;
export const huaweiPushAccountAvailableAtom = makePermissionStatusAtom<boolean | null>({
  label: "harmony:huawei-account-availability",
  initial: null,
  read: async () => {
    if (harmonyPushRegistration === null) return false;
    return (await native?.isHuaweiAccountAvailable?.().catch(() => false)) === true;
  },
});

export const signInHuaweiPushAccount = () => harmonyPushRegistration?.signIn();
export const signOutHuaweiPushAccount = () => harmonyPushRegistration?.signOut();
export const refreshHuaweiPushAccount = () => harmonyPushRegistration?.refresh();

function installHarmonyPushRegistration(
  native: NonNullable<typeof harmonyAgentNotifications>,
): () => void {
  const registration = harmonyPushRegistration;
  if (registration === null) return () => undefined;
  void registration.refresh();
  const releaseInputs = appAtomRegistry.subscribe(
    registrationInputsAtom,
    (inputs) => void registration.update(inputs),
    { immediate: true },
  );
  const releaseAppActive = subscribeAppActive(() => void registration.refresh());
  const tokenUpdates = DeviceEventEmitter.addListener(
    "T3AgentPushTokenUpdated",
    (token: unknown) => {
      void registration.observePushToken(token);
    },
  );
  void native.observePushToken?.().catch(() => {});
  return () => {
    releaseInputs();
    releaseAppActive();
    tokenUpdates.remove();
  };
}

const liveEnvironmentShellsAtom = Atom.make((get) => {
  const shells = new Map<EnvironmentId, HarmonyAlertShell>();
  if (get(harmonyAgentNotificationPermissionAtom) !== true) return shells;

  const environments = enabledEnvironmentIds(get(environmentCatalog.catalogValueAtom));
  for (const id of environments) {
    if (!sessionHasScope(get(environmentSession.sessionStateAtom(id)), AuthOrchestrationReadScope))
      continue;
    const { status, snapshot, generation } = get(environmentShell.stateValueAtom(id));
    if (status === "live" && Option.isSome(snapshot)) {
      shells.set(id, { ...snapshot.value, generation });
    }
  }
  return shells;
}).pipe(Atom.withLabel("harmony:live-notification-shells"));

const notificationText = {
  waiting_for_approval: msg("Approval needed"),
  waiting_for_input: msg("User input needed"),
  completed: msg("Agent work completed"),
  failed: msg("Agent work failed"),
} satisfies Record<HarmonyAgentAlert["phase"], string>;

export function installHarmonyAgentNotifications(
  navigate: (href: string) => void,
  threadOnScreen: () => string | null,
): () => void {
  const native = harmonyAgentNotifications;
  if (native === null) return () => undefined;
  let disposed = false;
  let previous = new Map<EnvironmentId, HarmonyAlertShell>();
  const releasePushRegistration = installHarmonyPushRegistration(native);
  const release = appAtomRegistry.subscribe(
    liveEnvironmentShellsAtom,
    (shells) => {
      const foreground = AppState.currentState === "active";
      const visibleThread = foreground ? threadOnScreen() : null;
      const result = appAtomRegistry.get(mobilePreferencesAtom);
      const preferences = AsyncResult.isSuccess(result) ? result.value : undefined;
      const pushReady =
        preferences?.harmonyBackgroundNotificationsEnabled === true && !foreground
          ? appAtomRegistry.get(harmonyPushRegistrationStateAtom).ready
          : undefined;
      for (const [environmentId, shell] of shells) {
        if (
          !usesHarmonyLocalAgentAlerts({
            foreground,
            pushReady: pushReady?.has(environmentId) === true,
          })
        )
          continue;
        for (const alert of collectHarmonyAgentAlerts(
          environmentId,
          previous.get(environmentId),
          shell,
          visibleThread,
          preferences?.harmonyNotificationPhases,
        )) {
          void native
            .publish(
              m(msg("Agent alerts")),
              m(notificationText[alert.phase]),
              environmentId,
              alert.threadId,
            )
            .catch(() => {});
        }
      }
      previous = shells;
    },
    { immediate: true },
  );

  const consumeLink = async () => {
    const link = await native.takePendingLink().catch(() => null);
    const href = link === null ? null : encodeThreadDeepLink(link);
    if (!disposed && href !== null) navigate(href);
  };
  const subscription = DeviceEventEmitter.addListener(
    "T3AgentNotificationTapped",
    () => void consumeLink(),
  );
  void consumeLink();
  return () => {
    disposed = true;
    release();
    releasePushRegistration();
    subscription.remove();
  };
}
