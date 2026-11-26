import { ARCHIVE_MAX_BYTES } from "@t3tools/client-runtime/zip/bounded-zip";
import { ZipError } from "@t3tools/client-runtime/zip/error";
import { File } from "expo-file-system";
import { downloadAttachmentForPreview } from "../../lib/attachmentDownload";
import type { ZipArchiveDownloadInput } from "./zipArchiveDownload";

export async function downloadZipArchive({
  url,
  name,
  signal,
  onProgress,
}: ZipArchiveDownloadInput) {
  const cached = await downloadAttachmentForPreview({
    url,
    attachment: { name, mimeType: "application/zip" },
    signal,
  });
  if (cached === null) throw signal.reason;
  try {
    const file = new File(cached.uri);
    if ((file.size ?? 0) > ARCHIVE_MAX_BYTES) throw new ZipError({ code: "file-too-large" });
    const bytes = await file.arrayBuffer();
    if (signal.aborted) throw signal.reason;
    if (bytes.byteLength > ARCHIVE_MAX_BYTES) throw new ZipError({ code: "file-too-large" });
    onProgress(bytes.byteLength);
    return bytes;
  } finally {
    cached.dispose();
  }
}
