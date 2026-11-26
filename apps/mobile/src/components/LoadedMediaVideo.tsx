import { useEvent } from "expo";
import { useVideoPlayer, VideoView } from "expo-video";
import { T, useGT } from "gt-react-native";
import { useEffect, useEffectEvent, useRef, useState } from "react";
import { Pressable, View } from "react-native";

import { AppActivityIndicator } from "./ui/AppActivityIndicator";
import { AppText } from "./ui/AppText";
import { useMediaVideoPlayback } from "../lib/useMediaVideoPlayback";
import { createAudioPlaybackSession } from "../lib/audioSession";

export interface LoadedMediaVideoProps {
  readonly uri: string;
  readonly resolvePlaybackUri?: () => Promise<string | null>;
  readonly playRequested: boolean;
  readonly paused: boolean;
  readonly visible: boolean;
  readonly fullscreen?: boolean | undefined;
  readonly initialPosition?: number | undefined;
  readonly onExpand?: ((position: number) => void) | undefined;
  readonly onPlaybackStart?: () => void;
}

export function LoadedMediaVideo(props: LoadedMediaVideoProps) {
  const gt = useGT();
  const [attempt, setAttempt] = useState(0);
  // Expo's Android player also reports completed playback as idle.
  const [loadState, setLoadState] = useState<"pending" | "complete" | "error">("pending");
  const player = useVideoPlayer(null, (player) => {
    player.staysActiveInBackground = false;
    player.bufferOptions = { preferredForwardBufferDuration: 5 };
  });
  const playback = createAudioPlaybackSession(player, true);
  const { active, fullscreen, createPlayRequest, onFullscreenEnter, onFullscreenExit } =
    useMediaVideoPlayback(player, props, playback);
  const previousPlaybackRequested = useRef(false);
  const onPlaybackStart = useEffectEvent(() => props.onPlaybackStart?.());
  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- subscribes to native video player events to keep the shared audio session in step
  useEffect(() => {
    const subscription = player.addListener("playingChange", ({ isPlaying }) => {
      if (isPlaying && !active.current && !fullscreen.current) playback.pause();
      else playback.playingChanged(isPlaying);
    });
    const requested = player.addListener("playbackRequestedChange", ({ isPlaybackRequested }) => {
      const wasPlaybackRequested = previousPlaybackRequested.current;
      previousPlaybackRequested.current = isPlaybackRequested;
      if (!isPlaybackRequested) {
        if (playback.requested) playback.pause();
      } else if (!active.current && !fullscreen.current) playback.pause();
      else {
        if (!wasPlaybackRequested) onPlaybackStart();
        playback.playingChanged(true);
      }
    });
    const ended = player.addListener("playToEnd", () => playback.pause());
    const failed = player.addListener("statusChange", ({ status }) => {
      if (status === "error") playback.pause();
    });
    return () => {
      subscription.remove();
      requested.remove();
      ended.remove();
      failed.remove();
      playback.pause();
      previousPlaybackRequested.current = false;
    };
  }, [active, fullscreen, player, playback]);
  const { status } = useEvent(player, "statusChange", { status: player.status });
  const loadSource = useEffectEvent(async (signal: AbortSignal) => {
    const playIfUninterrupted = createPlayRequest();
    const uri = props.resolvePlaybackUri ? await props.resolvePlaybackUri() : props.uri;
    if (signal.aborted) return;
    if (uri === null) throw new Error("Video unavailable");
    playback.pause();
    previousPlaybackRequested.current = false;
    await player.replaceAsync({ uri, contentType: "progressive" });
    if (!signal.aborted && props.playRequested) await playIfUninterrupted();
  });

  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- loads the video source into the native player and aborts the load on cleanup
  useEffect(() => {
    const controller = new AbortController();
    // oxlint-disable-next-line react/set-state-in-effect -- Starting a native media load publishes pending before its async result.
    setLoadState("pending");
    // A renewed signature is used on Retry, not as a reason to reset the native player.
    void loadSource(controller.signal).then(
      () => {
        if (!controller.signal.aborted) setLoadState("complete");
      },
      () => {
        if (!controller.signal.aborted) setLoadState("error");
      },
    );
    return () => controller.abort();
    // oxlint-disable-next-line react/exhaustive-effect-dependencies -- A play request or Retry (attempt) reloads the source into the same player.
  }, [player, props.playRequested, attempt]);

  return (
    <View collapsable={false} style={{ flex: 1 }}>
      <VideoView
        player={player}
        style={{ width: "100%", height: "100%" }}
        surfaceType="textureView"
        nativeControls
        contentFit="contain"
        fullscreenOptions={{ enable: true }}
        onFullscreenEnter={onFullscreenEnter}
        onFullscreenExit={onFullscreenExit}
        allowsPictureInPicture={false}
      />
      {loadState === "error" || (loadState === "complete" && status === "error") ? (
        <View className="absolute inset-0 items-center justify-center gap-2 bg-black px-4">
          <AppText className="text-center text-sm text-white/80">
            <T>Video unavailable</T>
          </AppText>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={gt("Retry video")}
            onPress={() => setAttempt((value) => value + 1)}
            className="min-h-11 justify-center px-4"
          >
            <AppText className="text-sm text-white">
              <T>Retry</T>
            </AppText>
          </Pressable>
        </View>
      ) : loadState === "pending" || status === "loading" ? (
        <View pointerEvents="none" className="absolute inset-0 items-center justify-center">
          <AppActivityIndicator color="#ffffff" accessibilityLabel={gt("Loading video")} />
        </View>
      ) : null}
    </View>
  );
}
