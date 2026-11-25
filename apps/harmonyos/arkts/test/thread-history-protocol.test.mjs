import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import {
  EnvironmentOrchestrationThreadHistoryQuery,
  OrchestrationV2ThreadHistoryPage,
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
const protocol = import(new URL("ThreadHistoryProtocol.ets", client).href);
void protocol.catch(() => {});
NodeTest.after(() => loader.deregister());

const decodeQuery = Schema.decodeUnknownSync(EnvironmentOrchestrationThreadHistoryQuery);
const decodePage = Schema.decodeUnknownSync(Schema.toCodecJson(OrchestrationV2ThreadHistoryPage));
const start = "2026-11-24T10:01:00.000Z";
const finish = "2026-11-24T10:02:00.000Z";

function row(visibility, sourceThreadId, position, fields) {
  const id = `item-${position}`;
  return {
    position,
    visibility,
    sourceThreadId,
    sourceItemId: id,
    item: {
      id,
      threadId: sourceThreadId,
      runId: "run-1",
      nodeId: null,
      providerThreadId: null,
      providerTurnId: null,
      nativeItemRef: null,
      parentItemId: null,
      ordinal: position,
      status: "completed",
      title: null,
      startedAt: start,
      completedAt: finish,
      updatedAt: finish,
      ...fields,
    },
  };
}

function page(items, nextCursor = null, hasMoreHistory = nextCursor !== null) {
  const wire = { snapshotSequence: 7, items, nextCursor, hasMoreHistory };
  decodePage(wire);
  return wire;
}

NodeTest.test("encodes the thread and opaque cursor for the history route", async () => {
  const { threadHistoryPath } = await protocol;
  const path = new URL(
    threadHistoryPath("thread:part/one", "older+anchor=1&other?#"),
    "https://environment.example.test",
  );
  NodeAssert.equal(path.pathname, "/api/orchestration/threads/thread%3Apart%2Fone/history");
  NodeAssert.deepEqual(decodeQuery(Object.fromEntries(path.searchParams)), {
    cursor: "older+anchor=1&other?#",
  });
  for (const threadId of ["", ".", "..", " thread "]) {
    NodeAssert.throws(() => threadHistoryPath(threadId, "older"));
  }
  NodeAssert.throws(() => threadHistoryPath("thread-1", ""));
  NodeAssert.equal(
    threadHistoryPath("thread-1", "opaque-cursor", "message?a=b"),
    "/api/orchestration/threads/thread-1/history?cursor=opaque-cursor&throughEntryId=message%3Fa%3Db",
  );
  NodeAssert.throws(() => threadHistoryPath("thread-1", "opaque-cursor", "bad\nmessage"));
});

NodeTest.test(
  "reads local and inherited messages with exact IDs, body and chronology",
  async () => {
    const { readThreadHistory } = await protocol;
    const inherited = row("inherited", "parent-thread", 0, {
      type: "user_message",
      messageId: "parent-message",
      creationSource: "mobile",
      createdBy: "user",
      inputIntent: "turn_start",
      text: " preserve these spaces ",
      attachments: [
        {
          type: "file",
          id: "attachment-report-txt",
          name: "report.txt",
          mimeType: "text/plain",
          sizeBytes: 4,
        },
      ],
    });
    const work = row("inherited", "parent-thread", 1, {
      type: "command_execution",
      title: "Read file",
      input: "cat fixture.txt",
      outputOmitted: true,
    });
    const fork = row("synthetic", "parent-thread", 2, {
      type: "fork",
      threadId: "thread-1",
      targetThreadId: "thread-1",
      source: { type: "run", threadId: "parent-thread", runId: "run-parent" },
    });
    const local = row("local", "thread-1", 3, {
      type: "assistant_message",
      messageId: "local-message",
      text: "result",
      streaming: false,
      startedAt: null,
    });
    const items = [inherited, work, fork, local];
    NodeAssert.deepEqual(readThreadHistory(page(items, "older"), "thread-1", "recent"), {
      messages: [
        {
          id: "parent-message",
          threadId: "parent-thread",
          runId: "run-1",
          role: "user",
          text: " preserve these spaces ",
          streaming: false,
          createdAt: start,
          attachments: inherited.item.attachments,
          attachmentNames: ["report.txt"],
        },
        {
          id: "local-message",
          threadId: "thread-1",
          runId: "run-1",
          forkSource: { sourceThreadId: "thread-1", runId: "run-1" },
          role: "assistant",
          text: "result",
          streaming: false,
          createdAt: finish,
        },
      ],
      visibleTurnItems: items,
      nextCursor: "older",
    });
    const inheritedReply = row("inherited", "parent-thread", 4, {
      type: "assistant_message",
      messageId: "inherited-message",
      text: "old reply",
      streaming: false,
      runId: "parent-run",
    });
    const pending = row("local", "thread-1", 5, {
      type: "assistant_message",
      messageId: "unfinished-message",
      text: "unfinished reply",
      streaming: true,
      status: "running",
    });
    const historical = readThreadHistory(
      page([inheritedReply, pending], "older"),
      "thread-1",
      "recent",
    );
    NodeAssert.deepEqual(historical.messages[0].forkSource, {
      sourceThreadId: "parent-thread",
      runId: "parent-run",
    });
    NodeAssert.equal(historical.messages[1].forkSource, undefined);
  },
);

NodeTest.test("rejects local or inherited rows whose source identities do not match", async () => {
  const { readThreadHistory } = await protocol;
  const item = {
    type: "assistant_message",
    messageId: "message-1",
    text: "unexpected body",
    streaming: false,
  };
  for (const outOfScope of [
    row("local", "other-thread", 0, item),
    row("inherited", "parent-thread", 0, { ...item, threadId: "other-thread" }),
    { ...row("local", "thread-1", 0, item), sourceItemId: "other-item" },
    row("synthetic", "parent-thread", 0, { ...item, threadId: "thread-1" }),
  ]) {
    NodeAssert.throws(() => readThreadHistory(page([outOfScope]), "thread-1", "recent"));
  }
});

NodeTest.test("stops at the empty end and rejects non-advancing continuation cursors", async () => {
  const { readThreadHistory } = await protocol;
  const terminal = readThreadHistory(page([]), "thread-1", "recent");
  NodeAssert.deepEqual(terminal.messages, []);
  NodeAssert.deepEqual(terminal.visibleTurnItems, []);
  NodeAssert.equal(terminal.nextCursor, undefined);
  NodeAssert.equal(readThreadHistory(page([], "older"), "thread-1", "recent").nextCursor, "older");
  for (const cursor of ["recent", null]) {
    NodeAssert.throws(() => readThreadHistory(page([], cursor, true), "thread-1", "recent"));
  }
});
