import { describe, expect, it, vi } from "vitest";
import {
  getItemAsync,
  setItem,
  WHEN_UNLOCKED_THIS_DEVICE_ONLY,
} from "./expo-secure-store.harmony.js";

const storage = vi.hoisted(() => ({
  current: new Map(),
  getDeviceOnlyItem: vi.fn(async (key) => storage.current.get(key) ?? null),
  setDeviceOnlyItem: vi.fn((key, value) => storage.current.set(key, value)),
}));

vi.mock("react-native", () => ({
  TurboModuleRegistry: { getEnforcing: () => storage },
}));

describe("Harmony secure store", () => {
  it("restores a device-only voice grant and preserves its revoked value", async () => {
    const options = { keychainAccessible: WHEN_UNLOCKED_THIS_DEVICE_ONLY };
    const key = "t3code.voice.audio-grant.v1";
    setItem(key, '{"id":"approved"}', options);
    expect(await getItemAsync(key, options)).toBe('{"id":"approved"}');
    setItem(key, "null", options);
    expect(await getItemAsync(key, options)).toBe("null");
  });
});
