import { act, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vite-plus/test";

type Reverification = {
  level: "multi_factor";
  complete: () => void;
  cancel: () => void;
};

type Address = {
  id: string;
  emailAddress: string;
  verification: { status: string };
  destroy: () => Promise<void>;
};

const clerk = vi.hoisted(() => {
  const emailAddresses: Address[] = [];
  return {
    user: {
      id: "user",
      primaryEmailAddressId: "primary",
      emailAddresses,
      createEmailAddress: vi.fn(),
      reload: vi.fn(),
      update: vi.fn(),
    },
    session: {
      id: "session",
      startVerification: vi.fn(),
      prepareFirstFactorVerification: vi.fn(),
      attemptFirstFactorVerification: vi.fn(),
      attemptSecondFactorVerification: vi.fn(),
    },
    activeSessionId: "session",
    requireReverification: false,
  };
});

vi.mock("@clerk/expo", () => ({
  getClerkInstance: () => ({ session: { id: clerk.activeSessionId } }),
  useUser: () => ({ user: clerk.user }),
  useSession: () => ({ session: clerk.session }),
  useReverification:
    (
      fetcher: (input: unknown) => Promise<unknown>,
      options: { onNeedsReverification: (request: Reverification) => void },
    ) =>
    async (input: unknown) => {
      if (clerk.requireReverification) {
        await new Promise<void>((complete, reject) =>
          options.onNeedsReverification({
            level: "multi_factor",
            complete,
            cancel: () =>
              reject(Object.assign(new Error("Cancelled"), { code: "reverification_cancelled" })),
          }),
        );
      }
      return fetcher(input);
    },
}));
vi.mock("react-native", () => ({
  View: ({ children }: { children?: ReactNode }) => <div>{children}</div>,
  Keyboard: { dismiss: () => {} },
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
    onChangeText: (text: string) => void;
  }) => (
    <input
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
    loading,
    onPress,
    accessibilityLabel,
  }: {
    label: string;
    disabled?: boolean;
    loading?: boolean;
    onPress: () => void;
    accessibilityLabel?: string;
  }) => (
    <button
      type="button"
      aria-label={accessibilityLabel}
      disabled={disabled || loading}
      onClick={onPress}
    >
      {label}
    </button>
  ),
}));
vi.mock("../../components/ui/Dialog", () => ({
  confirm: (request: { onConfirm: () => void }) => request.onConfirm(),
}));
vi.mock("../../components/ui/ListRowLayout", () => ({
  ListRowLayout: ({ label, detail }: { label: string; detail?: string }) => (
    <p>
      {label} {detail}
    </p>
  ),
}));
vi.mock("../../components/ui/SecretTextInput", () => ({ SecretTextInput: () => null }));
vi.mock("./components/SettingsSection", () => ({
  SettingsSection: ({ children }: { children?: ReactNode }) => <section>{children}</section>,
}));

import { HarmonyAccountEmailAddresses } from "./HarmonyAccountEmailAddresses";

function mountAddresses() {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  const container = document.createElement("div");
  const root = createRoot(container);
  return {
    container,
    render: () => act(() => root.render(<HarmonyAccountEmailAddresses />)),
    press: (label: string) => {
      const button = [...container.querySelectorAll("button")].find(
        (candidate) => (candidate.getAttribute("aria-label") ?? candidate.textContent) === label,
      );
      if (!button) throw new Error(`Missing button "${label}"`);
      return act(async () => button.click());
    },
    fill: (label: string, value: string) => {
      const input = container.querySelector<HTMLInputElement>(`input[aria-label="${label}"]`);
      if (!input) throw new Error(`Missing input "${label}"`);
      return act(async () => {
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set?.call(
          input,
          value,
        );
        input.dispatchEvent(new Event("input", { bubbles: true }));
      });
    },
    [Symbol.dispose]() {
      act(() => root.unmount());
      vi.unstubAllGlobals();
    },
  };
}

