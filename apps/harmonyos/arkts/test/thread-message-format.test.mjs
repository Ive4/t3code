import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import { serializeAssistantCitation } from "@t3tools/shared/assistantCitations";

const formatUrl = new URL("../entry/src/main/ets/pages/ThreadMessageFormat.ets", import.meta.url);
const citationUrl = new URL(
  "../entry/src/main/ets/client/ThreadCitationProtocol.ets",
  import.meta.url,
);
const historicalCommentUrl = new URL(
  "../entry/src/main/ets/client/ThreadHistoricalReviewCommentProtocol.ets",
  import.meta.url,
);
const loader = NodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    if (context.parentURL === formatUrl.href && specifier === "../client/ThreadCitationProtocol") {
      return nextResolve(citationUrl.href, context);
    }
    if (
      context.parentURL === formatUrl.href &&
      specifier === "../client/ThreadHistoricalReviewCommentProtocol"
    ) {
      return nextResolve(historicalCommentUrl.href, context);
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url !== formatUrl.href && url !== citationUrl.href && url !== historicalCommentUrl.href)
      return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(new URL(url), "utf8")),
    };
  },
});
const { threadMessageBlocks } = await import(formatUrl.href);
loader.deregister();

NodeTest.test("renders a saved user review comment between surrounding message blocks", () => {
  const source =
    'Before\n\n<review_comment sectionId="s" sectionTitle="Working tree" filePath="src/app.ts" startIndex="0" endIndex="0" rangeLabel="+1">Clarify this.\n```diff\n+const answer = 42;\n```\n</review_comment>\n\nAfter';
  const blocks = threadMessageBlocks(source, true);
  NodeAssert.deepEqual(
    blocks.map((block) => block.kind),
    ["text", "review-comment", "text"],
  );
  NodeAssert.equal(blocks[0].text, "Before");
  NodeAssert.equal(blocks[1].reviewComment.filePath, "src/app.ts");
  NodeAssert.equal(blocks[1].reviewComment.text, "Clarify this.");
  NodeAssert.equal(blocks[2].text, "After");
  NodeAssert.ok(threadMessageBlocks(source).every((block) => block.kind !== "review-comment"));
});

NodeTest.test("renders only the stored review comment referenced by the message", () => {
  const record = {
    version: 1,
    kind: "review-comment",
    contextId: "file-note",
    sectionId: "turn:3",
    sectionTitle: "Round 3",
    filePath: "src/app.ts",
    startIndex: 0,
    endIndex: 0,
    rangeLabel: "file",
    text: "Check this file.",
    diff: "+added",
  };
  const text = "Before\n\n[File note](t3-context://v1/review-comment/file-note)\n\nAfter";
  const blocks = threadMessageBlocks(text, true, { version: 1, records: [record] });
  NodeAssert.deepEqual(
    blocks.map((block) => block.kind),
    ["text", "review-comment", "text"],
  );
  NodeAssert.equal(blocks[1].reviewComment.text, "Check this file.");
  NodeAssert.ok(
    threadMessageBlocks(text, true, {
      version: 1,
      records: [{ ...record, contextId: "unreferenced" }],
    }).every((block) => block.kind !== "review-comment"),
  );
});

NodeTest.test("positions fenced code between prose and preserves code indentation", () => {
  NodeAssert.deepEqual(
    threadMessageBlocks(
      "说明\r\n\r\n```ts title=demo\r\n  const port = 1;\r\n\r\n```\r\n\r\n完成。",
    ),
    [
      { kind: "text", text: "说明", language: "", index: 0 },
      { kind: "code", text: "  const port = 1;\n", language: "ts", index: 1 },
      { kind: "text", text: "完成。", language: "", index: 2 },
    ],
  );
});

NodeTest.test("retains the Markdown source and distinguishes shorter and mixed fences", () => {
  const blocks = threadMessageBlocks("Use `pnpm`.\n````markdown\n```js\n~~~\n````");
  NodeAssert.equal(blocks[0].text, "Use `pnpm`.");
  NodeAssert.deepEqual(blocks[1], {
    kind: "code",
    text: "```js\n~~~",
    language: "markdown",
    index: 1,
  });
});

NodeTest.test("renders aligned Markdown tables between prose and fences", () => {
  const table = [
    "| **Name** | C\\|D | Result |",
    "| :--- | :---: | ---: |",
    "| `A\\|B` | [details](https://example.com) |",
    "| x | y | z | ignored |",
  ].join("\n");
  const blocks = threadMessageBlocks(`Before\n\n${table}\n\n\`\`\`md\n${table}\n\`\`\`\nAfter`);
  NodeAssert.deepEqual(
    blocks.map((block) => [block.kind, block.text]),
    [
      ["text", "Before"],
      ["table", table],
      ["code", table],
      ["text", "After"],
    ],
  );
  NodeAssert.deepEqual(blocks[1].table, {
    alignments: ["left", "center", "right"],
    rows: [
      [
        [{ kind: "strong", text: "Name" }],
        [{ kind: "text", text: "C|D" }],
        [{ kind: "text", text: "Result" }],
      ],
      [
        [{ kind: "code", text: "A|B" }],
        [{ kind: "link", text: "details", href: "https://example.com" }],
        [],
      ],
      [[{ kind: "text", text: "x" }], [{ kind: "text", text: "y" }], [{ kind: "text", text: "z" }]],
    ],
  });
  NodeAssert.equal(threadMessageBlocks("a | b\n--- | nope")[0].kind, "text");
});

