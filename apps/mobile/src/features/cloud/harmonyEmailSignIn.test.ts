import { describe, expect, it, vi } from "vite-plus/test";

import {
  advanceHarmonyPasswordRecovery,
  finishHarmonyEmailSignIn,
  startHarmonyEmailSignIn,
  supportsHarmonyPasswordRecovery,
} from "./harmonyEmailSignIn";

function signInAttempt(
  status: Parameters<typeof finishHarmonyEmailSignIn>[0]["status"],
  firstFactors: Parameters<typeof startHarmonyEmailSignIn>[0]["supportedFirstFactors"] = [],
  secondFactors: Parameters<typeof finishHarmonyEmailSignIn>[0]["supportedSecondFactors"] = [],
) {
  const success = () => Promise.resolve({ error: null });
  return {
    status,
    supportedFirstFactors: firstFactors,
    supportedSecondFactors: secondFactors,
    create: vi.fn(success),
    emailCode: { sendCode: vi.fn(success) },
    mfa: { sendEmailCode: vi.fn(success) },
    finalize: vi.fn(success),
  };
}

describe("Harmony email sign-in", () => {
  it("uses the code factor advertised by Clerk and offers password when available", async () => {
    const signIn = signInAttempt("needs_first_factor", [
      { strategy: "email_code", emailAddressId: "email", safeIdentifier: "a***@example.com" },
      { strategy: "password" },
    ]);

    await expect(startHarmonyEmailSignIn(signIn, "alice@example.com")).resolves.toEqual({
      kind: "emailCode",
      passwordAvailable: true,
    });
    expect(signIn.create).toHaveBeenCalledWith({ identifier: "alice@example.com" });
    expect(signIn.emailCode.sendCode).toHaveBeenCalledOnce();
    expect(signIn.finalize).not.toHaveBeenCalled();
  });

  it("uses password only when it is one of the available first factors", async () => {
    const password = signInAttempt("needs_first_factor", [{ strategy: "password" }]);
    const hosted = signInAttempt("needs_first_factor");

    await expect(startHarmonyEmailSignIn(password, "alice@example.com")).resolves.toEqual({
      kind: "password",
      emailCodeAvailable: false,
    });
    await expect(startHarmonyEmailSignIn(hosted, "alice@example.com")).resolves.toEqual({
      kind: "hosted",
    });
    expect(password.emailCode.sendCode).not.toHaveBeenCalled();
  });

  it("requires device verification before finalizing the session", async () => {
    const trust = signInAttempt(
      "needs_client_trust",
      [],
      [{ strategy: "email_code", emailAddressId: "email", safeIdentifier: "a***@example.com" }],
    );
    const complete = signInAttempt("complete");

    await expect(finishHarmonyEmailSignIn(trust)).resolves.toEqual({ kind: "mfaEmail" });
    expect(trust.mfa.sendEmailCode).toHaveBeenCalledOnce();
    expect(trust.finalize).not.toHaveBeenCalled();
    await expect(finishHarmonyEmailSignIn(complete)).resolves.toEqual({ kind: "complete" });
    expect(complete.finalize).toHaveBeenCalledOnce();
  });

  it("uses the advertised reset factor and finalizes only after the new password is accepted", async () => {
    const signIn = {
      ...signInAttempt("needs_first_factor", [
        {
          strategy: "reset_password_email_code",
          emailAddressId: "email",
          safeIdentifier: "a***@example.com",
        },
      ]),
      resetPasswordEmailCode: {
        sendCode: vi.fn(async () => ({ error: null })),
        verifyCode: vi.fn(async () => {
          signIn.status = "needs_new_password";
          return { error: null };
        }),
        submitPassword: vi.fn(async () => {
          signIn.status = "complete";
          return { error: null };
        }),
      },
    };

    expect(supportsHarmonyPasswordRecovery(signIn)).toBe(true);
    expect(supportsHarmonyPasswordRecovery(signInAttempt("needs_first_factor"))).toBe(false);
    await expect(
      advanceHarmonyPasswordRecovery(
        { ...signIn, supportedFirstFactors: [] },
        {
          kind: "send",
        },
      ),
    ).resolves.toEqual({ kind: "hosted" });
    expect(signIn.resetPasswordEmailCode.sendCode).not.toHaveBeenCalled();
    await expect(advanceHarmonyPasswordRecovery(signIn, { kind: "send" })).resolves.toEqual({
      kind: "passwordResetCode",
    });
    await expect(
      advanceHarmonyPasswordRecovery(signIn, { kind: "verify", code: "123456" }),
    ).resolves.toEqual({ kind: "passwordResetNewPassword" });
    expect(signIn.finalize).not.toHaveBeenCalled();
    await expect(
      advanceHarmonyPasswordRecovery(signIn, {
        kind: "password",
        password: " new password ",
        signOutOfOtherSessions: false,
      }),
    ).resolves.toEqual({ kind: "complete" });
    expect(signIn.resetPasswordEmailCode.submitPassword).toHaveBeenCalledWith({
      password: " new password ",
      signOutOfOtherSessions: false,
    });
    expect(signIn.finalize).toHaveBeenCalledOnce();
  });
});
