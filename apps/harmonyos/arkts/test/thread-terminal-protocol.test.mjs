import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import {
  DEFAULT_MAX_TERMINAL_BUFFER_BYTES,
  TerminalAttachInput,
  TerminalAttachStreamEvent,
  TerminalClearInput,
  TerminalCloseInput,
  TerminalMetadataStreamEvent,
  TerminalObserveInput,
  TerminalResizeInput,
  TerminalWriteInput,
  WS_METHODS,
} from "@t3tools/contracts";
import * as Schema from "effect/Schema";

const client = new URL("../entry/src/main/ets/client/", import.meta.url);
const loader = NodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith("@kit.")) return { url: specifier, shortCircuit: true };
    if (specifier.startsWith("./") && context.parentURL?.startsWith(client.href)) {
      return nextResolve(`${specifier}.ets`, context);
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url === "@kit.ArkTS") {
      return { format: "module", shortCircuit: true, source: "export const util = {};" };
    }
    if (url === "@kit.NetworkKit") {
      return {
        format: "module",
        shortCircuit: true,
        source:
          "export const webSocket = { createWebSocket: () => globalThis.terminalSocketFixture() };",
      };
    }
    if (!url.startsWith(client.href) || !url.endsWith(".ets")) return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(new URL(url), "utf8")),
    };
  },
});
const protocol = import(new URL("ThreadTerminalProtocol.ets", client).href);
const connection = import(new URL("ThreadTerminalConnection.ets", client).href);
void protocol.catch(() => {});
void connection.catch(() => {});
NodeTest.after(() => loader.deregister());

const session = { threadId: "task-1", terminalId: "term-1" };
const target = {
  ...session,
  operate: true,
  cwd: "/project",
  worktreePath: "/worktree",
  cols: 80,
  rows: 24,
};
const baseSnapshot = {
  ...session,
  cwd: "/project",
  worktreePath: "/worktree",
  pid: 123,
  status: "running",
  exitCode: null,
  exitSignal: null,
  label: "zsh",
  updatedAt: "2026-11-24T12:00:00.000Z",
};
const encodeEvent = Schema.encodeSync(Schema.toCodecJson(TerminalAttachStreamEvent));
const encodeMetadata = Schema.encodeSync(Schema.toCodecJson(TerminalMetadataStreamEvent));
const decodeRequests = {
  [WS_METHODS.terminalAttach]: Schema.decodeUnknownSync(Schema.toCodecJson(TerminalAttachInput)),
  [WS_METHODS.terminalObserve]: Schema.decodeUnknownSync(Schema.toCodecJson(TerminalObserveInput)),
  [WS_METHODS.terminalWrite]: Schema.decodeUnknownSync(Schema.toCodecJson(TerminalWriteInput)),
  [WS_METHODS.terminalResize]: Schema.decodeUnknownSync(Schema.toCodecJson(TerminalResizeInput)),
  [WS_METHODS.terminalClear]: Schema.decodeUnknownSync(Schema.toCodecJson(TerminalClearInput)),
  [WS_METHODS.terminalClose]: Schema.decodeUnknownSync(Schema.toCodecJson(TerminalCloseInput)),
};
const snapshot = (history, sequence = 5, fields = {}) =>
  encodeEvent({ type: "snapshot", snapshot: { ...baseSnapshot, history, sequence, ...fields } });
const output = (data, sequence, fields = {}) =>
  encodeEvent({ ...session, type: "output", data, sequence, ...fields });

function assertRequest(request, id, tag, expected) {
  const wire = JSON.parse(JSON.stringify(request));
  NodeAssert.deepEqual(
    { ...wire, payload: decodeRequests[tag](wire.payload) },
    {
      _tag: "Request",
      id,
      tag,
      headers: [],
      payload: expected,
    },
  );
}

