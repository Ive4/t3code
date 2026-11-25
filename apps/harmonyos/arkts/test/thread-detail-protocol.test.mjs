import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import {
  ORCHESTRATION_V2_WS_METHODS,
  OrchestrationV2PendingBackgroundTask,
  OrchestrationV2RpcSchemas,
} from "@t3tools/contracts";
import * as Schema from "effect/Schema";

const client = new URL("../entry/src/main/ets/client/", import.meta.url);
const decodeStream = Schema.decodeUnknownSync(
  Schema.toCodecJson(OrchestrationV2RpcSchemas.subscribeThread.output),
);
const decodeCommand = Schema.decodeUnknownSync(
  Schema.toCodecJson(OrchestrationV2RpcSchemas.dispatchCommand.input),
);
const decodeGetTurnItem = Schema.decodeUnknownSync(OrchestrationV2RpcSchemas.getTurnItem.input);
const start = "2026-11-24T10:00:00.000Z";
const end = "2026-11-24T10:01:00.000Z";
const modelSelection = { instanceId: "replay", model: "showcase" };
const thread = {
  createdBy: "user",
  creationSource: "mobile",
  id: "thread-1",
  projectId: "project-1",
  title: "Replay conversation",
  providerInstanceId: "replay",
  modelSelection,
  runtimeMode: "approval-required",
  interactionMode: "default",
  branch: null,
  worktreePath: null,
  activeProviderThreadId: null,
  lineage: { parentThreadId: null, relationshipToParent: null, rootThreadId: "thread-1" },
  forkedFrom: null,
  createdAt: start,
  updatedAt: start,
  archivedAt: null,
  deletedAt: null,
};

function snapshot(fields = {}) {
  const frame = {
    kind: "snapshot",
    snapshotSequence: 7,
    hasMoreHistory: true,
    historyCursor: "opaque-cursor",
    projection: {
      thread,
      runs: [],
      attempts: [],
      nodes: [],
      subagents: [],
      providerSessions: [],
      providerThreads: [],
      providerTurns: [],
      runtimeRequests: [],
      messages: [],
      plans: [],
      turnItems: [],
      checkpointScopes: [],
      checkpoints: [],
      contextHandoffs: [],
      contextTransfers: [],
      visibleTurnItems: [],
      updatedAt: start,
      ...fields,
    },
  };
  decodeStream(frame);
  return frame.projection;
}

function apply(projection, type, payload) {
  decodeStream({
    kind: "event",
    sequence: 8,
    event: { id: "event-8", type, threadId: "thread-1", occurredAt: end, payload },
  });
  return projection.apply(type, payload);
}

function run(id, ordinal, status, fields = {}) {
  return {
    id,
    threadId: "thread-1",
    ordinal,
    providerInstanceId: "replay",
    modelSelection,
    providerThreadId: null,
    userMessageId: `message-${id}`,
    rootNodeId: null,
    activeAttemptId: null,
    status,
    requestedAt: start,
    startedAt: status === "queued" ? null : start,
    completedAt: null,
    checkpointId: null,
    contextHandoffId: null,
    ...fields,
  };
}

function subagent(id, runId, status, fields = {}) {
  return {
    id,
    threadId: "thread-1",
    runId,
    parentNodeId: "node-parent",
    origin: "app_owned",
    createdBy: "agent",
    driver: "codex",
    providerInstanceId: "codex",
    providerThreadId: null,
    childThreadId: null,
    nativeTaskRef: null,
    prompt: "Worker instructions",
    title: id,
    model: null,
    status,
    result: null,
    startedAt: start,
    completedAt: null,
    updatedAt: start,
    ...fields,
  };
}

function message(id, text, fields = {}) {
  return {
    id,
    threadId: "thread-1",
    runId: null,
    nodeId: null,
    role: "user",
    createdBy: "user",
    creationSource: "mobile",
    text,
    attachments: [],
    streaming: false,
    createdAt: start,
    updatedAt: start,
    ...fields,
  };
}

function item(id, type, fields) {
  return {
    id,
    type,
    threadId: "thread-1",
    runId: "run-1",
    nodeId: "node-1",
    providerThreadId: null,
    providerTurnId: null,
    nativeItemRef: null,
    parentItemId: null,
    ordinal: 2,
    status: "completed",
    title: null,
    startedAt: start,
    completedAt: end,
    updatedAt: start,
    ...fields,
  };
}

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

NodeTest.test(
  "updates queued rows in delivery order and preserves guest attribution and attachments",
  async () => {
    const { ThreadDetailProjection } = await protocol;
    const projection = new ThreadDetailProjection("thread-1");
    const first = run("first", 3, "queued", { queuePosition: 1, queueHeld: true });
    const second = run("second", 2, "queued", { queuePosition: 2 });
    const hidden = run("hidden", 4, "queued");
    const guest = message("message-first", "Attributed guest words", {
      context: {
        version: 1,
        records: [],
        guest: { guestMessageId: "guest-1", name: "Lena", text: "Guest words" },
      },
    });
    const notes = message("message-second", "Review the notes", {
      attachments: [
        { type: "file", id: "notes", name: "notes.md", mimeType: "text/markdown", sizeBytes: 25 },
      ],
    });
    const notification = message("message-hidden", "Worker completed", {
      notification: { source: { kind: "command" }, outcome: "completed", summary: "Finished" },
    });
    projection.reset(
      snapshot({ runs: [second, first, hidden], messages: [notes, guest, notification] }),
    );
    const queuedMessages = projection.view().queuedMessages;
    NodeAssert.deepEqual(
      queuedMessages.map(({ runId, text, canEdit, canSendNow, attachments }) => [
        runId,
        text,
        canEdit,
        canSendNow,
        attachments,
      ]),
      [
        ["first", "Guest words", false, true, []],
        ["second", "Review the notes", true, true, ["notes.md"]],
      ],
    );
    apply(projection, "message.updated", { ...notes, text: "Review the appendix", updatedAt: end });
    NodeAssert.equal(projection.view().queuedMessages[1].text, "Review the appendix");
    apply(projection, "run.updated", { ...second, queuePosition: 1 });
    NodeAssert.deepEqual(
      projection.view().queuedMessages.map(({ runId }) => runId),
      ["second", "first"],
    );
    apply(projection, "run.updated", { ...first, status: "cancelled", queuePosition: null });
    NodeAssert.deepEqual(
      projection.view().queuedMessages.map(({ runId }) => runId),
      ["second"],
    );
    apply(projection, "thread.archived", { ...thread, archivedAt: end });
    NodeAssert.equal(projection.view().queuedMessages[0].canSendNow, false);
  },
);

