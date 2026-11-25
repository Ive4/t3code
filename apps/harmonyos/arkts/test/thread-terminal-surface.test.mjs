import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import * as NodeVM from "node:vm";
import { buildTerminalDocument } from "../../scripts/terminal-document.cjs";

const outputSource = new URL(
  "../entry/src/main/ets/pages/ThreadTerminalOutput.ets",
  import.meta.url,
);
const rawfile = new URL(
  "../entry/src/main/resources/rawfile/thread-terminal.html",
  import.meta.url,
);
const loader = NodeModule.registerHooks({
  load(url, context, nextLoad) {
    if (url !== outputSource.href) return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(outputSource, "utf8")),
    };
  },
});
const outputModule = import(outputSource.href);
void outputModule.catch(() => {});
NodeTest.after(() => loader.deregister());

NodeTest.test(
  "replays a terminal snapshot once and drains concurrent live output in order",
  async () => {
    const { ThreadTerminalOutput, TERMINAL_RENDER_CHUNK } = await outputModule;
    const output = new ThreadTerminalOutput();
    const history = "x".repeat(TERMINAL_RENDER_CHUNK - 1) + "😀 end";
    let notifications = 0;
    const stop = output.subscribe(() => notifications++);
    output.reset(history);
    const first = output.read();
    NodeAssert.equal(first.data, "x".repeat(TERMINAL_RENDER_CHUNK - 1));
    NodeAssert.equal(first.reset, true);
    NodeAssert.equal(first.replay, true);
    NodeAssert.equal(output.isSnapshotRendered(first.cursor), false);
    output.append("\x1b[6n");
    const second = output.read(first.cursor);
    NodeAssert.equal(second.data, "😀 end");
    NodeAssert.equal(second.reset, false);
    NodeAssert.equal(second.replay, true);
    NodeAssert.equal(output.isSnapshotRendered(second.cursor), true);
    const third = output.read(second.cursor);
    NodeAssert.equal(third.data, "\x1b[6n");
    NodeAssert.equal(third.reset, false);
    NodeAssert.equal(third.replay, false);
    NodeAssert.equal(output.read(third.cursor), undefined);
    stop();
    output.reset("");
    NodeAssert.equal(notifications, 2);
    NodeAssert.equal(output.isSnapshotRendered(third.cursor), false);
    const clear = output.read(third.cursor);
    NodeAssert.equal(clear.reset, true);
    NodeAssert.equal(clear.data, "");
  },
);

NodeTest.test(
  "recovers the retained tail for a slow renderer and replays live bytes on remount",
  async () => {
    const { ThreadTerminalOutput, TERMINAL_RENDER_HISTORY } = await outputModule;
    const output = new ThreadTerminalOutput();
    const initial = output.read();
    output.append("x".repeat(TERMINAL_RENDER_HISTORY) + "😀\r\nlast");
    const recovered = output.read(initial.cursor);
    NodeAssert.equal(recovered.reset, true);
    NodeAssert.equal(recovered.replay, true);
    let frame = recovered;
    let rendered = frame.data;
    while ((frame = output.read(frame.cursor))) {
      NodeAssert.equal(frame.replay, true);
      rendered += frame.data;
    }
    NodeAssert.equal(rendered.length, TERMINAL_RENDER_HISTORY);
    NodeAssert.ok(rendered.endsWith("😀\r\nlast"));
    NodeAssert.equal(output.read().replay, true);
  },
);

NodeTest.test("accepts only the supported data from the local terminal bridge", async () => {
  const { readThreadTerminalMessage } = await outputModule;
  NodeAssert.equal(readThreadTerminalMessage("{"), undefined);
  NodeAssert.equal(readThreadTerminalMessage('{"type":"resize","cols":-1,"rows":80}'), undefined);
  NodeAssert.equal(readThreadTerminalMessage('{"type":"input","data":123}'), undefined);
  NodeAssert.deepEqual(
    readThreadTerminalMessage('{"type":"input","data":"\\u0003","reply":true}'),
    { type: "input", data: "\u0003", reply: true },
  );
  NodeAssert.deepEqual(readThreadTerminalMessage('{"type":"resize","cols":120,"rows":36}'), {
    type: "resize",
    cols: 120,
    rows: 36,
  });
  NodeAssert.equal(readThreadTerminalMessage('{"type":"capture","data":"text"}'), undefined);
  NodeAssert.deepEqual(readThreadTerminalMessage('{"type":"capture","id":2,"epoch":7,"data":""}'), {
    type: "capture",
    id: 2,
    epoch: 7,
    data: "",
  });
});

