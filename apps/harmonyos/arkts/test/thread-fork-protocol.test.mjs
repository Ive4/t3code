import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import { ORCHESTRATION_V2_WS_METHODS, OrchestrationV2RpcSchemas } from "@t3tools/contracts";
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
NodeTest.after(() => loader.deregister());
const protocol = () => import(new URL("ThreadForkProtocol.ets", client).href);
const decode = (schema) => Schema.decodeUnknownSync(Schema.toCodecJson(schema));
const source = { sourceThreadId: "source-thread", runId: "reply-run" };
const attempt = { commandId: "command-1", targetThreadId: "target-thread" };
const time = "2026-11-25T05:00:00.000Z";
const completed = {
  threadId: source.sourceThreadId,
  id: "assistant-item",
  runId: source.runId,
  type: "assistant_message",
  status: "completed",
  messageId: "assistant-message",
  providerThreadId: "provider-a",
  updatedAt: time,
};
const inherited = {
  sourceThreadId: source.sourceThreadId,
  sourceItemId: completed.id,
  visibility: "inherited",
  item: completed,
};

NodeTest.test(
  "encodes the mobile user command for the exact run and retains retry identities",
  async () => {
    const { threadForkFromReplyRequest, readThreadForkReceipt } = await protocol();
    const request = threadForkFromReplyRequest(source, attempt, "Source fork");
    NodeAssert.equal(request.tag, ORCHESTRATION_V2_WS_METHODS.dispatchCommand);
    NodeAssert.deepEqual(decode(OrchestrationV2RpcSchemas.dispatchCommand.input)(request.payload), {
      type: "thread.fork",
      commandId: attempt.commandId,
      createdBy: "user",
      creationSource: "mobile",
      sourceThreadId: source.sourceThreadId,
      targetThreadId: attempt.targetThreadId,
      sourcePoint: { type: "run", runId: source.runId },
      title: "Source fork",
    });
    NodeAssert.deepEqual(threadForkFromReplyRequest(source, attempt, "Source fork"), request);
    NodeAssert.throws(() =>
      threadForkFromReplyRequest(source, { ...attempt, targetThreadId: source.sourceThreadId }),
    );
    NodeAssert.throws(() => threadForkFromReplyRequest({ ...source, runId: " " }, attempt));
    NodeAssert.throws(() =>
      threadForkFromReplyRequest(source, { ...attempt, targetThreadId: ".." }),
    );
    NodeAssert.equal(readThreadForkReceipt({ sequence: 7 }), true);
    NodeAssert.equal(readThreadForkReceipt({ sequence: -1 }), false);
    NodeAssert.equal(readThreadForkReceipt({ targetThreadId: attempt.targetThreadId }), false);
  },
);

NodeTest.test(
  "requires the host's matching target and exact source run after dispatch",
  async () => {
    const { readConfirmedThreadFork } = await protocol();
    const target = {
      id: attempt.targetThreadId,
      projectId: "host-project",
      title: "Host title",
      lineage: { relationshipToParent: "fork", parentThreadId: source.sourceThreadId },
      forkedFrom: { type: "run", threadId: source.sourceThreadId, runId: source.runId },
    };
    NodeAssert.equal(readConfirmedThreadFork(target, source, attempt), target);
    for (const wrong of [
      { ...target, id: "different-thread" },
      { ...target, forkedFrom: { ...target.forkedFrom, runId: "different-run" } },
      { ...target, lineage: { ...target.lineage, sideChat: true } },
      { ...target, deletedAt: time },
      { ...target, forkedFrom: null },
    ])
      NodeAssert.equal(readConfirmedThreadFork(wrong, source, attempt), undefined);
  },
);

NodeTest.test(
  "matches Android's assistant completion, inherited source, and provider capability gates",
  async () => {
    const { readProjectedThreadForkSource } = await protocol();
    const denied = {
      threads: { canForkThread: true, canForkFromTurn: true },
      identity: { nativeThreadIds: "weak" },
      context: { supportsFullThreadHandoff: false },
    };
    NodeAssert.deepEqual(readProjectedThreadForkSource(inherited), source);
    NodeAssert.equal(readProjectedThreadForkSource(inherited, denied), undefined);
    NodeAssert.deepEqual(
      readProjectedThreadForkSource(inherited, {
        ...denied,
        identity: { nativeThreadIds: "strong" },
      }),
      source,
    );
    NodeAssert.deepEqual(
      readProjectedThreadForkSource(inherited, {
        ...denied,
        context: { supportsFullThreadHandoff: true },
      }),
      source,
    );
    for (const item of [
      { ...completed, status: "running" },
      { ...completed, runId: null },
      { ...completed, streaming: true },
      { ...completed, type: "user_message" },
      { ...completed, messageId: undefined },
    ])
      NodeAssert.equal(readProjectedThreadForkSource({ ...inherited, item }), undefined);
    NodeAssert.equal(
      readProjectedThreadForkSource({ ...inherited, sourceThreadId: "current-thread" }),
      undefined,
    );
  },
);

NodeTest.test(
  "only exposes fork sources joined to their own provider session and completed turn item",
  async () => {
    const { ThreadDetailProjection } = await import(
      new URL("ThreadDetailProtocol.ets", client).href
    );
    const projection = new ThreadDetailProjection(source.sourceThreadId);
    const local = { ...inherited, visibility: "local" };
    const run = {
      id: source.runId,
      threadId: source.sourceThreadId,
      ordinal: 1,
      status: "completed",
    };
    const denied = {
      threads: { canForkThread: false, canForkFromTurn: false },
      identity: { nativeThreadIds: "none" },
      context: { supportsFullThreadHandoff: false },
    };
    const capable = { context: { supportsFullThreadHandoff: true } };
    projection.reset({
      thread: { id: source.sourceThreadId, title: "Source" },
      runs: [run],
      visibleTurnItems: [local],
      providerThreads: [
        { id: "provider-a", providerSessionId: "session-a", appThreadId: source.sourceThreadId },
        { id: "provider-b", providerSessionId: "session-b", appThreadId: source.sourceThreadId },
      ],
      providerSessions: [
        { id: "session-a", status: "running", capabilities: denied },
        { id: "session-b", status: "running", capabilities: capable },
      ],
    });
    NodeAssert.equal(projection.replyForkSources().size, 0);
    NodeAssert.equal(
      projection.apply("provider-session.updated", {
        id: "session-a",
        status: "running",
        capabilities: capable,
      }),
      true,
    );
    const eligible = projection.replyForkSources();
    NodeAssert.deepEqual(eligible.get(completed.messageId), source);
    NodeAssert.equal(projection.replyForkSources(), eligible);
    projection.apply("run.updated", { ...run, status: "running" });
    NodeAssert.equal(projection.replyForkSources().size, 0);
    projection.apply("run.updated", { ...run, status: "completed" });
    projection.apply("turn-item.updated", { ...completed, status: "failed" });
    NodeAssert.equal(projection.replyForkSources().size, 0);
  },
);