NodeTest.test(
  "sends a queued row into a starting run and skips a compaction for a fresh run",
  async () => {
    const { ThreadDetailProjection } = await protocol;
    const projection = new ThreadDetailProjection("thread-1");
    const active = run("active", 1, "starting");
    const first = run("first", 2, "queued");
    const fresh = run("fresh", 3, "queued", { freshContext: true });
    const activeMessage = message("message-active", "Check the build");
    projection.reset(
      snapshot({
        runs: [active, first, fresh],
        messages: [
          activeMessage,
          message("message-first", "Use Make"),
          message("message-fresh", "Start over"),
        ],
      }),
    );
    NodeAssert.deepEqual(
      projection
        .view()
        .queuedMessages.map(({ canSendNow, targetRunId }) => [canSendNow, targetRunId]),
      [
        [true, "active"],
        [false, ""],
      ],
    );
    apply(projection, "run.updated", { ...active, status: "running" });
    NodeAssert.equal(projection.view().queuedMessages[0].canSendNow, false);
    apply(projection, "message.updated", { ...activeMessage, text: "/compact", updatedAt: end });
    NodeAssert.deepEqual(
      projection
        .view()
        .queuedMessages.map(({ canSendNow, targetRunId }) => [canSendNow, targetRunId]),
      [
        [true, "active"],
        [true, "active"],
      ],
    );
    apply(projection, "run.updated", { ...active, status: "completed", completedAt: end });
    NodeAssert.deepEqual(
      projection
        .view()
        .queuedMessages.map(({ canSendNow, targetRunId }) => [canSendNow, targetRunId]),
      [
        [true, ""],
        [true, ""],
      ],
    );
  },
);

NodeTest.test("blocks queue editing while the provider waits for an answer", async () => {
  const { ThreadDetailProjection } = await protocol;
  const projection = new ThreadDetailProjection("thread-1");
  const pending = {
    id: "input-1",
    nodeId: "node-1",
    providerTurnId: null,
    nativeRequestRef: null,
    kind: "user_input",
    status: "pending",
    responseCapability: { type: "message" },
    createdAt: start,
    resolvedAt: null,
  };
  projection.reset(snapshot());
  NodeAssert.equal(projection.view().queueEditBlocked, false);
  apply(projection, "runtime-request.updated", pending);
  NodeAssert.equal(projection.view().queueEditBlocked, true);
  NodeAssert.equal(projection.view().approval, undefined);
  apply(projection, "runtime-request.updated", { ...pending, status: "resolved", resolvedAt: end });
  NodeAssert.equal(projection.view().queueEditBlocked, false);
});

NodeTest.test(
  "keeps attachment-only prompts and context URLs out of the queue preview",
  async () => {
    const { queuedMessageEditorText, queuedMessagePreview, queuedMessageSubmissionText } =
      await protocol;
    const attachmentPrompt =
      "[User attached one or more files without additional text. Respond using the conversation context and the attached files.]";
    NodeAssert.equal(queuedMessagePreview(attachmentPrompt), "");
    NodeAssert.equal(queuedMessageEditorText(`Ultrathink:\n${attachmentPrompt}`), "Ultrathink:");
    NodeAssert.equal(queuedMessageSubmissionText("  ", true), attachmentPrompt);
    NodeAssert.equal(
      queuedMessageSubmissionText("Ultrathink:", true),
      `Ultrathink:\n${attachmentPrompt}`,
    );
    NodeAssert.equal(queuedMessageSubmissionText("Keep the notes", true), "Keep the notes");
    NodeAssert.equal(queuedMessageSubmissionText("", false), "");
    const withContext = "Read [Development Notes](t3-context://v1/file/ref-1)";
    NodeAssert.equal(queuedMessagePreview(withContext), "Read Development Notes");
    NodeAssert.equal(queuedMessageEditorText(withContext), withContext);
  },
);
const protocol = import(new URL("ThreadDetailProtocol.ets", client).href);
void protocol.catch(() => {});
const transport = import(new URL("T3Protocol.ets", client).href);
NodeTest.after(() => loader.deregister());

