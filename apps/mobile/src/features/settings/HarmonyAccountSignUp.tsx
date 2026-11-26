import { useClerk, useSignUp } from "@clerk/expo";
import { useHostedAuth } from "@clerk/expo/hosted-auth";
import { useGT } from "gt-react-native";
import { useLayoutEffect, useRef, useState } from "react";
import { Keyboard, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { AppActivityIndicator } from "../../components/ui/AppActivityIndicator";
import { AppText, AppTextInput } from "../../components/ui/AppText";
import { Button } from "../../components/ui/Button";
import { ScreenScrollView } from "../../components/ui/ScreenScrollView";
import { SecretTextInput } from "../../components/ui/SecretTextInput";
import type { SecretTextInputHandle } from "../../components/ui/SecretTextInput.types";
import { harmonyAccountRedirect } from "../cloud/harmonyHostedAuth";

type SignUpStep = "form" | "code" | "activate" | "hosted" | "complete";
type Operation = "submit" | "resend" | "browser";

export function HarmonyAccountSignUp(props: {
  readonly initialEmail: string;
  readonly onBack: () => void;
}) {
  const gt = useGT();
  const { bottom } = useSafeAreaInsets();
  const { signUp, fetchStatus } = useSignUp();
  const clerk = useClerk();
  const { startHostedAuth } = useHostedAuth();
  const pending = useRef<AbortController | null>(null);
  const passwordInput = useRef<SecretTextInputHandle | null>(null);
  const [step, setStep] = useState<SignUpStep>("form");
  const [operation, setOperation] = useState<Operation | null>(null);
  const [email, setEmail] = useState(props.initialEmail);
  const [password, setPassword] = useState("");
  const [code, setCode] = useState("");
  const [failed, setFailed] = useState(false);
  const busy = operation !== null || fetchStatus === "fetching";

  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- prevents an abandoned account form from activating a session
  useLayoutEffect(() => () => pending.current?.abort(), []);

  async function perform(kind: Operation, action: (signal: AbortSignal) => Promise<void>) {
    if (pending.current) return;
    const controller = new AbortController();
    pending.current = controller;
    setOperation(kind);
    setFailed(false);
    Keyboard.dismiss();
    try {
      await action(controller.signal);
    } catch {
      if (!controller.signal.aborted) setFailed(true);
    } finally {
      pending.current = null;
      if (!controller.signal.aborted) setOperation(null);
    }
  }

  function showHostedStep() {
    setPassword("");
    setCode("");
    setStep("hosted");
  }

  async function sendEmailCode(signal: AbortSignal) {
    const { error } = await signUp.verifications.sendEmailCode();
    if (signal.aborted) return;
    if (signUp.protectCheck || (error && /captcha|protect_check/.test(error.code))) {
      showHostedStep();
    } else if (error) {
      throw error;
    }
  }

  function submitPassword(value: string) {
    const address = email.trim();
    if (!address || !value.trim()) return;
    void perform("submit", async (signal) => {
      const { error } = await signUp.password({ emailAddress: address, password: value });
      if (signal.aborted) return;
      if (error && !signUp.protectCheck && !/captcha|protect_check/.test(error.code)) throw error;
      if (
        error ||
        signUp.protectCheck ||
        signUp.status !== "missing_requirements" ||
        signUp.missingFields.length > 0 ||
        signUp.unverifiedFields.length !== 1 ||
        signUp.unverifiedFields[0] !== "email_address"
      ) {
        showHostedStep();
        return;
      }
      setEmail(address);
      setPassword("");
      setStep("code");
      await sendEmailCode(signal);
    });
  }

  async function activate(signal: AbortSignal) {
    const sessionId = signUp.createdSessionId;
    // oxlint-disable-next-line t3code/no-rpc-permission-bypass -- Clerk exposes pending signup tasks through its account client.
    const created = clerk.client?.sessions.find((session) => session.id === sessionId);
    if (
      signUp.status !== "complete" ||
      !sessionId ||
      signUp.protectCheck ||
      signUp.missingFields.length > 0 ||
      signUp.unverifiedFields.length > 0 ||
      signUp.verifications.emailAddress.status !== "verified" ||
      created?.status === "pending" ||
      created?.currentTask
    ) {
      showHostedStep();
      return;
    }
    setStep("activate");
    const additionalRequirements = new Error("Clerk requires another registration step.");
    const { error } = await signUp.finalize({
      navigate: ({ session }) => {
        if (signal.aborted) throw new Error("Registration was closed.");
        if (session.status === "pending" || session.currentTask) throw additionalRequirements;
      },
    });
    if (signal.aborted) return;
    if (error === additionalRequirements) {
      showHostedStep();
      return;
    }
    if (error) throw error;
    if (clerk.session?.id !== sessionId) throw new Error("Clerk did not activate the new session.");
    setStep("complete");
  }

  function verifyCode(value: string) {
    if (!value.trim()) return;
    void perform("submit", async (signal) => {
      const { error } = await signUp.verifications.verifyEmailCode({ code: value.trim() });
      if (signal.aborted) return;
      if (signUp.protectCheck || (error && /captcha|protect_check/.test(error.code))) {
        showHostedStep();
        return;
      }
      if (error) throw error;
      setCode("");
      await activate(signal);
    });
  }

  function openHosted() {
    setPassword("");
    void perform("browser", async (signal) => {
      const authSessionOptions = { showInRecents: false, signal };
      await startHostedAuth({
        mode: "sign-up",
        redirectUrl: harmonyAccountRedirect,
        authSessionOptions,
      });
    });
  }

  if (step === "complete") {
    return (
      <View className="flex-1 items-center justify-center">
        <AppActivityIndicator />
      </View>
    );
  }

  const emailLabel = gt("Email address");
  const passwordLabel = gt("New password");
  const codeLabel = gt("Verification code");
  return (
    <ScreenScrollView
      className="flex-1"
      keyboardShouldPersistTaps="handled"
      contentContainerStyle={{ paddingBottom: bottom + 24 }}
    >
      <View className="w-full max-w-[480px] self-center gap-4 px-6 pt-7">
        {failed ? (
          <AppText accessibilityRole="alert" textRole="footnote" className="text-danger-foreground">
            {gt("Could not create your account. Try again.")}
          </AppText>
        ) : null}
        {step === "form" ? (
          <>
            <AppTextInput
              accessibilityLabel={emailLabel}
              placeholder={emailLabel}
              autoCapitalize="none"
              autoComplete="email"
              autoCorrect={false}
              keyboardType="email-address"
              editable={!busy}
              value={email}
              onChangeText={setEmail}
              onSubmitEditing={() => passwordInput.current?.focus()}
              returnKeyType="next"
              submitBehavior="submit"
            />
            <SecretTextInput
              accessibilityLabel={passwordLabel}
              placeholder={passwordLabel}
              editable={!busy}
              value={password}
              onChangeText={setPassword}
              onSubmitEditing={submitPassword}
              onMount={(handle) => {
                passwordInput.current = handle;
              }}
            />
            <Button
              label={gt("Continue")}
              tone="primary"
              fullWidth
              disabled={busy || !email.trim() || !password.trim()}
              loading={operation === "submit"}
              onPress={() => submitPassword(password)}
            />
          </>
        ) : step === "code" ? (
          <>
            <AppText textRole="footnote">
              {gt("Enter the code sent to {email}.", { email })}
            </AppText>
            <AppTextInput
              accessibilityLabel={codeLabel}
              placeholder={codeLabel}
              autoComplete="one-time-code"
              keyboardType="number-pad"
              editable={!busy}
              value={code}
              onChangeText={setCode}
              onSubmitEditing={(event) => verifyCode(event.nativeEvent.text)}
              returnKeyType="go"
            />
            <Button
              label={gt("Verify")}
              tone="primary"
              fullWidth
              disabled={busy || !code.trim()}
              loading={operation === "submit"}
              onPress={() => verifyCode(code)}
            />
            <Button
              label={gt("Resend code")}
              tone="text"
              disabled={busy}
              loading={operation === "resend"}
              onPress={() => void perform("resend", sendEmailCode)}
            />
            <Button
              label={gt("Change email")}
              tone="text"
              disabled={busy}
              onPress={() =>
                void perform("submit", async (signal) => {
                  const { error } = await signUp.reset();
                  if (error) throw error;
                  if (!signal.aborted) {
                    setCode("");
                    setStep("form");
                  }
                })
              }
            />
          </>
        ) : step === "activate" ? (
          <Button
            label={gt("Retry")}
            tone="primary"
            fullWidth
            disabled={busy}
            loading={operation === "submit"}
            onPress={() => void perform("submit", activate)}
          />
        ) : (
          <AppText textRole="body">
            {gt("Continue in your browser to finish creating your account.")}
          </AppText>
        )}
        {operation === "browser" ? (
          <Button
            label={gt("Cancel")}
            tone="text"
            onPress={() => {
              pending.current?.abort();
              setOperation(null);
            }}
          />
        ) : (
          <Button
            label={gt("Sign up with your browser")}
            tone={step === "hosted" ? "primary" : "text"}
            fullWidth={step === "hosted"}
            disabled={busy}
            onPress={openHosted}
          />
        )}
        <Button label={gt("Back to sign in")} tone="text" onPress={props.onBack} />
      </View>
    </ScreenScrollView>
  );
}
