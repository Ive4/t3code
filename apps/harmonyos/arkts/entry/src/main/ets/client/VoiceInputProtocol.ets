export type VoiceInputMode = 'local' | 'environment';

export type VoiceRecordingState =
  | 'idle'
  | 'requesting-permission'
  | 'recording'
  | 'transcribing'
  | 'error';

export interface VoiceInputSnapshot {
  state: VoiceRecordingState;
  mode: VoiceInputMode;
  durationMs: number;
  audioLevel: number;
  errorMessage: string | null;
  transcript: string | null;
}

export interface VoiceSpeechRequest {
  url: string;
  method: string;
  headers: Record<string, string>;
  audioBytesLength: number;
  mimeType: string;
}

export interface VoiceSpeechRequestOptions {
  authToken?: string;
  model?: string;
  provider?: string;
}

interface SpeechTranscriptionOptionsWire {
  speechLanguage: string;
  speechTranslateToEnglish: boolean;
  speechCustomWords: Array<Object>;
  speechRemoveFillerWords: boolean;
  speechSilenceFiltering: boolean;
}

interface RawSpeechTranscriptionResponse {
  text?: Object | null;
  message?: Object | null;
  error?: Object | null;
}

const SPEECH_MAX_OPTIONS_BYTES = 128_000;

export function createInitialVoiceInputSnapshot(
  mode: VoiceInputMode = 'local',
): VoiceInputSnapshot {
  return {
    state: 'idle',
    mode,
    durationMs: 0,
    audioLevel: 0,
    errorMessage: null,
    transcript: null,
  };
}

function clampAudioLevel(audioLevel: number): number {
  if (!Number.isFinite(audioLevel)) {
    return 0;
  }
  if (audioLevel <= 0) {
    return 0;
  }
  if (audioLevel >= 1) {
    return 1;
  }
  return audioLevel;
}

function clampDurationMs(durationMs: number, fallback: number): number {
  if (!Number.isFinite(durationMs)) {
    return fallback;
  }
  if (durationMs <= 0) {
    return 0;
  }
  return Math.round(durationMs);
}

export function requestVoicePermission(
  snapshot: VoiceInputSnapshot,
  mode?: VoiceInputMode,
): VoiceInputSnapshot {
  return {
    state: 'requesting-permission',
    mode: mode ?? snapshot.mode,
    durationMs: 0,
    audioLevel: 0,
    errorMessage: null,
    transcript: null,
  };
}

export function startVoiceRecording(
  snapshot: VoiceInputSnapshot,
  mode?: VoiceInputMode,
): VoiceInputSnapshot {
  return {
    state: 'recording',
    mode: mode ?? snapshot.mode,
    durationMs: 0,
    audioLevel: 0,
    errorMessage: null,
    transcript: null,
  };
}

export function updateVoiceLevel(
  snapshot: VoiceInputSnapshot,
  audioLevel: number,
  durationMs: number,
): VoiceInputSnapshot {
  if (snapshot.state !== 'recording') {
    return {
      state: snapshot.state,
      mode: snapshot.mode,
      durationMs: snapshot.durationMs,
      audioLevel: snapshot.audioLevel,
      errorMessage: snapshot.errorMessage,
      transcript: snapshot.transcript,
    };
  }
  return {
    state: 'recording',
    mode: snapshot.mode,
    durationMs: clampDurationMs(durationMs, snapshot.durationMs),
    audioLevel: clampAudioLevel(audioLevel),
    errorMessage: null,
    transcript: null,
  };
}

export function finishVoiceRecording(snapshot: VoiceInputSnapshot): VoiceInputSnapshot {
  if (snapshot.state !== 'recording') {
    return {
      state: snapshot.state,
      mode: snapshot.mode,
      durationMs: snapshot.durationMs,
      audioLevel: snapshot.audioLevel,
      errorMessage: snapshot.errorMessage,
      transcript: snapshot.transcript,
    };
  }
  return {
    state: 'transcribing',
    mode: snapshot.mode,
    durationMs: snapshot.durationMs,
    audioLevel: 0,
    errorMessage: null,
    transcript: null,
  };
}

export function completeVoiceTranscription(
  snapshot: VoiceInputSnapshot,
  transcript: string,
): VoiceInputSnapshot {
  if (snapshot.state !== 'transcribing' && snapshot.state !== 'recording') {
    return {
      state: snapshot.state,
      mode: snapshot.mode,
      durationMs: snapshot.durationMs,
      audioLevel: snapshot.audioLevel,
      errorMessage: snapshot.errorMessage,
      transcript: snapshot.transcript,
    };
  }
  return {
    state: 'idle',
    mode: snapshot.mode,
    durationMs: snapshot.durationMs,
    audioLevel: 0,
    errorMessage: null,
    transcript,
  };
}

