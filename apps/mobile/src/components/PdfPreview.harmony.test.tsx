import { RegistryContext } from "@effect/atom-react";
import { AtomRegistry } from "effect/reactivity";
import { act, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vite-plus/test";

const native = vi.hoisted(() => ({
  supported: true,
  listeners: new Map<string, (event: unknown) => void>(),
  open: vi.fn(),
  openUrl: vi.fn(),
  download: vi.fn(),
}));

vi.mock("../lib/nativeFileActions.harmony", () => ({
  isInlinePdfAvailable: () => native.supported,
}));
vi.mock("../lib/attachmentDownload", () => ({
  downloadAttachmentForPreview: native.download,
  openAttachmentInViewer: native.open,
}));
vi.mock("expo-file-system", () => ({
  FileMode: { ReadOnly: "read" },
  File: class {
    open() {
      return { readBytes: () => new TextEncoder().encode("%PDF-"), close: () => {} };
    }
  },
}));
vi.mock("react-native", () => ({
  DeviceEventEmitter: {
    addListener(name: string, listener: (event: unknown) => void) {
      native.listeners.set(name, listener);
      return { remove: () => native.listeners.delete(name) };
    },
  },
  Linking: { openURL: native.openUrl },
  requireNativeComponent:
    () =>
    (props: { readonly uri: string; readonly initialPage: number; readonly nativeID: string }) => (
      <output data-uri={props.uri} data-page={props.initialPage} data-id={props.nativeID} />
    ),
  View: ({ children }: { readonly children: ReactNode }) => <div>{children}</div>,
}));
vi.mock("../features/files/FilePreviewFeedback", () => ({
  FilePreviewLoading: (props: { readonly message: string }) => <span>{props.message}</span>,
  FilePreviewNotice: (props: { readonly children: ReactNode }) => <span>{props.children}</span>,
}));
vi.mock("./ui/ControlPill", () => ({
  ControlPill: (props: { readonly label: string; readonly onPress: () => void }) => (
    <button onClick={props.onPress}>{props.label}</button>
  ),
}));

import { PdfPreview } from "./PdfPreview.harmony";

function setup() {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  native.supported = true;
  native.listeners.clear();
  native.open.mockReset();
  native.openUrl.mockReset();
  native.download.mockReset();
  const container = document.createElement("div");
  const root = createRoot(container);
  const registry = AtomRegistry.make({
    scheduleTask: (task) => {
      queueMicrotask(task);
      return () => {};
    },
  });
  return {
    container,
    render: (uri: string) =>
      act(async () =>
        root.render(
          <RegistryContext.Provider value={registry}>
            <PdfPreview uri={uri} />
          </RegistryContext.Provider>,
        ),
      ),
    close: () => act(async () => root.render(null)),
    emit(event: unknown) {
      const id = container.querySelector("output")?.dataset.id;
      if (id === undefined) throw new Error("Missing native PDF view");
      act(() => native.listeners.get("T3PdfPreview:" + id)?.(event));
    },
    [Symbol.asyncDispose]: async () => {
      await act(async () => root.unmount());
      registry.dispose();
    },
  };
}

it("loads a signed document from app storage, forwards the starting page, and filters PDF links", async () => {
  await using screen = setup();
  const dispose = vi.fn();
  native.download.mockResolvedValueOnce({ uri: "file:///cache/preview.pdf", dispose });
  await screen.render("https://assets.test/docs/report.pdf?token=current#page=2");
  expect(native.download).toHaveBeenCalledExactlyOnceWith(
    expect.objectContaining({ url: "https://assets.test/docs/report.pdf?token=current" }),
  );
  const view = screen.container.querySelector("output");
  expect(view?.dataset.uri).toBe("file:///cache/preview.pdf");
  expect(view?.dataset.page).toBe("1");
  screen.emit({ type: "ready" });
  screen.emit({ type: "link", href: "file:///cache/another.pdf" });
  screen.emit({ type: "link", href: "handbook.html" });
  expect(native.openUrl).toHaveBeenCalledExactlyOnceWith("https://assets.test/docs/handbook.html");
  expect(dispose).not.toHaveBeenCalled();
  await screen.close();
  expect(native.listeners.size).toBe(0);
  expect(dispose).toHaveBeenCalled();
});

it.each(["capability", "runtime"])(
  "hands the PDF to the system when the %s is unavailable",
  async (source) => {
    await using screen = setup();
    const opened = Promise.withResolvers<void>();
    native.open.mockReturnValueOnce(opened.promise);
    native.supported = source === "runtime";
    await screen.render("file:///cache/report.pdf#page=2");
    if (native.supported) screen.emit({ type: "unavailable" });
    expect(screen.container.querySelector("output")).toBeNull();
    const button = screen.container.querySelector("button");
    expect(button?.textContent).toBe("Open PDF");
    act(() => button?.click());
    expect(native.open).toHaveBeenCalledExactlyOnceWith(
      expect.objectContaining({ uri: "file:///cache/report.pdf" }),
    );
    const signal = native.open.mock.calls[0]![0].signal;
    await screen.close();
    expect(signal.aborted).toBe(true);
    await act(async () => opened.resolve());
  },
);