NodeTest.test(
  "keeps the interruptible run ahead of a newer queue and follows queue holds",
  async () => {
    const active = run("run-1", 1, "running");
    const queued = run("run-2", 2, "queued", { queuePosition: 1, queueHeld: true });
    const initial = snapshot({ runs: [queued, active] });
    const { ThreadDetailProjection } = await protocol;
    const projection = new ThreadDetailProjection("thread-1");
    projection.reset(initial);
    NodeAssert.equal(projection.view().title, "Replay conversation");
    NodeAssert.equal(projection.view().modelLabel, "showcase");
    NodeAssert.deepEqual(projection.view().modelSelection, modelSelection);
    NodeAssert.equal(projection.view().runtimeMode, "approval-required");
    apply(projection, "thread.runtime-mode-updated", { ...thread, runtimeMode: "auto" });
    NodeAssert.equal(projection.view().runtimeMode, "auto");
    NodeAssert.equal(projection.view().activeRunId, "run-1");
    NodeAssert.equal(projection.view().runBusy, true);
    NodeAssert.equal(projection.view().queuedCount, 1);
    NodeAssert.equal(projection.view().queueHeld, true);

    apply(projection, "run.updated", { ...active, status: "waiting" });
    NodeAssert.equal(projection.view().activeRunId, "");
    NodeAssert.equal(projection.view().runBusy, true);
    apply(projection, "run.updated", { ...active, status: "interrupted", completedAt: end });
    NodeAssert.equal(projection.view().activeRunId, "");
    NodeAssert.equal(projection.view().runBusy, false);
    NodeAssert.equal(projection.view().queueHeld, true);
    apply(projection, "run.updated", { ...queued, queueHeld: false });
    NodeAssert.equal(projection.view().queuedCount, 1);
    NodeAssert.equal(projection.view().queueHeld, false);
    apply(projection, "run.updated", { ...queued, status: "starting", queuePosition: null });
    NodeAssert.equal(projection.view().activeRunId, "run-2");
    NodeAssert.equal(projection.view().queuedCount, 0);

    apply(projection, "thread.model-selection-updated", {
      ...thread,
      modelSelection: { instanceId: "replay", model: "multi-turn" },
      updatedAt: end,
    });
    NodeAssert.equal(projection.view().modelLabel, "multi-turn");
    NodeAssert.deepEqual(projection.view().modelSelection, {
      instanceId: "replay",
      model: "multi-turn",
    });
    const advancedSelection = {
      instanceId: "replay",
      model: "multi-turn",
      options: [
        { id: "fastMode", value: false },
        { id: "effort", value: "high" },
      ],
    };
    NodeAssert.equal(
      apply(projection, "thread.model-selection-updated", {
        ...thread,
        modelSelection: advancedSelection,
      }),
      true,
    );
    NodeAssert.deepEqual(projection.view().modelSelection, advancedSelection);
    NodeAssert.equal(
      apply(projection, "thread.model-selection-updated", {
        ...thread,
        modelSelection: { ...advancedSelection, options: [...advancedSelection.options].reverse() },
      }),
      false,
    );
    apply(projection, "thread.metadata-updated", {
      ...thread,
      worktreePath: "/tmp/replay-worktree",
    });
    NodeAssert.equal(projection.view().worktreePath, "/tmp/replay-worktree");
    apply(projection, "thread.metadata-updated", { ...thread, worktreePath: null });
    NodeAssert.equal(projection.view().worktreePath, "");
    apply(projection, "thread.metadata-updated", { ...thread, id: "thread-other" });
    NodeAssert.equal(projection.view().title, "Replay conversation");
  },
);

NodeTest.test(
  "joins approval requests in either order and ignores late details after settlement",
  async () => {
    const options = [
      { decision: "acceptAlways", label: "Always permit", warning: "Persists for future requests" },
      { decision: "cancel", label: "Cancel command" },
    ];
    const approval = item("item-approval", "approval_request", {
      requestId: "approval-1",
      requestKind: "command",
      status: "waiting",
      prompt: "Run the build?",
      reason: "Build verification",
      options,
    });
    const live = { type: "live", providerSessionId: "session-1" };
    const runtime = {
      id: "approval-1",
      nodeId: "node-1",
      providerTurnId: null,
      nativeRequestRef: null,
      kind: "command",
      status: "pending",
      responseCapability: live,
      createdAt: start,
      resolvedAt: null,
    };
    const initial = snapshot({ turnItems: [approval] });
    const { ThreadDetailProjection } = await protocol;
    const projection = new ThreadDetailProjection("thread-1");
    projection.reset(initial);
    NodeAssert.equal(projection.view().approval, undefined);
    apply(projection, "runtime-request.updated", runtime);
    NodeAssert.deepEqual(projection.view().approval, {
      id: "approval-1",
      prompt: "Run the build?",
      reason: "Build verification\nPersists for future requests",
      options,
      canRespond: true,
      supportsFeedback: false,
    });
    apply(projection, "runtime-request.updated", {
      ...runtime,
      status: "resolved",
      resolvedAt: end,
      decision: "cancel",
    });
    apply(projection, "turn-item.updated", { ...approval, updatedAt: end });
    apply(projection, "runtime-request.updated", runtime);
    NodeAssert.equal(projection.view().approval, undefined);

    projection.reset(snapshot({ runtimeRequests: [runtime] }));
    NodeAssert.equal(projection.view().approval?.canRespond ?? false, false);
    apply(projection, "turn-item.updated", approval);
    NodeAssert.equal(projection.view().approval?.canRespond, true);
    apply(projection, "runtime-request.updated", {
      ...runtime,
      responseCapability: { ...live, supportsFeedback: true },
    });
    apply(projection, "turn-item.updated", { ...approval, options: [], updatedAt: end });
    NodeAssert.equal(projection.view().approval?.canRespond, false);
    NodeAssert.equal(projection.view().approval?.supportsFeedback, true);
    apply(projection, "runtime-request.updated", {
      ...runtime,
      responseCapability: { type: "not_resumable", reason: "Provider stopped" },
    });
    NodeAssert.equal(projection.view().approval?.canRespond, false);
    NodeAssert.equal(projection.view().approval?.supportsFeedback, false);
    NodeAssert.match(projection.view().approval?.reason ?? "", /Provider stopped/);
    apply(projection, "runtime-request.updated", {
      ...runtime,
      status: "cancelled",
      resolvedAt: end,
    });
    NodeAssert.equal(projection.view().approval, undefined);

    apply(projection, "runtime-request.updated", { ...runtime, id: "input-1", kind: "user_input" });
    NodeAssert.equal(projection.view().approval, undefined);
  },
);

