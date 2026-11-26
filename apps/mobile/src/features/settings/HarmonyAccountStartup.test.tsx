import { act, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vite-plus/test";

vi.mock("react-native", () => ({
  View: ({ children }: { children?: ReactNode }) => <div>{children}</div>,
}));
vi.mock("../../components/ui/AppText", () => ({
  AppText: ({ children }: { children?: ReactNode }) => <span>{children}</span>,
}));
vi.mock("../../components/ui/AppActivityIndicator", () => ({
  AppActivityIndicator: () => <span role="progressbar" />,
}));
vi.mock("../../components/ui/Button", () => ({
  Button: ({ label, onPress }: { label: string; onPress: () => void }) => (
    <button type="button" onClick={onPress}>
      {label}
    </button>
  ),
}));

import { HarmonyAccountStartup } from "./HarmonyAccountStartup";

it("replaces a stalled check with a retry and keeps retry available on failure", async () => {
  vi.useFakeTimers();
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  const container = document.createElement("div");
  const root = createRoot(container);
  const reload = vi.fn().mockRejectedValue(new Error("Connection refused"));
  try {
    await act(() => root.render(<HarmonyAccountStartup reload={reload} />));
    expect(container.querySelector('[role="progressbar"]')).not.toBeNull();

    await act(() => vi.runOnlyPendingTimersAsync());
    expect(container.textContent).toContain("Could not connect to T3 Account");
    await act(() => container.querySelector("button")?.click());

    expect(reload).toHaveBeenCalledOnce();
    expect(container.querySelector("button")?.textContent).toBe("Try again");
  } finally {
    await act(() => root.unmount());
    vi.useRealTimers();
    vi.unstubAllGlobals();
  }
});
