import { describe, expect, it } from "vite-plus/test";

import { resolveLocaleSelection, SYSTEM_LANGUAGE } from "./locales.ts";

describe("system locale selection", () => {
  const supported = ["en", "pt-BR", "zh"];

  it.each([
    ["pt_BR", "pt-BR"],
    ["pt-Latn-BR", "pt-Latn-BR"],
  ])("matches Brazilian Portuguese for %s", (systemLocale, formattingLocale) => {
    expect(resolveLocaleSelection(SYSTEM_LANGUAGE, [systemLocale], supported, "en")).toEqual({
      catalogLocale: "pt-BR",
      formattingLocale,
    });
  });

  it("keeps Traditional Chinese separate from the Simplified Chinese catalog", () => {
    expect(resolveLocaleSelection(SYSTEM_LANGUAGE, ["zh_Hant_TW"], supported, "en")).toEqual({
      catalogLocale: "en",
      formattingLocale: "en",
    });
  });
});
