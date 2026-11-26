import { FILE_TEXT_PREVIEW_MAX_BYTES } from "@t3tools/shared/filePreview";
import { expect, it, vi } from "vite-plus/test";

import { readRemoteAttachmentText } from "./attachmentTextTransport.harmony";

const files = vi.hoisted(() => ({
  download: vi.fn(),
  open: vi.fn(),
}));

vi.mock("./attachmentDownload", () => ({ downloadAttachmentForPreview: files.download }));
vi.mock("expo-file-system", () => ({
  File: class {
    constructor(private readonly uri: string) {}
    open() {
      return files.open(this.uri);
    }
  },
  FileMode: { ReadOnly: "r" },
}));

const url = "https://environment.example/api/assets/signed-token";
const headers = {
  Range: `bytes=0-${FILE_TEXT_PREVIEW_MAX_BYTES}`,
  "Cache-Control": "no-cache",
};

it("reads a bounded prefix from a staged response that exceeded the requested range", async () => {
  const dispose = vi.fn();
  files.download.mockResolvedValueOnce({ uri: "file:///cache/preview", dispose });
  let totalRead = 0;
  files.open.mockReturnValueOnce({
    readBytes: async (length: number) => {
      totalRead += length;
      return new Uint8Array(length).fill(65);
    },
    close: vi.fn(),
  });
  const signal = new AbortController().signal;
  const preview = await readRemoteAttachmentText(url, headers, signal);
  expect(preview).toEqual({ text: "A".repeat(FILE_TEXT_PREVIEW_MAX_BYTES), truncated: true });
  expect(totalRead).toBe(FILE_TEXT_PREVIEW_MAX_BYTES + 1);
  expect(files.download).toHaveBeenLastCalledWith(
    expect.objectContaining({ url, headers, signal }),
  );
  expect(dispose).toHaveBeenCalledOnce();
});

it("closes and removes the staged file when the preview is aborted during a read", async () => {
  const close = vi.fn();
  const dispose = vi.fn();
  const controller = new AbortController();
  const failure = new Error("View closed");
  files.download.mockResolvedValueOnce({ uri: "file:///cache/preview", dispose });
  files.open.mockReturnValueOnce({
    close,
    readBytes: async () => {
      controller.abort(failure);
      return new Uint8Array([65]);
    },
  });
  await expect(readRemoteAttachmentText(url, headers, controller.signal)).rejects.toBe(failure);
  expect(close).toHaveBeenCalledOnce();
  expect(dispose).toHaveBeenCalledOnce();
});