export function failVoiceInput(
  snapshot: VoiceInputSnapshot,
  errorMessage: string,
): VoiceInputSnapshot {
  const trimmed = typeof errorMessage === 'string' ? errorMessage.trim() : '';
  return {
    state: 'error',
    mode: snapshot.mode,
    durationMs: snapshot.durationMs,
    audioLevel: 0,
    errorMessage: trimmed.length > 0 ? trimmed : 'Voice input failed.',
    transcript: null,
  };
}

export function cancelVoiceInput(snapshot: VoiceInputSnapshot): VoiceInputSnapshot {
  return {
    state: 'idle',
    mode: snapshot.mode,
    durationMs: 0,
    audioLevel: 0,
    errorMessage: null,
    transcript: null,
  };
}

function normalizeSpeechLanguage(locale: string): string {
  const trimmed = typeof locale === 'string' ? locale.trim() : '';
  if (trimmed.length < 2) {
    return 'auto';
  }
  if (trimmed.length > 16) {
    return trimmed.slice(0, 16);
  }
  return trimmed;
}

function encodeUtf8(text: string): Uint8Array {
  const bytes: number[] = [];
  for (let i = 0; i < text.length; i += 1) {
    let code = text.charCodeAt(i);
    if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
      const next = text.charCodeAt(i + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        code = 0x10000 + ((code - 0xd800) << 10) + (next - 0xdc00);
        i += 1;
      }
    }
    if (code <= 0x7f) {
      bytes.push(code);
    } else if (code <= 0x7ff) {
      bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    } else if (code <= 0xffff) {
      bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    } else {
      bytes.push(
        0xf0 | (code >> 18),
        0x80 | ((code >> 12) & 0x3f),
        0x80 | ((code >> 6) & 0x3f),
        0x80 | (code & 0x3f),
      );
    }
  }
  return new Uint8Array(bytes);
}

export function buildVoiceSpeechRequest(
  baseUrl: string,
  audioBytesLength: number,
  options?: VoiceSpeechRequestOptions,
): VoiceSpeechRequest {
  const normalizedBase = baseUrl.replace(/\/+$/, '');
  const provider = options?.provider ? options.provider.trim() : '';
  const model = options?.model ? options.model.trim() : '';
  let path = provider.length > 0
    ? `/api/voice/cloud/${encodeURIComponent(provider)}/transcribe`
    : '/api/voice/transcribe';
  if (model.length > 0) {
    path = `${path}?model=${encodeURIComponent(model)}`;
  }
  const headers: Record<string, string> = {
    'Content-Type': 'application/octet-stream',
  };
  const token = options?.authToken ? options.authToken.trim() : '';
  if (token.length > 0) {
    headers['Authorization'] = `Bearer ${token}`;
  }
  return {
    url: `${normalizedBase}${path}`,
    method: 'POST',
    headers,
    audioBytesLength: Math.max(0, Math.round(audioBytesLength)),
    mimeType: 'audio/pcm',
  };
}

export function buildSpeechTranscriptionPayload(
  pcmBytes: Uint8Array,
  locale: string,
  model?: string,
): Uint8Array {
  if (!(pcmBytes instanceof Uint8Array) || pcmBytes.byteLength === 0) {
    throw new Error('PCM audio buffer is empty.');
  }
  const options: SpeechTranscriptionOptionsWire = {
    speechLanguage: normalizeSpeechLanguage(locale),
    speechTranslateToEnglish: false,
    speechCustomWords: [],
    speechRemoveFillerWords: true,
    speechSilenceFiltering: true,
  };
  if (model !== undefined && model.trim().length > 0) {
    // Model selection is carried on the request URL query when targeting cloud endpoints;
    // keep options strictly aligned with SpeechTranscriptionOptions.
  }
  const metadata = encodeUtf8(JSON.stringify(options));
  if (metadata.byteLength > SPEECH_MAX_OPTIONS_BYTES) {
    throw new Error('Speech options are too large.');
  }
  const body = new Uint8Array(4 + metadata.byteLength + pcmBytes.byteLength);
  const view = new DataView(body.buffer);
  view.setUint32(0, metadata.byteLength, true);
  body.set(metadata, 4);
  body.set(pcmBytes, 4 + metadata.byteLength);
  return body;
}

export function parseSpeechTranscriptionResponse(status: number, body: string): string {
  let parsed: Object | null = null;
  if (typeof body === 'string' && body.trim().length > 0) {
    try {
      parsed = JSON.parse(body) as Object | null;
    } catch (_) {
      parsed = null;
    }
  }
  const record =
    parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed)
      ? (parsed as RawSpeechTranscriptionResponse)
      : null;

  if (status < 200 || status >= 300) {
    const message =
      record && typeof record.message === 'string' && record.message.trim().length > 0
        ? record.message.trim()
        : record && typeof record.error === 'string' && record.error.trim().length > 0
          ? record.error.trim()
          : `Speech transcription failed with status ${status}.`;
    throw new Error(message);
  }

  if (!record || typeof record.text !== 'string') {
    throw new Error('Invalid speech transcription response.');
  }
  return record.text;
}