NodeTest.test(
  "joins pending questionnaires to their runtime requests and advances after an answer",
  async () => {
    const questions = [
      {
        id: "priority",
        header: "Priority",
        question: "Which comes first?",
        options: [{ label: "Correctness", description: "Check every input", value: "strict" }],
        allowCustomAnswer: false,
      },
    ];
    const waiting = run("run-1", 1, "waiting");
    const questionnaire = item("item-input", "user_input_request", {
      requestId: "input-1",
      status: "waiting",
      questions,
    });
    const request = {
      id: "input-1",
      nodeId: "node-1",
      providerTurnId: null,
      nativeRequestRef: null,
      kind: "user_input",
      status: "pending",
      responseCapability: { type: "live", providerSessionId: "session-1" },
      createdAt: start,
      resolvedAt: null,
    };
    const followUp = {
      ...questionnaire,
      id: "item-follow-up",
      requestId: "input-2",
      responseMode: "message",
    };
    const messageRequest = {
      ...request,
      id: "input-2",
      responseCapability: { type: "message" },
      createdAt: end,
    };
    const approval = { ...request, id: "approval-1", kind: "command" };
    const { ThreadDetailProjection } = await protocol;
    const projection = new ThreadDetailProjection("thread-1");
    projection.reset(snapshot({ runs: [waiting], runtimeRequests: [request, approval] }));
    NodeAssert.equal(projection.view().userInput, undefined);
    NodeAssert.equal(projection.view().queueEditBlocked, true);
    apply(projection, "turn-item.updated", questionnaire);
    NodeAssert.deepEqual(projection.view().userInput, {
      id: "input-1",
      questions,
      canRespond: true,
      dismissible: false,
      reason: "",
      stopRunId: "run-1",
    });
    NodeAssert.equal(projection.view().userInput, projection.view().userInput);
    NodeAssert.equal(projection.view().approval?.id, "approval-1");
    apply(projection, "turn-item.updated", followUp);
    apply(projection, "runtime-request.updated", messageRequest);
    apply(projection, "runtime-request.updated", {
      ...request,
      responseCapability: { type: "not_resumable", reason: "Provider stopped" },
    });
    NodeAssert.equal(projection.view().userInput?.canRespond, false);
    NodeAssert.equal(projection.view().userInput?.reason, "Provider stopped");
    apply(projection, "runtime-request.updated", {
      ...request,
      status: "resolved",
      resolvedAt: end,
    });
    apply(projection, "runtime-request.updated", request);
    NodeAssert.equal(projection.view().userInput?.id, "input-2");
    NodeAssert.equal(projection.view().userInput?.canRespond, true);
    NodeAssert.equal(projection.view().userInput?.dismissible, true);
    apply(projection, "runtime-request.updated", {
      ...messageRequest,
      status: "cancelled",
      resolvedAt: end,
    });
    NodeAssert.equal(projection.view().userInput, undefined);
    NodeAssert.equal(projection.view().queueEditBlocked, false);
  },
);

NodeTest.test(
  "submits exact option values, multi-selection and text in the runtime answer command",
  async () => {
    const { buildUserInputAnswers, respondUserInputRequest, dismissUserInputRequest } =
      await protocol;
    const questions = [
      {
        id: "approach",
        options: [{ label: "Strict", description: "Validate all inputs", value: " strict " }],
        allowCustomAnswer: false,
      },
      {
        id: "targets",
        options: [
          { label: "Build", description: "Run the build" },
          { label: "Lint", description: "Run lint" },
        ],
        multiSelect: true,
      },
      { id: "detail", options: [] },
      { id: "provided", options: [], initialAnswer: "Editable text\n" },
      {
        id: "optional",
        options: [{ label: "Include details", description: "Add the extra information" }],
        allowCustomAnswer: false,
        required: false,
      },
    ];
    const drafts = new Map([
      ["approach", { selected: [" strict "], custom: "Unavailable custom answer" }],
      ["targets", { selected: ["Lint", "Build", "Lint", "Unlisted"] }],
      ["detail", { custom: " \n Read the fixture \n " }],
    ]);
    NodeAssert.equal(buildUserInputAnswers(questions, new Map()), undefined);
    for (const value of ["", " \n"]) {
      const answer = buildUserInputAnswers(
        questions,
        new Map([...drafts, ["provided", { custom: value }]]),
      );
      NodeAssert.equal(answer?.provided, value);
    }
    NodeAssert.equal(buildUserInputAnswers([questions[4]], new Map(), true), undefined);
    const unusualId = { id: "__proto__", options: [], initialAnswer: "exact answer" };
    NodeAssert.equal(
      JSON.stringify(buildUserInputAnswers([unusualId], new Map())),
      '{"__proto__":"exact answer"}',
    );
    const answers = buildUserInputAnswers(questions, drafts);
    NodeAssert.deepEqual(answers, {
      approach: " strict ",
      targets: ["Lint", "Build"],
      detail: "Read the fixture",
      provided: "Editable text\n",
      optional: "",
    });
    const request = respondUserInputRequest("command-answer", "thread-1", "input-1", answers);
    NodeAssert.equal(request.tag, ORCHESTRATION_V2_WS_METHODS.dispatchCommand);
    NodeAssert.deepEqual(decodeCommand(request.payload), {
      type: "runtime-request.respond",
      commandId: "command-answer",
      threadId: "thread-1",
      requestId: "input-1",
      answers,
    });
    NodeAssert.deepEqual(
      decodeCommand(dismissUserInputRequest("command-dismiss", "thread-1", "input-2").payload),
      {
        type: "thread.user-input.dismiss",
        commandId: "command-dismiss",
        threadId: "thread-1",
        requestId: "input-2",
      },
    );
  },
);

