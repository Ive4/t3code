import { expect, it, vi } from "vite-plus/test";

import { installReactNativeFetch } from "./installReactNativeFetch.js";

it.each(["", new URLSearchParams()])("omits an empty body from a POST", async (body) => {
  const transport = vi.fn(async () => new Response(null, { status: 200 }));
  vi.stubGlobal("fetch", transport);
  try {
    installReactNativeFetch();
    await fetch("https://example.test/token", { method: "POST", body });

    expect(transport).toHaveBeenCalledWith(
      "https://example.test/token",
      expect.objectContaining({ method: "POST", body: null }),
    );
  } finally {
    vi.unstubAllGlobals();
  }
});

it("serializes populated forms and preserves explicit headers", async () => {
  const transport = vi.fn(async () => new Response(null, { status: 200 }));
  vi.stubGlobal("fetch", transport);
  try {
    installReactNativeFetch();
    await fetch("https://example.test/token", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", "x-test": "fixture" },
      body: new URLSearchParams({ field: "a b" }),
    });

    const options = transport.mock.calls[0][1];
    expect(options.body).toBe("field=a+b");
    expect(options.headers.get("Content-Type")).toBe("application/x-www-form-urlencoded");
    expect(options.headers.get("X-Test")).toBe("fixture");
  } finally {
    vi.unstubAllGlobals();
  }
});
