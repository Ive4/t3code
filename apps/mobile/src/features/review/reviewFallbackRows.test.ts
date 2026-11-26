import { expect, it } from "vite-plus/test";
import { buildNativeReviewDiffData } from "./nativeReviewDiffAdapter";
import { formatReviewCommentContext, parseReviewInlineComments } from "./reviewCommentSelection";
import { buildReviewParsedDiff } from "./reviewModel";
import { buildReviewFallbackLineTokens, buildReviewFallbackRows } from "./reviewFallbackRows";
import { highlightReviewFallbackLine } from "./reviewFallbackHighlight.harmony";
import type { NativeReviewDiffRow } from "../diffs/nativeReviewDiffSurface";

it("keeps file jump targets when preceding files collapse and preserves expanded comments", () => {
  const rows: NativeReviewDiffRow[] = [
    { kind: "file", id: "a:header", fileId: "a" },
    { kind: "hunk", id: "a:hunk", fileId: "a" },
    { kind: "line", id: "a:1", fileId: "a" },
    { kind: "comment", id: "a:comment", fileId: "a" },
    { kind: "file", id: "b:header", fileId: "b" },
    { kind: "line", id: "b:1", fileId: "b" },
    { kind: "comment", id: "b:comment", fileId: "b" },
    { kind: "line", id: "b:2", fileId: "b" },
    { kind: "line", id: "b:3", fileId: "b" },
    { kind: "line", id: "b:4", fileId: "b" },
    { kind: "file", id: "c:header", fileId: "c" },
  ];

  const visible = buildReviewFallbackRows(rows, ["a"]);

  expect(visible.rows.map((row) => row.id)).toEqual([
    "a:header",
    "b:header",
    "b:1",
    "b:comment",
    "b:2",
    "b:3",
    "b:4",
    "c:header",
  ]);
  expect([...visible.fileIndexes]).toEqual([
    ["a", 0],
    ["b", 1],
    ["c", 7],
  ]);
  expect(buildReviewFallbackRows(rows, []).fileIndexes.get("b")).toBe(4);
  expect(buildReviewFallbackRows(rows, ["a"], { fileId: "c" }).initialScrollIndex).toBe(7);
  expect(
    buildReviewFallbackRows(rows, ["a"], { fileId: "b", rowId: "b:4" }).initialScrollIndex,
  ).toBe(3);
  expect(
    buildReviewFallbackRows(rows, ["a"], { fileId: "b", rowId: "b:1" }).initialScrollIndex,
  ).toBe(1);
  expect(
    buildReviewFallbackRows(rows, ["a", "b"], { fileId: "b", rowId: "b:4" }).initialScrollIndex,
  ).toBe(1);
});

it("keeps parsed line IDs for the shared review comment and its draft reference", () => {
  const path = "src/example.ts";
  const patch = [
    `diff --git a/${path} b/${path}`,
    `--- a/${path}`,
    `+++ b/${path}`,
    "@@ -8,1 +8,1 @@",
    "-const before = true;",
    "+const after = true;",
  ].join("\n");
  const parsedDiff = buildReviewParsedDiff(patch, "review-fallback-fixture");
  const data = buildNativeReviewDiffData(parsedDiff);
  const { rows } = buildReviewFallbackRows(data.rows, []);
  const row = rows.find((item) => item.change === "add");
  expect(row).toMatchObject({ newLineNumber: 8, content: "const after = true;" });
  if (!row?.content) throw new Error("Missing changed line");
  const tokens = buildReviewFallbackLineTokens(
    row,
    highlightReviewFallbackLine(row.content, "typescript", "dark"),
  );
  expect(tokens.map((token) => token.content).join("")).toBe(row.content);
  expect(tokens).toContainEqual(expect.objectContaining({ content: "const", color: "#ff7b72" }));
  expect(tokens.filter((token) => token.diffHighlight).map((token) => token.content)).toEqual([
    "after",
  ]);
  expect(buildReviewFallbackLineTokens(row, null).filter((token) => token.diffHighlight)).toEqual([
    expect.objectContaining({ content: "after" }),
  ]);

  const target = data.commentTargetsByRowId.get(row.id);
  expect(target).toMatchObject({ filePath: path, lineIndex: 1 });
  if (!target) throw new Error("Missing review target");
  const message = formatReviewCommentContext(
    {
      sectionId: "working-tree",
      sectionTitle: "Working tree",
      filePath: target.filePath,
      lines: target.lines,
      startIndex: target.lineIndex,
      endIndex: target.lineIndex,
    },
    "Confirm this change.",
  );
  const comments = parseReviewInlineComments(message);
  const commentedDiff = buildNativeReviewDiffData({ parsedDiff, comments });

  expect(buildReviewFallbackRows(commentedDiff.rows, []).rows.at(-1)).toMatchObject({
    kind: "comment",
    filePath: path,
    commentText: "Confirm this change.",
  });
});
