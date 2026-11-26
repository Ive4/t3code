import { ARCHIVE_MAX_BYTES } from "@t3tools/client-runtime/zip/bounded-zip";
import { expect, it, vi } from "vite-plus/test";

const io = vi.hoisted(() => ({
  arrayBuffer: vi.fn<() => Promise<ArrayBuffer>>(),
  download: vi.fn(),
  size: 0,
}));

vi.mock("expo-file-system", () => ({
  File: class {
    get size() {
      return io.size;
    }

    arrayBuffer() {
      return io.arrayBuffer();
    }
  },
}));

vi.mock("../../lib/attachmentDownload", () => ({
  downloadAttachmentForPreview: io.download,
}));

import { downloadZipArchive } from "./zipArchiveDownload.harmony";

function setup(size = 4) {
  const bytes = new Uint8Array([0x50, 0x4b, 0x03, 0x04]).buffer;
  const dispose = vi.fn();
  io.size = size;
  io.arrayBuffer.mockReset().mockResolvedValue(bytes);
  io.download.mockReset().mockResolvedValue({ uri: "file:///cache/test.zip", dispose });
  const controller = new AbortController();
  const onProgress = vi.fn();
  const load = () =>
    downloadZipArchive({
      url: "https://example.test/signed.zip",
      name: "test.zip",
      signal: controller.signal,
      onProgress,
    });
  return { bytes, controller, dispose, load, onProgress };
}

it("opens a signed ZIP through the native download and releases its temporary copy", async () => {
  const { bytes, dispose, load, onProgress } = setup();

  await expect(load()).resolves.toBe(bytes);
  expect(onProgress).toHaveBeenCalledWith(bytes.byteLength);
  expect(dispose).toHaveBeenCalledOnce();
});

it("rejects an oversized download before loading it into JavaScript memory", async () => {
  const { dispose, load } = setup(ARCHIVE_MAX_BYTES + 1);

  await expect(load()).rejects.toMatchObject({ code: "file-too-large" });
  expect(io.arrayBuffer).not.toHaveBeenCalled();
  expect(dispose).toHaveBeenCalledOnce();
});

it("discards a download cancelled during the file read", async () => {
  const { bytes, controller, dispose, load, onProgress } = setup();
  io.arrayBuffer.mockImplementationOnce(async () => {
    controller.abort();
    return bytes;
  });

  await expect(load()).rejects.toBeInstanceOf(DOMException);
  expect(onProgress).not.toHaveBeenCalled();
  expect(dispose).toHaveBeenCalledOnce();
});
