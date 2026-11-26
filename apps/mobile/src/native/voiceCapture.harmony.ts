import { SPEECH_MAX_OPTIONS_BYTES } from "@t3tools/contracts";
import { VOICE_RECORDING_LIMIT_SECONDS } from "@t3tools/client-runtime/voice-input";
import { File, FileMode, Paths } from "expo-file-system";
import { TurboModuleRegistry, type TurboModule } from "react-native";

import { uuidv4 } from "../lib/uuid";

interface AudioBridge extends TurboModule {
  requestSpeech(
    id: string,
    url: string,
    method: string,
    headers: string,
    bodyUri: string,
  ): Promise<{ status: number; body: string; headers: string }>;
  cancelSpeech(id: string): Promise<void>;
}

const native = TurboModuleRegistry.get<AudioBridge>("T3Audio");
const maxPcmBytes = 16_000 * 2 * VOICE_RECORDING_LIMIT_SECONDS;
const maxRequestBytes = maxPcmBytes * 2 + SPEECH_MAX_OPTIONS_BYTES + 4;

export const decodeVoiceRecording = native
  ? async (uri: string): Promise<Uint8Array> => {
      const file = new File(uri);
      const size = file.size;
      if (
        uri !== new File(Paths.cache, file.name).uri ||
        !/^t3-recording-[0-9a-f-]+\.pcm$/i.test(file.name) ||
        size === null ||
        size === 0 ||
        size % 2 !== 0 ||
        size > maxPcmBytes
      ) {
        throw new Error("Invalid voice recording.");
      }
      return file.bytes();
    }
  : undefined;

export const fetchSpeech: typeof fetch = async (url, options) => {
  if (!native) throw new Error("Voice transcription is unavailable.");
  if (typeof url !== "string" && !(url instanceof URL)) throw new Error("Expected a speech URL.");
  const method = options?.method ?? "GET";
  const signal = options?.signal;
  if (signal?.aborted) throw signal.reason;
  const body = options?.body;
  const bytes = typeof body === "string" ? new TextEncoder().encode(body) : body;
  if (bytes != null && (!(bytes instanceof Uint8Array) || bytes.byteLength > maxRequestBytes))
    throw new Error("Invalid speech request body.");

  const id = uuidv4();
  const file = bytes == null ? null : new File(Paths.cache, "t3-speech-send-" + id);
  const stopped = Promise.withResolvers<never>();
  const abort = () => {
    stopped.reject(signal?.reason);
    void native.cancelSpeech(id).catch(() => {});
  };
  try {
    if (file && bytes != null) {
      file.create();
      const handle = file.open(FileMode.WriteOnly);
      try {
        const chunkSize = 64 * 1024;
        for (let offset = 0; offset < bytes.length; offset += chunkSize) {
          if (signal?.aborted) throw signal.reason;
          await handle.writeBytes(bytes.subarray(offset, offset + chunkSize));
        }
      } finally {
        handle.close();
      }
    }
    if (signal?.aborted) throw signal.reason;
    signal?.addEventListener("abort", abort, { once: true });
    const headers = new Headers(options?.headers);
    const request = native.requestSpeech(
      id,
      url.toString(),
      method,
      JSON.stringify(Object.fromEntries(headers.entries())),
      file?.uri ?? "",
    );
    const response = await Promise.race([request, stopped.promise]);
    if (response.status >= 300 && response.status < 400)
      throw new Error("Speech redirects are unsupported.");
    return new Response(response.status === 204 || response.status === 205 ? null : response.body, {
      status: response.status,
      headers: JSON.parse(response.headers),
    });
  } finally {
    signal?.removeEventListener("abort", abort);
    try {
      file?.delete();
    } catch {}
  }
};
