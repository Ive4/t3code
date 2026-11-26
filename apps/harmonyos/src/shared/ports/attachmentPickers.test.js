import { expect, it, vi } from "vite-plus/test";

import { getDocumentAsync } from "./expo-document-picker.harmony.js";
import { launchImageLibraryAsync } from "./expo-image-picker.harmony.js";

vi.mock("react-native", () => ({
  TurboModuleRegistry: {
    getEnforcing: () => ({
      pickDocuments: async (limit) =>
        [
          {
            uri: "file://docs/storage/Report%20draft.pdf",
            name: "Report draft.pdf",
            mimeType: "application/pdf",
            size: 42,
          },
          { uri: "file://docs/storage/report.txt", name: "report.txt" },
        ].slice(0, limit),
      pickMedia: async (limit, allowVideo) => {
        if (limit === 1 && !allowVideo) return [];
        return [
          {
            uri: "file://media/Photo/1/IMG/photo.jpg",
            name: "photo.jpg",
            mimeType: "image/jpeg",
            type: "image",
            size: 200,
            width: 640,
            height: 480,
          },
          {
            uri: "file://media/Photo/2/VID/clip.mp4",
            name: "clip.mp4",
            mimeType: "video/mp4",
            type: "video",
          },
        ]
          .filter((item) => allowVideo || item.type === "image")
          .slice(0, limit);
      },
    }),
  },
}));

it("returns a single document with its original granted URI and display name", async () => {
  expect(await getDocumentAsync()).toEqual({
    canceled: false,
    assets: [
      {
        uri: "file://docs/storage/Report%20draft.pdf",
        name: "Report draft.pdf",
        mimeType: "application/pdf",
        size: 42,
      },
    ],
  });
});

it("returns all selected documents even when MIME type and size are unavailable", async () => {
  expect(await getDocumentAsync({ multiple: true })).toMatchObject({
    canceled: false,
    assets: [{ name: "Report draft.pdf" }, { name: "report.txt" }],
  });
});

it("maps an empty selection to Expo cancellation", async () => {
  expect(await launchImageLibraryAsync()).toEqual({ canceled: true, assets: null });
});

it("passes the gallery selection limit and uses Expo's image metadata fields", async () => {
  expect(
    await launchImageLibraryAsync({
      mediaTypes: ["images", "videos"],
      allowsMultipleSelection: true,
      selectionLimit: 1,
    }),
  ).toEqual({
    canceled: false,
    assets: [
      {
        uri: "file://media/Photo/1/IMG/photo.jpg",
        fileName: "photo.jpg",
        mimeType: "image/jpeg",
        type: "image",
        fileSize: 200,
        width: 640,
        height: 480,
      },
    ],
  });
});

it("carries video metadata only when video selection is requested", async () => {
  const options = { allowsMultipleSelection: true, selectionLimit: 2 };
  const photos = await launchImageLibraryAsync({ ...options, mediaTypes: ["images"] });
  expect(photos.assets).toHaveLength(1);

  const media = await launchImageLibraryAsync({ ...options, mediaTypes: ["images", "videos"] });
  expect(media.assets?.[1]).toMatchObject({
    type: "video",
    mimeType: "video/mp4",
    fileName: "clip.mp4",
  });
});
