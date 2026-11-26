import { act, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vite-plus/test";

const fixture = vi.hoisted(() => ({
  authenticatorEnabled: true,
  backupCodesEnabled: true,
  user: {
    id: "user",
    totpEnabled: false,
    twoFactorEnabled: false,
    backupCodeEnabled: false,
    createTOTP: vi.fn(),
    verifyTOTP: vi.fn(),
    disableTOTP: vi.fn(),
    createBackupCode: vi.fn(),
    reload: vi.fn(),
  },
  confirm: vi.fn(),
}));

vi.mock("@clerk/expo", () => ({
  getClerkInstance: () => ({
    __internal_environment: {
      userSettings: {
        attributes: {
          authenticator_app: {
            enabled: fixture.authenticatorEnabled,
            used_for_second_factor: fixture.authenticatorEnabled,
          },
          backup_code: {
            enabled: fixture.backupCodesEnabled,
            used_for_second_factor: fixture.backupCodesEnabled,
          },
        },
      },
    },
    session: { id: "session" },
    user: fixture.user,
  }),
  useSession: () => ({ session: { id: "session" } }),
  useUser: () => ({ user: fixture.user }),
  useReverification: (action: unknown) => action,
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
    onChangeText: (value: string) => void;
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
  }: {
    label: string;
    disabled?: boolean;
    loading?: boolean;
    onPress: () => void;
  }) => (
    <button type="button" disabled={disabled || loading} onClick={onPress}>
      {label}
    </button>
  ),
}));
vi.mock("../../components/ui/Dialog", () => ({
  confirm: fixture.confirm,
}));
vi.mock("../../components/ui/SecretTextInput", () => ({ SecretTextInput: () => null }));
vi.mock("./components/SettingsSection", () => ({
  SettingsSection: ({ children }: { children: ReactNode }) => <section>{children}</section>,
}));

import { HarmonyAccountMfa } from "./HarmonyAccountMfa";

function setup(enabled = false) {
  vi.resetAllMocks();
  fixture.authenticatorEnabled = true;
  fixture.backupCodesEnabled = true;
  fixture.user.totpEnabled = enabled;
  fixture.user.twoFactorEnabled = enabled;
  fixture.user.backupCodeEnabled = enabled;
}

function mountMfa() {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  const container = document.createElement("div");
  const root = createRoot(container);
  return {
    container,
    render: () => act(() => root.render(<HarmonyAccountMfa />)),
    press: (label: string) => {
      const button = [...container.querySelectorAll("button")].find(
        (candidate) => candidate.textContent === label,
      );
      if (!button) throw new Error(`Missing button "${label}"`);
      return act(async () => button.click());
    },
    enterCode: (code: string) =>
      act(() => {
        const input = container.querySelector<HTMLInputElement>(
          'input[aria-label="Verification code"]',
        );
        if (!input) throw new Error("Missing verification code input");
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set?.call(
          input,
          code,
        );
        input.dispatchEvent(new Event("input", { bubbles: true }));
      }),
    confirm: () => {
      const dialog = fixture.confirm.mock.lastCall?.[0];
      if (!dialog) throw new Error("Missing confirmation dialog");
      return act(async () => dialog.onConfirm());
    },
    [Symbol.dispose]() {
      act(() => root.unmount());
      vi.unstubAllGlobals();
    },
  };
}

it("retries an authenticator code without creating a second secret and dismisses recovery codes only on acknowledgment", async () => {
  setup();
  fixture.user.createTOTP.mockResolvedValue({ secret: "FAKESETUPSECRET" });
  fixture.user.verifyTOTP
    .mockRejectedValueOnce(new Error("Invalid code"))
    .mockImplementationOnce(async () => {
      fixture.user.totpEnabled = true;
      fixture.user.twoFactorEnabled = true;
      fixture.user.backupCodeEnabled = true;
      return { verified: true, backupCodes: ["DISPLAY-ONCE"] };
    });
  using mfa = mountMfa();
  await mfa.render();

  await mfa.press("Add authenticator app");
  expect(mfa.container.textContent).toContain("FAKESETUPSECRET");
  await mfa.enterCode("123456");
  await mfa.press("Verify");
  expect(mfa.container.querySelector('[role="alert"]')).not.toBeNull();
  expect(mfa.container.textContent).toContain("FAKESETUPSECRET");
  await mfa.enterCode("654321");
  await mfa.press("Verify");
  expect(fixture.user.createTOTP).toHaveBeenCalledOnce();
  expect(mfa.container.textContent).not.toContain("FAKESETUPSECRET");
  expect(mfa.container.textContent).toContain("DISPLAY-ONCE");
  await mfa.press("I saved my codes");
  expect(mfa.container.textContent).not.toContain("DISPLAY-ONCE");
  expect(mfa.container.textContent).toContain("Remove authenticator app");
});

it("requires confirmation before replacing backup codes or removing an enrolled authenticator", async () => {
  setup(true);
  fixture.user.createBackupCode.mockResolvedValue({ codes: ["REPLACEMENT-ONLY"] });
  fixture.user.disableTOTP.mockImplementationOnce(async () => {
    fixture.user.totpEnabled = false;
    fixture.user.twoFactorEnabled = false;
    fixture.user.backupCodeEnabled = false;
  });
  using mfa = mountMfa();
  await mfa.render();

  await mfa.press("Generate new backup codes");
  expect(fixture.user.createBackupCode).not.toHaveBeenCalled();
  await mfa.confirm();
  expect(mfa.container.textContent).toContain("REPLACEMENT-ONLY");
  await mfa.press("I saved my codes");
  await mfa.press("Remove authenticator app");
  expect(fixture.user.disableTOTP).not.toHaveBeenCalled();
  await mfa.confirm();
  expect(fixture.user.disableTOTP).toHaveBeenCalledOnce();
  expect(mfa.container.textContent).not.toContain("Generate new backup codes");
});

it("does not offer account mutations for instance-disabled factors", async () => {
  setup(true);
  fixture.authenticatorEnabled = false;
  fixture.backupCodesEnabled = false;
  using mfa = mountMfa();
  await mfa.render();
  expect(mfa.container.querySelector("button")).toBeNull();
});
