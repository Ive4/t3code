import { expect, it, vi } from "vite-plus/test";
import { encodeComposerContextClipboardHtml } from "@t3tools/shared/composerContextClipboard";

import { deliverHarmonyComposerPaste, harmonyComposerPaste } from "./harmonyComposerPaste";

const fragment = JSON.stringify({ version: 1, source: { environmentId: "source" }, records: [] });
const imageUri = "file://media/Photo/1/IMG/photo.jpg";

it("preserves context from the HTML clipboard representation", () => {
  const html = encodeComposerContextClipboardHtml("reference", fragment);
  expect(harmonyComposerPaste({ text: "reference", html, uris: [imageUri] })).toEqual({
    kind: "context",
    text: "reference",
    html,
  });
});

it("retains granted image URIs and falls back to ordinary text", () => {
  expect(harmonyComposerPaste({ text: "photo", html: "", uris: [imageUri] })).toEqual({
    kind: "images",
    uris: [imageUri],
  });
  expect(harmonyComposerPaste({ text: "plain 🌏", html: "<b>plain</b>", uris: [] })).toEqual({
    kind: "text",
    text: "plain 🌏",
  });
  expect(harmonyComposerPaste({ text: "", html: "", uris: [] })).toBeNull();
});

it("routes copied thread links through the existing context import path", () => {
  const text = "[Thread](t3-thread://v2/source/thread)";
  expect(harmonyComposerPaste({ text, html: "", uris: [] })).toEqual({
    kind: "context",
    text,
    html: "",
  });
});

it("keeps a bitmap's cache file available while the attachment consumes it", async () => {
  const uri = "file:///data/storage/el2/base/cache/t3-pasted-image.png";
  const attachment = Promise.withResolvers<void>();
  const started = Promise.withResolvers<void>();
  const releaseImage = vi.fn(async () => {});
  const pending = deliverHarmonyComposerPaste(
    { text: "", html: "", uris: [imageUri], imageToken: "bitmap" },
    new AbortController().signal,
    {
      takeImages: async () => [uri],
      releaseImage,
      deliver: (paste) => {
        expect(paste).toEqual({ kind: "images", uris: [imageUri, uri] });
        started.resolve();
        return attachment.promise;
      },
    },
  );
  await started.promise;
  expect(releaseImage).not.toHaveBeenCalled();
  attachment.reject(new Error("attachment failed"));
  await expect(pending).rejects.toThrow("attachment failed");
  expect(releaseImage.mock.calls).toEqual([[uri]]);
});

it("cleans up a bitmap claimed by the composer before it was closed", async () => {
  const uri = "file:///data/storage/el2/base/cache/t3-pasted-image.png";
  const controller = new AbortController();
  const releaseImage = vi.fn(async () => {});
  const deliver = vi.fn();
  await deliverHarmonyComposerPaste(
    { text: "", html: "", uris: [], imageToken: "bitmap" },
    controller.signal,
    {
      takeImages: async () => {
        controller.abort();
        return [uri];
      },
      releaseImage,
      deliver,
    },
  );
  expect(deliver).not.toHaveBeenCalled();
  expect(releaseImage.mock.calls).toEqual([[uri]]);
});
