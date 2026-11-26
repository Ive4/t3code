import { msg } from "gt-react-native";
import { TurboModuleRegistry, type TurboModule } from "react-native";

import {
  VoiceTranscriptionError,
  throwIfVoiceTranscriptionAborted,
  type VoiceTranscriber,
  type VoiceTranscriptionOptions,
} from "@t3tools/client-runtime/voice-input";
import { m } from "../i18n/messages";
import { uuidv4 } from "../lib/uuid";

interface LocalSpeechBridge extends TurboModule {
  checkLocalSpeechAvailability(): Promise<boolean>;
  transcribeLocalSpeech(id: string, uri: string): Promise<string>;
  cancelLocalSpeech(id: string): Promise<void>;
}

const native = TurboModuleRegistry.get<LocalSpeechBridge>("T3Audio");

export async function getLocalVoiceTranscriber(): Promise<VoiceTranscriber | null> {
  if (!native?.checkLocalSpeechAvailability || !(await native.checkLocalSpeechAvailability())) {
    return null;
  }
  const module = native;
  const transcribe = (uri: string, options: VoiceTranscriptionOptions) =>
    transcribeRecording(module, uri, options);
  return {
    prepare: async ({ signal }) => {
      throwIfVoiceTranscriptionAborted(signal);
      return { locale: "zh-CN", start: transcribe, transcribe };
    },
  };
}

async function transcribeRecording(
  module: LocalSpeechBridge,
  uri: string,
  { signal }: VoiceTranscriptionOptions,
): Promise<string> {
  throwIfVoiceTranscriptionAborted(signal);
  const id = uuidv4();
  let cancellation: Promise<void> | undefined;
  const abort = () => {
    cancellation = module.cancelLocalSpeech(id).catch(() => {});
  };
  signal.addEventListener("abort", abort, { once: true });
  try {
    const transcript = await module.transcribeLocalSpeech(id, uri);
    throwIfVoiceTranscriptionAborted(signal);
    return transcript;
  } catch (error) {
    throwIfVoiceTranscriptionAborted(signal);
    throw new VoiceTranscriptionError({
      code: "transcription-failed",
      message: m(msg("Voice transcription failed.")),
      cause: error,
    });
  } finally {
    signal.removeEventListener("abort", abort);
    await cancellation;
  }
}
