import { act, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vite-plus/test";

import type { ConfirmDialogRequest } from "../../components/ui/Dialog";

const clerk = vi.hoisted(() => ({
  user: { id: "user", getSessions: vi.fn() },
  session: { id: "current", reload: vi.fn() },
}));
const confirm = vi.hoisted(() => vi.fn<(request: ConfirmDialogRequest) => void>());

vi.mock("@clerk/expo", () => ({
  useAuth: () => ({ sessionId: clerk.session.id }),
  useClerk: () => clerk,
}));
vi.mock("react-native", () => ({
  View: ({ children }: { children?: ReactNode }) => <div>{children}</div>,
}));
vi.mock("../../components/ui/AppActivityIndicator", () => ({ AppActivityIndicator: () => null }));
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
vi.mock("../../components/ui/Dialog", () => ({ confirm }));

import { HarmonyAccountSessions } from "./HarmonyAccountSessions";

function fixtureSession(id: string, deviceType: string, status = "active") {
  return {
    id,
    status,
    latestActivity: { deviceType },
    lastActiveAt: new Date("2026-11-23T11:00:00Z"),
    revoke: vi.fn().mockResolvedValue(undefined),
  };
}

function mountSessions() {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  clerk.user.id = "user";
  clerk.session.id = "current";
  clerk.session.reload.mockReset();
  confirm.mockReset();
  const current = fixtureSession("current", "HarmonyOS phone");
  const other = fixtureSession("other", "Android tablet");
  const revoked = fixtureSession("revoked", "Old desktop", "revoked");
  clerk.user.getSessions.mockReset();
  clerk.user.getSessions.mockResolvedValue([other, revoked, current]);
  const container = document.createElement("div");
  const root = createRoot(container);
  return {
    container,
    current,
    other,
    open: () => act(async () => root.render(<HarmonyAccountSessions user={clerk.user} />)),
    pressSignOut: () => act(() => container.querySelector("button")?.click()),
    [Symbol.dispose]() {
      act(() => root.unmount());
      vi.unstubAllGlobals();
    },
  };
}

function pendingConfirmation() {
  const request = confirm.mock.lastCall?.[0];
  if (!request) throw new Error("Missing sign-out confirmation");
  return request;
}

it("shows the current session and only signs out another device after confirmation", async () => {
  using screen = mountSessions();
  await screen.open();

  expect(screen.container.textContent).toContain("Current session");
  expect(screen.container.textContent).toContain("Android tablet");
  expect(screen.container.textContent).not.toContain("Old desktop");
  expect(screen.container.querySelectorAll("button")).toHaveLength(1);

  screen.pressSignOut();
  expect(pendingConfirmation().destructive).toBe(true);
  expect(screen.other.revoke).not.toHaveBeenCalled();
  await act(async () => pendingConfirmation().onConfirm());

  expect(screen.other.revoke).toHaveBeenCalledOnce();
  expect(screen.current.revoke).not.toHaveBeenCalled();
  expect(screen.container.textContent).toContain("Current session");
  expect(screen.container.textContent).not.toContain("Android tablet");
});

it("rejects a confirmation when the active session switched to the selected device", async () => {
  using screen = mountSessions();
  await screen.open();
  screen.pressSignOut();
  clerk.session.id = "other";

  await act(async () => pendingConfirmation().onConfirm());

  expect(screen.other.revoke).not.toHaveBeenCalled();
  expect(screen.current.revoke).not.toHaveBeenCalled();
});

it("keeps the other session available after a failed revocation", async () => {
  using screen = mountSessions();
  screen.other.revoke.mockRejectedValueOnce(new Error("Offline"));
  await screen.open();
  screen.pressSignOut();
  await act(async () => pendingConfirmation().onConfirm());

  expect(screen.container.querySelector('[role="alert"]')).not.toBeNull();
  expect(screen.container.textContent).toContain("Android tablet");
  screen.pressSignOut();
  await act(async () => pendingConfirmation().onConfirm());
  expect(screen.container.textContent).not.toContain("Android tablet");
});

it("retries an unavailable session list through a refreshed Clerk session", async () => {
  using screen = mountSessions();
  clerk.user.getSessions.mockResolvedValue([]);
  const getSessions = vi.fn().mockResolvedValue([screen.current, screen.other]);
  clerk.session.reload.mockResolvedValue({ id: "current", user: { id: "user", getSessions } });
  await screen.open();

  expect(screen.container.querySelector('[role="alert"]')?.textContent).toBe(
    "Could not load active sessions.",
  );
  expect(screen.container.querySelector("button")?.textContent).toBe("Retry");
  await act(async () => screen.container.querySelector("button")?.click());

  expect(screen.container.textContent).toContain("Current session");
  expect(screen.container.textContent).toContain("Android tablet");
  expect(clerk.user.getSessions).toHaveBeenCalledOnce();
  expect(getSessions).toHaveBeenCalledOnce();
});

it("discards a session reload after the active account changes", async () => {
  using screen = mountSessions();
  clerk.user.getSessions.mockResolvedValue([]);
  const getSessions = vi.fn().mockResolvedValue([screen.current, screen.other]);
  clerk.session.reload.mockImplementation(async () => {
    clerk.user.id = "different-user";
    return { id: "current", user: { id: "user", getSessions } };
  });
  await screen.open();

  expect(screen.container.querySelector("button")?.textContent).toBe("Retry");
  await act(async () => screen.container.querySelector("button")?.click());

  expect(clerk.session.reload).toHaveBeenCalledOnce();
  expect(getSessions).not.toHaveBeenCalled();
  expect(screen.container.textContent).not.toContain("Android tablet");
});
