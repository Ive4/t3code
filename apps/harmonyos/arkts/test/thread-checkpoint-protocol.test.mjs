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
const protocol = () => import(new URL("ThreadCheckpointProtocol.ets", client).href);
const decode = (schema) => Schema.decodeUnknownSync(Schema.toCodecJson(schema));

const start = "2026-11-25T03:00:00.000Z";
const end = "2026-11-25T03:01:00.000Z";
const threadId = "thread-1";
const patch = [
  "diff --git a/README.md b/README.md",
  "--- a/README.md",
  "+++ b/README.md",
  "@@ -1 +1 @@",
  "-old",
  "+new",
].join("\n");

NodeTest.test(
  "encodes only the selected thread's adjacent turn diff, including the first turn",
  async () => {
    const { threadCheckpointDiffRequest } = await protocol();
    const first = threadCheckpointDiffRequest(threadId, 1);
    NodeAssert.equal(first.tag, ORCHESTRATION_V2_WS_METHODS.getTurnDiff);
    NodeAssert.deepEqual(decode(OrchestrationV2RpcSchemas.getTurnDiff.input)(first.payload), {
      threadId,
      fromTurnCount: 0,
      toTurnCount: 1,
      ignoreWhitespace: false,
    });
    NodeAssert.deepEqual(threadCheckpointDiffRequest(threadId, 19).payload, {
      threadId,
      fromTurnCount: 18,
      toTurnCount: 19,
      ignoreWhitespace: false,
    });
    for (const ordinal of [0, -1, 1.5, Infinity]) {
      NodeAssert.throws(() => threadCheckpointDiffRequest(threadId, ordinal));
    }
    NodeAssert.throws(() => threadCheckpointDiffRequest("wrong\0id", 1));
  },
);

NodeTest.test(
  "parses patches without merging repositories and rejects mismatched response identities",
  async () => {
    const { readThreadCheckpointDiff, threadCheckpointDiffRequest } = await protocol();
    const request = threadCheckpointDiffRequest(threadId, 2).payload;
    const value = {
      threadId,
      fromTurnCount: 1,
      toTurnCount: 2,
      diff: patch,
      repositories: [
        {
          name: "Shared",
          repositoryPath: "../shared",
          relativePath: "../shared",
          diff: patch + "\n\n[truncated]",
        },
        { name: "Empty", repositoryPath: "nothing", relativePath: "nothing", diff: "" },
      ],
    };
    NodeAssert.deepEqual(decode(OrchestrationV2RpcSchemas.getTurnDiff.output)(value), value);
    const result = readThreadCheckpointDiff(value, request);
    NodeAssert.deepEqual(
      result.groups.map((group) => [group.key, group.files[0].path, group.incomplete]),
      [
        [".", "README.md", false],
        ["repo:../shared", "README.md", true],
      ],
    );
    NodeAssert.equal(result.groups[1].relativePath, "../shared");
    NodeAssert.equal(result.groups[1].files[0].patch.truncated, true);
    NodeAssert.deepEqual(result.groups[0].files[0].patch.lines.slice(-2), ["-old", "+new"]);
    NodeAssert.throws(() =>
      readThreadCheckpointDiff({ ...value, threadId: "other-thread" }, request),
    );
    NodeAssert.throws(() => readThreadCheckpointDiff({ ...value, toTurnCount: 3 }, request));
    NodeAssert.throws(() =>
      readThreadCheckpointDiff(
        {
          ...value,
          repositories: [value.repositories[0], value.repositories[0]],
        },
        request,
      ),
    );
  },
);

NodeTest.test(
  "projects scoped checkpoints and latest assistant messages with server file totals",
  async () => {
    const { ThreadDetailProjection } = await import(
      new URL("ThreadDetailProtocol.ets", client).href
    );
    const view = new ThreadDetailProjection(threadId);
    const file = { path: " README.md ", kind: "modified", additions: 1, deletions: 1 };
    const root = {
      id: "cp-1",
      scopeId: "root",
      threadId,
      runId: "run-1",
      ordinalWithinScope: 1,
      appRunOrdinal: 1,
      status: "missing",
      capturedAt: end,
      files: [],
    };
    const repository = {
      ...root,
      id: "cp-repo-1",
      scopeId: "repo",
      status: "ready",
      appRunOrdinal: null,
      files: [file],
      filesTotal: { count: 29, additions: 37, deletions: 12 },
    };
    const message = {
      id: "assistant-1",
      threadId,
      runId: "run-1",
      role: "assistant",
      createdAt: start,
    };
    view.reset({
      thread: { id: threadId, title: "Project" },
      checkpointScopes: [
        { id: "root", threadId, cwd: "/project" },
        { id: "repo", threadId, cwd: "/shared", label: "Shared", repositoryPath: "../shared" },
      ],
      checkpoints: [
        root,
        repository,
        { ...root, id: "outside", threadId: "other", appRunOrdinal: 12 },
      ],
      messages: [message],
    });
    const first = view.view().checkpoints;
    NodeAssert.equal(first.length, 1);
    NodeAssert.equal(first[0].assistantMessageId, message.id);
    NodeAssert.equal(first[0].status, "missing");
    NodeAssert.deepEqual(first[0].repositories[0].files, [file]);
    NodeAssert.deepEqual(first[0].totals, repository.filesTotal);
    NodeAssert.equal(view.view().checkpoints, first);
    NodeAssert.equal(
      view.apply("message.updated", { ...message, id: "assistant-2", createdAt: end }),
      true,
    );
    NodeAssert.equal(view.view().checkpoints[0].assistantMessageId, "assistant-2");
    NodeAssert.equal(view.apply("message.updated", message), false);
    NodeAssert.equal(
      view.apply("checkpoint.captured", {
        ...root,
        id: "cp-2",
        runId: "run-2",
        appRunOrdinal: 2,
        status: "ready",
      }),
      true,
    );
    NodeAssert.deepEqual(
      view.view().checkpoints.map((checkpoint) => checkpoint.ordinal),
      [1, 2],
    );
  },
);
