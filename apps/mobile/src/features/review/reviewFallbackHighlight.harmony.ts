import type { HighlightScheme } from "../../lib/highlights";
import { highlightHarmonyCode } from "../../native/harmonyCodeBlock";

export function highlightReviewFallbackLine(
  content: string,
  language: string,
  scheme: HighlightScheme,
) {
  return (
    highlightHarmonyCode(content, language, scheme)?.map(({ content, color }) => ({
      content,
      color: color ?? null,
      fontStyle: null,
    })) ?? null
  );
}
