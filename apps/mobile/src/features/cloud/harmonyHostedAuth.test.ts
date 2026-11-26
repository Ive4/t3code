import { describe, expect, it, vi } from "vite-plus/test";

import { openAuthSessionAsync } from "./harmonyHostedAuth";
import { Linking } from "react-native";

vi.mock("react-native", () => ({
  Linking: { addEventListener: vi.fn(), openURL: vi.fn() },
}));

const callback = "clerk://com.t3tools.t3code.dev.hosted-callback";
const portal = "https://accounts.example.test/sign-in";

describe("Harmony Clerk browser session", () => {
  it("waits for the matching callback and releases the listener", async () => {
    const remove = vi.fn();
    vi.mocked(Linking.addEventListener).mockReturnValue({ remove });
    vi.mocked(Linking.openURL).mockResolvedValue(undefined);
    const result = openAuthSessionAsync(portal, callback);
    const listener = vi.mocked(Linking.addEventListener).mock.lastCall![1];
    listener({ url: callback + "-extra?state=unrelated" });
    expect(remove).not.toHaveBeenCalled();
    const url = callback + "?state=fixture";
    listener({ url });
    await expect(result).resolves.toEqual({ type: "success", url });
    expect(remove).toHaveBeenCalledOnce();
  });

  it("cancels a pending attempt and leaves an aborted attempt in the app", async () => {
    const remove = vi.fn();
    vi.mocked(Linking.addEventListener).mockReturnValue({ remove });
    vi.mocked(Linking.openURL).mockResolvedValue(undefined);
    const controller = new AbortController();
    const options = { signal: controller.signal };
    const result = openAuthSessionAsync(portal, callback, options);
    controller.abort();
    await expect(result).resolves.toEqual({ type: "cancel" });
    expect(remove).toHaveBeenCalledOnce();
    vi.mocked(Linking.openURL).mockClear();
    await expect(openAuthSessionAsync(portal, callback, options)).resolves.toEqual({
      type: "cancel",
    });
    expect(Linking.openURL).not.toHaveBeenCalled();
  });
});