NodeTest.test("keeps projected message and tool order when their timestamps match", async () => {
  const { ThreadDetailProjection, readThreadActivityIds } = await protocol;
  const command = item("command-order", "command_execution", {
    title: "Run checks",
    input: "check",
  });
  const assistant = item("assistant-order", "assistant_message", {
    messageId: "reply-order",
    text: "Done",
    streaming: false,
  });
  const messageItem = item("user-order", "user_message", {
    messageId: "prompt-order",
    text: "Test",
    createdBy: "user",
    creationSource: "mobile",
    attachments: [],
    inputIntent: "turn_start",
  });
  const visibleTurnItems = [messageItem, command, assistant].map((activity, position) => ({
    position,
    visibility: "local",
    sourceThreadId: "thread-1",
    sourceItemId: activity.id,
    item: activity,
  }));
  const projection = new ThreadDetailProjection("thread-1");
  projection.reset(snapshot({ visibleTurnItems, turnItems: [command] }));
  const expected = ["message:prompt-order", "work:command-order", "message:reply-order"];
  NodeAssert.deepEqual(readThreadActivityIds(visibleTurnItems), expected);
  NodeAssert.deepEqual(projection.view().activityIds, expected);
  const liveCommand = item("next-command", "command_execution", {
    title: "Run again",
    input: "check",
  });
  apply(projection, "turn-item.updated", liveCommand);
  NodeAssert.deepEqual(projection.view().activityIds, [...expected, "work:next-command"]);
});

NodeTest.test(
  "updates actual tool work in place, includes inherited work and ignores reasoning",
  async () => {
    const command = item("command-1", "command_execution", {
      title: "Run checks",
      status: "running",
      completedAt: null,
      input: "vp test run sample.test.ts",
    });
    const file = item("file-1", "file_change", {
      fileName: "src/example.ts",
      additions: 3,
      deletions: 1,
      threadId: "thread-parent",
    });
    const reasoning = item("hidden", "reasoning", { text: "Private reasoning", streaming: false });
    const initial = snapshot({
      turnItems: [command, reasoning],
      visibleTurnItems: [
        {
          position: 0,
          visibility: "inherited",
          sourceThreadId: "thread-parent",
          sourceItemId: file.id,
          item: file,
        },
        {
          position: 1,
          visibility: "local",
          sourceThreadId: "thread-1",
          sourceItemId: command.id,
          item: command,
        },
      ],
    });
    const { ThreadDetailProjection } = await protocol;
    const projection = new ThreadDetailProjection("thread-1");
    projection.reset(initial);
    NodeAssert.deepEqual(
      projection.view().work.map((entry) => entry.id),
      ["file-1", "command-1"],
    );
    NodeAssert.match(projection.view().work[0].detail, /src\/example\.ts.*\+3.*-1/s);
    NodeAssert.equal(projection.view().work[1].status, "running");
    apply(projection, "turn-item.updated", {
      ...command,
      status: "completed",
      output: "1 failed",
      exitCode: 1,
      updatedAt: end,
      completedAt: end,
    });
    NodeAssert.equal(apply(projection, "turn-item.updated", command), false);
    NodeAssert.deepEqual(projection.view().work[1], {
      id: "command-1",
      threadId: "thread-1",
      runId: "run-1",
      type: "command_execution",
      wantsOutput: false,
      title: "Run checks",
      detail: "vp test run sample.test.ts\n1 failed",
      status: "failed",
      timestamp: start,
    });
    NodeAssert.equal(apply(projection, "turn-item.updated", reasoning), false);
    apply(
      projection,
      "turn-item.updated",
      item("error-1", "error", {
        status: "failed",
        failure: {
          class: "provider_error",
          message: "Runner stopped",
          code: null,
          retryable: null,
        },
      }),
    );
    NodeAssert.equal(projection.view().work[2].detail, "Runner stopped");
    projection.reset(snapshot());
    NodeAssert.deepEqual(projection.view().work, []);
  },
);

NodeTest.test("fetches output omitted from an existing command row", async () => {
  const { ThreadDetailProjection, threadWorkDetailRequest, readThreadWorkDetail } = await protocol;
  const command = item("command-output", "command_execution", {
    input: "print fixture",
    outputOmitted: true,
  });
  const projection = new ThreadDetailProjection("thread-1");
  projection.reset(snapshot({ turnItems: [command] }));
  const work = projection.view().work[0];
  NodeAssert.equal(work.wantsOutput, true);
  NodeAssert.deepEqual(decodeGetTurnItem(threadWorkDetailRequest(work.threadId, work.id).payload), {
    threadId: "thread-1",
    itemId: "command-output",
  });
  const result = { item: { ...command, output: "Replay output marker", outputOmitted: undefined } };
  NodeAssert.equal(
    readThreadWorkDetail(result, work.threadId, work.id),
    "print fixture\nReplay output marker",
  );
  NodeAssert.throws(() => readThreadWorkDetail(result, work.threadId, "different-item"));
});

