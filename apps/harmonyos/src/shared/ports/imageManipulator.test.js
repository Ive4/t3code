import { expect, it, vi } from "vite-plus/test";

import { ImageManipulator, SaveFormat } from "./expo-image-manipulator.harmony.js";

const { getSize, render, base64, remove } = vi.hoisted(() => ({
  getSize: vi.fn(),
  render: vi.fn(),
  base64: vi.fn(),
  remove: vi.fn(),
}));

vi.mock("react-native", () => ({
  TurboModuleRegistry: { getEnforcing: () => ({ getSize, render }) },
}));

vi.mock("./expo-file-system.harmony.js", () => ({
  File: class {
    constructor(uri) {
      this.uri = uri;
    }

    get exists() {
      return true;
    }

    base64() {
      return base64(this.uri);
    }

    delete() {
      remove(this.uri);
    }
  },
}));

it("reads photo dimensions before decoding and uses the original URI for each resize", async () => {
  const uri = "file://media/Photo/1/IMG/large.png";
  getSize.mockResolvedValueOnce({ width: 6000, height: 3000 });
  render
    .mockResolvedValueOnce("file:///cache/first.png")
    .mockResolvedValueOnce("file:///cache/resized.png");
  base64.mockResolvedValue("aW1hZ2U=");
  const save = { format: SaveFormat.PNG, compress: 0.85, base64: true };

  const original = await ImageManipulator.manipulate(uri).renderAsync();
  expect(original).toMatchObject({ width: 6000, height: 3000 });
  expect(render).not.toHaveBeenCalled();

  const resized = await ImageManipulator.manipulate(original)
    .resize({ width: 2000, height: 1000 })
    .renderAsync();
  expect(await resized.saveAsync(save)).toEqual({
    width: 2000,
    height: 1000,
    uri: "file:///cache/first.png",
    base64: "aW1hZ2U=",
  });

  const smaller = await ImageManipulator.manipulate(resized)
    .resize({ width: 1643, height: 821 })
    .renderAsync();
  await smaller.saveAsync(save);
  expect(render).toHaveBeenNthCalledWith(1, uri, 2000, 1000, "png", 0.85);
  expect(render).toHaveBeenNthCalledWith(2, uri, 1643, 821, "png", 0.85);
});

it("removes an encoded JPEG if its bytes cannot be read", async () => {
  const uri = "file://media/Photo/2/IMG/portrait.heic";
  getSize.mockResolvedValueOnce({ width: 1080, height: 1920 });
  render.mockResolvedValueOnce("file:///cache/rendered.jpg");
  base64.mockRejectedValueOnce(new Error("Could not read output"));

  const photo = await ImageManipulator.manipulate(uri).renderAsync();
  await expect(
    photo.saveAsync({ format: SaveFormat.JPEG, compress: 0.85, base64: true }),
  ).rejects.toThrow("Could not read output");
  expect(render).toHaveBeenLastCalledWith(uri, 1080, 1920, "jpeg", 0.85);
  expect(remove).toHaveBeenCalledWith("file:///cache/rendered.jpg");
});
