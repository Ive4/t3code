import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";

const url = new URL(
  "../entry/src/main/ets/client/ThreadHistoricalReviewCommentProtocol.ets",
  import.meta.url,
);
const loader = NodeModule.registerHooks({
  load(moduleUrl, context, nextLoad) {
    if (moduleUrl !== url.href) return nextLoad(moduleUrl, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(url, "utf8")),
    };
  },
});
NodeTest.after(() => loader.deregister());
const protocol = () => import(url.href);

const open =
  '<review_comment sectionId="working-tree" filePath="src/app.ts" startIndex="1" endIndex="3">';
const close = "</review_comment>";
const wrap = (value) => open + value + close;

NodeTest.test(
  "keeps Markdown and multiple old review blocks in their original UTF-16 ranges",
  async () => {
    const { parseHistoricalReviewCommentBlocks } = await protocol();
    const prefix = "🐜 **审查**\r\n";
    const first =
      [
        '<review_comment sectionId="turn:42" sectionTitle="Diff &gt; 5 &amp; updates"',
        ' filePath="src/&lt;example&gt;&quot;&amp;lt;.ts" startIndex="07" endIndex="2" rangeLabel="  +3 to +8 ">',
      ].join("") +
      [
        "",
        "Keep &lt;/review_comment&gt; literal.",
        "```diff",
        "@@ -1 +1 @@",
        "-before",
        "+after",
        "```",
        close,
      ].join("\n");
    const middle = "\n\nSome context.\n";
    const second = wrap("\r\nCheck this.\r\n```md\r\n# Plan\r\n- Step\r\n```\r\n");
    const tail = "\nFinished.  ";
    const source = prefix + first + middle + second + tail;
    const blocks = parseHistoricalReviewCommentBlocks(source);
    NodeAssert.deepEqual(
      blocks.map((block) => block.kind),
      ["text", "review-comment", "text", "review-comment", "text"],
    );
    NodeAssert.deepEqual(
      blocks.map((block) => block.text),
      [prefix, first, middle, second, tail],
    );
    let cursor = 0;
    for (const block of blocks) {
      NodeAssert.equal(block.start, cursor);
      NodeAssert.equal(source.slice(block.start, block.end), block.text);
      cursor = block.end;
    }
    NodeAssert.equal(cursor, source.length);
    NodeAssert.deepEqual(blocks[1].comment, {
      id: 'review-comment:0:turn:42:src/<example>"&lt;.ts:7:2',
      sectionId: "turn:42",
      sectionTitle: "Diff > 5 & updates",
      filePath: 'src/<example>"&lt;.ts',
      startIndex: 2,
      endIndex: 7,
      rangeLabel: "+3 to +8",
      text: "Keep &lt;/review_comment&gt; literal.",
      diff: "@@ -1 +1 @@\n-before\n+after",
      fenceLanguage: "diff",
    });
    NodeAssert.equal(blocks[3].comment.fenceLanguage, "md");
    NodeAssert.equal(blocks[3].comment.diff, "# Plan\r\n- Step");
  },
);

NodeTest.test(
  "masks valid structured chips at scan time and keeps the original source afterward",
  async () => {
    const { parseHistoricalReviewCommentBlocks } = await protocol();
    const opaque = "[" + wrap("Looks like a review") + "](t3-context://v1/mention/context_1)";
    const chip = "![</review_comment>](t3-context://v1/image/attachment_1)";
    const body = "Before " + chip + " after";
    const review = wrap(body);
    const source = opaque + review;
    const blocks = parseHistoricalReviewCommentBlocks(source);
    NodeAssert.equal(blocks.length, 2);
    NodeAssert.deepEqual(blocks[0], { kind: "text", start: 0, end: opaque.length, text: opaque });
    NodeAssert.equal(blocks[1].start, opaque.length);
    NodeAssert.equal(blocks[1].text, review);
    NodeAssert.equal(blocks[1].comment.text, body);
    NodeAssert.equal(blocks[1].comment.diff, "");
    NodeAssert.equal(blocks[1].comment.rangeLabel, "行");
  },
);

NodeTest.test("leaves invalid and unfinished review markup in its original text", async () => {
  const { parseHistoricalReviewCommentBlocks } = await protocol();
  const invalid = '<review_comment filePath="app.ts">Missing fields</review_comment>';
  const overflow =
    open.replace('startIndex="1"', 'startIndex="9007199254740992"') + "Bad index" + close;
  const unclosed = open + "\nValid prose\n```diff\n+unfinished\n" + close;
  const source = "plain " + invalid + " between " + wrap("Valid") + overflow + unclosed;
  const blocks = parseHistoricalReviewCommentBlocks(source);
  NodeAssert.deepEqual(
    blocks.filter((block) => block.comment).map((block) => block.comment.text),
    ["Valid"],
  );
  NodeAssert.equal(blocks.map((block) => block.text).join(""), source);
  NodeAssert.equal(blocks.at(-1).text, unclosed);
  NodeAssert.deepEqual(parseHistoricalReviewCommentBlocks("  普通 Markdown  "), [
    { kind: "text", start: 0, end: 15, text: "  普通 Markdown  " },
  ]);
  NodeAssert.deepEqual(parseHistoricalReviewCommentBlocks(""), []);
});

NodeTest.test(
  "keeps the final fence's long source literal and retains earlier prose fences",
  async () => {
    const { parseHistoricalReviewCommentBlocks } = await protocol();
    const example = ["Try this:", "```ts", "const value = 1;", "```", "Then retry."].join("\n");
    const diff = ["@@ -0,0 +1,3 @@", "+ " + "x".repeat(3000), "```", close, "+ final"].join("\n");
    const review = wrap("\n" + example + "\n````diff\n" + diff + "\n````\n");
    const [block] = parseHistoricalReviewCommentBlocks(review);
    NodeAssert.equal(block.end, review.length);
    NodeAssert.equal(block.comment.text, example);
    NodeAssert.equal(block.comment.diff, diff);
  },
);