NodeTest.test(
  "serializes the selected visible lines as an Android-compatible context",
  async () => {
    const {
      threadTerminalCaptureLines,
      threadTerminalSelectionText,
      threadTerminalContextRecord,
      threadTerminalContextReference,
      THREAD_TERMINAL_CONTEXT_MAX_CHARS,
    } = await outputModule;
    const lines = threadTerminalCaptureLines("previous\n汉字\n\n  error\n\n");
    NodeAssert.deepEqual(lines, ["previous", "汉字", "", "  error"]);
    NodeAssert.equal(threadTerminalCaptureLines("line\n".repeat(501)), undefined);
    NodeAssert.equal(threadTerminalCaptureLines("a".repeat(512 * 1024 + 1)), undefined);
    const selection = {
      terminalId: "term-scripts",
      terminalLabel: "Shell [test]",
      lineStart: 2,
      lineEnd: 4,
      text: threadTerminalSelectionText(lines, 2, 4),
    };
    const record = threadTerminalContextRecord("selection-id", selection);
    NodeAssert.deepEqual(record, {
      version: 1,
      kind: "terminal",
      contextId: "selection-id",
      terminalId: "term-scripts",
      terminalLabel: "Shell [test] (visible output)",
      label: "Shell [test] · visible lines 2–4",
      lineStart: 2,
      lineEnd: 4,
      text: "汉字\n\n  error",
    });
    NodeAssert.equal(
      threadTerminalContextReference(record),
      "[Shell test · visible lines 2–4](t3-context://v1/terminal/selection-id)",
    );
    NodeAssert.equal(threadTerminalSelectionText(lines, 0, 1), "");
    NodeAssert.equal(threadTerminalSelectionText(lines, 4, 2), "");
    NodeAssert.throws(() =>
      threadTerminalContextRecord("selection-id", { ...selection, text: "\n " }),
    );
    NodeAssert.throws(() =>
      threadTerminalContextRecord("selection-id", {
        ...selection,
        text: "字".repeat(THREAD_TERMINAL_CONTEXT_MAX_CHARS + 1),
      }),
    );
  },
);

NodeTest.test(
  "ships a reproducible offline Ghostty document for the native ArkWeb component",
  async () => {
    const html = await buildTerminalDocument();
    NodeAssert.equal(NodeFS.readFileSync(rawfile, "utf8"), html);
    NodeAssert.ok(html.includes("default-src 'none'"));
    NodeAssert.doesNotMatch(html, /<script[^>]+src=/i);
  },
);

NodeTest.test(
  "separates live PTY replies from keys and suppresses replies across replay chunks",
  async () => {
    const html = await buildTerminalDocument();
    const messages = [];
    const element = { addEventListener() {} };
    const canvas = { ...element, getContext: () => ({ fillStyle: "#000000" }) };
    const window = {
      ReactNativeWebView: { postMessage: (value) => messages.push(JSON.parse(value)) },
    };
    NodeVM.runInNewContext(html.match(/<script>(.*)<\/script>/s)[1], {
      document: {
        body: { ...element, style: {} },
        querySelector: (selector) => (selector === "canvas" ? canvas : element),
      },
      fetch,
      TextDecoder,
      TextEncoder,
      window,
      navigator: { platform: "Linux" },
      KeyboardEvent: class {
        constructor(_type, event) {
          Object.assign(this, event);
        }
        getModifierState() {
          return false;
        }
      },
      ResizeObserver: class {
        observe() {}
      },
      requestAnimationFrame() {},
    });
    const config = {
      arktsBridge: true,
      readOnly: false,
      palette: [],
      foregroundColor: "#ffffff",
      backgroundColor: "#000000",
      cursor: "#ffffff",
    };
    await window.terminalCommand({ type: "configure", config });
    await window.terminalCommand({
      type: "write",
      data: "\x1b[",
      reset: true,
      replay: true,
      id: 1,
    });
    await window.terminalCommand({ type: "write", data: "6n", replay: true, id: 2 });
    await window.terminalCommand({ type: "write", data: "\x1b[6n\x1b[?1h\x1b[?2004h", id: 3 });
    await window.terminalCommand({ type: "key", key: "ArrowUp" });
    await window.terminalCommand({ type: "key", key: "c", code: "KeyC", ctrlKey: true });
    await window.terminalCommand({ type: "paste", data: "one\ntwo" });
    await window.terminalCommand({ type: "configure", config: { ...config, readOnly: true } });
    await window.terminalCommand({ type: "key", key: "ArrowUp" });
    await window.terminalCommand({ type: "paste", data: "blocked" });

    NodeAssert.deepEqual(messages, [
      { type: "ready" },
      { type: "written", id: 1 },
      { type: "written", id: 2 },
      { type: "input", data: "\x1b[1;1R", reply: true },
      { type: "written", id: 3 },
      { type: "input", data: "\x1bOA" },
      { type: "input", data: "\x03" },
      { type: "input", data: "\x1b[200~one\ntwo\x1b[201~" },
    ]);
    await window.terminalCommand({
      type: "configure",
      config: { ...config, epoch: 7, readOnly: true },
    });
    await window.terminalCommand({
      type: "write",
      reset: true,
      data: "one\r\n\r\n  \x1b[31mtwo\x1b[0m",
      id: 4,
    });
    await window.terminalCommand({ type: "capture", id: 3 });
    NodeAssert.deepEqual(messages.at(-1), {
      type: "capture",
      id: 3,
      epoch: 7,
      data: "one\n\n  two",
    });
  },
);
