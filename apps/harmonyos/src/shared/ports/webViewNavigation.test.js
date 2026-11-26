import { expect, it, vi } from "vite-plus/test";

import { allowWebNavigation } from "./webViewNavigation.js";

it("applies each host's navigation callback to the actual URL and frame", () => {
  const callback = vi.fn(({ isTopFrame, url }) => !isTopFrame || url === "about:blank");
  expect(allowWebNavigation("https://example.com", false, ["*"], callback)).toBe(true);
  expect(allowWebNavigation("https://example.com", true, ["*"], callback)).toBe(false);
  expect(allowWebNavigation("about:blank", true, [], callback)).toBe(true);
});

it("restricts the URI by scheme and host before invoking the caller", () => {
  const callback = vi.fn(() => true);
  expect(
    allowWebNavigation(
      "https://docs.example.com/path",
      true,
      ["https://docs.example.com"],
      callback,
    ),
  ).toBe(true);
  expect(
    allowWebNavigation(
      "https://docs.example.com.invalid/path",
      true,
      ["https://docs.example.com"],
      callback,
    ),
  ).toBe(false);
  expect(allowWebNavigation("javascript:alert(1)", true, ["https://*"], callback)).toBe(false);
  expect(callback).toHaveBeenCalledTimes(1);
});