NodeTest.test(
  "projects the active run's agents, live background work and finished workflows",
  async () => {
    const { ThreadDetailProjection } = await protocol;
    const projection = new ThreadDetailProjection("thread-1");
    const active = run("active", 3, "running");
    const workflow = { name: "Build workflow", phases: [{ index: 0, title: "Build" }], agents: [] };
    const remoteChild = { environmentId: "peer-env", threadId: "peer-thread", label: "Other host" };
    projection.reset(
      snapshot({
        runs: [
          run("older", 2, "completed"),
          run("later", 8, "queued"),
          active,
          run("discarded", 9, "rolled_back"),
        ],
        subagents: [
          subagent("done", active.id, "completed", { startedAt: end, updatedAt: end }),
          subagent("local", active.id, "pending", {
            childThreadId: "child-local",
            startedAt: end,
            updatedAt: end,
          }),
          subagent("unavailable", "discarded", "running"),
          subagent("older-done", "older", "completed"),
          subagent("remote", "older", "waiting", { remoteChild }),
          subagent("workflow", "older", "completed", { workflow }),
        ],
      }),
    );
    const roster = projection.view().subagents;
    NodeAssert.equal(roster.runId, active.id);
    NodeAssert.equal(roster.turnActive, true);
    NodeAssert.equal(roster.latestTurn, true);
    NodeAssert.equal(roster.liveCount, 2);
    NodeAssert.equal(roster.settledCount, 2);
    NodeAssert.equal(roster.showPill, true);
    NodeAssert.deepEqual(
      roster.subagents.map(({ id }) => id),
      ["remote", "workflow", "done", "local"],
    );
    NodeAssert.deepEqual(roster.subagents[0].remoteChild, remoteChild);
    NodeAssert.deepEqual(roster.subagents[1].workflow, workflow);
    NodeAssert.equal(roster.subagents[3].childThreadId, "child-local");
    NodeAssert.equal(projection.view().subagents, roster);

    const finished = subagent("settled", "older", "completed");
    projection.reset(
      snapshot({
        runs: [run("older", 2, "completed"), run("later", 8, "queued")],
        subagents: [finished],
      }),
    );
    NodeAssert.equal(projection.view().subagents.showPill, true);
    const cancelledBeforeStart = run("later", 8, "cancelled", { startedAt: null });
    NodeAssert.equal(apply(projection, "run.updated", cancelledBeforeStart), true);
    NodeAssert.equal(projection.view().subagents.showPill, true);
    NodeAssert.equal(
      apply(projection, "run.updated", { ...cancelledBeforeStart, startedAt: end }),
      true,
    );
    NodeAssert.equal(projection.view().subagents.latestTurn, false);
    NodeAssert.equal(projection.view().subagents.showPill, false);
    NodeAssert.equal(
      apply(projection, "run.updated", {
        ...cancelledBeforeStart,
        status: "rolled_back",
        startedAt: end,
      }),
      true,
    );
    NodeAssert.equal(projection.view().subagents.showPill, true);
  },
);

NodeTest.test(
  "retains omitted subagent bodies for this stream and rejects stale or out-of-scope events",
  async () => {
    const { ThreadDetailProjection } = await protocol;
    const projection = new ThreadDetailProjection("thread-1");
    const worker = subagent("worker", null, "running", { result: "Partial output" });
    projection.reset(snapshot({ subagents: [worker] }));
    const deduped = {
      ...worker,
      prompt: "",
      result: null,
      promptOmitted: true,
      resultOmitted: true,
      progress: "Step two",
      updatedAt: end,
    };
    NodeAssert.equal(apply(projection, "subagent.updated", deduped), true);
    let result = projection.view().subagents.subagents[0];
    NodeAssert.equal(result.progress, "Step two");
    NodeAssert.equal(result.prompt, worker.prompt);
    NodeAssert.equal(result.result, worker.result);
    NodeAssert.equal(result.promptOmitted, undefined);
    NodeAssert.equal(result.resultOmitted, undefined);
    NodeAssert.equal(apply(projection, "subagent.updated", worker), false);
    NodeAssert.equal(
      apply(projection, "subagent.updated", {
        ...deduped,
        threadId: "other-thread",
        progress: "Foreign",
      }),
      false,
    );
    NodeAssert.equal(projection.view().subagents.subagents[0], result);

    projection.reset(snapshot({ subagents: [deduped] }));
    result = projection.view().subagents.subagents[0];
    NodeAssert.equal(result.prompt, "");
    NodeAssert.equal(result.result, null);
    NodeAssert.equal(result.promptOmitted, true);
    NodeAssert.equal(result.resultOmitted, true);
    projection.reset(snapshot());
    NodeAssert.equal(projection.view().subagents, undefined);
  },
);

NodeTest.test("dispatches the same draft and stable IDs with the selected queue mode", async () => {
  const { dispatchRequest } = await transport;
  for (const [queue, mode] of [
    [false, "start_immediately"],
    [true, "queue_after_active"],
  ]) {
    const request = dispatchRequest("send-1", "message-1", "thread-1", "draft\ntext", queue);
    NodeAssert.equal(request.tag, ORCHESTRATION_V2_WS_METHODS.dispatchCommand);
    NodeAssert.deepEqual(decodeCommand(request.payload), {
      type: "message.dispatch",
      commandId: "send-1",
      messageId: "message-1",
      threadId: "thread-1",
      createdBy: "user",
      creationSource: "mobile",
      dispatchMode: { type: mode },
      text: "draft\ntext",
      attachments: [],
    });
  }
});

