import { getClerkInstance, useAuth, useSignIn } from "@clerk/expo";
import { useSSO } from "@clerk/expo/experimental";
import { useHostedAuth } from "@clerk/expo/hosted-auth";
import { useNavigation } from "@react-navigation/native";
import { useGT } from "gt-react-native";
import { useEffect, useRef, useState } from "react";
import { Keyboard, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { AppActivityIndicator } from "../../components/ui/AppActivityIndicator";
import { AppBar } from "../../components/ui/AppBar";
import { AppText, AppTextInput } from "../../components/ui/AppText";
import { Button } from "../../components/ui/Button";
import { ScreenScrollView } from "../../components/ui/ScreenScrollView";
import { SecretTextInput } from "../../components/ui/SecretTextInput";
import { useHardwareBack } from "../../lib/backHandler";
import {
  advanceHarmonyPasswordRecovery,
  finishHarmonyEmailSignIn,
  startHarmonyEmailSignIn,
  supportsHarmonyPasswordRecovery,
  type HarmonyEmailSignInStep,
} from "../cloud/harmonyEmailSignIn";
import { harmonyAccountRedirect } from "../cloud/harmonyHostedAuth";
import { hasCloudPublicConfig } from "../cloud/publicConfig";
import { HarmonyAccountProfile } from "./HarmonyAccountProfile";
import { HarmonyAccountSignUp } from "./HarmonyAccountSignUp";
import { HarmonyAccountStartup } from "./HarmonyAccountStartup";
import {
  canSubmitHarmonyNewPassword,
  emptyHarmonyNewPassword,
  HarmonyNewPasswordFields,
} from "./HarmonyNewPasswordFields";

type Provider = "oauth_google" | "oauth_github" | "oauth_apple" | "oauth_microsoft";
type SignInStep = HarmonyEmailSignInStep | { readonly kind: "email" };
type Operation = "submit" | "resend" | "recover" | "browser";

export function SettingsAuthRouteScreen() {
  return hasCloudPublicConfig() ? <AccountScreen /> : null;
}

function AccountScreen() {
  const gt = useGT();
  const navigation = useNavigation();
  const { isLoaded, isSignedIn } = useAuth({ treatPendingAsSignedOut: false });
  const [signUpEmail, setSignUpEmail] = useState<string | null>(null);
  const goBack = () => {
    if (navigation.canGoBack()) navigation.goBack();
  };
  const closeSignUp = () => setSignUpEmail(null);
  useHardwareBack(signUpEmail !== null && !isSignedIn, () => {
    closeSignUp();
    return true;
  });

  if (isLoaded && isSignedIn) {
    return <HarmonyAccountProfile onBack={goBack} onSignedOut={goBack} />;
  }

  return (
    <View className="flex-1 bg-sheet">
      <AppBar
        title={signUpEmail === null ? gt("T3 Account") : gt("Create an account")}
        onBack={signUpEmail === null ? goBack : closeSignUp}
      />
      {!isLoaded ? (
        <HarmonyAccountStartup
          reload={() => getClerkInstance().__internal_reloadInitialResources()}
        />
      ) : signUpEmail !== null ? (
        <HarmonyAccountSignUp initialEmail={signUpEmail} onBack={closeSignUp} />
      ) : (
        <HarmonySignIn onSignUp={setSignUpEmail} />
      )}
    </View>
  );
}

function HarmonySignIn(props: { readonly onSignUp: (email: string) => void }) {
  const gt = useGT();
  const { bottom } = useSafeAreaInsets();
  const { signIn, fetchStatus } = useSignIn();
  const { startHostedAuth } = useHostedAuth();
  const { startSSOFlow } = useSSO();
  const pending = useRef<AbortController | null>(null);
  const [operation, setOperation] = useState<Operation | null>(null);
  const [error, setError] = useState(false);
  const [step, setStep] = useState<SignInStep>({ kind: "email" });
  const [email, setEmail] = useState("");
  const [value, setValue] = useState("");
  const [resetPassword, setResetPassword] = useState(emptyHarmonyNewPassword);
  const busy = operation !== null || fetchStatus === "fetching";

  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- closing the route releases any pending browser callback listener
  useEffect(() => () => pending.current?.abort(), []);

  async function perform(kind: Operation, action: (signal: AbortSignal) => Promise<void>) {
    if (pending.current) return;
    const controller = new AbortController();
    pending.current = controller;
    setOperation(kind);
    setError(false);
    Keyboard.dismiss();
    try {
      await action(controller.signal);
    } catch {
      if (!controller.signal.aborted) setError(true);
    } finally {
      pending.current = null;
      if (!controller.signal.aborted) setOperation(null);
    }
  }

  function submit(input: string) {
    const credential = step.kind === "password" ? input : input.trim();
    if (!credential) return;
    if (step.kind === "passwordResetCode") {
      recoverPassword({ kind: "verify", code: credential });
      return;
    }
    void perform("submit", async (signal) => {
      if (step.kind === "email") {
        const next = await startHarmonyEmailSignIn(signIn, credential);
        if (!signal.aborted) setStep(next);
        return;
      }
      if (
        step.kind === "hosted" ||
        step.kind === "complete" ||
        step.kind === "passwordResetNewPassword"
      )
        return;
      const result =
        step.kind === "password"
          ? await signIn.password({ password: credential })
          : step.kind === "emailCode"
            ? await signIn.emailCode.verifyCode({ code: credential })
            : step.kind === "mfaEmail"
              ? await signIn.mfa.verifyEmailCode({ code: credential })
              : step.kind === "totp"
                ? await signIn.mfa.verifyTOTP({ code: credential })
                : await signIn.mfa.verifyBackupCode({ code: credential });
      if (result.error) throw result.error;
      if (signal.aborted) return;
      const next = await finishHarmonyEmailSignIn(signIn);
      if (!signal.aborted) {
        setStep(next);
        setValue("");
      }
    });
  }

  function recoverPassword(action: Parameters<typeof advanceHarmonyPasswordRecovery>[1]) {
    const operation =
      action.kind !== "send" ? "submit" : step.kind === "passwordResetCode" ? "resend" : "recover";
    void perform(operation, async (signal) => {
      const next = await advanceHarmonyPasswordRecovery(signIn, action, signal);
      if (!next || signal.aborted) return;
      setStep(next);
      setValue("");
      setResetPassword(emptyHarmonyNewPassword);
    });
  }

  function submitResetPassword(confirmation: string) {
    if (!canSubmitHarmonyNewPassword(resetPassword.password, confirmation)) return;
    recoverPassword({
      kind: "password",
      password: resetPassword.password,
      signOutOfOtherSessions: resetPassword.signOutOfOtherSessions,
    });
  }

  function sendCode() {
    if (step.kind === "passwordResetCode") {
      recoverPassword({ kind: "send" });
      return;
    }
    void perform("resend", async (signal) => {
      const result =
        step.kind === "mfaEmail"
          ? await signIn.mfa.sendEmailCode()
          : await signIn.emailCode.sendCode();
      if (result.error) throw result.error;
      if (!signal.aborted && step.kind === "password") {
        setValue("");
        setStep({ kind: "emailCode", passwordAvailable: true });
      }
    });
  }

  function openHosted() {
    void perform("browser", async (signal) => {
      const authSessionOptions = { showInRecents: false, signal };
      await startHostedAuth({
        mode: "sign-in",
        redirectUrl: harmonyAccountRedirect,
        authSessionOptions,
      });
    });
  }

  function openProvider(strategy: Provider) {
    void perform("browser", async (signal) => {
      const authSessionOptions = { showInRecents: false, signal };
      const result = await startSSOFlow({
        strategy,
        redirectUrl: harmonyAccountRedirect,
        authSessionOptions,
      });
      if (
        signal.aborted ||
        result.authSessionResult?.type !== "success" ||
        result.createdSessionId
      ) {
        return;
      }
      if (result.signIn?.existingSession || result.signUp?.existingSession) return;
      const next = result.signIn
        ? await finishHarmonyEmailSignIn(result.signIn)
        : { kind: "hosted" as const };
      if (!signal.aborted) setStep(next);
    });
  }

  function changeEmail() {
    void perform("submit", async (signal) => {
      const { error } = await signIn.reset();
      if (error) throw error;
      if (!signal.aborted) {
        setValue("");
        setResetPassword(emptyHarmonyNewPassword);
        setStep({ kind: "email" });
      }
    });
  }

  const emailLabel = gt("Email address");
  const passwordLabel = gt("Password");
  const codeLabel =
    step.kind === "backupCode"
      ? gt("Backup code")
      : step.kind === "passwordResetCode"
        ? gt("Password reset code")
        : gt("Verification code");
  const offerPasswordRecovery =
    (step.kind === "password" || step.kind === "emailCode" || step.kind === "hosted") &&
    supportsHarmonyPasswordRecovery(signIn);
  const providerButtons = [
    { strategy: "oauth_google", label: gt("Continue with Google") },
    { strategy: "oauth_github", label: gt("Continue with GitHub") },
    { strategy: "oauth_apple", label: gt("Continue with Apple") },
    { strategy: "oauth_microsoft", label: gt("Continue with Microsoft") },
  ] as const;

  if (step.kind === "complete") {
    return (
      <View className="flex-1 items-center justify-center">
        <AppActivityIndicator />
      </View>
    );
  }

  return (
    <ScreenScrollView
      className="flex-1"
      keyboardShouldPersistTaps="handled"
      contentContainerStyle={{ paddingBottom: bottom + 24 }}
    >
      <View className="w-full max-w-[480px] self-center gap-5 px-6 pt-7">
        <AppText accessibilityRole="header" textRole="display" className="font-t3-semibold">
          {gt("Sign in to T3 Code")}
        </AppText>
        {error ? (
          <AppText accessibilityRole="alert" textRole="footnote" className="text-danger-foreground">
            {gt("The action could not be completed. Try again.")}
          </AppText>
        ) : null}
        {step.kind === "email" ? (
          <>
            <View className="gap-2">
              <AppText textRole="footnote" className="font-t3-medium">
                {emailLabel}
              </AppText>
              <AppTextInput
                accessibilityLabel={emailLabel}
                autoCapitalize="none"
                autoComplete="email"
                autoCorrect={false}
                keyboardType="email-address"
                editable={!busy}
                onChangeText={setEmail}
                onSubmitEditing={(event) => submit(event.nativeEvent.text)}
                returnKeyType="go"
                value={email}
              />
            </View>
            <Button
              label={gt("Continue")}
              tone="primary"
              fullWidth
              disabled={busy || !email.trim()}
              loading={operation === "submit"}
              onPress={() => submit(email)}
            />
            <View className="flex-row items-center gap-3">
              <View className="h-px flex-1 bg-border" />
              <AppText textRole="footnote" className="text-foreground-muted">
                {gt("or")}
              </AppText>
              <View className="h-px flex-1 bg-border" />
            </View>
            <View className="gap-2">
              {providerButtons.map(({ label, strategy }) => (
                <Button
                  key={strategy}
                  label={label}
                  fullWidth
                  disabled={busy}
                  onPress={() => openProvider(strategy)}
                />
              ))}
            </View>
            <Button
              label={gt("Create an account")}
              tone="text"
              disabled={busy}
              onPress={() => {
                Keyboard.dismiss();
                props.onSignUp(email);
              }}
            />
          </>
        ) : step.kind === "hosted" ? (
          <AppText textRole="body">{gt("Continue in your browser to complete sign-in.")}</AppText>
        ) : step.kind === "passwordResetNewPassword" ? (
          <View className="gap-3">
            <HarmonyNewPasswordFields
              value={resetPassword}
              editable={!busy}
              onChange={setResetPassword}
              onSubmit={submitResetPassword}
            />
            <Button
              label={gt("Reset password")}
              tone="primary"
              fullWidth
              disabled={
                busy ||
                !canSubmitHarmonyNewPassword(resetPassword.password, resetPassword.confirmation)
              }
              loading={operation === "submit"}
              onPress={() => submitResetPassword(resetPassword.confirmation)}
            />
          </View>
        ) : (
          <View className="gap-3">
            <AppText textRole="footnote" className="text-foreground-muted" selectable>
              {email}
            </AppText>
            {step.kind === "password" ? (
              <SecretTextInput
                accessibilityLabel={passwordLabel}
                placeholder={passwordLabel}
                value={value}
                editable={!busy}
                onChangeText={setValue}
                onSubmitEditing={submit}
              />
            ) : (
              <>
                <AppText textRole="footnote" className="font-t3-medium">
                  {step.kind === "totp" ? gt("Authenticator code") : codeLabel}
                </AppText>
                <AppTextInput
                  key={step.kind}
                  accessibilityLabel={step.kind === "totp" ? gt("Authenticator code") : codeLabel}
                  autoCapitalize="none"
                  autoComplete={step.kind === "backupCode" ? "off" : "one-time-code"}
                  keyboardType={step.kind === "backupCode" ? "default" : "number-pad"}
                  editable={!busy}
                  returnKeyType="go"
                  value={value}
                  onChangeText={setValue}
                  onSubmitEditing={(event) => submit(event.nativeEvent.text)}
                />
              </>
            )}
            <Button
              label={step.kind === "password" ? gt("Sign in") : gt("Verify")}
              tone="primary"
              fullWidth
              disabled={busy || !value}
              loading={operation === "submit"}
              onPress={() => submit(value)}
            />
            {step.kind === "emailCode" ||
            step.kind === "mfaEmail" ||
            step.kind === "passwordResetCode" ? (
              <Button
                label={gt("Resend code")}
                tone="text"
                disabled={busy}
                loading={operation === "resend"}
                onPress={sendCode}
              />
            ) : null}
            {step.kind === "emailCode" && step.passwordAvailable ? (
              <Button
                label={gt("Use a password")}
                tone="text"
                disabled={busy}
                onPress={() => {
                  setError(false);
                  setValue("");
                  setStep({ kind: "password", emailCodeAvailable: true });
                }}
              />
            ) : null}
            {step.kind === "password" && step.emailCodeAvailable ? (
              <Button
                label={gt("Use an email code")}
                tone="text"
                disabled={busy}
                onPress={sendCode}
              />
            ) : null}
            {step.kind === "totp" &&
            signIn.supportedSecondFactors.some((factor) => factor.strategy === "backup_code") ? (
              <Button
                label={gt("Use a backup code")}
                tone="text"
                disabled={busy}
                onPress={() => {
                  setError(false);
                  setValue("");
                  setStep({ kind: "backupCode" });
                }}
              />
            ) : null}
          </View>
        )}
        {offerPasswordRecovery ? (
          <Button
            label={gt("Forgot password?")}
            tone="text"
            disabled={busy}
            loading={operation === "recover"}
            onPress={() => recoverPassword({ kind: "send" })}
          />
        ) : null}
        {step.kind !== "email" && email ? (
          <Button label={gt("Change email")} tone="text" disabled={busy} onPress={changeEmail} />
        ) : null}
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
            label={gt("Sign in with your browser")}
            tone={step.kind === "hosted" ? "primary" : "text"}
            disabled={busy}
            fullWidth={step.kind === "hosted"}
            onPress={openHosted}
          />
        )}
      </View>
    </ScreenScrollView>
  );
}