NodeTest.test(
  "uses Effect terminal RPC methods and gates commands to writable terminal targets",
  async () => {
    const {
      threadTerminalStreamRequest,
      threadTerminalWriteRequest,
      threadTerminalResizeRequest,
      threadTerminalClearRequest,
      threadTerminalCloseRequest,
    } = await protocol;
    assertRequest(threadTerminalStreamRequest("1", target, false), "1", WS_METHODS.terminalAttach, {
      ...session,
      cwd: "/project",
      worktreePath: "/worktree",
      cols: 80,
      rows: 24,
      maxHistoryBytes: DEFAULT_MAX_TERMINAL_BUFFER_BYTES,
    });
    assertRequest(
      threadTerminalStreamRequest("1", { ...target, restartIfNotRunning: true }, true),
      "1",
      WS_METHODS.terminalAttach,
      {
        ...session,
        cwd: "/project",
        worktreePath: "/worktree",
        cols: 80,
        rows: 24,
        resume: true,
        maxHistoryBytes: DEFAULT_MAX_TERMINAL_BUFFER_BYTES,
      },
    );
    assertRequest(
      threadTerminalStreamRequest("2", { ...target, operate: false }, false),
      "2",
      WS_METHODS.terminalObserve,
      session,
    );
    assertRequest(
      threadTerminalWriteRequest("3", target, "\u001b[1;2R", false, true),
      "3",
      WS_METHODS.terminalWrite,
      { ...session, data: "\u001b[1;2R", binary: false, reply: true },
    );
    assertRequest(
      threadTerminalResizeRequest("4", target, 64, 30),
      "4",
      WS_METHODS.terminalResize,
      { ...session, cols: 64, rows: 30 },
    );
    assertRequest(threadTerminalClearRequest("5", target), "5", WS_METHODS.terminalClear, session);
    assertRequest(threadTerminalCloseRequest("6", target, false), "6", WS_METHODS.terminalClose, {
      ...session,
      deleteHistory: false,
    });
    NodeAssert.throws(() => threadTerminalWriteRequest("3", { ...target, operate: false }, "x"));
    NodeAssert.throws(() => threadTerminalWriteRequest("3", target, "x".repeat(65537)));
    NodeAssert.throws(() => threadTerminalResizeRequest("4", target, 0, 30));
    NodeAssert.throws(() =>
      threadTerminalStreamRequest("1", { ...target, terminalId: " bad" }, false),
    );
  },
);

NodeTest.test(
  "applies scoped ordered events after a bounded, Unicode-safe initial snapshot",
  async () => {
    const { ThreadTerminalProjection } = await protocol;
    const projection = new ThreadTerminalProjection(target);
    NodeAssert.equal(projection.apply(output("early", 5)), undefined);
    NodeAssert.equal(
      projection.apply(snapshot("unrelated", 5, { terminalId: "term-2" })),
      undefined,
    );
    const state = projection.apply(
      snapshot("始".repeat(DEFAULT_MAX_TERMINAL_BUFFER_BYTES / 2) + "😀end"),
    );
    NodeAssert.equal(state.kind, "snapshot");
    NodeAssert.equal(state.status, "running");
    NodeAssert.equal(state.label, "zsh");
    NodeAssert.ok(Buffer.byteLength(state.history) <= DEFAULT_MAX_TERMINAL_BUFFER_BYTES);
    NodeAssert.match(state.history, /^始+😀end$/u);
    NodeAssert.equal(projection.apply(output("duplicate", 5)), undefined);
    NodeAssert.equal(projection.apply(output("other task", 6, { threadId: "task-2" })), undefined);
    NodeAssert.deepEqual(projection.apply(output("first", 6)), {
      kind: "output",
      data: "first",
      status: "running",
    });
    NodeAssert.deepEqual(projection.apply(output("second", 8)), {
      kind: "output",
      data: "second",
      status: "running",
    });
    NodeAssert.equal(projection.apply(output("late", 7)), undefined);
    const activity = projection.apply(
      encodeEvent({
        ...session,
        type: "activity",
        sequence: 9,
        label: "make",
        hasRunningSubprocess: true,
      }),
    );
    NodeAssert.equal(activity?.kind, "activity");
    NodeAssert.equal(activity.label, "make");
    NodeAssert.equal(activity.hasRunningSubprocess, true);
    NodeAssert.deepEqual(
      projection.apply(
        encodeEvent({ ...session, type: "exited", sequence: 10, exitCode: 17, exitSignal: null }),
      ),
      { kind: "exited", status: "exited", exitCode: 17, exitSignal: null },
    );
    const longTitle = "\u001b]0;" + "t".repeat(DEFAULT_MAX_TERMINAL_BUFFER_BYTES) + "\u0007visible";
    NodeAssert.ok(
      projection.apply(snapshot(longTitle, 11)).history === "visible",
      "truncated OSC text stays hidden",
    );
  },
);

