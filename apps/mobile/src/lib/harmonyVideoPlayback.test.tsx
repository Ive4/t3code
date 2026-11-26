import {
  act,
  createContext,
  useImperativeHandle,
  useLayoutEffect,
  useState,
  type ReactNode,
  type Ref,
} from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vite-plus/test";
import type { MediaActionsSource } from "./mediaActionsSource";
import type { VideoPreviewSource } from "./videoPreviewSource";

const state = vi.hoisted(() => ({
  active: true,
  blur: undefined as (() => void) | undefined,
  refresh: vi.fn(),
  share: vi.fn<(source: MediaActionsSource) => Promise<void>>(),
  listeners: new Map<string, (event: unknown) => void>(),
}));

vi.mock("@react-navigation/native", () => ({
  useIsFocused: () => true,
  useNavigation: () => navigation,
}));
const navigation = {
  isFocused: () => true,
  addListener: (_event: string, listener: () => void) => {
    state.blur = listener;
    return () => {
      state.blur = undefined;
    };
  },
};

type MeasureRef = Ref<{
  measureInWindow: (measure: (x: number, y: number, w: number, h: number) => void) => void;
}>;

vi.mock("gt-react-native", () => ({
  T: ({ children }: { children: ReactNode }) => children,
  useGT: () => (message: string) => message,
  useMessages: () => (message: string) => message,
}));
vi.mock("react-native", () => ({
  findNodeHandle: () => null,
  UIManager: {},
  Platform: { OS: "harmony" },
  DeviceEventEmitter: {
    addListener(name: string, receive: (event: unknown) => void) {
      state.listeners.set(name, receive);
      return { remove: () => state.listeners.delete(name) };
    },
  },
  Keyboard: { dismiss: () => {} },
  Modal: (props: { children?: ReactNode; onRequestClose: () => void }) => (
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
    children?: ReactNode;
    onPress?: () => void;
    accessibilityLabel?: string;
    disabled?: boolean;
    ref?: MeasureRef;
  }) => {
    useImperativeHandle(
      props.ref,
      () => ({ measureInWindow: (measure) => measure(160, 0, 44, 44) }),
      [],
    );
    return (
      <button
        aria-label={props.accessibilityLabel}
        disabled={props.disabled}
        onClick={props.onPress}
      >
        {props.children}
      </button>
    );
  },
  View: (props: {
    children?: ReactNode;
    onLayout?: (event: { nativeEvent: { layout: { width: number; height: number } } }) => void;
    ref?: MeasureRef;
  }) => {
    useImperativeHandle(
      props.ref,
      () => ({ measureInWindow: (measure) => measure(0, 0, 400, 720) }),
      [],
    );
    const [onLayout] = useState(() => props.onLayout);
    useLayoutEffect(
      () => onLayout?.({ nativeEvent: { layout: { width: 400, height: 720 } } }),
      [onLayout],
    );
    return <div>{props.children}</div>;
  },
  ScrollView: ({ children }: { children?: ReactNode }) => <div>{children}</div>,
  requireNativeComponent:
    () =>
    (props: {
      uri: string;
      initialAutoPlay: boolean;
      playbackAllowed: boolean;
      nativeID: string;
      initialPosition?: number;
    }) => (
      <video
        src={props.uri}
        data-id={props.nativeID}
        data-position={props.initialPosition}
        data-autoplay={props.initialAutoPlay}
        data-allowed={props.playbackAllowed}
      />
    ),
}));
vi.mock("../components/ui/AppText", () => ({
  AppText: ({ children }: { children?: ReactNode }) => <span>{children}</span>,
}));
vi.mock("../components/ui/AppSymbol", () => ({ SymbolView: () => null }));
vi.mock("../components/ui/AppSymbol.android", () => ({ isAppSymbolName: () => true }));
vi.mock("../components/ui/AppActivityIndicator", () => ({ AppActivityIndicator: () => null }));
vi.mock("../components/VideoThumbnailImage", () => ({ VideoThumbnailImage: () => null }));
vi.mock("../state/mediaActions", () => ({
  useMediaActions: (source?: MediaActionsSource) => {
    const [sharing, setSharing] = useState(false);
    const share = () => {
      if (source === undefined || sharing) return;
      setSharing(true);
      void state.share(source).finally(() => setSharing(false));
    };
    return {
      actions: source
        ? [{ id: "save", run: share, title: "Save or share", disabled: sharing }]
        : [],
      sharing,
      share,
    };
  },
}));
vi.mock("@react-native-menu/menu", () => ({ MenuView: () => null }));
vi.mock("expo", () => ({ requireOptionalNativeModule: () => null }));
vi.mock("expo-haptics", () => ({}));
vi.mock("react-native-keyboard-controller", () => ({ useKeyboardState: () => false }));
vi.mock("react-native-safe-area-context", () => ({
  useSafeAreaInsets: () => ({ top: 0, bottom: 0 }),
}));
vi.mock("../components/ui/Menu", () => import("../components/ui/Menu.harmony"));
vi.mock("../components/ui/MenuPopup", () => import("../components/ui/MenuPopup.harmony"));
vi.mock("../components/ui/useAndroidControlSizing", () => ({
  useAndroidControlSizing: () => ({ scale: 1, menuWidth: 240, menuItemHeight: 48 }),
}));
vi.mock("../native/window-hinge-context", () => ({ WindowHingeContext: createContext(null) }));
vi.mock("./backHandler", () => ({ useHardwareBack: () => {} }));
vi.mock("./localAttachmentPreview", () => ({
  useLocalAttachmentPreview: () => ({ uri: "file:///clip.mp4", error: null }),
}));
vi.mock("../state/session", () => ({ usePreparedConnection: () => ({ _tag: "Some" }) }));
vi.mock("../state/assets", () => ({
  useRefreshAssetUrl: () => state.refresh,
  useAssetUrlState: () => ({ _tag: "Success", url: "https://media.example/expired.mp4" }),
}));
vi.mock("./appState", () => ({ useAppActive: () => state.active }));
vi.mock("./audioSession", () => ({
  createAudioPlaybackSession: () => ({ pause: () => {}, playingChanged: () => {} }),
}));
vi.mock("./videoThumbnails", () => ({
  cachedVideoThumbnail: () => null,
  loadVideoThumbnail: async () => null,
}));

