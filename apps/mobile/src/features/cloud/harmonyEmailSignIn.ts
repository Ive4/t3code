import type { useSignIn } from "@clerk/expo";

type SignIn = ReturnType<typeof useSignIn>["signIn"];
type CompletionAttempt = Pick<SignIn, "status" | "supportedSecondFactors" | "finalize"> & {
  readonly mfa: Pick<SignIn["mfa"], "sendEmailCode">;
};
type EmailAttempt = CompletionAttempt &
  Pick<SignIn, "supportedFirstFactors" | "create"> & {
    readonly emailCode: Pick<SignIn["emailCode"], "sendCode">;
  };
type RecoveryAttempt = CompletionAttempt &
  Pick<SignIn, "supportedFirstFactors" | "resetPasswordEmailCode">;
type PasswordRecoveryAction =
  | { readonly kind: "send" }
  | { readonly kind: "verify"; readonly code: string }
  | {
      readonly kind: "password";
      readonly password: string;
      readonly signOutOfOtherSessions: boolean;
    };

export type HarmonyEmailSignInStep =
  | { readonly kind: "emailCode"; readonly passwordAvailable: boolean }
  | { readonly kind: "password"; readonly emailCodeAvailable: boolean }
  | { readonly kind: "passwordResetCode" | "passwordResetNewPassword" }
  | { readonly kind: "mfaEmail" | "totp" | "backupCode" | "hosted" | "complete" };

export function supportsHarmonyPasswordRecovery(
  signIn: Pick<RecoveryAttempt, "status" | "supportedFirstFactors">,
) {
  return (
    signIn.status === "needs_first_factor" &&
    signIn.supportedFirstFactors.some((factor) => factor.strategy === "reset_password_email_code")
  );
}

export async function advanceHarmonyPasswordRecovery(
  signIn: RecoveryAttempt,
  action: PasswordRecoveryAction,
  signal?: AbortSignal,
): Promise<HarmonyEmailSignInStep | null> {
  if (signal?.aborted) return null;
  if (action.kind === "send" && !supportsHarmonyPasswordRecovery(signIn)) return { kind: "hosted" };
  const reset = signIn.resetPasswordEmailCode;
  const { error } =
    action.kind === "send"
      ? await reset.sendCode()
      : action.kind === "verify"
        ? await reset.verifyCode({ code: action.code })
        : await reset.submitPassword({
            password: action.password,
            signOutOfOtherSessions: action.signOutOfOtherSessions,
          });
  if (error) throw error;
  if (signal?.aborted) return null;
  return action.kind === "send" ? { kind: "passwordResetCode" } : finishHarmonyEmailSignIn(signIn);
}

export async function startHarmonyEmailSignIn(
  signIn: EmailAttempt,
  email: string,
): Promise<HarmonyEmailSignInStep> {
  const { error } = await signIn.create({ identifier: email });
  if (error) throw error;
  if (signIn.status !== "needs_first_factor") return finishHarmonyEmailSignIn(signIn);

  const passwordAvailable = signIn.supportedFirstFactors.some(
    (factor) => factor.strategy === "password",
  );
  if (signIn.supportedFirstFactors.some((factor) => factor.strategy === "email_code")) {
    const { error } = await signIn.emailCode.sendCode();
    if (error) throw error;
    return { kind: "emailCode", passwordAvailable };
  }
  return passwordAvailable ? { kind: "password", emailCodeAvailable: false } : { kind: "hosted" };
}

export async function finishHarmonyEmailSignIn(
  signIn: CompletionAttempt,
): Promise<HarmonyEmailSignInStep> {
  if (signIn.status === "needs_new_password") return { kind: "passwordResetNewPassword" };
  if (signIn.status === "complete") {
    const { error } = await signIn.finalize();
    if (error) throw error;
    return { kind: "complete" };
  }
  if (signIn.status === "needs_client_trust" || signIn.status === "needs_second_factor") {
    const strategies = signIn.supportedSecondFactors.map((factor) => factor.strategy);
    if (strategies.includes("email_code")) {
      const { error } = await signIn.mfa.sendEmailCode();
      if (error) throw error;
      return { kind: "mfaEmail" };
    }
    if (strategies.includes("totp")) return { kind: "totp" };
    if (strategies.includes("backup_code")) return { kind: "backupCode" };
  }
  return { kind: "hosted" };
}
