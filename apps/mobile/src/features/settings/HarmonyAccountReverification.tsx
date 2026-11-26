import { getClerkInstance, useReverification, useSession } from "@clerk/expo";
import type {
  SessionResource,
  SessionVerificationFirstFactor,
  SessionVerificationLevel,
  SessionVerificationResource,
  SessionVerificationSecondFactor,
} from "@clerk/expo/types";
import { useGT } from "gt-react-native";
import { useLayoutEffect, useRef, useState } from "react";
import { Keyboard, View } from "react-native";

import { AppText, AppTextInput } from "../../components/ui/AppText";
import { Button } from "../../components/ui/Button";
import { SecretTextInput } from "../../components/ui/SecretTextInput";

type Reverification = {
  readonly level: SessionVerificationLevel | undefined;
  readonly complete: () => void;
  readonly cancel: () => void;
};

let pendingChallenge: Reverification | null = null;

export function isHarmonyReverificationCancelled(error: unknown): boolean {
  return error instanceof Error && "code" in error && error.code === "reverification_cancelled";
}

export function useHarmonyAccountReverification<Args extends unknown[], Result>(
  action: (...args: Args) => Promise<Result>,
) {
  const { session } = useSession();
  const sessionId = session?.id;
  const [challenge, setChallenge] = useState<{
    readonly request: Reverification;
    readonly sessionId: string;
  } | null>(null);
  const activeSessionId = useRef<string | undefined>(undefined);
  const challengeRef = useRef<Reverification | null>(null);
  const isActive = () =>
    sessionId !== undefined &&
    activeSessionId.current === sessionId &&
    getClerkInstance().session?.id === sessionId;

  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- cancels Clerk's deferred mutation when the active session or screen changes
  useLayoutEffect(() => {
    activeSessionId.current = sessionId;
    return () => {
      activeSessionId.current = undefined;
      const previous = challengeRef.current;
      if (!previous) return;
      challengeRef.current = null;
      if (pendingChallenge === previous) pendingChallenge = null;
      previous.cancel();
    };
  }, [sessionId]);

  const protectedAction = useReverification(
    async (...args: Args) => {
      if (!isActive()) throw new Error("The account screen has closed.");
      return { value: await action(...args) };
    },
    {
      onNeedsReverification(request) {
        if (sessionId === undefined || !isActive() || pendingChallenge) return request.cancel();
        pendingChallenge = request;
        challengeRef.current = request;
        setChallenge({ request, sessionId });
      },
    },
  );

  async function run(...args: Args): Promise<Result> {
    const result = await protectedAction(...args);
    if (!result || !Object.hasOwn(result, "value")) {
      throw new Error("Clerk could not complete reverification.");
    }
    return result.value;
  }

  function finish(verified: boolean) {
    const request = challengeRef.current;
    if (!request || request !== challenge?.request) return;
    challengeRef.current = null;
    if (pendingChallenge === request) pendingChallenge = null;
    setChallenge(null);
    if (verified && isActive()) request.complete();
    else request.cancel();
  }

  return {
    run,
    isActive,
    prompt:
      session && challenge?.sessionId === session.id ? (
        <VerifySession session={session} request={challenge.request} onFinish={finish} />
      ) : null,
  };
}

type Factor = SessionVerificationFirstFactor | SessionVerificationSecondFactor;
type SupportedFactor = Exclude<Factor, { strategy: "passkey" | "enterprise_sso" }>;

function supportedFactor(factor: Factor): factor is SupportedFactor {
  return (
    factor.strategy === "email_code" ||
    factor.strategy === "phone_code" ||
    factor.strategy === "password" ||
    factor.strategy === "totp" ||
    factor.strategy === "backup_code"
  );
}

