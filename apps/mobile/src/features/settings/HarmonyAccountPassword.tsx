import { useAuth, useClerk, useUser } from "@clerk/expo";
import type { UpdateUserPasswordParams, UserResource } from "@clerk/expo/types";
import { useGT } from "gt-react-native";
import { useRef, useState } from "react";
import { Keyboard, View } from "react-native";

import { AppText } from "../../components/ui/AppText";
import { Button } from "../../components/ui/Button";
import { SecretTextInput } from "../../components/ui/SecretTextInput";
import type { SecretTextInputHandle } from "../../components/ui/SecretTextInput.types";
import {
  isHarmonyReverificationCancelled,
  useHarmonyAccountReverification,
} from "./HarmonyAccountReverification";
import {
  canSubmitHarmonyNewPassword,
  emptyHarmonyNewPassword,
  HarmonyNewPasswordFields,
} from "./HarmonyNewPasswordFields";
import { SettingsSection } from "./components/SettingsSection";

export function HarmonyAccountPassword() {
  const { user } = useUser();
  const { sessionId } = useAuth();
  return user && sessionId ? (
    <AccountPassword key={`${user.id}:${sessionId}`} user={user} sessionId={sessionId} />
  ) : null;
}

function AccountPassword({
  user,
  sessionId,
}: {
  readonly user: UserResource;
  readonly sessionId: string;
}) {
  const gt = useGT();
  const clerk = useClerk();
  const [editing, setEditing] = useState(false);
  const [currentPassword, setCurrentPassword] = useState("");
  const [draft, setDraft] = useState(emptyHarmonyNewPassword);
  const [status, setStatus] = useState<"pending" | "saved" | "failed" | null>(null);
  const busy = useRef(false);
  const firstInput = useRef<SecretTextInputHandle | null>(null);
  const userId = user.id;
  const hasPassword = user.passwordEnabled;
  const { run, prompt } = useHarmonyAccountReverification(
    async (changes: UpdateUserPasswordParams) => {
      if (clerk.user?.id !== userId || clerk.session?.id !== sessionId) {
        throw new Error("The active account changed.");
      }
      return user.updatePassword(changes);
    },
  );

  function closeEditor() {
    setEditing(false);
    setCurrentPassword("");
    setDraft(emptyHarmonyNewPassword);
  }

  function canSubmit(confirmation: string) {
    return (
      (!hasPassword || Boolean(currentPassword)) &&
      canSubmitHarmonyNewPassword(draft.password, confirmation)
    );
  }

  async function submit(confirmation: string) {
    if (busy.current || !canSubmit(confirmation)) return;
    busy.current = true;
    setStatus("pending");
    Keyboard.dismiss();
    try {
      const updated = await run({
        ...(hasPassword ? { currentPassword } : {}),
        newPassword: draft.password,
        signOutOfOtherSessions: draft.signOutOfOtherSessions,
      });
      if (!updated?.passwordEnabled) throw new Error("The password change did not complete.");
      closeEditor();
      setStatus("saved");
    } catch (error) {
      if (isHarmonyReverificationCancelled(error)) {
        closeEditor();
        setStatus(null);
      } else {
        setStatus("failed");
      }
    } finally {
      busy.current = false;
    }
  }

  const pending = status === "pending";
  const currentLabel = gt("Current password");
  return (
    <SettingsSection title={gt("Password")}>
      <View className="gap-3 p-4">
        {prompt ??
          (editing ? (
            <>
              {hasPassword ? (
                <SecretTextInput
                  accessibilityLabel={currentLabel}
                  placeholder={currentLabel}
                  value={currentPassword}
                  editable={!pending}
                  onChangeText={setCurrentPassword}
                  onSubmitEditing={() => firstInput.current?.focus()}
                  returnKeyType="next"
                />
              ) : null}
              <HarmonyNewPasswordFields
                value={draft}
                editable={!pending}
                onChange={setDraft}
                onSubmit={(confirmation) => void submit(confirmation)}
                onFirstInputMount={(handle) => {
                  firstInput.current = handle;
                }}
              />
              <View className="flex-row flex-wrap gap-2">
                <Button
                  label={gt("Save")}
                  tone="primary"
                  loading={pending}
                  disabled={pending || !canSubmit(draft.confirmation)}
                  onPress={() => void submit(draft.confirmation)}
                />
                <Button
                  label={gt("Cancel")}
                  tone="text"
                  disabled={pending}
                  onPress={() => {
                    Keyboard.dismiss();
                    closeEditor();
                    setStatus(null);
                  }}
                />
              </View>
            </>
          ) : (
            <Button
              label={hasPassword ? gt("Change password") : gt("Add password")}
              onPress={() => {
                setStatus(null);
                setEditing(true);
              }}
            />
          ))}
        {status === "saved" ? (
          <AppText accessibilityRole="alert">{gt("Password saved.")}</AppText>
        ) : null}
        {status === "failed" ? (
          <AppText accessibilityRole="alert" className="text-danger-foreground">
            {gt("Could not save the password. Try again.")}
          </AppText>
        ) : null}
      </View>
    </SettingsSection>
  );
}