function transport() {
  const opened = [];
  const requests = [];
  let wait = Promise.withResolvers();
  globalThis.terminalSocketFixture = () => {
    const handlers = new Map();
    const socket = {
      on(event, handler) {
        handlers.set(event, handler);
      },
      off(event) {
        handlers.delete(event);
      },
      async connect(address) {
        opened.push(address);
        handlers.get("open")?.();
        return true;
      },
      async send(raw) {
        const request = JSON.parse(raw);
        requests.push({ request, socket });
        if (request._tag === "Request") {
          wait.resolve({ request, socket });
          wait = Promise.withResolvers();
        }
        return true;
      },
      async close() {},
      frame(frame) {
        handlers.get("message")?.(null, JSON.stringify(frame));
      },
      disconnect() {
        handlers.get("close")?.();
      },
    };
    return socket;
  };
  let ticket = 0;
  return {
    opened,
    requests,
    address: async () => `wss://fixture.example.test/ws?wsTicket=single-use-${++ticket}`,
    nextRequest: () => wait.promise,
  };
}

const chunk = (request, values) => ({ _tag: "Chunk", requestId: request.id, values });
const exit = (request) => ({ _tag: "Exit", requestId: request.id, exit: { _tag: "Success" } });

NodeTest.test(
  "shares its attach socket with mutations, rejects uncertain writes, and resubscribes only the stream",
  async (test) => {
    test.mock.timers.enable({ apis: ["setTimeout", "setInterval"] });
    const { ThreadTerminalConnection } = await connection;
    const fixture = transport();
    const updates = [];
    const errors = [];
    const terminal = new ThreadTerminalConnection(
      fixture.address,
      () => true,
      target,
      (update) => updates.push(update),
      (_error, reconnecting) => errors.push(reconnecting),
    );
    try {
      const firstRequest = fixture.nextRequest();
      terminal.start();
      const { request: attach, socket } = await firstRequest;
      socket.frame(chunk(attach, [snapshot("initial"), output("one", 6), output("two", 7)]));
      NodeAssert.deepEqual(
        updates.map((item) => item.history ?? item.data),
        ["initial", "one", "two"],
      );
      NodeAssert.ok(
        fixture.requests.some(
          ({ request }) => request._tag === "Ack" && request.requestId === attach.id,
        ),
      );
      const firstCommand = fixture.nextRequest();
      const input = terminal.write("echo 1\r");
      const sent = await firstCommand;
      NodeAssert.equal(sent.socket, socket);
      NodeAssert.notEqual(sent.request.id, attach.id);
      NodeAssert.equal(sent.request.payload.data, "echo 1\r");
      const inputRejected = NodeAssert.rejects(input);
      socket.disconnect();
      await inputRejected;
      NodeAssert.deepEqual(errors, [true]);
      const resumedRequest = fixture.nextRequest();
      test.mock.timers.tick(1000);
      const resumed = await resumedRequest;
      NodeAssert.equal(resumed.request.tag, WS_METHODS.terminalAttach);
      NodeAssert.equal(resumed.request.payload.resume, true);
      resumed.socket.frame(chunk(resumed.request, [snapshot("replaced", 9)]));
      socket.frame(chunk(attach, [output("retired socket", 10)]));
      const resizeRequest = fixture.nextRequest();
      const resize = terminal.resize(70, 23);
      const resized = await resizeRequest;
      NodeAssert.equal(resized.socket, resumed.socket);
      resized.socket.frame(exit(resized.request));
      await resize;
      NodeAssert.deepEqual(
        updates.map((item) => item.history ?? item.data),
        ["initial", "one", "two", "replaced"],
      );
      NodeAssert.deepEqual(fixture.opened, [
        "wss://fixture.example.test/ws?wsTicket=single-use-1",
        "wss://fixture.example.test/ws?wsTicket=single-use-2",
      ]);
      NodeAssert.equal(
        fixture.requests.filter(({ request }) => request.tag === WS_METHODS.terminalWrite).length,
        1,
      );
    } finally {
      terminal.dispose();
    }
  },
);

