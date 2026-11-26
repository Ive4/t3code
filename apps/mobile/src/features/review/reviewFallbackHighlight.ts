import { highlightCode, type HighlightScheme } from "../../lib/highlights";

export function highlightReviewFallbackLine(
  content: string,
  language: string,
  scheme: HighlightScheme,
) {
  return highlightCode(content, language, scheme)[0] ?? null;
}
