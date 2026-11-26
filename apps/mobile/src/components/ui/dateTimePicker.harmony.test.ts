import { describe, expect, it } from "vite-plus/test";

import { applyHarmonyDateTimeSelection } from "./dateTimePickerSelection";

describe("HarmonyOS date and time selection", () => {
  const value = new Date(2028, 11, 31, 23, 58, 19, 345);

  it("applies the calendar date without changing the local time at a year boundary", () => {
    expect(applyHarmonyDateTimeSelection(value, "date", 20290101)).toEqual(
      new Date(2029, 0, 1, 23, 58, 19, 345),
    );
    expect(applyHarmonyDateTimeSelection(value, "date", 20280229)).toEqual(
      new Date(2028, 1, 29, 23, 58, 19, 345),
    );
  });

  it("applies midnight to the date already in the draft", () => {
    expect(applyHarmonyDateTimeSelection(value, "time", 0)).toEqual(new Date(2028, 11, 31));
  });

  it("leaves the draft alone when the picker is cancelled", () => {
    expect(applyHarmonyDateTimeSelection(value, "time", null)).toBeNull();
  });
});
