import * as NodeVM from "node:vm";
import { expect, it, vi } from "vite-plus/test";

import { installDateTimeLocaleLoader } from "./installDateTimeLocaleLoader.js";

it.each([
  ["constructed formatters", () => new Intl.DateTimeFormat("en-CA")],
  ["called formatters", () => Intl.DateTimeFormat("zh-Hant-TW")],
  ["locale queries", () => Intl.DateTimeFormat.supportedLocalesOf(["fr-CA", "en-CA"])],
  ["date and time", () => new Date(0).toLocaleString("ja-JP")],
  ["date only", () => new Date(0).toLocaleDateString("pt-BR")],
  ["time only", () => new Date(0).toLocaleTimeString("es-MX")],
])("loads additional locale data on demand for %s", (_name, formatWithLocale) => {
  const realm = NodeVM.runInNewContext("({ Intl, Date })");
  Object.defineProperty(realm.Intl.DateTimeFormat, "__addLocaleData", { value: vi.fn() });
  vi.stubGlobal("Intl", realm.Intl);
  vi.stubGlobal("Date", realm.Date);
  try {
    const load = vi.fn();
    const date = new Date(0);
    const utc = { timeZone: "UTC" };
    const defaultDate = new Intl.DateTimeFormat(undefined, utc).format(date);
    installDateTimeLocaleLoader(load);
    expect(new Intl.DateTimeFormat(undefined, utc).format(date)).toBe(defaultDate);
    expect(date.toLocaleDateString("en", utc)).toBe("1/1/1970");
    expect(load).not.toHaveBeenCalled();

    formatWithLocale();
    formatWithLocale();
    expect(load).toHaveBeenCalledTimes(1);
  } finally {
    vi.unstubAllGlobals();
  }
});

it("leaves a native DateTimeFormat in place", () => {
  const formatter = Intl.DateTimeFormat;
  const load = vi.fn();
  installDateTimeLocaleLoader(load);
  expect(Intl.DateTimeFormat).toBe(formatter);
  expect(load).not.toHaveBeenCalled();
});
