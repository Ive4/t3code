import { useGT } from "gt-react-native";
import { useEffect, useEffectEvent, useId } from "react";
import { TurboModuleRegistry, type TurboModule } from "react-native";

import { loadLocalAttachmentPreview } from "../../lib/localAttachmentPreview";
import { usePreviewPresentation, videoPreviewKey } from "../../lib/previewPresentation";
import { fullscreenVideoClosed, fullscreenVideoOpened } from "../../lib/videoAudioSession";
import { mediaVideoPreviewUri, type VideoPreviewSource } from "../../lib/videoPreviewSource";
import { refreshAssetUrl } from "../../state/assets";
import * as Dialog from "./Dialog";

export type { VideoPreviewSource } from "../../lib/videoPreviewSource";

interface NativeVideo extends TurboModule {
  present(uri: string, title: string, closeLabel: string, identifier: string): Promise<void>;
  close(identifier: string): Promise<void>;
}

type VideoLease = { readonly uri: string; readonly dispose?: () => void };

export function HarmonyVideoPreview(props: {
  readonly name: string;
  readonly load: (signal: AbortSignal) => Promise<VideoLease | null>;
  readonly onRequestClose: () => void;
}) {
  const gt = useGT();
  const identifier = useId();
  const load = useEffectEvent(props.load);
  const present = useEffectEvent((nativeVideo: NativeVideo, uri: string) =>
    nativeVideo.present(uri, props.name, gt("Close video"), identifier),
  );
  const finish = useEffectEvent((failed: boolean) => {
    if (failed) Dialog.alert(gt("Could not open video"), gt("Could not load this video."));
    props.onRequestClose();
  });

  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- manages the native dialog and its attachment lease
  useEffect(() => {
    const controller = new AbortController();
    const nativeVideo = TurboModuleRegistry.get<NativeVideo>("T3Video");
    fullscreenVideoOpened();
    void load(controller.signal)
      .then(async (file) => {
        await (async () => {
          if (controller.signal.aborted) return;
          if (!file || !nativeVideo) {
            finish(true);
            return;
          }
          await present(nativeVideo, file.uri);
          if (!controller.signal.aborted) finish(false);
        })().finally(() => file?.dispose?.());
      })
      .catch(() => {
        if (!controller.signal.aborted) finish(true);
      });
    return () => {
      controller.abort();
      fullscreenVideoClosed();
      void nativeVideo?.close(identifier).catch(() => undefined);
    };
  }, [identifier]);

  return null;
}

export function VideoPreviewModal(props: {
  readonly source: VideoPreviewSource | null;
  readonly onRequestClose: () => void;
}) {
  const { source } = props;
  const key = source === null ? null : videoPreviewKey(source);
  usePreviewPresentation(key, props.onRequestClose);
  if (source === null) return null;
  const name = source.type === "local" ? source.attachment.name : source.name;
  return (
    <HarmonyVideoPreview
      key={key}
      name={name}
      onRequestClose={props.onRequestClose}
      load={async (signal) => {
        if (source.type === "local") return loadLocalAttachmentPreview(source.attachment, signal);
        if ("uri" in source) return { uri: source.uri };
        const url = await refreshAssetUrl(source.environmentId, source.resource);
        const uri = mediaVideoPreviewUri(source, url);
        return uri === null ? null : { uri };
      }}
    />
  );
}