NodeTest.test("a large paste stops when the server replaces the shell mid-write", async () => {
  const { ThreadTerminalConnection } = await connection;
  const fixture = transport();
  const terminal = new ThreadTerminalConnection(
    fixture.address,
    () => true,
    target,
    () => {},
    (error) => NodeAssert.fail(error.message),
  );
  try {
    const opened = fixture.nextRequest();
    terminal.start();
    const { request: attach, socket } = await opened;
    socket.frame(chunk(attach, [snapshot("initial")]));
    const firstWrite = fixture.nextRequest();
    const paste = terminal.write("a".repeat(65535) + "😀more");
    void paste.catch(() => {});
    const firstChunk = await firstWrite;
    NodeAssert.equal(firstChunk.request.payload.data.length, 65535);
    socket.frame(
      chunk(attach, [
        encodeEvent({
          ...session,
          type: "restarted",
          sequence: 6,
          snapshot: { ...baseSnapshot, history: "new process", pid: 456, sequence: 6 },
        }),
      ]),
    );
    socket.frame(exit(firstChunk.request));
    await Promise.resolve();
    NodeAssert.equal(
      fixture.requests.filter(({ request }) => request.tag === WS_METHODS.terminalWrite).length,
      1,
    );
    await NodeAssert.rejects(paste);
  } finally {
    terminal.dispose();
  }
});

NodeTest.test(
  "uses read-only observe and terminal metadata without constructing a shell",
  async () => {
    const { ThreadTerminalConnection, readThreadTerminals } = await connection;
    const fixture = transport();
    const metadataRequest = fixture.nextRequest();
    const list = readThreadTerminals(fixture.address, () => true, session.threadId);
    const listing = await metadataRequest;
    NodeAssert.equal(listing.request.tag, WS_METHODS.subscribeTerminalMetadata);
    NodeAssert.deepEqual(listing.request.payload, {});
    const summary = { ...baseSnapshot, hasRunningSubprocess: false };
    listing.socket.frame(
      chunk(listing.request, [
        encodeMetadata({
          type: "snapshot",
          managerId: "test-manager",
          terminals: [summary, { ...summary, threadId: "another-thread" }],
        }),
      ]),
    );
    NodeAssert.deepEqual(
      (await list).map(({ terminalId }) => terminalId),
      [session.terminalId],
    );
    const updates = [];
    const terminal = new ThreadTerminalConnection(
      fixture.address,
      () => true,
      { ...target, operate: false },
      (update) => updates.push(update),
      (error) => NodeAssert.fail(error.message),
    );
    try {
      const observeRequest = fixture.nextRequest();
      terminal.start();
      const observed = await observeRequest;
      NodeAssert.deepEqual(observed.request.payload, session);
      NodeAssert.equal(observed.request.tag, WS_METHODS.terminalObserve);
      observed.socket.frame(chunk(observed.request, [snapshot("observed")]));
      await NodeAssert.rejects(terminal.write("blocked"));
      NodeAssert.deepEqual(
        updates.map((item) => item.history),
        ["observed"],
      );
      NodeAssert.equal(
        fixture.requests.filter(({ request }) => request._tag === "Request").length,
        2,
      );
    } finally {
      terminal.dispose();
    }
  },
);

NodeTest.test("abandons pending tickets when the environment changes", async () => {
  const { ThreadTerminalConnection } = await connection;
  const fixture = transport();
  const ticket = Promise.withResolvers();
  let current = true;
  const terminal = new ThreadTerminalConnection(
    () => ticket.promise,
    () => current,
    target,
    () => NodeAssert.fail("Stale output reached the previous task"),
    () => {},
  );
  try {
    terminal.start();
    current = false;
    ticket.resolve("wss://fixture.example.test/ws?wsTicket=retired");
    await ticket.promise;
    NodeAssert.deepEqual(fixture.opened, []);
    await NodeAssert.rejects(terminal.resize(80, 24));
  } finally {
    terminal.dispose();
  }
});
