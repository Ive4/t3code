import { act, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vite-plus/test";

const clerk = vi.hoisted(() => ({
  session: { id: "session" },
  user: { id: "user", passwordEnabled: false, updatePassword: vi.fn() },
}));

vi.mock("@clerk/expo", () => ({
  useUser: () => ({ user: clerk.user }),
  useAuth: () => ({ sessionId: clerk.session.id }),
  useClerk: () => clerk,
}));
vi.mock("react-native", () => ({
  View: ({ children }: { children: ReactNode }) => <div>{children}</div>,
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
vi.mock("./components/SettingsSection", () => ({
  SettingsSection: ({ children }: { children: ReactNode }) => <section>{children}</section>,
}));
vi.mock("./components/SettingsSwitchRow", () => ({
  SettingsSwitchRow: ({
    label,
    value,
    onValueChange,
  }: {
    label: string;
    value: boolean;
    onValueChange: (value: boolean) => void;
  }) => (
    <input
      type="checkbox"
      aria-label={label}
      checked={value}
      onChange={(event) => onValueChange(event.currentTarget.checked)}
    />
  ),
}));
vi.mock("./HarmonyAccountReverification", () => ({
  useHarmonyAccountReverification: (run: unknown) => ({ run, prompt: null }),
  isHarmonyReverificationCancelled: () => false,
}));

import { HarmonyAccountPassword } from "./HarmonyAccountPassword";

function mountPassword(passwordEnabled: boolean) {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  clerk.user.passwordEnabled = passwordEnabled;
  clerk.user.updatePassword.mockReset().mockImplementation(async () => {
    clerk.user.passwordEnabled = true;
    return clerk.user;
  });
  const container = document.createElement("div");
  const root = createRoot(container);
  const input = (label: string) =>
    container.querySelector<HTMLInputElement>(`input[aria-label="${label}"]`);
  const button = (label: string) => {
    const found = [...container.querySelectorAll("button")].find(
      (item) => item.textContent === label,
    );
    if (!found) throw new Error(`Missing button ${label}`);
    return found;
  };
  return {
    container,
    input,
    button,
    render: () => act(() => root.render(<HarmonyAccountPassword />)),
    press: (label: string) => act(async () => button(label).click()),
    fill: (label: string, value: string) => {
      const field = input(label);
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

it("adds a confirmed password without requiring an old password or signing out other devices", async () => {
  using screen = mountPassword(false);
  await screen.render();
  await screen.press("Add password");
  expect(screen.input("Current password")).toBeNull();
  await screen.fill("New password", " new password ");
  await screen.fill("Confirm password", "different password");
  expect(screen.button("Save").disabled).toBe(true);
  await screen.fill("Confirm password", " new password ");
  await screen.press("Save");

  expect(clerk.user.updatePassword).toHaveBeenCalledExactlyOnceWith({
    newPassword: " new password ",
    signOutOfOtherSessions: false,
  });
  expect(screen.container.querySelector('input[type="password"]')).toBeNull();
  expect(screen.button("Change password")).toBeDefined();
});

it("passes the current password and signs out other devices only when selected", async () => {
  using screen = mountPassword(true);
  await screen.render();
  await screen.press("Change password");
  await screen.fill("New password", "new password");
  await screen.fill("Confirm password", "new password");
  expect(screen.button("Save").disabled).toBe(true);
  await screen.fill("Current password", "old password");
  await act(() => screen.input("Sign out of all other devices")?.click());
  await screen.press("Save");

  expect(clerk.user.updatePassword).toHaveBeenCalledExactlyOnceWith({
    currentPassword: "old password",
    newPassword: "new password",
    signOutOfOtherSessions: true,
  });
});
