import { useIsFocused } from "@react-navigation/native";
import { useGT } from "gt-react-native";
import { useLayoutEffect, useState } from "react";
import { Pressable, View } from "react-native";

import { AppActivityIndicator } from "./ui/AppActivityIndicator";
import { AppText } from "./ui/AppText";
import { SymbolView } from "./ui/AppSymbol";
import { VideoThumbnailImage } from "./VideoThumbnailImage";
import { useMediaActions } from "../state/mediaActions";
import { fitVideoFrame } from "../lib/videoFrameFit";
import { loadVideoThumbnail } from "../lib/videoThumbnails";
import { type MediaActionsSource } from "../lib/mediaActionsSource";
import { MediaActionsMenu } from "./MediaActionsMenu";
import { LoadedMediaVideo } from "./LoadedMediaVideo";

interface MediaVideoPlayerProps {
  readonly uri: string | null;
  readonly resolvePlaybackUri?: () => Promise<string | null>;
  readonly name: string;
  readonly thumbnailKey: string;
  readonly thumbnailVisible?: boolean;
  readonly visible?: boolean;
  readonly unavailable?: boolean;
  readonly unavailableDetail?: string | undefined;
  readonly expanded?: boolean;
  readonly fullscreen?: boolean | undefined;
  readonly initialPosition?: number | undefined;
  readonly onExpand?: ((position: number) => void) | undefined;
  /** Fill the parent and size the frame to the video's shape instead of a fixed 16:9 slot. */
  readonly fitToVideo?: boolean;
  readonly autoPlay?: boolean;
  readonly paused?: boolean;
  readonly onPlaybackStart?: () => void;
  readonly actionsSource?: MediaActionsSource;
  readonly borderRadius?: number;
}

function MediaVideoPlayerContent(props: MediaVideoPlayerProps) {
  const gt = useGT();
  const mediaActions = useMediaActions(props.actionsSource);
  const isFocused = useIsFocused();
  const [playbackUri, setPlaybackUri] = useState<string | null>(props.expanded ? props.uri : null);
  // Keep an opened player mounted while signing or reconnecting temporarily has no usable URL.
  if (playbackUri === null && props.expanded && props.uri !== null) setPlaybackUri(props.uri);
  const unavailableText = props.unavailableDetail
    ? gt("Video unavailable. {detail}", { detail: props.unavailableDetail })
    : gt("Video unavailable");
  const [videoSize, setVideoSize] = useState<{ width: number; height: number } | null>(null);
  const [bounds, setBounds] = useState<{ width: number; height: number } | null>(null);
  const sizeSource = props.fitToVideo && isFocused && videoSize === null ? props.uri : null;
  // Queue before the poster so early Play cannot cancel the extraction that supplies frame dimensions.
  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- loads native thumbnail dimensions independently of the poster's lifetime
  useLayoutEffect(() => {
    if (sizeSource === null) return;
    // Thumbnails are oriented like the displayed frame, unlike VideoTrack.size.
    const controller = new AbortController();
    void loadVideoThumbnail(
      props.thumbnailKey,
      async () => ({ uri: sizeSource, dispose: () => undefined }),
      controller.signal,
    ).then((thumbnail) => {
      if (thumbnail && !controller.signal.aborted) {
        setVideoSize({ width: thumbnail.width, height: thumbnail.height });
      }
    });
    return () => controller.abort();
  }, [props.thumbnailKey, sizeSource]);
  const fittedFrame =
    props.fitToVideo && videoSize && bounds ? fitVideoFrame(videoSize, bounds, 480) : null;

  const frame = (
    <View
      collapsable={false}
      className="overflow-hidden rounded-[10px] bg-black"
      style={[
        props.expanded
          ? { flex: 1 }
          : (fittedFrame ?? { width: "100%", maxWidth: 480, aspectRatio: 16 / 9 }),
        props.borderRadius === undefined ? null : { borderRadius: props.borderRadius },
      ]}
    >
      {playbackUri ? (
        <LoadedMediaVideo
          uri={props.uri ?? playbackUri}
          resolvePlaybackUri={props.resolvePlaybackUri}
          playRequested={!props.expanded || props.autoPlay === true}
          paused={(props.paused ?? false) || mediaActions.sharing}
          visible={props.visible ?? true}
          fullscreen={props.fullscreen}
          initialPosition={props.initialPosition}
          onExpand={props.onExpand}
          onPlaybackStart={props.onPlaybackStart}
        />
      ) : (
        <MediaActionsMenu media={mediaActions} inModal={props.expanded} style={{ flex: 1 }}>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={
              props.unavailable
                ? `${props.name}. ${unavailableText}`
                : gt("Play {name}", { name: props.name })
            }
            accessibilityHint={
              mediaActions.actions.length > 0 ? gt("Touch and hold for media actions") : undefined
            }
            accessibilityState={{ disabled: props.uri === null || props.unavailable === true }}
            // Stays pressable so the long-press menu still opens on a failed or unsigned tile.
            onPress={() => {
              if (props.uri !== null && !props.unavailable) {
                props.onPlaybackStart?.();
                setPlaybackUri(props.uri);
              }
            }}
            className="flex-1 items-center justify-center px-4"
          >
            {!props.unavailable ? (
              <VideoThumbnailImage
                cacheKey={props.thumbnailKey}
                source={props.thumbnailVisible === false ? null : props.uri}
                contentFit="contain"
              />
            ) : null}
            {props.unavailable ? (
              <AppText className="text-center text-sm text-white/80">{unavailableText}</AppText>
            ) : props.uri === null ? (
              <AppActivityIndicator color="#ffffff" accessibilityLabel={gt("Loading video")} />
            ) : (
              <View className="size-12 items-center justify-center rounded-full bg-black/60">
                <SymbolView name="play" size={28} tintColor="#ffffff" type="monochrome" />
              </View>
            )}
            {props.uri !== null && !props.unavailable ? (
              <AppText
                className="absolute right-2 bottom-2 max-w-[75%] rounded bg-black/60 px-2 py-1 text-right text-xs text-white"
                numberOfLines={1}
              >
                {props.name}
              </AppText>
            ) : null}
          </Pressable>
        </MediaActionsMenu>
      )}
    </View>
  );
  if (!props.fitToVideo) return frame;
  return (
    <View
      className="flex-1 items-center justify-center self-stretch"
      onLayout={(event) => {
        const { width, height } = event.nativeEvent.layout;
        setBounds({ width, height });
      }}
    >
      {frame}
    </View>
  );
}

export function MediaVideoPlayer(props: MediaVideoPlayerProps) {
  return <MediaVideoPlayerContent key={props.thumbnailKey} {...props} />;
}
