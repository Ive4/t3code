import { requireOptionalNativeModule } from "expo";
import { fetch as expoFetch } from "expo/fetch";

const native = requireOptionalNativeModule<{
  decodeRecording?: (uri: string) => Promise<Uint8Array>;
}>("T3VoiceTranscription");

export const decodeVoiceRecording = native?.decodeRecording?.bind(native);
export const fetchSpeech: typeof fetch = (url, options) =>
  expoFetch(url, { ...options, redirect: "error" });
