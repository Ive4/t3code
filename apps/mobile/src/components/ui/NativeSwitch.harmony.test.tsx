import { act, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vite-plus/test";

vi.mock("react-native", () => ({
  Pressable: ({
    children,
    disabled,
    onPress,
  }: {
    children: ReactNode;
    disabled?: boolean;
    onPress: () => void;
  }) => (
    <button type="button" disabled={disabled} onClick={onPress}>
      {children}
    </button>
  ),
  View: ({ children }: { children: ReactNode }) => <div>{children}</div>,
}));
vi.mock("./useControlTheme", () => ({ useControlTheme: () => ({ colors: {} }) }));

import { NativeSwitch } from "./NativeSwitch.harmony";

it("routes a Harmony switch tap through the shared controlled callback", async () => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  const container = document.createElement("div");
  const root = createRoot(container);
  const change = vi.fn();
  try {
    await act(() => root.render(<NativeSwitch value={false} onValueChange={change} />));
    await act(() => container.querySelector("button")?.click());
    expect(change).toHaveBeenCalledExactlyOnceWith(true);

    await act(() => root.render(<NativeSwitch value disabled onValueChange={change} />));
    await act(() => container.querySelector("button")?.click());
    expect(change).toHaveBeenCalledOnce();
  } finally {
    await act(() => root.unmount());
    vi.unstubAllGlobals();
  }
});
