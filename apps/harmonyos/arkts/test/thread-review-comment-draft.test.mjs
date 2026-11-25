import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import {
  COMPOSER_CONTEXT_REVIEW_DIFF_MAX_CHARS,
  COMPOSER_CONTEXT_REVIEW_TEXT_MAX_CHARS,
  OrchestrationMessageContext,
} from "@t3tools/contracts";
import * as Schema from "effect/Schema";

const clientPath = new URL("../entry/src/main/ets/client/", import.meta.url);
const loader = NodeModule.registerHooks({
  load(url, context, nextLoad) {
    if (!url.startsWith(clientPath.href) || !url.endsWith(".ets")) return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(new URL(url), "utf8")),
    };
  },
});
NodeTest.after(() => loader.deregister());
const protocol = () => import(new URL("ThreadReviewCommentDraftProtocol.ets", clientPath).href);
const decode = Schema.decodeUnknownSync(OrchestrationMessageContext);

NodeTest.test(
  "builds a full-file review comment the mobile draft and command recognize",
  async () => {
    const { createThreadFileReviewCommentRecord } = await protocol();
    const { composerCommandContextReference, referencedComposerCommandContext } = await import(
      new URL("ComposerCommandProtocol.ets", clientPath).href
    );
    const filePath = "src/review[old].ts";
    const diff = "@@ -1,1 +1,1 @@\n-before\n+after";
    const record = createThreadFileReviewCommentRecord(
      "context-f1",
      { filePath, diff },
      "  Check this.  ",
    );
    NodeAssert.deepEqual(record, {
      version: 1,
      contextId: "context-f1",
      kind: "review-comment",
      label: "review old .ts file",
      sectionId: "file:src/review[old].ts",
      sectionTitle: "File comment",
      filePath,
      startIndex: 0,
      endIndex: 0,
      rangeLabel: "file",
      text: "Check this.",
      diff,
      fenceLanguage: "diff",
    });
    const text = composerCommandContextReference(record);
    NodeAssert.equal(text, "[review old .ts file](t3-context://v1/review-comment/context-f1)");
    const records = referencedComposerCommandContext(text, [record]);
    NodeAssert.deepEqual(decode({ version: 1, records }).records, [record]);
  },
);

NodeTest.test(
  "retains a tracked repository's scope and respects the comment and diff limits",
  async () => {
    const { createThreadFileReviewCommentRecord, THREAD_REVIEW_COMMENT_MAX_CHARS } =
      await protocol();
    NodeAssert.equal(THREAD_REVIEW_COMMENT_MAX_CHARS, COMPOSER_CONTEXT_REVIEW_TEXT_MAX_CHARS);
    const longPrefix = "a".repeat(COMPOSER_CONTEXT_REVIEW_DIFF_MAX_CHARS - 1);
    const filePath = `src/${"x".repeat(255)}.ts`;
    const target = {
      filePath,
      sectionId: "turn:3:repo:tracked",
      sectionTitle: "Tracked root",
      diff: `${longPrefix}🚀suffix`,
    };
    const record = createThreadFileReviewCommentRecord("context-f2", target, "Explain this.");
    NodeAssert.equal(record.filePath, filePath);
    NodeAssert.equal(record.sectionId, target.sectionId);
    NodeAssert.equal(record.sectionTitle, target.sectionTitle);
    NodeAssert.equal(record.diff, longPrefix);
    NodeAssert.ok(record.label.length <= 200);
    NodeAssert.doesNotThrow(() => decode({ version: 1, records: [record] }));
    NodeAssert.equal(
      createThreadFileReviewCommentRecord(
        "context-f3",
        { filePath },
        "a".repeat(THREAD_REVIEW_COMMENT_MAX_CHARS + 1),
      ),
      undefined,
    );
    for (const [id, path, comment] of [
      ["#no-id", "main.ts", "comment"],
      ["okay", " main.ts", "comment"],
      ["okay", "main.ts", " \n "],
    ]) {
      NodeAssert.equal(
        createThreadFileReviewCommentRecord(id, { filePath: path }, comment),
        undefined,
      );
    }
  },
);

NodeTest.test("indexes selectable unified diff lines and keeps side-specific numbers", async () => {
  const { parseThreadReviewDiffRows } = await protocol();
  const patch = [
    "--- a/file.ts",
    "+++ b/file.ts",
    "@@ -10,3 +10,4 @@ example",
    " unchanged",
    "-removed",
    "+first",
    "+second",
    " tail",
    "\\ No newline at end of file",
    "@@ -30,0 +33 @@",
    "+later",
  ];
  const rows = parseThreadReviewDiffRows(patch);
  NodeAssert.deepEqual(
    rows.map((row) => [row.kind, row.index, row.oldNumber, row.newNumber]),
    [
      ["metadata", null, null, null],
      ["metadata", null, null, null],
      ["hunk", null, null, null],
      ["context", 0, 10, 10],
      ["delete", 1, 11, null],
      ["add", 2, null, 11],
      ["add", 3, null, 12],
      ["context", 4, 12, 13],
      ["metadata", null, null, null],
      ["hunk", null, null, null],
      ["add", 5, null, 33],
    ],
  );
  NodeAssert.deepEqual(
    rows.map((row) => row.text),
    patch,
  );
  NodeAssert.equal(rows[5].content, "first");
  NodeAssert.equal(rows[3].content, "unchanged");
});

NodeTest.test(
  "uses Android labels and selected diff excerpts for single lines and ranges",
  async () => {
    const {
      parseThreadReviewDiffRows,
      buildThreadReviewLineSelection,
      createThreadFileReviewCommentRecord,
    } = await protocol();
    const rows = parseThreadReviewDiffRows(["@@ -11,1 +11,2 @@", "-removed", "+first", "+second"]);
    const addition = buildThreadReviewLineSelection(rows, 1);
    NodeAssert.deepEqual(addition, {
      startIndex: 1,
      endIndex: 1,
      rangeLabel: "+11",
      diff: "@@ -0,0 +11,1 @@\n+first",
      rows: [rows[2]],
    });
    const deletion = buildThreadReviewLineSelection(rows, 0);
    NodeAssert.equal(deletion.rangeLabel, "-11");
    NodeAssert.equal(deletion.diff, "@@ -11,1 +0,0 @@\n-removed");
    const additions = buildThreadReviewLineSelection(rows, 2, 1);
    NodeAssert.equal(additions.rangeLabel, "+11 to +12");
    NodeAssert.equal(additions.diff, "@@ -0,0 +11,2 @@\n+first\n+second");
    const mixed = buildThreadReviewLineSelection(rows, 2, 0);
    NodeAssert.equal(mixed.rangeLabel, "11 to 12");
    NodeAssert.equal(mixed.diff, "@@ -11,1 +11,2 @@\n-removed\n+first\n+second");
    NodeAssert.equal(buildThreadReviewLineSelection(rows, 2, 3), undefined);
    NodeAssert.equal(buildThreadReviewLineSelection(rows, 0.5, 2), undefined);

    const record = createThreadFileReviewCommentRecord(
      "context-l1",
      {
        filePath: "src/file.ts",
        sectionId: "turn:3:repo:tracked",
        sectionTitle: "Tracked root",
        diff: "unselected file patch",
        selection: additions,
      },
      "Explain the added lines.",
    );
    NodeAssert.equal(record.startIndex, 1);
    NodeAssert.equal(record.endIndex, 2);
    NodeAssert.equal(record.label, "file.ts +11 to +12");
    NodeAssert.equal(record.diff, additions.diff);
    NodeAssert.deepEqual(decode({ version: 1, records: [record] }).records, [record]);
  },
);
