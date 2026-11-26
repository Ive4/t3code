import { expect, it, vi } from "vite-plus/test";

import { fetchSpeech } from "./voiceCapture.harmony";

const { request, cancel, write, remove } = vi.hoisted(() => ({
  request: vi.fn(),
  cancel: vi.fn(),
  write: vi.fn(),
  remove: vi.fn(),
}));

vi.mock("react-native", () => ({
  TurboModuleRegistry: {
    get: () => ({ requestSpeech: request, cancelSpeech: cancel }),
  },
}));

vi.mock("expo-file-system", () => ({
  Paths: { cache: "file:///cache" },
  FileMode: { WriteOnly: "write" },
  File: class {
    uri = "file:///cache/t3-speech-send-upload";
    create() {}
    open() {
      return { writeBytes: write, close() {} };
    }
    delete = remove;
  },
}));

vi.mock("../lib/uuid", () => ({ uuidv4: () => "upload" }));

it("cancels an in-flight speech upload and removes its temporary body", async () => {
  const inFlight = Promise.withResolvers<void>();
  const upload = Promise.withResolvers<never>();
  write.mockResolvedValueOnce(undefined);
  cancel.mockResolvedValueOnce(undefined);
  request.mockImplementationOnce(() => {
    inFlight.resolve();
    return upload.promise;
  });
  const controller = new AbortController();
  const pending = fetchSpeech(new URL("https://voice.example/api/voice"), {
    method: "POST",
    body: new Uint8Array([0, 1, 2, 3]),
    signal: controller.signal,
  });
  await inFlight.promise;
  const reason = new Error("Transcription destination changed");
  controller.abort(reason);
  await expect(pending).rejects.toBe(reason);
  expect(cancel).toHaveBeenCalledWith("upload");
  expect(remove).toHaveBeenCalledOnce();
});

it("refuses a redirect instead of treating it as a transcription response", async () => {
  request.mockResolvedValueOnce({
    status: 307,
    body: "",
    headers: '{"location":"https://unpaired.example/api/voice"}',
  });

  await expect(fetchSpeech("https://voice.example/api/voice")).rejects.toThrow(/redirect/i);
});
