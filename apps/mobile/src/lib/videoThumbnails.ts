import type { AttachmentPreviewFile } from "./attachmentDownload";
import { extractVideoFrame } from "./extractVideoFrame";

export type VideoThumbnail = NonNullable<Awaited<ReturnType<typeof extractVideoFrame>>>;

const thumbnails = new Map<string, VideoThumbnail>();
const MAX_CACHED_THUMBNAILS = 32;
let pending: Promise<unknown> = Promise.resolve();

export function cachedVideoThumbnail(key: string): VideoThumbnail | null {
  return thumbnails.get(key) ?? null;
}

export function loadVideoThumbnail(
  key: string,
  resolveSource: (
    signal: AbortSignal,
  ) => Promise<Pick<AttachmentPreviewFile, "uri" | "dispose"> | null>,
  signal: AbortSignal,
): Promise<VideoThumbnail | null> {
  if (signal.aborted) return Promise.resolve(null);
  const cached = cachedVideoThumbnail(key);
  if (cached) return Promise.resolve(cached);
  const load = pending
    .then(async () => {
      if (signal.aborted) return null;
      const cached = cachedVideoThumbnail(key);
      if (cached) return cached;

      const source = await resolveSource(signal);
      if (!source) return null;
      try {
        if (signal.aborted) return null;
        // A started extraction finishes even if its reader leaves: its requests are already in
        // flight, and a re-signed URL for the same video replaces the reader, not the frame.
        const thumbnail = await extractVideoFrame(source.uri);
        if (!thumbnail) return null;
        thumbnails.set(key, thumbnail);
        if (thumbnails.size > MAX_CACHED_THUMBNAILS) {
          thumbnails.delete(thumbnails.keys().next().value!);
        }
        return thumbnail;
      } finally {
        source.dispose();
      }
    })
    .catch(() => null);
  pending = load;
  return load;
}
