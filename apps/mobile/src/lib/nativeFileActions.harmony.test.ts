import { expect, it, vi } from "vite-plus/test";

import { openFile, saveLocalImage } from "./nativeFileActions.harmony";

const native = vi.hoisted(() => ({
  openFile: vi.fn<(uri: string, mimeType: string) => Promise<void>>(),
  saveImageToLibrary: vi.fn<(uri: string, mimeType: string, name: string) => Promise<boolean>>(),
}));

vi.mock("react-native", () => ({
  TurboModuleRegistry: {
    getEnforcing: (name: string) => {
      if (name !== "T3FileActions") throw new Error("Unexpected native module");
      return native;
    },
  },
}));

it("preserves a viewer failure so the preview session can offer sharing", async () => {
  const failure = new Error("The file cannot be previewed.");
  native.openFile.mockRejectedValueOnce(failure);
  await expect(openFile("file:///cache/report.pdf", "application/pdf")).rejects.toBe(failure);
});

it("reports a declined gallery save without reporting success", async () => {
  native.saveImageToLibrary.mockResolvedValueOnce(false);
  await expect(saveLocalImage("file:///cache/photo.png", "image/png", "photo.png")).resolves.toBe(
    false,
  );
});
