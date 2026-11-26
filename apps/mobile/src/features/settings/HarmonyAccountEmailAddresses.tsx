import { useSession, useUser } from "@clerk/expo";
import type { EmailAddressResource, UserResource } from "@clerk/expo/types";
import { useGT } from "gt-react-native";
import { useRef, useState } from "react";
import { Keyboard, View } from "react-native";

import { AppText, AppTextInput } from "../../components/ui/AppText";
import { Button } from "../../components/ui/Button";
import * as Dialog from "../../components/ui/Dialog";
import { ListRowLayout } from "../../components/ui/ListRowLayout";
import { SettingsSection } from "./components/SettingsSection";
import {
  HarmonyVerificationCodeInput,
  isHarmonyReverificationCancelled,
  useHarmonyAccountReverification,
} from "./HarmonyAccountReverification";

type Mutation =
  | { readonly kind: "add"; readonly email: string }
  | { readonly kind: "primary" | "remove"; readonly id: string };

type Form =
  | { readonly kind: "add" }
  | { readonly kind: "verify"; readonly address: EmailAddressResource; readonly sent: boolean };

export function HarmonyAccountEmailAddresses() {
  const { user } = useUser();
  const { session } = useSession();
  return user && session ? <EmailAddresses key={session.id} user={user} /> : null;
}

function EmailAddresses({ user }: { readonly user: UserResource }) {
  const gt = useGT();
  const [form, setForm] = useState<Form | null>(null);
  const [value, setValue] = useState("");
  const [pending, setPending] = useState(false);
  const [failed, setFailed] = useState(false);
  const busy = useRef(false);
  const {
    run: mutate,
    prompt,
    isActive,
  } = useHarmonyAccountReverification(
    async (mutation: Mutation): Promise<EmailAddressResource | undefined> => {
      if (mutation.kind === "add") return user.createEmailAddress({ email: mutation.email });
      const address = user.emailAddresses.find(({ id }) => id === mutation.id);
      if (!address || address.id === user.primaryEmailAddressId) {
        throw new Error("The email address is no longer available for this action.");
      }
      if (mutation.kind === "primary") {
        if (address.verification.status !== "verified")
          throw new Error("Unverified email address.");
        await user.update({ primaryEmailAddressId: address.id });
      } else {
        await address.destroy();
      }
    },
  );

  async function perform(action: () => Promise<void>) {
    if (!isActive() || busy.current) return;
    busy.current = true;
    setPending(true);
    setFailed(false);
    Keyboard.dismiss();
    try {
      await action();
    } catch (error) {
      if (isActive() && !isHarmonyReverificationCancelled(error)) setFailed(true);
    } finally {
      busy.current = false;
      if (isActive()) setPending(false);
    }
  }

  async function sendCode(address: EmailAddressResource) {
    setForm({ kind: "verify", address, sent: false });
    setValue("");
    await address.prepareVerification({ strategy: "email_code" });
    if (isActive()) setForm({ kind: "verify", address, sent: true });
  }

  function submit() {
    const input = value.trim();
    if (!form || !input || (form.kind === "verify" && !form.sent)) return;
    void perform(async () => {
      if (form.kind === "add") {
        const address = await mutate({ kind: "add", email: input });
        if (!address) throw new Error("Could not add the email.");
        try {
          if (isActive()) await sendCode(address);
        } finally {
          await user.reload();
        }
        return;
      }
      const address = await form.address.attemptVerification({ code: input });
      if (address.verification.status !== "verified") throw new Error("Unverified email address.");
      if (isActive()) {
        setForm(null);
        setValue("");
      }
      await user.reload();
    });
  }

  function updateAddress(kind: "primary" | "remove", id: string) {
    void perform(async () => {
      await mutate({ kind, id });
      await user.reload();
    });
  }

  const emailLabel = gt("Email address");
  const controlsDisabled = pending || form !== null;
  return (
    <SettingsSection title={gt("Email addresses")}>
      {user.emailAddresses.map((address) => {
        const primary = address.id === user.primaryEmailAddressId;
        const verified = address.verification.status === "verified";
        const action = verified ? gt("Make primary") : gt("Verify email");
        const remove = gt("Remove");
        return (
          <View key={address.id}>
            <ListRowLayout
              label={address.emailAddress}
              detail={primary ? gt("Primary") : verified ? undefined : gt("Unverified")}
            />
            {primary && verified ? null : (
              <View className="flex-row flex-wrap gap-2 px-4 pb-3">
                <Button
                  label={action}
                  accessibilityLabel={`${action}, ${address.emailAddress}`}
                  tone="text"
                  disabled={controlsDisabled}
                  onPress={() =>
                    verified
                      ? updateAddress("primary", address.id)
                      : void perform(() => sendCode(address))
                  }
                />
                {primary ? null : (
                  <Button
                    label={remove}
                    accessibilityLabel={`${remove}, ${address.emailAddress}`}
                    tone="text"
                    disabled={controlsDisabled}
                    onPress={() =>
                      Dialog.confirm({
                        title: gt("Remove email address?"),
                        message: address.emailAddress,
                        confirmText: remove,
                        destructive: true,
                        onConfirm: () => updateAddress("remove", address.id),
                      })
                    }
                  />
                )}
              </View>
            )}
          </View>
        );
      })}
      <View className="gap-3 p-4">
        {prompt ??
          (form ? (
            <>
              {form.kind === "add" ? (
                <AppTextInput
                  accessibilityLabel={emailLabel}
                  placeholder={emailLabel}
                  autoCapitalize="none"
                  autoComplete="email"
                  autoCorrect={false}
                  keyboardType="email-address"
                  editable={!pending}
                  value={value}
                  onChangeText={setValue}
                  onSubmitEditing={submit}
                />
              ) : form.sent ? (
                <>
                  <AppText textRole="footnote">
                    {gt("Enter the code sent to {address}.", {
                      address: form.address.emailAddress,
                    })}
                  </AppText>
                  <HarmonyVerificationCodeInput
                    value={value}
                    onChange={setValue}
                    onSubmit={submit}
                    disabled={pending}
                  />
                </>
              ) : null}
              <View className="flex-row flex-wrap gap-2">
                {form.kind === "add" || form.sent ? (
                  <Button
                    label={form.kind === "add" ? gt("Send code") : gt("Verify")}
                    tone="primary"
                    disabled={pending || !value.trim()}
                    onPress={submit}
                  />
                ) : null}
                {form.kind === "verify" ? (
                  <Button
                    label={gt("Resend code")}
                    tone="text"
                    disabled={pending}
                    onPress={() => void perform(() => sendCode(form.address))}
                  />
                ) : null}
                <Button
                  label={gt("Cancel")}
                  tone="text"
                  disabled={pending}
                  onPress={() => {
                    Keyboard.dismiss();
                    setFailed(false);
                    setForm(null);
                    setValue("");
                  }}
                />
              </View>
            </>
          ) : (
            <Button
              label={gt("Add email address")}
              disabled={pending}
              onPress={() => {
                setFailed(false);
                setForm({ kind: "add" });
              }}
            />
          ))}
        {failed ? (
          <AppText accessibilityRole="alert" className="text-danger-foreground">
            {gt("Could not update your email addresses. Try again.")}
          </AppText>
        ) : null}
      </View>
    </SettingsSection>
  );
}