vi.mock("../components/LoadedMediaVideo", () => import("../components/LoadedMediaVideo.harmony"));
vi.mock(
  "../components/ui/VideoPreviewModal",
  () => import("../components/ui/VideoPreviewModal.harmony"),
);

import { MediaVideoPlayer } from "../components/MediaVideoPlayer";
import { OverlayPortalHost } from "../components/ui/OverlayPortal";
import { VideoPreviewModal } from "../components/ui/VideoPreviewModal.harmony";
import { ChatAttachmentId, EnvironmentId } from "@t3tools/contracts";
import { useFullscreenVideoOpen } from "./videoAudioSession";
import { ThreadMarkdownVideo } from "../features/threads/ThreadMarkdownVideo";
import { WorkspaceFileVideoPreview } from "../features/files/WorkspaceFileVideoPreview";

function InlineVideo(props: { readonly visible?: boolean; readonly paused?: boolean }) {
  return (
    <MediaVideoPlayer
      name="inline.mp4"
      thumbnailKey="inline"
      uri="https://media.example/inline.mp4"
      visible={props.visible ?? true}
      paused={props.paused ?? false}
    />
  );
}

function FullscreenPlaybackMarker() {
  return <output>{String(useFullscreenVideoOpen())}</output>;
}

function setup() {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  state.active = true;
  state.share.mockReset().mockResolvedValue(undefined);
  state.refresh.mockReset().mockResolvedValue("https://media.example/fresh.mp4");
  const container = document.createElement("div");
  const root = createRoot(container);
  const source = Promise.withResolvers<string>();
  return {
    container,
    source,
    openInline(element: ReactNode) {
      return act(async () => root.render(element));
    },
    fullscreen() {
      const id = container.querySelector("video")?.dataset.id;
      if (!id) throw new Error("Missing inline player");
      return act(async () =>
        state.listeners.get("T3InlineVideo:" + id)?.({ fullscreenPosition: 7 }),
      );
    },
    preview(video: VideoPreviewSource | null, onClose = () => {}) {
      return act(async () => {
        root.render(
          <>
            <InlineVideo />
            <VideoPreviewModal source={video} onRequestClose={onClose} />
            <OverlayPortalHost />
            <FullscreenPlaybackMarker />
          </>,
        );
      });
    },
    press(label: string) {
      act(() => container.querySelector<HTMLButtonElement>(`[aria-label="${label}"]`)!.click());
    },
    back() {
      act(() =>
        container
          .querySelector('[role="dialog"]')!
          .dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })),
      );
    },
    render(visible = true, paused = false) {
      act(() =>
        root.render(
          <MediaVideoPlayer
            name="clip.mp4"
            thumbnailKey="clip"
            uri="https://media.example/expired.mp4"
            resolvePlaybackUri={() => source.promise}
            visible={visible}
            paused={paused}
          />,
        ),
      );
    },
    tapPlay() {
      act(() => container.querySelector("button")!.click());
    },
    async signedUrl() {
      await act(async () => source.resolve("https://media.example/fresh.mp4"));
    },
    [Symbol.dispose]() {
      act(() => root.unmount());
    },
  };
}