function setup() {
  vi.resetAllMocks();
  clerk.activeSessionId = "session";
  clerk.requireReverification = false;
  clerk.user.primaryEmailAddressId = "primary";
  const destroy = vi.fn<() => Promise<void>>().mockResolvedValue(undefined);
  clerk.user.emailAddresses = [
    {
      id: "primary",
      emailAddress: "ada@example.com",
      verification: { status: "verified" },
      destroy,
    },
  ];
}

it("sends the new address a code only after Clerk completes both requested factors", async () => {
  setup();
  clerk.requireReverification = true;
  const first = {
    status: "needs_first_factor",
    supportedFirstFactors: [
      { strategy: "email_code", emailAddressId: "primary", safeIdentifier: "ad***@example.com" },
    ],
  };
  clerk.session.startVerification.mockResolvedValue(first);
  clerk.session.prepareFirstFactorVerification.mockResolvedValue(first);
  clerk.session.attemptFirstFactorVerification.mockResolvedValue({
    status: "needs_second_factor",
    supportedSecondFactors: [{ strategy: "totp" }],
  });
  clerk.session.attemptSecondFactorVerification.mockResolvedValue({ status: "complete" });
  const prepareVerification = vi.fn().mockResolvedValue(undefined);
  const attemptVerification = vi
    .fn()
    .mockRejectedValueOnce(new Error("Incorrect code"))
    .mockResolvedValueOnce({ verification: { status: "verified" } });
  clerk.user.createEmailAddress.mockResolvedValue({
    id: "secondary",
    emailAddress: "work@example.com",
    prepareVerification,
    attemptVerification,
  });
  using addresses = mountAddresses();
  await addresses.render();

  await addresses.press("Add email address");
  await addresses.fill("Email address", " work@example.com ");
  await addresses.press("Send code");
  expect(clerk.user.createEmailAddress).not.toHaveBeenCalled();
  await addresses.press("Continue");
  expect(clerk.session.startVerification).toHaveBeenCalledWith({ level: "multi_factor" });
  await addresses.press("Send code to ad***@example.com");
  await addresses.fill("Verification code", "111111");
  await addresses.press("Verify");
  expect(clerk.user.createEmailAddress).not.toHaveBeenCalled();
  await addresses.press("Use an authenticator app");
  await addresses.fill("Verification code", "222222");
  await addresses.press("Verify");

  expect(clerk.user.createEmailAddress).toHaveBeenCalledExactlyOnceWith({
    email: "work@example.com",
  });
  expect(prepareVerification).toHaveBeenCalledExactlyOnceWith({ strategy: "email_code" });
  await addresses.fill("Verification code", "333333");
  await addresses.press("Verify");
  expect(addresses.container.querySelector('[role="alert"]')).not.toBeNull();
  await addresses.fill("Verification code", "444444");
  await addresses.press("Verify");
  expect(addresses.container.querySelector("input")).toBeNull();
  expect(attemptVerification.mock.calls).toEqual([[{ code: "333333" }], [{ code: "444444" }]]);
  expect(clerk.user.createEmailAddress).toHaveBeenCalledTimes(1);
});

it("offers promotion only for verified secondary addresses and keeps the primary address protected", async () => {
  setup();
  const primary = clerk.user.emailAddresses[0]!;
  const verified = vi.fn<() => Promise<void>>().mockResolvedValue(undefined);
  const unverified = vi.fn<() => Promise<void>>().mockResolvedValue(undefined);
  clerk.user.emailAddresses.push(
    {
      id: "verified",
      emailAddress: "verified@example.com",
      verification: { status: "verified" },
      destroy: verified,
    },
    {
      id: "unverified",
      emailAddress: "unverified@example.com",
      verification: { status: "unverified" },
      destroy: unverified,
    },
  );
  clerk.user.update.mockImplementation(
    async ({ primaryEmailAddressId }: { primaryEmailAddressId: string }) => {
      clerk.user.primaryEmailAddressId = primaryEmailAddressId;
    },
  );
  using addresses = mountAddresses();
  await addresses.render();
  expect(
    addresses.container.querySelector('button[aria-label="Remove, ada@example.com"]'),
  ).toBeNull();
  expect(
    addresses.container.querySelector('button[aria-label="Make primary, unverified@example.com"]'),
  ).toBeNull();

  await addresses.press("Make primary, verified@example.com");
  expect(clerk.user.update).toHaveBeenCalledExactlyOnceWith({ primaryEmailAddressId: "verified" });
  expect(
    addresses.container.querySelector('button[aria-label="Remove, verified@example.com"]'),
  ).toBeNull();
  await addresses.press("Remove, unverified@example.com");
  expect(unverified).toHaveBeenCalledOnce();
  expect(verified).not.toHaveBeenCalled();
  expect(primary.destroy).not.toHaveBeenCalled();
});

