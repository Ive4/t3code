import { useSession, useUser } from "@clerk/expo";
import type { UserResource } from "@clerk/expo/types";
import { useGT } from "gt-react-native";
import { useRef, useState } from "react";
import { Keyboard, View } from "react-native";

import { AppText } from "../../components/ui/AppText";
import { Button } from "../../components/ui/Button";
import * as Dialog from "../../components/ui/Dialog";
import { SettingsSection } from "./components/SettingsSection";
import { readHarmonyAccountUserSettings } from "./harmonyAccountClerkSettings";
import {
  HarmonyVerificationCodeInput,
  isHarmonyReverificationCancelled,
  useHarmonyAccountReverification,
} from "./HarmonyAccountReverification";

type Mutation =
  | { readonly kind: "start" }
  | { readonly kind: "remove" }
  | { readonly kind: "generate" }
  | { readonly kind: "verify"; readonly code: string };

type Form =
  | { readonly kind: "setup"; readonly secret: string }
  | { readonly kind: "codes"; readonly codes: ReadonlyArray<string> };

function mfaCapabilities() {
  const attributes = readHarmonyAccountUserSettings()?.attributes;
  const authenticator = attributes?.authenticator_app;
  const backupCodes = attributes?.backup_code;
  return {
    authenticator: authenticator?.enabled === true && authenticator.used_for_second_factor,
    backupCodes: backupCodes?.enabled === true && backupCodes.used_for_second_factor,
  };
}

export function HarmonyAccountMfa() {
  const { user } = useUser();
  const { session } = useSession();
  const { authenticator, backupCodes } = mfaCapabilities();
  if (!user || !session || (!authenticator && !(backupCodes && user.twoFactorEnabled))) {
    return null;
  }
  return (
    <AccountMfa
      key={session.id}
      user={user}
      authenticatorAvailable={authenticator}
      backupCodesAvailable={backupCodes}
    />
  );
}

function AccountMfa({
  user,
  authenticatorAvailable,
  backupCodesAvailable,
}: {
  readonly user: UserResource;
  readonly authenticatorAvailable: boolean;
  readonly backupCodesAvailable: boolean;
}) {
  const gt = useGT();
  const [form, setForm] = useState<Form | null>(null);
  const [code, setCode] = useState("");
  const [pending, setPending] = useState(false);
  const [failed, setFailed] = useState(false);
  const busy = useRef(false);

  const { run, prompt, isActive } = useHarmonyAccountReverification(
    async (mutation: Mutation): Promise<Form | null> => {
      const { authenticator, backupCodes } = mfaCapabilities();
      if (mutation.kind === "generate") {
        if (!backupCodes || !user.twoFactorEnabled)
          throw new Error("Backup codes are unavailable.");
        const { codes } = await user.createBackupCode();
        if (!codes.length) throw new Error("Clerk did not generate backup codes.");
        return { kind: "codes", codes };
      }
      if (!authenticator) throw new Error("Authenticator apps are unavailable.");
      if (mutation.kind === "start") {
        if (user.totpEnabled) throw new Error("An authenticator app is already enabled.");
        const { secret } = await user.createTOTP();
        if (!secret) throw new Error("Clerk did not provide an authenticator setup key.");
        return { kind: "setup", secret };
      }
      if (mutation.kind === "remove") {
        await user.disableTOTP();
        return null;
      }
      const result = await user.verifyTOTP({ code: mutation.code });
      if (!result.verified) throw new Error("Clerk did not verify the authenticator code.");
      return result.backupCodes?.length ? { kind: "codes", codes: result.backupCodes } : null;
    },
  );

  async function perform(mutation: Mutation) {
    if (busy.current || !isActive()) return;
    busy.current = true;
    setPending(true);
    setFailed(false);
    setCode("");
    Keyboard.dismiss();
    try {
      const next = await run(mutation);
      if (!isActive()) return;
      setForm(next);
      if (mutation.kind !== "start") await user.reload();
    } catch (error) {
      if (isActive() && !isHarmonyReverificationCancelled(error)) {
        setFailed(true);
      }
    } finally {
      busy.current = false;
      if (isActive()) setPending(false);
    }
  }

  function verify() {
    const submitted = code.trim();
    if (form?.kind === "setup" && submitted) void perform({ kind: "verify", code: submitted });
  }

  function closeForm() {
    setCode("");
    setFailed(false);
    setForm(null);
  }

  return (
    <SettingsSection title={gt("Two-step verification")}>
      <View className="gap-3 p-4">
        {prompt ??
          (form?.kind === "setup" ? (
            <>
              <AppText textRole="footnote">
                {gt(
                  "Enter this setup key in your authenticator app, then enter the code it shows.",
                )}
              </AppText>
              <AppText selectable textRole="body">
                {form.secret}
              </AppText>
              <HarmonyVerificationCodeInput
                value={code}
                onChange={setCode}
                onSubmit={verify}
                disabled={pending}
              />
              <View className="flex-row flex-wrap gap-2">
                <Button
                  label={gt("Verify")}
                  tone="primary"
                  disabled={pending || !code.trim()}
                  onPress={verify}
                />
                <Button label={gt("Cancel")} tone="text" disabled={pending} onPress={closeForm} />
              </View>
            </>
          ) : form?.kind === "codes" ? (
            <>
              <AppText textRole="body" className="font-t3-semibold">
                {gt("Backup codes")}
              </AppText>
              <AppText textRole="footnote">
                {gt("Save these one-time codes somewhere safe. Each code can only be used once.")}
              </AppText>
              <AppText selectable textRole="body">
                {form.codes.join("\n")}
              </AppText>
              <Button
                label={gt("I saved my codes")}
                tone="primary"
                disabled={pending}
                onPress={closeForm}
              />
            </>
          ) : (
            <>
              {authenticatorAvailable &&
                (user.totpEnabled ? (
                  <Button
                    label={gt("Remove authenticator app")}
                    tone="danger"
                    disabled={pending}
                    onPress={() =>
                      Dialog.confirm({
                        title: gt("Remove authenticator app?"),
                        confirmText: gt("Remove"),
                        destructive: true,
                        onConfirm: () => void perform({ kind: "remove" }),
                      })
                    }
                  />
                ) : (
                  <Button
                    label={gt("Add authenticator app")}
                    disabled={pending}
                    onPress={() => void perform({ kind: "start" })}
                  />
                ))}
              {backupCodesAvailable && user.twoFactorEnabled ? (
                <Button
                  label={gt("Generate new backup codes")}
                  disabled={pending}
                  onPress={() =>
                    Dialog.confirm({
                      title: gt("Generate new backup codes?"),
                      ...(user.backupCodeEnabled
                        ? { message: gt("This invalidates your existing backup codes.") }
                        : {}),
                      confirmText: gt("Generate"),
                      onConfirm: () => void perform({ kind: "generate" }),
                    })
                  }
                />
              ) : null}
            </>
          ))}
        {failed ? (
          <AppText accessibilityRole="alert" className="text-danger-foreground">
            {gt("Could not update two-step verification. Try again.")}
          </AppText>
        ) : null}
      </View>
    </SettingsSection>
  );
}
