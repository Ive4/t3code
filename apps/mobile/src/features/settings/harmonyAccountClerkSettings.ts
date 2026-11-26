import { getClerkInstance } from "@clerk/expo";
import type { UserSettingsResource } from "@clerk/expo/types";

export function readHarmonyAccountUserSettings() {
  // Expo's native singleton exposes the loaded environment at runtime.
  const clerk: ReturnType<typeof getClerkInstance> & {
    readonly __internal_environment?: { readonly userSettings?: UserSettingsResource } | null;
  } = getClerkInstance();
  return clerk.__internal_environment?.userSettings;
}
