import { describe, expect, it } from "vitest";

import { sharedCloudConfig } from "./shared-cloud-config.cjs";

describe("Harmony build account configuration", () => {
  it("exposes only the public settings read by the shared mobile client", () => {
    expect(
      sharedCloudConfig({
        EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY: "pk_test_example",
        EXPO_PUBLIC_CLERK_JWT_TEMPLATE: "t3-connect",
        T3CODE_RELAY_URL: "https://relay.example.test",
        T3CODE_HARMONY_PUSH_URL: "https://push.example.test",
        CLERK_SECRET_KEY: "server-only",
        EXPO_PUBLIC_OTLP_TRACES_TOKEN: "unrelated",
      }),
    ).toEqual({
      clerk: { publishableKey: "pk_test_example", jwtTemplate: "t3-connect" },
      relay: { url: "https://relay.example.test" },
      harmonyPush: { url: "https://push.example.test" },
    });
  });

  it("supports a direct-connect build without account settings", () => {
    expect(sharedCloudConfig({})).toEqual({
      clerk: { publishableKey: null, jwtTemplate: null },
      relay: { url: null },
      harmonyPush: { url: null },
    });
  });
});
