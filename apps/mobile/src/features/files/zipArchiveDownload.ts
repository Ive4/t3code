import { ARCHIVE_MAX_BYTES } from "@t3tools/client-runtime/zip/bounded-zip";
import { ZipError } from "@t3tools/client-runtime/zip/error";
import { fetch } from "expo/fetch";

export interface ZipArchiveDownloadInput {
  readonly url: string;
  readonly name: string;
  readonly signal: AbortSignal;
  readonly onProgress: (receivedBytes: number) => void;
}

export async function downloadZipArchive({ url, signal, onProgress }: ZipArchiveDownloadInput) {
  const response = await fetch(url, { signal });
  if (!response.ok || !response.body) throw new Error("ZIP response unavailable");
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > ARCHIVE_MAX_BYTES) throw new ZipError({ code: "file-too-large" });
      chunks.push(value);
      onProgress(size);
    }
  } finally {
    void reader.cancel().catch(() => {});
  }
  signal.throwIfAborted();
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes.buffer;
}