it("keeps a newly added address recoverable after Clerk creates it but cannot send the code", async () => {
  setup();
  const sending = Promise.withResolvers<void>();
  const address = {
    id: "secondary",
    emailAddress: "work@example.com",
    verification: { status: "unverified" },
    destroy: vi.fn(),
    prepareVerification: vi
      .fn()
      .mockReturnValueOnce(sending.promise)
      .mockResolvedValueOnce(undefined),
  };
  clerk.user.createEmailAddress.mockResolvedValue(address);
  clerk.user.reload.mockImplementation(async () => {
    clerk.user.emailAddresses.push(address);
  });
  using addresses = mountAddresses();
  await addresses.render();
  await addresses.press("Add email address");
  await addresses.fill("Email address", address.emailAddress);
  await addresses.press("Send code");

  expect(
    [...addresses.container.querySelectorAll("button")].every(({ disabled }) => disabled),
  ).toBe(true);
  await act(async () => sending.reject(new Error("Offline")));
  expect(addresses.container.querySelector('[role="alert"]')).not.toBeNull();
  expect(addresses.container.querySelector("input")).toBeNull();
  await addresses.press("Cancel");
  await addresses.press("Verify email, work@example.com");
  expect(addresses.container.querySelector('input[aria-label="Verification code"]')).not.toBeNull();
  expect(clerk.user.createEmailAddress).toHaveBeenCalledOnce();
});

it("cancels an unsupported step-up challenge without performing the account mutation", async () => {
  setup();
  clerk.requireReverification = true;
  clerk.session.startVerification.mockResolvedValue({
    status: "needs_first_factor",
    supportedFirstFactors: [{ strategy: "passkey" }],
  });
  using addresses = mountAddresses();
  await addresses.render();
  await addresses.press("Add email address");
  await addresses.fill("Email address", "work@example.com");
  await addresses.press("Send code");
  await addresses.press("Continue");
  expect(addresses.container.querySelector('[role="alert"]')).not.toBeNull();
  await addresses.press("Cancel");
  expect(addresses.container.querySelector('[role="alert"]')).toBeNull();
  expect(clerk.user.createEmailAddress).not.toHaveBeenCalled();
});

it("does not replay a verified mutation after Clerk switches the active session", async () => {
  setup();
  clerk.requireReverification = true;
  const first = {
    status: "needs_first_factor",
    supportedFirstFactors: [
      { strategy: "email_code", emailAddressId: "primary", safeIdentifier: "ad***@example.com" },
    ],
  };
  clerk.session.startVerification.mockResolvedValue(first);
  clerk.session.prepareFirstFactorVerification.mockResolvedValue(first);
  clerk.session.attemptFirstFactorVerification.mockImplementationOnce(async () => {
    clerk.activeSessionId = "different-session";
    return { status: "complete" };
  });
  using addresses = mountAddresses();
  await addresses.render();
  await addresses.press("Add email address");
  await addresses.fill("Email address", "work@example.com");
  await addresses.press("Send code");
  await addresses.press("Continue");
  await addresses.press("Send code to ad***@example.com");
  await addresses.fill("Verification code", "111111");
  await addresses.press("Verify");

  expect(clerk.user.createEmailAddress).not.toHaveBeenCalled();
});