NodeTest.test(
  "renders titles, lists, quotes and inline formatting without changing the source",
  () => {
    const source = [
      "## 验收结果",
      "",
      "- **通过** Use `pnpm` and _check_.",
      "  2. 查看结果",
      "> 引用文字",
      "普通正文",
    ].join("\n");
    const [block] = threadMessageBlocks(source);
    NodeAssert.equal(block.text, source);
    NodeAssert.deepEqual(block.prose, [
      {
        kind: "heading",
        index: 0,
        level: 2,
        marker: "",
        separated: false,
        spans: [{ kind: "text", text: "验收结果" }],
      },
      {
        kind: "list",
        index: 1,
        level: 0,
        marker: "•",
        separated: true,
        spans: [
          { kind: "strong", text: "通过" },
          { kind: "text", text: " Use " },
          { kind: "code", text: "pnpm" },
          { kind: "text", text: " and " },
          { kind: "emphasis", text: "check" },
          { kind: "text", text: "." },
        ],
      },
      {
        kind: "list",
        index: 2,
        level: 1,
        marker: "2.",
        separated: false,
        spans: [{ kind: "text", text: "查看结果" }],
      },
      {
        kind: "quote",
        index: 3,
        level: 0,
        marker: "",
        separated: false,
        spans: [{ kind: "text", text: "引用文字" }],
      },
      {
        kind: "paragraph",
        index: 4,
        level: 0,
        marker: "",
        separated: false,
        spans: [{ kind: "text", text: "普通正文" }],
      },
    ]);
  },
);

NodeTest.test(
  "links only HTTP destinations and leaves files, unsupported schemes and images selectable",
  () => {
    const [block] = threadMessageBlocks(
      "[站点](https://example.com/path) <http://example.com> [执行](javascript:example) " +
        "[登录](https://user@example.com) [文件](src/main.ts) ![示例](https://example.com/image.png)",
    );
    NodeAssert.deepEqual(block.prose[0].spans, [
      { kind: "link", text: "站点", href: "https://example.com/path" },
      { kind: "text", text: " " },
      { kind: "link", text: "http://example.com", href: "http://example.com" },
      {
        kind: "text",
        text:
          " [执行](javascript:example) [登录](https://user@example.com) [文件](src/main.ts)" +
          " ![示例](https://example.com/image.png)",
      },
    ]);
  },
);

NodeTest.test("keeps plain identifiers and partially streamed formatting readable", () => {
  const first = "snake_case \\*literal\\* **waiting";
  NodeAssert.deepEqual(threadMessageBlocks(first)[0].prose[0].spans, [
    { kind: "text", text: "snake_case *literal* **waiting" },
  ]);
  NodeAssert.deepEqual(threadMessageBlocks(first + "**")[0].prose[0].spans, [
    { kind: "text", text: "snake_case *literal* " },
    { kind: "strong", text: "waiting" },
  ]);
});

NodeTest.test(
  "presents a persisted assistant citation with its selected text instead of an internal URL",
  () => {
    const marker =
      "[Assistant quote](t3-citation://v1/env/thread/message?text=selected+text&start=0&end=13&prefix=&suffix=)";
    const [block] = threadMessageBlocks(marker + " follow-up");
    NodeAssert.equal(block.text, marker + " follow-up");
    NodeAssert.deepEqual(block.prose[0].spans, [
      {
        kind: "citation",
        text: "“selected text”",
        citation: {
          version: 1,
          environmentId: "env",
          threadId: "thread",
          messageId: "message",
          text: "selected text",
          start: 0,
          end: 13,
          prefix: "",
          suffix: "",
        },
      },
      { kind: "text", text: " follow-up" },
    ]);
  },
);

NodeTest.test(
  "retains scoped Android quote data and distinguishes terminal context and malformed URLs",
  () => {
    const citation = {
      version: 1,
      environmentId: "other/host",
      threadId: "another thread",
      messageId: "message🧪",
      text: "命令 🧪",
      start: 7,
      end: 12,
      prefix: "First: ",
      suffix: " next",
      comment: "复查版本",
    };
    const marker = serializeAssistantCitation(citation);
    const broken = marker.replace("&start=7", "&text=ignored&start=7");
    NodeAssert.deepEqual(
      threadMessageBlocks(marker + " [terminal](t3-context://v1/terminal/one) " + broken)[0]
        .prose[0].spans,
      [
        { kind: "citation", text: "“复查版本”", citation },
        { kind: "text", text: " " },
        { kind: "citation", text: "terminal" },
        { kind: "text", text: " " + broken },
      ],
    );
  },
);

NodeTest.test("renders unfinished streaming fences and keeps their block IDs after closure", () => {
  const open = "Before\n\n~~~sh\n  echo hello";
  NodeAssert.deepEqual(threadMessageBlocks(open), [
    { kind: "text", text: "Before", language: "", index: 0 },
    { kind: "code", text: "  echo hello", language: "sh", index: 1 },
  ]);
  NodeAssert.deepEqual(threadMessageBlocks(open + "\n~~~"), threadMessageBlocks(open));
  NodeAssert.deepEqual(threadMessageBlocks("    ```\n  plain text\n"), [
    { kind: "text", text: "    ```\n  plain text", language: "", index: 0 },
  ]);
});