function VerifySession({
  session,
  request,
  onFinish,
}: {
  readonly session: SessionResource;
  readonly request: Reverification;
  readonly onFinish: (verified: boolean) => void;
}) {
  const gt = useGT();
  const [verification, setVerification] = useState<SessionVerificationResource | null>(null);
  const [factor, setFactor] = useState<SupportedFactor | null>(null);
  const [value, setValue] = useState("");
  const [pending, setPending] = useState(false);
  const [failed, setFailed] = useState(false);
  const busy = useRef(false);
  const second = verification?.status === "needs_second_factor";
  const secretLabel =
    factor?.strategy === "password"
      ? gt("Password")
      : factor?.strategy === "backup_code"
        ? gt("Backup code")
        : null;
  const factors =
    (second ? verification?.supportedSecondFactors : verification?.supportedFirstFactors)?.filter(
      supportedFactor,
    ) ?? [];

  async function perform(action: () => Promise<void>) {
    if (busy.current) return;
    busy.current = true;
    setPending(true);
    setFailed(false);
    try {
      await action();
    } catch {
      setFailed(true);
    } finally {
      busy.current = false;
      setPending(false);
    }
  }

  function advance(next: SessionVerificationResource) {
    if (next.status === "complete") {
      onFinish(true);
      return;
    }
    setVerification(next);
    setFactor(null);
  }

  function choose(next: SupportedFactor) {
    void perform(async () => {
      if (next.strategy === "email_code") {
        await session.prepareFirstFactorVerification({
          strategy: "email_code",
          emailAddressId: next.emailAddressId,
        });
      } else if (next.strategy === "phone_code") {
        const options = { strategy: "phone_code", phoneNumberId: next.phoneNumberId } as const;
        if (second) await session.prepareSecondFactorVerification(options);
        else await session.prepareFirstFactorVerification(options);
      }
      setValue("");
      setFactor(next);
    });
  }

  function submit() {
    const input = factor?.strategy === "password" ? value : value.trim();
    if (!factor || !input) return;
    void perform(async () => {
      setValue("");
      Keyboard.dismiss();
      const { strategy } = factor;
      const next =
        strategy === "password"
          ? await session.attemptFirstFactorVerification({ strategy, password: input })
          : strategy === "email_code" || (strategy === "phone_code" && !second)
            ? await session.attemptFirstFactorVerification({ strategy, code: input })
            : await session.attemptSecondFactorVerification({ strategy, code: input });
      if (next.status === verification?.status) throw new Error("Verification is incomplete.");
      advance(next);
    });
  }

  function factorLabel(option: SupportedFactor) {
    switch (option.strategy) {
      case "email_code":
      case "phone_code":
        return gt("Send code to {address}", { address: option.safeIdentifier });
      case "password":
        return gt("Use a password");
      case "totp":
        return gt("Use an authenticator app");
      case "backup_code":
        return gt("Use a backup code");
    }
  }

  return (
    <View className="gap-3">
      <AppText textRole="body" className="font-t3-semibold">
        {gt("Confirm your identity")}
      </AppText>
      {!verification ? (
        <Button
          label={gt("Continue")}
          tone="primary"
          loading={pending}
          onPress={() =>
            void perform(async () =>
              advance(await session.startVerification({ level: request.level ?? "multi_factor" })),
            )
          }
        />
      ) : factor ? (
        <>
          {secretLabel ? (
            <SecretTextInput
              accessibilityLabel={secretLabel}
              placeholder={secretLabel}
              value={value}
              onChangeText={setValue}
              onSubmitEditing={submit}
              editable={!pending}
            />
          ) : (
            <HarmonyVerificationCodeInput
              value={value}
              onChange={setValue}
              onSubmit={submit}
              disabled={pending}
            />
          )}
          <View className="flex-row flex-wrap gap-2">
            <Button
              label={gt("Verify")}
              tone="primary"
              disabled={pending || !value}
              onPress={submit}
            />
            {factor.strategy === "email_code" || factor.strategy === "phone_code" ? (
              <Button
                label={gt("Resend code")}
                tone="text"
                disabled={pending}
                onPress={() => choose(factor)}
              />
            ) : null}
            {factors.length > 1 ? (
              <Button
                label={gt("Use another method")}
                tone="text"
                disabled={pending}
                onPress={() => {
                  setFailed(false);
                  setFactor(null);
                  setValue("");
                }}
              />
            ) : null}
          </View>
        </>
      ) : (
        factors.map((option) => (
          <Button
            key={
              option.strategy === "email_code"
                ? option.emailAddressId
                : option.strategy === "phone_code"
                  ? option.phoneNumberId
                  : option.strategy
            }
            label={factorLabel(option)}
            disabled={pending}
            onPress={() => choose(option)}
          />
        ))
      )}
      {failed || (verification && factors.length === 0) ? (
        <AppText accessibilityRole="alert" className="text-danger-foreground">
          {failed
            ? gt("Could not verify your identity. Try again.")
            : gt("No supported verification methods are available.")}
        </AppText>
      ) : null}
      <Button
        label={gt("Cancel")}
        tone="text"
        disabled={pending}
        onPress={() => {
          Keyboard.dismiss();
          onFinish(false);
        }}
      />
    </View>
  );
}

export function HarmonyVerificationCodeInput({
  value,
  onChange,
  onSubmit,
  disabled,
}: {
  readonly value: string;
  readonly onChange: (value: string) => void;
  readonly onSubmit: () => void;
  readonly disabled: boolean;
}) {
  const gt = useGT();
  const label = gt("Verification code");
  return (
    <AppTextInput
      accessibilityLabel={label}
      placeholder={label}
      autoComplete="one-time-code"
      keyboardType="number-pad"
      editable={!disabled}
      value={value}
      onChangeText={onChange}
      onSubmitEditing={onSubmit}
    />
  );
}