it("plays a refreshed source inline and keeps its position when automatic playback is interrupted", async () => {
  using screen = setup();
  screen.render();
  expect(screen.container.querySelector("video")).toBeNull();
  screen.tapPlay();
  await screen.signedUrl();

  const video = screen.container.querySelector("video");
  expect(video?.getAttribute("src")).toBe("https://media.example/fresh.mp4");
  expect(video?.dataset.autoplay).toBe("true");
  expect(video?.dataset.allowed).toBe("true");

  screen.render(false);
  expect(video?.dataset.allowed).toBe("false");
  screen.render();
  expect(screen.container.querySelector("video")).toBe(video);
  expect(video?.dataset.allowed).toBe("true");
  expect(video?.dataset.autoplay).toBe("false");
});

it.each(["thread", "workspace"])(
  "routes %s video expansion to the app-owned sharing preview",
  async (surface) => {
    using screen = setup();
    const source = {
      type: "media",
      uri: "https://media.example/inline.mp4",
      name: "clip.mp4",
      mimeType: "video/mp4",
    } satisfies VideoPreviewSource;
    await screen.openInline(
      surface === "thread" ? (
        <ThreadMarkdownVideo source={source} thumbnailVisible />
      ) : (
        <WorkspaceFileVideoPreview
          name={source.name}
          thumbnailKey="inline"
          uri={source.uri}
          source={source}
          resolvePlaybackUri={async () => source.uri}
        />
      ),
    );
    await act(async () => screen.press("Play {name}"));
    await screen.fullscreen();
    const modal = screen.container.querySelector('[role="dialog"]');
    expect(modal?.querySelector("video")?.dataset.position).toBe("7");
    expect(modal?.querySelector('[aria-label="Save or share video"]')).not.toBeNull();
  },
);

it("does not auto-start a video after entering the background while signing", async () => {
  using screen = setup();
  screen.render();
  screen.tapPlay();
  state.active = false;
  screen.render();
  state.active = true;
  screen.render();
  await screen.signedUrl();

  expect(screen.container.querySelector("video")?.dataset.autoplay).toBe("false");
});

