import { act, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vite-plus/test";

import type { ConfirmDialogRequest } from "../../components/ui/Dialog";

const fixture = vi.hoisted(() => ({
  user: {
    id: "user",
    externalAccounts: [] as ReturnType<typeof externalAccount>[],
    passkeys: [] as ReturnType<typeof passkey>[],
    emailAddresses: [],
    phoneNumbers: [],
    passwordEnabled: true,
    createExternalAccount: vi.fn(),
    reload: vi.fn(),
  },
  session: { id: "current" },
  buildUserProfileUrl: vi.fn(),
  openBrowser: vi.fn(),
  userListeners: new Set<() => void>(),
  listeners: new Set<(state: string) => void>(),
  browserListeners: new Set<(event: { url: string }) => void>(),
  confirm: vi.fn<(request: ConfirmDialogRequest) => void>(),
}));

vi.mock("@clerk/expo", async () => {
  const { useSyncExternalStore } = await import("react");
  function subscribe(listener: () => void) {
    fixture.userListeners.add(listener);
    return () => fixture.userListeners.delete(listener);
  }
  return {
    useClerk: () => fixture,
    useUser: () => ({ user: useSyncExternalStore(subscribe, () => fixture.user) }),
    useSession: () => ({ session: fixture.session }),
  };
});
vi.mock("react-native", () => ({
  View: ({ children }: { children?: ReactNode }) => <div>{children}</div>,
  Linking: {
    openURL: fixture.openBrowser,
    addEventListener: (_name: string, listener: (event: { url: string }) => void) => {
      fixture.browserListeners.add(listener);
      return { remove: () => fixture.browserListeners.delete(listener) };
    },
  },
  AppState: {
    addEventListener: (_name: string, listener: (state: string) => void) => {
      fixture.listeners.add(listener);
      return { remove: () => fixture.listeners.delete(listener) };
    },
  },
}));
vi.mock("../../components/ui/AppText", () => ({
  AppText: ({
    children,
    accessibilityRole,
  }: {
    children: ReactNode;
    accessibilityRole?: string;
  }) => <span role={accessibilityRole}>{children}</span>,
  AppTextInput: () => null,
}));
vi.mock("../../components/ui/Button", () => ({
  Button: ({
    label,
    accessibilityLabel,
    disabled,
    loading,
    onPress,
  }: {
    label: string;
    accessibilityLabel?: string;
    disabled?: boolean;
    loading?: boolean;
    onPress: () => void;
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
vi.mock("../../components/ui/ListRowLayout", () => ({
  ListRowLayout: ({ label, detail }: { label: string; detail?: string }) => (
    <div>
      {label} {detail}
    </div>
  ),
}));
vi.mock("../../components/ui/Dialog", () => ({ confirm: fixture.confirm }));
vi.mock("./components/SettingsSection", () => ({
  SettingsSection: ({ title, children }: { title: string; children: ReactNode }) => (
    <section>
      <h2>{title}</h2>
      {children}
    </section>
  ),
}));
vi.mock("./HarmonyAccountReverification", () => ({
  useHarmonyAccountReverification: (run: unknown) => ({ run, prompt: null }),
  isHarmonyReverificationCancelled: () => false,
}));

import { harmonyAccountRedirect } from "../cloud/harmonyHostedAuth";
import {
  HarmonyAccountLinkedAccounts,
  HarmonyAccountPasskeys,
} from "./HarmonyAccountLinkedAccounts";

function externalAccount(id: string, status: string) {
  return {
    id,
    verification: {
      status,
      externalVerificationRedirectURL: new URL("https://accounts.example.test/link"),
    },
    providerSlug: () => "google",
    providerTitle: () => "Google Account",
    accountIdentifier: () => "ada@example.test",
    destroy: vi.fn().mockResolvedValue(undefined),
    reauthorize: vi.fn(),
  };
}

function passkey() {
  return {
    id: "passkey",
    name: "Tablet passkey",
    verification: { status: "verified" },
    delete: vi.fn().mockResolvedValue(undefined),
  };
}

function publishUser(patch: Partial<typeof fixture.user>) {
  fixture.user = { ...fixture.user, ...patch };
  for (const listener of fixture.userListeners) listener();
  return fixture.user;
}

function mount() {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  fixture.session.id = "current";
  fixture.user.passwordEnabled = true;
  fixture.user.externalAccounts = [];
  fixture.user.passkeys = [];
  fixture.user.createExternalAccount.mockReset();
  fixture.user.reload.mockReset().mockImplementation(async () => fixture.user);
  fixture.openBrowser.mockReset().mockResolvedValue(undefined);
  fixture.buildUserProfileUrl.mockReset().mockReturnValue("");
  fixture.confirm.mockReset();
  const container = document.createElement("div");
  const root = createRoot(container);
  return {
    container,
    browserCallback: (url: string) => {
      for (const listener of fixture.browserListeners) listener({ url });
    },
    linked: () => act(async () => root.render(<HarmonyAccountLinkedAccounts />)),
    passkeys: (key = "passkeys") =>
      act(async () => root.render(<HarmonyAccountPasskeys key={key} />)),
    button(label: string) {
      return [...container.querySelectorAll("button")].find(
        (button) => (button.getAttribute("aria-label") ?? button.textContent) === label,
      );
    },
    async press(label: string) {
      const button = this.button(label);
      if (!button) throw new Error(`Missing button "${label}"`);
      await act(async () => button.click());
    },
    async confirm() {
      const request = fixture.confirm.mock.lastCall?.[0];
      if (!request) throw new Error("Missing destructive confirmation");
      expect(request.destructive).toBe(true);
      await act(async () => request.onConfirm());
    },
    [Symbol.dispose]() {
      act(() => root.unmount());
      vi.unstubAllGlobals();
    },
  };
}

it("reloads the connected identity only after the registered browser callback", async () => {
  using screen = mount();
  const pending = externalAccount("pending", "unverified");
  fixture.user.createExternalAccount.mockResolvedValue(pending);
  await screen.linked();
  await screen.press("Connect Google");

  expect(fixture.user.createExternalAccount).toHaveBeenCalledWith({
    strategy: "oauth_google",
    redirectUrl: harmonyAccountRedirect,
  });
  expect(fixture.openBrowser).toHaveBeenCalledWith("https://accounts.example.test/link");
  expect(fixture.user.reload).not.toHaveBeenCalled();
  fixture.user.externalAccounts = [externalAccount("pending", "verified")];
  await act(async () => screen.browserCallback(harmonyAccountRedirect + "?status=complete"));

  expect(fixture.user.reload).toHaveBeenCalledOnce();
  expect(screen.container.textContent).toContain("Google Account");
  expect(screen.button("Connect Google")).toBeUndefined();
});

it("waits for Clerk to verify the exact linked identity after a callback", async () => {
  using screen = mount();
  fixture.user.createExternalAccount.mockResolvedValue(externalAccount("pending", "unverified"));
  await screen.linked();
  await screen.press("Connect Google");
  fixture.user.externalAccounts = [externalAccount("different", "verified")];
  await act(async () => screen.browserCallback(harmonyAccountRedirect));

  expect(screen.container.querySelector('[role="alert"]')?.textContent).toBe(
    "Could not connect this account. Try again.",
  );
});

it("releases the OAuth callback on cancel and leaves a pending connection resumable", async () => {
  using screen = mount();
  const pending = externalAccount("pending", "unverified");
  fixture.user.createExternalAccount.mockResolvedValue(pending);
  await screen.linked();
  await screen.press("Connect Google");
  expect(fixture.browserListeners.size).toBe(1);

  fixture.user.externalAccounts = [pending];
  await screen.press("Cancel");

  expect(fixture.browserListeners.size).toBe(0);
  expect(screen.container.querySelector('[role="alert"]')).toBeNull();
  expect(screen.button("Continue connecting")).toBeDefined();
  expect(screen.button("Connect Google")).toBeUndefined();
});

it("keeps the last linked sign-in method and checks the session again after confirmation", async () => {
  using screen = mount();
  const linked = externalAccount("linked", "verified");
  fixture.user.passwordEnabled = false;
  fixture.user.externalAccounts = [linked];
  await screen.linked();
  expect(screen.button("Remove Google Account")?.disabled).toBe(true);
  await act(async () => publishUser({ passwordEnabled: true }));
  await screen.press("Remove Google Account");
  expect(linked.destroy).not.toHaveBeenCalled();

  fixture.session.id = "different";
  await screen.confirm();
  expect(linked.destroy).not.toHaveBeenCalled();
});

it("opens only the configured HTTPS passkey profile and refreshes on return", async () => {
  using screen = mount();
  const profileUrl = "https://accounts.example.test/user";
  fixture.buildUserProfileUrl.mockReturnValue("http://accounts.example.test/user");
  await screen.passkeys();
  expect(screen.button("Manage passkeys in browser")).toBeUndefined();

  fixture.buildUserProfileUrl.mockReturnValue(profileUrl);
  await screen.passkeys("configured");
  await screen.press("Manage passkeys in browser");
  expect(fixture.openBrowser).toHaveBeenCalledWith(profileUrl);
  expect(fixture.user.reload).not.toHaveBeenCalled();
  fixture.user.reload.mockImplementationOnce(async () => publishUser({ passkeys: [passkey()] }));
  await act(async () => {
    for (const listener of fixture.listeners) listener("active");
  });
  expect(fixture.user.reload).toHaveBeenCalledOnce();
  expect(screen.container.textContent).toContain("Tablet passkey");
});

it("removes a passkey with another sign-in method only after confirmation", async () => {
  using screen = mount();
  const credential = passkey();
  fixture.user.passkeys = [credential];
  credential.delete.mockImplementationOnce(async () => {
    fixture.user.passkeys = [];
  });
  await screen.passkeys();
  await screen.press("Remove Tablet passkey");
  expect(credential.delete).not.toHaveBeenCalled();

  await screen.confirm();

  expect(credential.delete).toHaveBeenCalledOnce();
  expect(fixture.user.reload).toHaveBeenCalledOnce();
  expect(screen.container.textContent).not.toContain("Tablet passkey");
});
