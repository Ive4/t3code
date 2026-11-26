import { decodeFilePreviewText, FILE_TEXT_PREVIEW_MAX_BYTES } from "@t3tools/shared/filePreview";
import { File, FileMode } from "expo-file-system";

import { downloadAttachmentForPreview } from "./attachmentDownload";

const READ_CHUNK_BYTES = 64 * 1024;

export async function readLocalAttachmentText(uri: string, signal: AbortSignal) {
  if (signal.aborted) throw signal.reason;
  const reader = new File(uri).open(FileMode.ReadOnly);
  try {
    const bytes = new Uint8Array(FILE_TEXT_PREVIEW_MAX_BYTES + 1);
    let length = 0;
    while (length < bytes.length) {
      const chunk = await reader.readBytes(Math.min(READ_CHUNK_BYTES, bytes.length - length));
      if (signal.aborted) throw signal.reason;
      if (chunk.length === 0) break;
      bytes.set(chunk, length);
      length += chunk.length;
    }
    return decodeFilePreviewText(bytes.subarray(0, length));
  } finally {
    reader.close();
  }
}

export async function readRemoteAttachmentText(
  url: string,
  headers: Record<string, string>,
  signal: AbortSignal,
) {
  // Harmony's fetch lacks a response stream. The native download enforces its own byte limit.
  const file = await downloadAttachmentForPreview({
    url,
    attachment: { name: "preview.txt", mimeType: "text/plain" },
    signal,
    headers,
  });
  if (file === null) throw signal.reason;
  try {
    return await readLocalAttachmentText(file.uri, signal);
  } finally {
    file.dispose();
  }
}
