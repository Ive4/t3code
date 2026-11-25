import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import {
  ORCHESTRATION_V2_WS_METHODS,
  OrchestrationV2SearchThreadsInput,
  OrchestrationV2SearchThreadsResult,
} from "@t3tools/contracts";
import * as Schema from "effect/Schema";

const client = new URL("../entry/src/main/ets/client/", import.meta.url);
const loader = NodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith("./") && context.parentURL?.startsWith(client.href)) {
      return nextResolve(`${specifier}.ets`, context);
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (!url.startsWith(client.href) || !url.endsWith(".ets")) return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(new URL(url), "utf8")),
    };
  },
});
const protocol = import(new URL("ThreadSearchProtocol.ets", client).href);
void protocol.catch(() => {});
NodeTest.after(() => loader.deregister());

const decodeInput = Schema.decodeUnknownSync(Schema.toCodecJson(OrchestrationV2SearchThreadsInput));
const encodeResult = Schema.encodeSync(Schema.toCodecJson(OrchestrationV2SearchThreadsResult));
const matched = {
  threadId: "thread:same-id",
  projectId: "project-1",
  source: "assistant",
  snippet: "… preserve  exact text 🐜 and 设置 …",
  messageCreatedAt: "2026-11-25T01:02:03.000Z",
  messageId: "message:42",
  quality: 0.8,
  hits: 4,
};

NodeTest.test("bounds a pasted query and sends the real message search RPC", async () => {
  const { searchThreadsRequest } = await protocol;
  const request = searchThreadsRequest(` ${"needle".repeat(33)}  ignored fragment `);
  NodeAssert.deepEqual(request, {
    _tag: "Request",
    id: "1",
    tag: ORCHESTRATION_V2_WS_METHODS.searchThreads,
    payload: { query: "needle".repeat(33), limit: 50 },
    headers: [],
  });
  NodeAssert.deepEqual(decodeInput(request.payload), request.payload);
  NodeAssert.equal(searchThreadsRequest("  Set   Up  ").payload.query, "Set   Up");
});

NodeTest.test("uses Android's length gate for Latin, CJK and normalized tokens", async () => {
  const { canSearchThreadMessages, searchThreadsRequest } = await protocol;
  for (const query of ["'Abc'", "fix me", "设置", "かな", "한글", "e\u0301bc", "İa"]) {
    NodeAssert.equal(canSearchThreadMessages(query), true, query);
  }
  for (const query of ["", " ab cd ", "“ab”", "中", "👩🦊", "e\u0301b"]) {
    NodeAssert.equal(canSearchThreadMessages(query), false, query);
    NodeAssert.throws(() => searchThreadsRequest(query));
  }
});

NodeTest.test(
  "keeps ranked snippets and navigation identities scoped to the queried environment",
  async () => {
    const { readThreadSearchMatches } = await protocol;
    const legacy = {
      threadId: "older-thread",
      projectId: "project-2",
      source: "user",
      snippet: "older message",
      messageCreatedAt: null,
    };
    const result = encodeResult({ matches: [matched, legacy] });
    NodeAssert.deepEqual(readThreadSearchMatches(result, "env-a"), [
      { ...matched, environmentId: "env-a" },
      { ...legacy, environmentId: "env-a" },
    ]);
    NodeAssert.deepEqual(readThreadSearchMatches(result, "env-b")[0], {
      ...matched,
      environmentId: "env-b",
    });
    NodeAssert.deepEqual(readThreadSearchMatches({ matches: [] }, "env-a"), []);
  },
);

NodeTest.test("rejects malformed results and repeated or oversized match lists", async () => {
  const { readThreadSearchMatches } = await protocol;
  const invalidMatches = [
    null,
    { ...matched, threadId: " " },
    { ...matched, source: "title" },
    { ...matched, snippet: "a".repeat(241) },
    { ...matched, messageCreatedAt: 12 },
    { ...matched, messageId: "" },
    { ...matched, quality: Infinity },
    { ...matched, hits: 1.5 },
  ];
  for (const match of invalidMatches) {
    NodeAssert.throws(() => readThreadSearchMatches({ matches: [match] }, "env-a"));
  }
  NodeAssert.throws(() => readThreadSearchMatches({ matches: [matched, matched] }, "env-a"));
  NodeAssert.throws(() =>
    readThreadSearchMatches(
      {
        matches: Array.from({ length: 51 }, (_, index) => ({
          ...matched,
          threadId: String(index),
        })),
      },
      "env-a",
    ),
  );
});
