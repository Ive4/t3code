import { useGT } from "gt-react-native";
import { useState, type ComponentProps } from "react";
import { Pressable } from "react-native";

import type { MediaVideoPlayer as CommonMediaVideoPlayer } from "./MediaVideoPlayer";
import { usePreviewPresentation } from "../lib/previewPresentation";
import { AppText } from "./ui/AppText";
import { SymbolView } from "./ui/AppSymbol";
import { HarmonyVideoPreview } from "./ui/VideoPreviewModal.harmony";

export function MediaVideoPlayer(props: ComponentProps<typeof CommonMediaVideoPlayer>) {
  const gt = useGT();
  const [open, setOpen] = useState(false);
  const close = () => setOpen(false);
  usePreviewPresentation(open ? props.thumbnailKey : null, close);
  const canPlay = props.uri !== null && !props.unavailable;
  const label = canPlay ? gt("Play {name}", { name: props.name }) : gt("Video unavailable");
  return (
    <>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={label}
        disabled={!canPlay}
        onPress={() => {
          props.onPlaybackStart?.();
          setOpen(true);
        }}
        className="aspect-video w-full max-w-[480px] items-center justify-center gap-2 bg-black px-4"
        style={{ borderRadius: props.borderRadius ?? 10 }}
      >
        {canPlay ? <SymbolView name="play" size={28} tintColor="#ffffff" /> : null}
        <AppText className="text-center text-sm text-white" numberOfLines={2}>
          {canPlay ? props.name : (props.unavailableDetail ?? label)}
        </AppText>
      </Pressable>
      {open && props.visible !== false && !props.paused ? (
        <HarmonyVideoPreview
          name={props.name}
          onRequestClose={close}
          load={async () => {
            const uri = props.resolvePlaybackUri ? await props.resolvePlaybackUri() : props.uri;
            return uri === null ? null : { uri };
          }}
        />
      ) : null}
    </>
  );
}