NodeTest.test(
  "reads shell background tasks with forward-compatible kinds and scoped child links",
  async () => {
    const { readThreads } = await transport;
    const input = [
      {
        taskId: "agent",
        kind: "subagent",
        description: "Build",
        awaited: true,
        childThreadId: "child",
      },
      { taskId: "command", kind: "command", description: "Compile", awaited: true },
      { taskId: "pull-request-watch:git.example/team/repo#4", kind: "monitor" },
      {
        taskId: "new-task",
        kind: "future-task",
        description: "Extra work",
        awaited: true,
        parentTaskId: "agent",
      },
    ];
    const decodeTask = Schema.decodeUnknownSync(OrchestrationV2PendingBackgroundTask);
    const [row, legacy, malformed] = readThreads({
      threads: [
        { ...thread, pendingBackgroundTasks: input },
        { ...thread, id: "legacy" },
        {
          ...thread,
          id: "malformed",
          pendingBackgroundTasks: [
            { taskId: "", kind: "command" },
            { taskId: "watch", kind: "monitor", childThreadId: "must-not-open" },
          ],
        },
      ],
    });
    NodeAssert.deepEqual(row.pendingBackgroundTasks, input.map(decodeTask));
    NodeAssert.deepEqual(legacy.pendingBackgroundTasks, []);
    NodeAssert.deepEqual(malformed.pendingBackgroundTasks, [{ taskId: "watch", kind: "monitor" }]);
    const { hasNativeThreadBackgroundWork } = await import(
      new URL("ThreadBackgroundWorkProtocol.ets", client).href
    );
    NodeAssert.equal(hasNativeThreadBackgroundWork(row.pendingBackgroundTasks), true);
    NodeAssert.equal(hasNativeThreadBackgroundWork([row.pendingBackgroundTasks[2]]), false);
  },
);

NodeTest.test(
  "selects scoped background stop commands and keeps PR watches separate on a legacy host",
  async () => {
    const { ThreadDetailProjection, backgroundWorkStopRequest, backgroundPullRequestStopRequest } =
      await protocol;
    const projection = new ThreadDetailProjection("thread-1");
    const watch = {
      startedAt: start,
      headSha: null,
      failedChecks: [],
      passed: false,
      passedChecks: [],
      remarksThrough: start,
      remarkIds: [],
      conflicting: false,
      wakes: 0,
    };
    const link = {
      host: "git.example",
      repository: "team/repo",
      number: 4,
      source: "manual",
      linkedAt: start,
      url: "https://git.example/team/repo/pull/4",
      snapshot: null,
      stack: null,
      watch,
    };
    const settled = run("latest", 4, "completed", { completedAt: end });
    const running = item("background-1", "command_execution", {
      runId: settled.id,
      status: "running",
      completedAt: null,
      input: "vp run dev",
    });
    projection.reset(
      snapshot({
        thread: {
          ...thread,
          pullRequests: [link, { ...link, number: 5, source: "stack-dismissed" }],
        },
        runs: [settled],
      }),
    );
    const ready = projection.view();
    NodeAssert.equal(ready.backgroundStopRunId, "");
    NodeAssert.deepEqual(ready.backgroundStopWatches, [
      { host: link.host, repository: link.repository, number: 4 },
    ]);
    const readOnlyConfig = { environment: { capabilities: {} } };
    NodeAssert.equal(
      backgroundWorkStopRequest(
        "legacy-stop",
        "thread-1",
        readOnlyConfig,
        ready.backgroundStopRunId,
      ),
      undefined,
    );
    NodeAssert.deepEqual(
      decodeCommand(
        backgroundPullRequestStopRequest("unwatch", "thread-1", ready.backgroundStopWatches[0])
          .payload,
      ),
      {
        type: "thread.pull-request.watch",
        commandId: "unwatch",
        threadId: "thread-1",
        host: link.host,
        repository: link.repository,
        number: 4,
        watching: false,
      },
    );
    NodeAssert.equal(
      apply(projection, "turn-item.updated", { ...running, threadId: "other-thread" }),
      false,
    );
    NodeAssert.equal(projection.view().backgroundStopRunId, "");
    NodeAssert.equal(apply(projection, "turn-item.updated", running), true);
    NodeAssert.equal(projection.view().backgroundStopRunId, settled.id);
    NodeAssert.deepEqual(
      decodeCommand(
        backgroundWorkStopRequest(
          "legacy-stop",
          "thread-1",
          readOnlyConfig,
          projection.view().backgroundStopRunId,
        ).payload,
      ),
      {
        type: "run.interrupt",
        commandId: "legacy-stop",
        threadId: "thread-1",
        runId: settled.id,
        holdQueue: true,
      },
    );
    const currentConfig = { environment: { capabilities: { threadStop: true } } };
    NodeAssert.deepEqual(
      decodeCommand(
        backgroundWorkStopRequest("new-stop", "thread-1", currentConfig, settled.id).payload,
      ),
      {
        type: "thread.stop",
        commandId: "new-stop",
        threadId: "thread-1",
      },
    );
    NodeAssert.equal(
      apply(projection, "turn-item.updated", {
        ...running,
        status: "completed",
        updatedAt: end,
        completedAt: end,
      }),
      true,
    );
    NodeAssert.equal(projection.view().backgroundStopRunId, "");
    NodeAssert.equal(apply(projection, "turn-item.updated", running), false);
    NodeAssert.equal(projection.view().backgroundStopRunId, "");
    const waiting = run("waiting", 5, "waiting");
    apply(projection, "run.updated", waiting);
    NodeAssert.equal(projection.view().backgroundStopRunId, waiting.id);
    const ended = { ...link, endedWatch: watch };
    delete ended.watch;
    NodeAssert.equal(apply(projection, "thread.pull-request-link-updated", ended), true);
    NodeAssert.deepEqual(projection.view().backgroundStopWatches, []);
  },
);

NodeTest.test(
  "sends the captured terminal lines as structured context with their message",
  async () => {
    const { dispatchRequest } = await transport;
    const context = {
      version: 1,
      records: [
        {
          version: 1,
          kind: "terminal",
          contextId: "terminal-context",
          label: "Shell · visible lines 1–2",
          terminalId: "shell-1",
          terminalLabel: "Shell (visible output)",
          lineStart: 1,
          lineEnd: 2,
          text: "line 1\nline 2",
        },
      ],
    };
    const text = "[Shell · visible lines 1–2](t3-context://v1/terminal/terminal-context)";
    const request = dispatchRequest(
      "send-1",
      "message-1",
      "thread-1",
      text,
      true,
      undefined,
      [],
      context,
    );
    NodeAssert.deepEqual(decodeCommand(request.payload).context, context);
  },
);

