import { useClerk, useUser } from "@clerk/expo";
import { useGT } from "gt-react-native";
import { useRef, useState } from "react";
import { Keyboard, View } from "react-native";

import { AppText, AppTextInput } from "../../components/ui/AppText";
import { Button } from "../../components/ui/Button";
import {
  isHarmonyReverificationCancelled,
  useHarmonyAccountReverification,
} from "./HarmonyAccountReverification";

export function HarmonyAccountDelete({ onDeleted }: { readonly onDeleted: () => void }) {
  const { user } = useUser();
  const clerk = useClerk();
  const gt = useGT();
  const [open, setOpen] = useState(false);
  const [confirmation, setConfirmation] = useState("");
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);
  const pending = useRef(false);
  const label = gt("Delete account");
  const { run, prompt } = useHarmonyAccountReverification(async (sessionId: string | undefined) => {
    if (
      !sessionId ||
      clerk.session?.id !== sessionId ||
      clerk.user?.id !== user?.id ||
      !user?.deleteSelfEnabled
    ) {
      throw new Error("The account is no longer available for deletion.");
    }
    await user.delete();
  });

  async function deleteAccount() {
    if (pending.current || confirmation.trim() !== label) return;
    pending.current = true;
    setBusy(true);
    setFailed(false);
    Keyboard.dismiss();
    try {
      await run(clerk.session?.id);
      onDeleted();
    } catch (error) {
      if (!isHarmonyReverificationCancelled(error)) setFailed(true);
    } finally {
      pending.current = false;
      setBusy(false);
    }
  }

  if (!user?.deleteSelfEnabled) return null;
  return (
    <View className="gap-3 rounded-[24px] bg-grouped-card p-4">
      {prompt ??
        (open ? (
          <>
            <AppText>{gt("Deleting your T3 account is permanent and cannot be undone.")}</AppText>
            <AppText textRole="footnote">
              {gt("Enter {phrase} to confirm.", { phrase: label })}
            </AppText>
            <AppTextInput
              accessibilityLabel={gt("Confirm account deletion")}
              autoCapitalize="none"
              autoCorrect={false}
              editable={!busy}
              value={confirmation}
              onChangeText={setConfirmation}
            />
            {failed ? (
              <AppText accessibilityRole="alert" className="text-danger-foreground">
                {gt("Could not delete your account. Try again.")}
              </AppText>
            ) : null}
            <View className="flex-row flex-wrap gap-2">
              <Button
                label={label}
                tone="danger"
                loading={busy}
                disabled={busy || confirmation.trim() !== label}
                onPress={() => void deleteAccount()}
              />
              <Button
                label={gt("Cancel")}
                tone="text"
                disabled={busy}
                onPress={() => {
                  Keyboard.dismiss();
                  setOpen(false);
                  setConfirmation("");
                  setFailed(false);
                }}
              />
            </View>
          </>
        ) : (
          <Button label={label} tone="danger" onPress={() => setOpen(true)} />
        ))}
    </View>
  );
}
