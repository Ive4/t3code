import { describe, expect, it, vi } from "@effect/vitest";
import type { SharePayload } from "expo-sharing";

import { createIncomingSharePayloadReader, startNativeShareInbox } from "./incoming-share-native";

describe("createIncomingSharePayloadReader", () => {
  it("treats a missing iOS App Group as an unavailable inbox", () => {
    const readPayloads = vi.fn((): ReadonlyArray<SharePayload> => {
      throw Object.assign(new Error("Expo-sharing has failed to fetch the app group id"), {
        code: "ERR_FAILED_TO_RESOLVE_APP_GROUP_ID",
      });
    });
    const read = createIncomingSharePayloadReader({ platform: "ios", readPayloads });

    expect(read()).toEqual([]);
    expect(read()).toEqual([]);
    expect(readPayloads).toHaveBeenCalledTimes(1);
  });

  // regression: #4943 stop shared content errors in Personal Team builds
  it("preserves other native errors", () => {
    const error = new Error("native failure");
    const read = createIncomingSharePayloadReader({
      platform: "ios",
      readPayloads: () => {
        throw error;
      },
    });

    expect(read).toThrow(error);
  });
});

describe("startNativeShareInbox", () => {
  it("checks pending shares after subscribing and refreshes on resume and native delivery", () => {
    const events = new EventTarget();
    const refresh = vi.fn();
    const stop = startNativeShareInbox({
      enabled: true,
      refresh,
      subscribeAppActive: (listener) => {
        events.addEventListener("resume", listener);
        return () => events.removeEventListener("resume", listener);
      },
      subscribeNativeShare: (listener) => {
        events.addEventListener("share", listener);
        return () => events.removeEventListener("share", listener);
      },
    });

    expect(refresh).toHaveBeenCalledTimes(1);
    events.dispatchEvent(new Event("share"));
    events.dispatchEvent(new Event("resume"));
    expect(refresh).toHaveBeenCalledTimes(3);
    stop();
    events.dispatchEvent(new Event("share"));
    events.dispatchEvent(new Event("resume"));
    expect(refresh).toHaveBeenCalledTimes(3);
  });

  it("loads persisted drafts without subscribing when native receipt is unavailable", () => {
    const refresh = vi.fn();
    const subscribe = vi.fn(() => () => {});
    const stop = startNativeShareInbox({
      enabled: false,
      refresh,
      subscribeAppActive: subscribe,
      subscribeNativeShare: subscribe,
    });

    expect(refresh).toHaveBeenCalledTimes(1);
    expect(subscribe).not.toHaveBeenCalled();
    stop();
  });
});