NodeTest.test("keeps provider handoff unavailable while a session is starting", async () => {
  const { ThreadDetailProjection } = await protocol;
  const projection = new ThreadDetailProjection("thread-1");
  projection.reset(snapshot());
  NodeAssert.equal(projection.view().canSwitchProvider, true);

  apply(projection, "run.created", run("run-1", 1, "starting"));
  NodeAssert.equal(projection.view().canSwitchProvider, false);
});

NodeTest.test("dispatches a pending provider pick only as part of the next message", async () => {
  const { dispatchRequest } = await transport;
  const target = {
    instanceId: "secondReplay",
    model: "multi-turn",
    options: [{ id: "fastMode", value: false }],
  };
  const request = dispatchRequest("send-1", "message-1", "thread-1", "next turn", true, target);
  NodeAssert.equal(request.tag, ORCHESTRATION_V2_WS_METHODS.dispatchCommand);
  NodeAssert.deepEqual(decodeCommand(request.payload), {
    type: "message.dispatch",
    commandId: "send-1",
    messageId: "message-1",
    threadId: "thread-1",
    createdBy: "user",
    creationSource: "mobile",
    dispatchMode: { type: "queue_after_active" },
    text: "next turn",
    attachments: [],
    modelSelection: target,
  });
});

NodeTest.test("sets an in-place model pick for the exact thread", async () => {
  const { modelSelectionRequest } = await protocol;
  const selection = { instanceId: "replay", model: "multi-turn" };
  const request = modelSelectionRequest("switch-model", "thread-1", selection);
  NodeAssert.equal(request.tag, ORCHESTRATION_V2_WS_METHODS.dispatchCommand);
  NodeAssert.deepEqual(decodeCommand(request.payload), {
    type: "thread.model-selection.set",
    commandId: "switch-model",
    threadId: "thread-1",
    modelSelection: selection,
  });
});

NodeTest.test("binds each control to its exact command, thread, run or approval ID", async () => {
  const {
    interruptRequest,
    resumeQueueRequest,
    respondApprovalRequest,
    startQueuedRunRequest,
    promoteQueuedRunRequest,
    cancelQueuedRunRequest,
    editQueuedRunRequest,
    runtimeModeSelectionRequest,
  } = await protocol;
  const requests = [
    [
      runtimeModeSelectionRequest("send-1:runtime-mode", "thread-1", "auto-accept-edits"),
      {
        type: "thread.runtime-mode.set",
        commandId: "send-1:runtime-mode",
        threadId: "thread-1",
        runtimeMode: "auto-accept-edits",
      },
    ],
    [
      interruptRequest("stop", "thread-1", "run-1"),
      {
        type: "run.interrupt",
        commandId: "stop",
        threadId: "thread-1",
        runId: "run-1",
        holdQueue: true,
      },
    ],
    [
      resumeQueueRequest("resume", "thread-1"),
      {
        type: "queue.resume",
        commandId: "resume",
        threadId: "thread-1",
      },
    ],
    [
      respondApprovalRequest("respond", "thread-1", "approval-1", "acceptAlways"),
      {
        type: "runtime-request.respond",
        commandId: "respond",
        threadId: "thread-1",
        requestId: "approval-1",
        decision: "acceptAlways",
      },
    ],
    [
      respondApprovalRequest(
        "feedback",
        "thread-1",
        "approval-child",
        "decline",
        "  Use a safer command.\n",
      ),
      {
        type: "runtime-request.respond",
        commandId: "feedback",
        threadId: "thread-1",
        requestId: "approval-child",
        decision: "decline",
        feedback: "Use a safer command.",
      },
    ],
    [
      startQueuedRunRequest("start", "thread-1", "queued-1"),
      { type: "queued-run.start", commandId: "start", threadId: "thread-1", runId: "queued-1" },
    ],
    [
      promoteQueuedRunRequest("steer", "thread-1", "queued-1", "active-1"),
      {
        type: "queued-message.promote-to-steer",
        commandId: "steer",
        threadId: "thread-1",
        queuedRunId: "queued-1",
        targetRunId: "active-1",
      },
    ],
    [
      cancelQueuedRunRequest("cancel", "thread-1", "queued-1"),
      { type: "queued-run.cancel", commandId: "cancel", threadId: "thread-1", runId: "queued-1" },
    ],
    [
      editQueuedRunRequest("edit", "thread-1", "queued-1", "  Keep formatting.\n"),
      {
        type: "queued-run.edit",
        commandId: "edit",
        threadId: "thread-1",
        runId: "queued-1",
        text: "  Keep formatting.\n",
      },
    ],
  ];
  for (const [request, payload] of requests) {
    NodeAssert.deepEqual(request, {
      _tag: "Request",
      id: "1",
      tag: ORCHESTRATION_V2_WS_METHODS.dispatchCommand,
      payload,
      headers: [],
    });
    NodeAssert.deepEqual(decodeCommand(request.payload), payload);
  }
  NodeAssert.throws(() => editQueuedRunRequest("edit", "thread-1", "queued-1", "  \n"));
  NodeAssert.throws(() =>
    respondApprovalRequest("feedback", "thread-1", "approval-1", "decline", "  \n"),
  );
  NodeAssert.throws(() =>
    respondApprovalRequest("feedback", "thread-1", "approval-1", "accept", "Use a safer command."),
  );
});
