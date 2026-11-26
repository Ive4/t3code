import { useEffect } from "react";

import { fullscreenVideoClosed, fullscreenVideoOpened } from "../../lib/videoAudioSession";
import type { VideoPreviewSource } from "../../lib/videoPreviewSource";
import { VideoPreviewModal as FullscreenVideoPreview } from "./VideoPreviewModal.fullscreen";

export type { VideoPreviewSource } from "../../lib/videoPreviewSource";

export function VideoPreviewModal(props: {
  readonly source: VideoPreviewSource | null;
  readonly onRequestClose: () => void;
}) {
  const open = props.source !== null;
  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- pauses inline playback while the modal owns playback
  useEffect(() => {
    if (!open) return;
    fullscreenVideoOpened();
    return fullscreenVideoClosed;
  }, [open]);

  return <FullscreenVideoPreview {...props} harmony />;
}
