import { act, use, useState, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vite-plus/test";

vi.mock("react-native", () => ({
  Modal: (props: { readonly children: ReactNode; readonly onRequestClose: () => void }) => (
    <section
      role="dialog"
      onKeyDown={(event) => {
        if (event.key === "Escape") props.onRequestClose();
      }}
    >
      {props.children}
    </section>
  ),
  Pressable: (props: {
    readonly accessibilityLabel?: string;
    readonly children?: ReactNode;
    readonly onPress?: () => void;
    readonly disabled?: boolean;
  }) => (
    <button aria-label={props.accessibilityLabel} onClick={props.onPress} disabled={props.disabled}>
      {props.children}
    </button>
  ),
  View: (props: {
    readonly children?: ReactNode;
    readonly style?: React.CSSProperties;
    readonly accessibilityElementsHidden?: boolean;
  }) => (
    <div style={props.style} aria-hidden={props.accessibilityElementsHidden}>
      {props.children}
    </div>
  ),
}));
vi.mock("react-native-safe-area-context", async () => {
  const { createContext, use } = await import("react");
  const SafeAreaInsetsContext = createContext({ top: 23, bottom: 14, left: 0, right: 0 });
  return { SafeAreaInsetsContext, useSafeAreaInsets: () => use(SafeAreaInsetsContext) };
});
vi.mock("./PaneSheet", () => import("./PaneSheet.harmony"));
vi.mock(
  "../../features/layout/inspector-host",
  () => import("../../features/layout/inspector-host.harmony"),
);
vi.mock("../RenderErrorBoundary", () => ({
  RenderErrorBoundary: ({ children }: { readonly children: ReactNode }) => children,
  RenderFailureView: () => null,
}));
vi.mock("./AppBar", () => ({
  AppBar: (props: { readonly title: string; readonly leading?: ReactNode }) => (
    <header>
      {props.title}
      {props.leading}
    </header>
  ),
}));
vi.mock("./IconButton", () => ({
  IconButton: (props: {
    readonly accessibilityLabel: string;
    readonly onPress: () => void;
    readonly disabled?: boolean;
  }) => (
    <button
      aria-label={props.accessibilityLabel}
      onClick={props.onPress}
      disabled={props.disabled}
    />
  ),
}));

import { PaneSheet } from "./PaneSheet.harmony";
import { Sheet } from "./Sheet.harmony";
import { OverlayPortal } from "./OverlayPortal";
import {
  InspectorSheetContext,
  WorkspaceInspectorSheet,
} from "../../features/layout/workspace-inspector-sheet";

function setup() {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  const container = document.createElement("div");
  const root = createRoot(container);
  return {
    container,
    render: (child: ReactNode) => act(() => root.render(child)),
    back: () =>
      act(() => {
        container
          .querySelector('[role="dialog"]')
          ?.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
      }),
    press: (label: string) =>
      act(() => {
        const button = container.querySelector<HTMLButtonElement>(`[aria-label="${label}"]`);
        if (!button) throw new Error(`Missing button ${label}`);
        button.click();
      }),
    [Symbol.dispose]: () => act(() => root.unmount()),
  };
}

it("opens Git branches after removing the inspector", () => {
  using app = setup();
  const states: boolean[] = [];

  function GitPane() {
    const closeInspector = use(InspectorSheetContext);
    return (
      <button
        aria-label="Branches"
        onClick={() =>
          closeInspector?.(() => {
            states.push(app.container.querySelector('[role="dialog"]') !== null);
          })
        }
      >
        Git status
      </button>
    );
  }
  function Inspector() {
    const [open, setOpen] = useState(true);
    return (
      <WorkspaceInspectorSheet
        open={open}
        onClose={() => setOpen(false)}
        content={{ active: "git", panes: [{ key: "git", render: () => <GitPane /> }] }}
      />
    );
  }
  app.render(<Inspector />);
  expect(app.container.textContent).toContain("Git status");
  app.press("Branches");
  expect(states).toEqual([false]);
});

it("removes the inspector on Back before notifying its owner once", () => {
  using app = setup();
  const states: boolean[] = [];
  const onNativeDismiss = () =>
    states.push(app.container.querySelector('[role="dialog"]') !== null);
  const onDismiss = vi.fn();
  app.render(
    <PaneSheet isOpen detents={[0.6, 0.95]} onDismiss={onDismiss} onNativeDismiss={onNativeDismiss}>
      Files
    </PaneSheet>,
  );
  expect(app.container.textContent).toBe("Files");
  app.back();
  app.back();
  expect(states).toEqual([false]);
  expect(onDismiss).not.toHaveBeenCalled();
});

it("shows inspector menus inside the modal and dismisses the menu before the inspector", () => {
  using app = setup();
  const onDismiss = vi.fn();

  function Inspector() {
    const [menuOpen, setMenuOpen] = useState(true);
    return (
      <PaneSheet isOpen detents={[0.6]} onDismiss={onDismiss} onNativeDismiss={onDismiss}>
        Files
        {menuOpen ? (
          <OverlayPortal onRequestClose={() => setMenuOpen(false)}>File menu</OverlayPortal>
        ) : null}
      </PaneSheet>
    );
  }

  app.render(<Inspector />);
  expect(app.container.querySelector('[role="dialog"]')?.textContent).toContain("File menu");
  app.back();
  expect(app.container.textContent).toBe("Files");
  expect(onDismiss).not.toHaveBeenCalled();
  app.back();
  expect(onDismiss).toHaveBeenCalledOnce();
});

it("keeps a protected sheet open from its button or Back until dismissal is allowed", () => {
  using app = setup();
  const onClose = vi.fn();
  const show = (dismissDisabled: boolean) =>
    app.render(
      <Sheet title="Terminal output" dismissDisabled={dismissDisabled} onClose={onClose}>
        Command output
      </Sheet>,
    );
  show(true);
  app.press("Close Terminal output");
  app.back();
  expect(app.container.textContent).toContain("Command output");
  expect(onClose).not.toHaveBeenCalled();

  show(false);
  app.press("Close Terminal output");
  expect(app.container.querySelector('[role="dialog"]')).toBeNull();
  expect(onClose).toHaveBeenCalledTimes(1);
});
