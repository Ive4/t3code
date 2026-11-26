import { act, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vite-plus/test";

const { startHostedAuth, signUp, clerk } = vi.hoisted(() => ({
  startHostedAuth: vi.fn(),
  clerk: { client: null, session: null as { id: string } | null },
  signUp: {
    status: "missing_requirements",
    missingFields: [] as string[],
    unverifiedFields: ["email_address"],
    protectCheck: null,
    createdSessionId: null as string | null,
    password: vi.fn(),
    finalize: vi.fn(),
    reset: vi.fn(),
    verifications: {
      emailAddress: { status: "unverified" },
      sendEmailCode: vi.fn(),
      verifyEmailCode: vi.fn(),
    },
  },
}));

vi.mock("@clerk/expo", () => ({
  useClerk: () => clerk,
  useSignUp: () => ({ signUp, fetchStatus: "idle" }),
}));
vi.mock("@clerk/expo/hosted-auth", () => ({ useHostedAuth: () => ({ startHostedAuth }) }));
vi.mock("react-native", () => ({
  View: ({ children }: { children: ReactNode }) => <div>{children}</div>,
  Keyboard: { dismiss: () => {} },
}));
vi.mock("react-native-safe-area-context", () => ({ useSafeAreaInsets: () => ({ bottom: 0 }) }));
vi.mock("../../components/ui/AppActivityIndicator", () => ({ AppActivityIndicator: () => null }));
vi.mock("../../components/ui/ScreenScrollView", () => ({
  ScreenScrollView: ({ children }: { children: ReactNode }) => <div>{children}</div>,
}));
vi.mock("../../components/ui/AppText", () => ({
  AppText: ({
    children,
    accessibilityRole,
  }: {
    children: ReactNode;
    accessibilityRole?: string;
  }) => <span role={accessibilityRole}>{children}</span>,
  AppTextInput: ({
    accessibilityLabel,
    value,
    onChangeText,
  }: {
    accessibilityLabel: string;
    value: string;
    onChangeText: (value: string) => void;
  }) => (
    <input
      aria-label={accessibilityLabel}
      value={value}
      onChange={(event) => onChangeText(event.currentTarget.value)}
    />
  ),
}));
vi.mock("../../components/ui/SecretTextInput", () => ({
  SecretTextInput: ({
    accessibilityLabel,
    value,
    onChangeText,
  }: {
    accessibilityLabel: string;
    value: string;
    onChangeText: (value: string) => void;
  }) => (
    <input
      type="password"
      aria-label={accessibilityLabel}
      value={value}
      onChange={(event) => onChangeText(event.currentTarget.value)}
    />
  ),
}));
vi.mock("../../components/ui/Button", () => ({
  Button: ({
    label,
    disabled,
    onPress,
  }: {
    label: string;
    disabled?: boolean;
    onPress: () => void;
  }) => (
    <button type="button" disabled={disabled} onClick={onPress}>
      {label}
    </button>
  ),
}));

import { HarmonyAccountSignUp } from "./HarmonyAccountSignUp";

function mountSignUp() {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  signUp.status = "missing_requirements";
  signUp.missingFields = [];
  signUp.unverifiedFields = ["email_address"];
  signUp.createdSessionId = null;
  signUp.verifications.emailAddress.status = "unverified";
  clerk.session = null;
  signUp.password.mockReset().mockResolvedValue({ error: null });
  signUp.verifications.sendEmailCode.mockReset().mockResolvedValue({ error: null });
  signUp.verifications.verifyEmailCode.mockReset().mockImplementation(async () => {
    signUp.status = "complete";
    signUp.unverifiedFields = [];
    signUp.createdSessionId = "session_id";
    signUp.verifications.emailAddress.status = "verified";
    return { error: null };
  });
  signUp.finalize.mockReset().mockImplementation(async () => {
    clerk.session = { id: "session_id" };
    return { error: null };
  });
  startHostedAuth.mockReset().mockResolvedValue(undefined);
  const container = document.createElement("div");
  const root = createRoot(container);
  return {
    container,
    render: () =>
      act(() =>
        root.render(<HarmonyAccountSignUp initialEmail=" user@example.com " onBack={() => {}} />),
      ),
    press: (label: string) => {
      const button = [...container.querySelectorAll("button")].find(
        (item) => item.textContent === label,
      );
      if (!button) throw new Error(`Missing button ${label}`);
      return act(async () => button.click());
    },
    fill: (label: string, value: string) => {
      const field = container.querySelector<HTMLInputElement>(`input[aria-label="${label}"]`);
      if (!field) throw new Error(`Missing input ${label}`);
      return act(() => {
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set?.call(
          field,
          value,
        );
        field.dispatchEvent(new Event("input", { bubbles: true }));
      });
    },
    [Symbol.dispose]() {
      act(() => root.unmount());
      vi.unstubAllGlobals();
    },
  };
}

it("verifies the email before activating a native sign-up and retries a transient activation error", async () => {
  using screen = mountSignUp();
  signUp.finalize.mockResolvedValueOnce({ error: { code: "network_error" } });
  await screen.render();
  await screen.fill("New password", " correct password ");
  await screen.press("Continue");

  expect(signUp.password).toHaveBeenCalledWith({
    emailAddress: "user@example.com",
    password: " correct password ",
  });
  expect(signUp.verifications.sendEmailCode).toHaveBeenCalledOnce();
  expect(signUp.finalize).not.toHaveBeenCalled();
  expect(screen.container.querySelector('input[type="password"]')).toBeNull();

  await screen.fill("Verification code", " 123456 ");
  await screen.press("Verify");
  expect(signUp.verifications.verifyEmailCode).toHaveBeenCalledWith({ code: "123456" });
  expect(signUp.finalize).toHaveBeenCalledOnce();
  await screen.press("Retry");
  expect(signUp.finalize).toHaveBeenCalledTimes(2);
  expect(signUp.verifications.verifyEmailCode).toHaveBeenCalledOnce();
});

it.each([["legal_accepted"], ["protect_check"], ["phone_number"]])(
  "keeps %s requirements in official hosted registration",
  async (requirement) => {
    using screen = mountSignUp();
    signUp.missingFields = [requirement];
    await screen.render();
    await screen.fill("New password", "signup password");
    await screen.press("Continue");

    expect(signUp.verifications.sendEmailCode).not.toHaveBeenCalled();
    expect(signUp.finalize).not.toHaveBeenCalled();
    await screen.press("Sign up with your browser");
    expect(startHostedAuth).toHaveBeenCalledWith(expect.objectContaining({ mode: "sign-up" }));
  },
);

it("falls back when Clerk discovers additional session tasks while activating", async () => {
  using screen = mountSignUp();
  signUp.finalize.mockImplementationOnce(
    async (options: { navigate: (args: { session: { id: string; status: string } }) => void }) => {
      try {
        options.navigate({ session: { id: "session_id", status: "pending" } });
        clerk.session = { id: "session_id" };
        return { error: null };
      } catch (error) {
        return { error };
      }
    },
  );
  await screen.render();
  await screen.fill("New password", "signup password");
  await screen.press("Continue");
  await screen.fill("Verification code", "123456");
  await screen.press("Verify");

  expect(clerk.session).toBeNull();
  expect(screen.container.textContent).toContain(
    "Continue in your browser to finish creating your account.",
  );
});
