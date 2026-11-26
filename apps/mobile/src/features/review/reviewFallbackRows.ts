import type { NativeReviewDiffRow } from "../diffs/nativeReviewDiffSurface";
import type { ReviewHighlightedToken } from "./reviewHighlightedToken.types";
import { applyDiffRangesToTokens } from "./reviewWordDiffs";

export function buildReviewFallbackLineTokens(
  row: NativeReviewDiffRow,
  tokens: ReadonlyArray<ReviewHighlightedToken> | null,
) {
  const lineTokens = tokens?.length
    ? tokens
    : [{ content: row.content || " ", color: null, fontStyle: null }];
  return applyDiffRangesToTokens(lineTokens, row.wordDiffRanges ?? []);
}

export function buildReviewFallbackRows(
  rows: ReadonlyArray<NativeReviewDiffRow>,
  collapsedFileIds: ReadonlyArray<string>,
  initialPosition?: { readonly fileId?: string | undefined; readonly rowId?: string | undefined },
) {
  const collapsedFiles = new Set(collapsedFileIds);
  const visibleRows: NativeReviewDiffRow[] = [];
  const fileIndexes = new Map<string, number>();
  let initialRowIndex: number | undefined;
  for (const row of rows) {
    if (row.fileId !== undefined) {
      if (row.kind === "file") {
        fileIndexes.set(row.fileId, visibleRows.length);
      } else if (collapsedFiles.has(row.fileId)) {
        continue;
      }
    }
    if (row.id === initialPosition?.rowId) {
      initialRowIndex = Math.max(fileIndexes.get(row.fileId ?? "") ?? 0, visibleRows.length - 3);
    }
    visibleRows.push(row);
  }
  const initialFileIndex = initialPosition?.fileId
    ? fileIndexes.get(initialPosition.fileId)
    : undefined;
  return {
    rows: visibleRows,
    fileIndexes,
    initialScrollIndex: initialRowIndex ?? initialFileIndex,
  };
}
