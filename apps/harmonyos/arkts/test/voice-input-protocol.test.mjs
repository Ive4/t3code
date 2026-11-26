import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import { decodeSpeechPcmRequest } from "@t3tools/shared/speech";

const client = new URL("../entry/src/main/ets/client/", import.meta.url);
const loader = NodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith("./") && context.parentURL?.startsWith(client.href)) {
      return nextResolve(`${specifier}.ets`, context);
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (!url.startsWith(client.href) || !url.endsWith(".ets")) return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(new URL(url), "utf8")),
    };
  },
});
const {
  buildSpeechTranscriptionPayload,
  buildVoiceSpeechRequest,
  cancelVoiceInput,
  completeVoiceTranscription,
  createInitialVoiceInputSnapshot,
  failVoiceInput,
  finishVoiceRecording,
  parseSpeechTranscriptionResponse,
  requestVoicePermission,
  startVoiceRecording,
  updateVoiceLevel,
} = await import(new URL("VoiceInputProtocol.ets", client).href);
loader.deregister();

NodeTest.test("transitions through permission, recording, transcribing, and completion", () => {
  const initial = createInitialVoiceInputSnapshot("local");
  NodeAssert.deepEqual(initial, {
    state: "idle",
    mode: "local",
    durationMs: 0,
    audioLevel: 0,
    errorMessage: null,
    transcript: null,
  });

  const requesting = requestVoicePermission(initial, "environment");
  NodeAssert.equal(requesting.state, "requesting-permission");
  NodeAssert.equal(requesting.mode, "environment");

  const recording = startVoiceRecording(requesting);
  NodeAssert.equal(recording.state, "recording");
  NodeAssert.equal(recording.mode, "environment");
  NodeAssert.equal(recording.durationMs, 0);
  NodeAssert.equal(recording.audioLevel, 0);

  const updated = updateVoiceLevel(recording, 0.72, 1450);
  NodeAssert.equal(updated.audioLevel, 0.72);
  NodeAssert.equal(updated.durationMs, 1450);
  NodeAssert.equal(recording.durationMs, 0);

  const transcribing = finishVoiceRecording(updated);
  NodeAssert.equal(transcribing.state, "transcribing");
  NodeAssert.equal(transcribing.audioLevel, 0);
  NodeAssert.equal(transcribing.durationMs, 1450);

  const completed = completeVoiceTranscription(transcribing, "hello world");
  NodeAssert.deepEqual(completed, {
    state: "idle",
    mode: "environment",
    durationMs: 1450,
    audioLevel: 0,
    errorMessage: null,
    transcript: "hello world",
  });
});

NodeTest.test("clamps audioLevel to [0, 1] and durationMs to non-negative integers", () => {
  const recording = startVoiceRecording(createInitialVoiceInputSnapshot());

  const high = updateVoiceLevel(recording, 2.5, 1234.6);
  NodeAssert.equal(high.audioLevel, 1);
  NodeAssert.equal(high.durationMs, 1235);

  const low = updateVoiceLevel(high, -0.4, -200);
  NodeAssert.equal(low.audioLevel, 0);
  NodeAssert.equal(low.durationMs, 0);

  const nonFinite = updateVoiceLevel(high, Number.NaN, Number.POSITIVE_INFINITY);
  NodeAssert.equal(nonFinite.audioLevel, 0);
  NodeAssert.equal(nonFinite.durationMs, 1235);

  const idle = createInitialVoiceInputSnapshot();
  NodeAssert.deepEqual(updateVoiceLevel(idle, 0.8, 500), idle);
  NodeAssert.deepEqual(finishVoiceRecording(idle), idle);
  NodeAssert.deepEqual(completeVoiceTranscription(idle, "ignored"), idle);
});

NodeTest.test("handles cancellation and error recovery", () => {
  const recording = updateVoiceLevel(
    startVoiceRecording(createInitialVoiceInputSnapshot("environment")),
    0.5,
    900,
  );

  const cancelled = cancelVoiceInput(recording);
  NodeAssert.deepEqual(cancelled, {
    state: "idle",
    mode: "environment",
    durationMs: 0,
    audioLevel: 0,
    errorMessage: null,
    transcript: null,
  });

  const failed = failVoiceInput(recording, "  Microphone permission denied  ");
  NodeAssert.deepEqual(failed, {
    state: "error",
    mode: "environment",
    durationMs: 900,
    audioLevel: 0,
    errorMessage: "Microphone permission denied",
    transcript: null,
  });

  const fallbackFailed = failVoiceInput(recording, "   ");
  NodeAssert.equal(fallbackFailed.errorMessage, "Voice input failed.");

  const recovered = startVoiceRecording(failed, "local");
  NodeAssert.deepEqual(recovered, {
    state: "recording",
    mode: "local",
    durationMs: 0,
    audioLevel: 0,
    errorMessage: null,
    transcript: null,
  });
});

NodeTest.test("builds T3 speech PCM payload and request compatible with server decoder", () => {
  const pcm = new Uint8Array([1, 2, 3, 4, 5, 6]);
  const payload = buildSpeechTranscriptionPayload(pcm, "zh-CN", "whisper-1");
  const decoded = decodeSpeechPcmRequest(payload);
  NodeAssert.deepEqual(decoded.pcm, pcm);
  NodeAssert.deepEqual(decoded.options, {
    speechLanguage: "zh-CN",
    speechTranslateToEnglish: false,
    speechCustomWords: [],
    speechRemoveFillerWords: true,
    speechSilenceFiltering: true,
  });

  const autoDecoded = decodeSpeechPcmRequest(buildSpeechTranscriptionPayload(pcm, ""));
  NodeAssert.equal(autoDecoded.options.speechLanguage, "auto");

  NodeAssert.throws(() => buildSpeechTranscriptionPayload(new Uint8Array(0), "en-US"));

  const request = buildVoiceSpeechRequest("https://example.test///", pcm.byteLength, {
    authToken: "secret-token",
    provider: "openai",
    model: "openai/whisper-1",
  });
  NodeAssert.deepEqual(request, {
    url: "https://example.test/api/voice/cloud/openai/transcribe?model=openai%2Fwhisper-1",
    method: "POST",
    headers: {
      "Content-Type": "application/octet-stream",
      Authorization: "Bearer secret-token",
    },
    audioBytesLength: 6,
    mimeType: "audio/pcm",
  });
});

NodeTest.test("parses speech transcription responses and surfaces server errors", () => {
  NodeAssert.equal(
    parseSpeechTranscriptionResponse(200, JSON.stringify({ text: "Ship it" })),
    "Ship it",
  );
  NodeAssert.equal(parseSpeechTranscriptionResponse(200, JSON.stringify({ text: "" })), "");
  NodeAssert.throws(
    () => parseSpeechTranscriptionResponse(200, "not-json"),
    /Invalid speech transcription response/,
  );
  NodeAssert.throws(
    () => parseSpeechTranscriptionResponse(200, JSON.stringify({ ok: true })),
    /Invalid speech transcription response/,
  );
  NodeAssert.throws(
    () => parseSpeechTranscriptionResponse(422, JSON.stringify({ message: "Missing API key." })),
    /Missing API key\./,
  );
  NodeAssert.throws(
    () => parseSpeechTranscriptionResponse(500, JSON.stringify({ error: "internal_error" })),
    /internal_error/,
  );
  NodeAssert.throws(
    () => parseSpeechTranscriptionResponse(503, ""),
    /Speech transcription failed with status 503\./,
  );
});
