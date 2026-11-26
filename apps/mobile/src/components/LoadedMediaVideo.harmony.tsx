import { useIsFocused } from "@react-navigation/native";
import { T, useGT } from "gt-react-native";
import { useEffect, useEffectEvent, useId, useRef, useState, type ComponentRef } from "react";
import {
  DeviceEventEmitter,
  findNodeHandle,
  Pressable,
  requireNativeComponent,
  UIManager,
  View,
  type ViewProps,
} from "react-native";

import { useAppActive } from "../lib/appState";
import { createAudioPlaybackSession } from "../lib/audioSession";
import { useFullscreenVideoOpen } from "../lib/videoAudioSession";
import type { LoadedMediaVideoProps } from "./LoadedMediaVideo";
import { AppActivityIndicator } from "./ui/AppActivityIndicator";
import { AppText } from "./ui/AppText";

const NativeVideo = requireNativeComponent<
  ViewProps & {
    uri: string;
    initialAutoPlay: boolean;
    playbackAllowed: boolean;
    appFullscreen: boolean;
    initialPosition: number;
  }
>("T3InlineVideo");

type NativeVideoRef = ComponentRef<typeof NativeVideo>;
const PAUSE_COMMAND = 1;

type NativeVideoEvent = "prepared" | "start" | "pause" | "error" | { fullscreenPosition: number };

function InlineVideoAttempt(props: LoadedMediaVideoProps & { readonly onRetry: () => void }) {
  const gt = useGT();
  const focused = useIsFocused();
  const appActive = useAppActive();
  const fullscreenOpen = useFullscreenVideoOpen();
  const playbackAllowed =
    (props.fullscreen || (focused && !fullscreenOpen)) &&
    appActive &&
    props.visible &&
    !props.paused;
  const id = useId();
  const view = useRef<NativeVideoRef | null>(null);
  const [uri, setUri] = useState<string | null>(null);
  const [status, setStatus] = useState<"pending" | "ready" | "error">("pending");
  const [interrupted, setInterrupted] = useState(false);
  if (!playbackAllowed && !interrupted) setInterrupted(true);

  const resolveUrl = useEffectEvent(async () =>
    props.resolvePlaybackUri ? await props.resolvePlaybackUri() : props.uri,
  );
  const onNativeEvent = useEffectEvent(
    (event: NativeVideoEvent, playback: ReturnType<typeof createAudioPlaybackSession>) => {
      if (typeof event === "object") {
        if (playbackAllowed) props.onExpand?.(event.fullscreenPosition);
        return;
      }
      if (event === "prepared") setStatus("ready");
      if (event === "start") {
        if (playbackAllowed) {
          playback.playingChanged(true);
          if (playback.requested) props.onPlaybackStart?.();
        } else playback.pause();
      }
      if ((event === "pause" || event === "error") && playback.requested) playback.pause();
      if (event === "error") setStatus("error");
    },
  );

  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- attaches native video events and scopes the URL request to this attempt
  useEffect(() => {
    const controller = new AbortController();
    const playback = createAudioPlaybackSession(
      {
        play() {},
        pause() {
          const tag = findNodeHandle(view.current);
          if (typeof tag === "number") UIManager.dispatchViewManagerCommand(tag, PAUSE_COMMAND, []);
        },
      },
      true,
    );
    const subscription = DeviceEventEmitter.addListener("T3InlineVideo:" + id, (event) =>
      onNativeEvent(event, playback),
    );
    void resolveUrl().then(
      (resolved) => {
        if (controller.signal.aborted) return;
        if (resolved === null) setStatus("error");
        else setUri(resolved);
      },
      () => {
        if (!controller.signal.aborted) setStatus("error");
      },
    );
    return () => {
      controller.abort();
      subscription.remove();
      if (playback.requested) playback.pause();
    };
  }, [id]);

  return (
    <View collapsable={false} style={{ flex: 1 }}>
      {uri !== null && status !== "error" ? (
        <NativeVideo
          ref={view}
          collapsable={false}
          nativeID={id}
          uri={uri}
          initialAutoPlay={props.playRequested && playbackAllowed && !interrupted}
          playbackAllowed={playbackAllowed}
          appFullscreen={props.fullscreen === true || props.onExpand !== undefined}
          initialPosition={props.initialPosition ?? 0}
          style={{ width: "100%", height: "100%" }}
        />
      ) : null}
      {status === "error" ? (
        <View className="absolute inset-0 items-center justify-center gap-2 bg-black px-4">
          <AppText className="text-center text-sm text-white/80">
            <T>Video unavailable</T>
          </AppText>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={gt("Retry video")}
            onPress={props.onRetry}
            className="min-h-11 justify-center px-4"
          >
            <AppText className="text-sm text-white">
              <T>Retry</T>
            </AppText>
          </Pressable>
        </View>
      ) : status === "pending" ? (
        <View pointerEvents="none" className="absolute inset-0 items-center justify-center">
          <AppActivityIndicator color="#ffffff" accessibilityLabel={gt("Loading video")} />
        </View>
      ) : null}
    </View>
  );
}

export function LoadedMediaVideo(props: LoadedMediaVideoProps) {
  const [attempt, setAttempt] = useState(0);
  return (
    <InlineVideoAttempt key={attempt} {...props} onRetry={() => setAttempt((value) => value + 1)} />
  );
}