it("shows full-screen actions over the modal, pauses during sharing, and keeps the remote resource", async () => {
  using screen = setup();
  const close = vi.fn();
  const share = Promise.withResolvers<void>();
  state.share.mockReturnValue(share.promise);
  const source = {
    type: "media",
    name: "clip.mp4",
    mimeType: "video/mp4",
    environmentId: EnvironmentId.make("env"),
    resource: {
      _tag: "attachment",
      attachmentId: ChatAttachmentId.make("clip"),
      fileName: "clip.mp4",
      mimeType: "video/mp4",
    },
  } satisfies VideoPreviewSource;
  await screen.preview(null, close);
  screen.press("Play {name}");
  await act(async () => {});
  const inline = screen.container.querySelector("video");
  expect(inline?.dataset.allowed).toBe("true");
  await screen.preview({ ...source, actionsSource: source }, close);

  const modal = screen.container.querySelector('[role="dialog"]');
  const video = modal?.querySelector("video");
  expect(video?.getAttribute("src")).toBe("https://media.example/fresh.mp4");
  expect(video?.dataset.allowed).toBe("true");
  expect(inline?.dataset.allowed).toBe("false");
  screen.press("Media actions");
  expect(modal?.textContent).toContain("Save or share");
  expect(
    [...modal!.querySelectorAll("button")].filter(
      (button) => button.textContent === "Save or share",
    ),
  ).toHaveLength(1);
  expect(screen.container.querySelector('[role="dialog"] + div')).toBeNull();
  screen.back();
  expect(close).not.toHaveBeenCalled();

  screen.press("Save or share video");
  expect(state.share).toHaveBeenCalledExactlyOnceWith(source);
  expect(video?.dataset.allowed).toBe("false");
  expect(
    modal?.querySelector<HTMLButtonElement>('[aria-label="Save or share video"]')?.disabled,
  ).toBe(true);
  await act(async () => share.resolve());
  expect(video?.dataset.allowed).toBe("true");
  screen.back();
  expect(close).toHaveBeenCalledOnce();
  await screen.preview(null, close);
  expect(screen.container.querySelector('[role="dialog"]')).toBeNull();
  expect(inline?.dataset.allowed).toBe("true");
  expect(inline?.dataset.autoplay).toBe("false");
});

it("passes the draft attachment to the share pipeline and releases the full-screen flag on route blur", async () => {
  using screen = setup();
  const close = vi.fn();
  const source = {
    type: "local",
    attachment: {
      type: "file",
      id: "draft",
      name: "draft.mp4",
      mimeType: "video/mp4",
      sizeBytes: 100,
      fileUri: "file:///clip.mp4",
    },
    sourceIdentifier: "draft-tile",
  } satisfies VideoPreviewSource;
  await screen.preview(source, close);
  expect(screen.container.querySelector("output")?.textContent).toBe("true");
  await act(async () => screen.press("Save or share video"));
  expect(state.share).toHaveBeenCalledExactlyOnceWith({
    attachment: source.attachment,
    name: "draft.mp4",
    mimeType: "video/mp4",
    sourceIdentifier: "draft-tile",
  });
  act(() => state.blur?.());
  expect(close).toHaveBeenCalledOnce();
  await screen.preview(null);
  expect(screen.container.querySelector("output")?.textContent).toBe("false");
  expect(state.blur).toBeUndefined();
});

it("shares the original external video URL from the modal menu", async () => {
  using screen = setup();
  const source = {
    type: "media",
    name: "clip.mp4",
    mimeType: "video/mp4",
    uri: "https://external.example/clip.mp4",
  } satisfies VideoPreviewSource;
  await screen.preview(source);
  screen.press("Media actions");
  const save = [...screen.container.querySelectorAll("button")].find(
    (button) => button.textContent === "Save or share",
  );
  await act(async () => save?.click());
  expect(state.share).toHaveBeenCalledExactlyOnceWith(source);
  expect(state.refresh).not.toHaveBeenCalled();
});
