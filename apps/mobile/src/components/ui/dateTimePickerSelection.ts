export function applyHarmonyDateTimeSelection(
  value: Date,
  mode: "date" | "time",
  selection: number | null,
): Date | null {
  if (selection === null) return null;

  const next = new Date(value);
  if (mode === "date") {
    // ArkUI sends a local calendar day as YYYYMMDD, independent of either app's timezone.
    next.setFullYear(
      Math.floor(selection / 10000),
      (Math.floor(selection / 100) % 100) - 1,
      selection % 100,
    );
  } else {
    next.setHours(Math.floor(selection / 60), selection % 60, 0, 0);
  }
  return next;
}
