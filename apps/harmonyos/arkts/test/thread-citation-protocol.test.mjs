import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import {
  ASSISTANT_CITATION_CONTEXT_LENGTH,
  ASSISTANT_CITATION_MAX_ID_LENGTH,
  ASSISTANT_CITATION_MAX_TEXT_LENGTH,
} from "@t3tools/contracts";
import {
  expandAssistantCitationsForProvider,
  findAssistantCitationText,
  serializeAssistantCitation,
} from "@t3tools/shared/assistantCitations";

const sourceUrl = new URL(
  "../entry/src/main/ets/client/ThreadCitationProtocol.ets",
  import.meta.url,
);
const loader = NodeModule.registerHooks({
  load(url, context, nextLoad) {
    if (url !== sourceUrl.href) return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(sourceUrl, "utf8")),
    };
  },
});
const {
  canLocatePlainThreadCitation,
  createThreadCitationSelector,
  serializeThreadCitation,
  readThreadCitationPreview,
} = await import(sourceUrl.href);
loader.deregister();

NodeTest.test("maps an exact UTF-16 selection through Android's whitespace normalization", () => {
  const source = "前文\n\n接着 😀  正文，结尾";
  NodeAssert.equal(canLocatePlainThreadCitation(source), true);
  const start = source.indexOf("😀");
  const end = source.indexOf("，");
  const selector = createThreadCitationSelector(source, start, end);
  NodeAssert.deepEqual(selector, {
    text: "😀  正文",
    start: 6,
    end: 11,
    prefix: "前文 接着 ",
    suffix: "，结尾",
  });
  NodeAssert.deepEqual(findAssistantCitationText("前文 接着 😀 正文，结尾", selector), {
    start: 6,
    end: 11,
  });
  NodeAssert.equal(createThreadCitationSelector(source, start + 1, end), undefined);
  NodeAssert.equal(createThreadCitationSelector(source, start, source.length + 1), undefined);
  NodeAssert.equal(createThreadCitationSelector(source, undefined, end), undefined);
  NodeAssert.equal(createThreadCitationSelector(source, 2, 4), undefined);
});

NodeTest.test("locates the selected occurrence and rejects indistinguishable repeats", () => {
  const source = "first quote then quote last";
  const selector = createThreadCitationSelector(source, 17, 22);
  NodeAssert.deepEqual(findAssistantCitationText(source, selector), { start: 17, end: 22 });
  NodeAssert.equal(selector.prefix, "first quote then ");
  const block = "x".repeat(40) + "quote" + "y".repeat(40);
  NodeAssert.equal(createThreadCitationSelector(block + " " + block, 40, 45), undefined);
});

NodeTest.test("keeps raw Markdown and oversized selections out of the quote action", () => {
  for (const text of [
    "## Header",
    "plain **bold**",
    "table | row",
    "Some text\n---",
    "plain &amp; text",
    "Some text\n1. list",
    "hello\n  indented",
  ])
    NodeAssert.equal(canLocatePlainThreadCitation(text), false, text);
  const tooLong = "x".repeat(ASSISTANT_CITATION_MAX_TEXT_LENGTH + 1);
  NodeAssert.equal(createThreadCitationSelector(tooLong, 0, tooLong.length), undefined);
});

NodeTest.test("round trips the exact mobile wire and previews the persisted quote", () => {
  const selected = "quôte (🚀) with  spaces";
  const source = "before " + selected + " after";
  const selector = createThreadCitationSelector(source, 7, 7 + selected.length);
  const marker = serializeThreadCitation("env/1", "thread-1", "message-emoji🚀", selector);
  NodeAssert.equal(
    marker,
    serializeAssistantCitation({
      version: 1,
      environmentId: "env/1",
      threadId: "thread-1",
      messageId: "message-emoji🚀",
      ...selector,
    }),
  );
  NodeAssert.match(expandAssistantCitationsForProvider(marker), /quôte \(🚀\) with  spaces/);
  const href = marker.slice("[Assistant quote](".length, -1);
  NodeAssert.equal(readThreadCitationPreview(href), "quôte (🚀) with spaces");
  NodeAssert.equal(readThreadCitationPreview(href + "&text=replaced"), undefined);
  NodeAssert.equal(serializeThreadCitation("", "thread-1", "message-emoji🚀", selector), undefined);
});

NodeTest.test("keeps citation wire limits aligned with the shared context and ID bounds", () => {
  const context = "a".repeat(ASSISTANT_CITATION_CONTEXT_LENGTH + 3);
  const selector = createThreadCitationSelector(
    context + "目标" + context,
    context.length,
    context.length + 2,
  );
  NodeAssert.equal(selector.prefix.length, ASSISTANT_CITATION_CONTEXT_LENGTH);
  NodeAssert.equal(selector.suffix.length, ASSISTANT_CITATION_CONTEXT_LENGTH);
  const id = "e".repeat(ASSISTANT_CITATION_MAX_ID_LENGTH);
  NodeAssert.ok(serializeThreadCitation(id, "thread", "message", selector));
  NodeAssert.equal(serializeThreadCitation(id + "e", "thread", "message", selector), undefined);
});
