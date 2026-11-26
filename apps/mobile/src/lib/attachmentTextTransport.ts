import { readFilePreviewResponse } from "@t3tools/client-runtime/file-preview";
import { fetch } from "expo/fetch";
import { File } from "expo-file-system";

export function readLocalAttachmentText(uri: string, signal: AbortSignal) {
  return readFilePreviewResponse({ ok: true, body: new File(uri).readableStream() }, signal);
}

export async function readRemoteAttachmentText(
  url: string,
  headers: Record<string, string>,
  signal: AbortSignal,
) {
  return readFilePreviewResponse(await fetch(url, { headers, signal }), signal);
}
