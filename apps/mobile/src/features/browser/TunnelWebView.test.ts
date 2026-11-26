import { expect, it, vi } from "vite-plus/test";

vi.mock("expo", () => ({
  requireNativeModule: () => {
    throw new Error("T3PreviewTunnel is unavailable");
  },
  requireOptionalNativeModule: () => null,
  requireNativeView: () => {
    throw new Error("T3PreviewTunnel view is unavailable");
  },
}));
vi.mock("react-native", () => ({}));
vi.mock("../../state/previewTunnel", () => ({}));

it("leaves the mobile browser usable without the native preview tunnel", async () => {
  await expect(import("./TunnelWebView")).resolves.toMatchObject({
    supportsNativePreviewTunnel: false,
  });
});
