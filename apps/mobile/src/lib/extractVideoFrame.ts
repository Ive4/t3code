export async function extractVideoFrame(uri: string) {
  const { createVideoPlayer } = await import("expo-video");
  const player = createVideoPlayer(null);
  let disposed = false;
  let timeout: ReturnType<typeof setTimeout> | undefined;
  let attachedSubscription: { remove(): void } | undefined;
  try {
    // Never play or change audio settings: thumbnails must leave the shared audio session alone.
    player.bufferOptions = { preferredForwardBufferDuration: 1 };
    const timedOut = new Promise<null>((resolve) => {
      timeout = setTimeout(() => resolve(null), 15_000);
    });
    // iOS resolves replaceAsync before the main thread attaches the item, and until then
    // generateThumbnailsAsync finds no asset and returns no frames.
    const attached = new Promise<void>((resolve) => {
      attachedSubscription = player.addListener("sourceChange", ({ source }) => {
        if (source) resolve();
      });
    });
    const frame = (async () => {
      await player.replaceAsync({ uri, contentType: "progressive" });
      await attached;
      if (disposed) return null;
      const [thumbnail] = await player.generateThumbnailsAsync([0], {
        maxWidth: 480,
        maxHeight: 480,
      });
      return thumbnail ?? null;
    })();
    return await Promise.race([frame, timedOut]);
  } finally {
    disposed = true;
    clearTimeout(timeout);
    attachedSubscription?.remove();
    player.release();
  }
}
