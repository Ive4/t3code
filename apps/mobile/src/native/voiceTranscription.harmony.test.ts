import { expect, it, vi } from "vite-plus/test";

const native = vi.hoisted(() => ({
  checkLocalSpeechAvailability: vi.fn<() => Promise<boolean>>(),
  transcribeLocalSpeech: vi.fn<(id: string, uri: string) => Promise<string>>(),
  cancelLocalSpeech: vi.fn<(id: string) => Promise<void>>(),
}));

vi.mock("react-native", () => ({ TurboModuleRegistry: { get: () => native } }));
vi.mock("../lib/uuid", () => ({ uuidv4: () => "speech-id" }));

import { getLocalVoiceTranscriber } from "./voiceTranscription.harmony";

const uri = "file:///cache/t3-recording-aabb.pcm";

async function prepare() {
  vi.resetAllMocks();
  native.checkLocalSpeechAvailability.mockResolvedValueOnce(true);
  const controller = new AbortController();
  const transcriber = await getLocalVoiceTranscriber();
  const prepared = await transcriber?.prepare({ signal: controller.signal });
  if (!prepared?.start) throw new Error("Expected live Mandarin transcription.");
  return { ...prepared, start: prepared.start, controller };
}

it("hides device transcription when the Mandarin speech capability is unavailable", async () => {
  native.checkLocalSpeechAvailability.mockResolvedValueOnce(false);
  await expect(getLocalVoiceTranscriber()).resolves.toBeNull();
});

it("identifies the transcript as Mandarin and supplies the existing recording to the native engine", async () => {
  const { locale, start, controller } = await prepare();
  native.transcribeLocalSpeech.mockResolvedValueOnce("请检查这个项目。");

  expect(locale).toBe("zh-CN");
  await expect(start(uri, { signal: controller.signal })).resolves.toBe("请检查这个项目。");
  expect(native.transcribeLocalSpeech).toHaveBeenCalledWith("speech-id", uri);
  expect(native.cancelLocalSpeech).not.toHaveBeenCalled();
});

it("cancels the matching native session and waits for cleanup", async () => {
  const { start, controller } = await prepare();
  const recognition = Promise.withResolvers<string>();
  const cleanup = Promise.withResolvers<void>();
  const completed: string[] = [];
  native.transcribeLocalSpeech.mockReturnValueOnce(recognition.promise);
  native.cancelLocalSpeech.mockReturnValueOnce(
    cleanup.promise.then(() => {
      completed.push("native cleanup");
    }),
  );

  const pending = start(uri, { signal: controller.signal }).finally(() => {
    completed.push("recognition");
  });
  const cancelled = expect(pending).rejects.toMatchObject({ code: "cancelled" });
  controller.abort();
  expect(native.cancelLocalSpeech).toHaveBeenCalledExactlyOnceWith("speech-id");
  recognition.resolve("太晚了");
  await recognition.promise;
  cleanup.resolve();
  await cancelled;
  expect(completed).toEqual(["native cleanup", "recognition"]);

  await expect(start(uri, { signal: controller.signal })).rejects.toMatchObject({
    code: "cancelled",
  });
  expect(native.transcribeLocalSpeech).toHaveBeenCalledOnce();
});

it("surfaces a native failure through the shared transcription error contract", async () => {
  const { transcribe, controller } = await prepare();
  native.transcribeLocalSpeech.mockRejectedValueOnce(new Error("Recognizer stopped early."));

  await expect(transcribe(uri, { signal: controller.signal })).rejects.toMatchObject({
    code: "transcription-failed",
  });
});
