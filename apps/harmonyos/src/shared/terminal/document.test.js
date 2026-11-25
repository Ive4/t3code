import * as NodeVM from "node:vm";
import { expect, it } from "vite-plus/test";
import { buildTerminalDocument } from "../../../scripts/terminal-document.cjs";

it("packages the pinned VT engine and its PTY trampoline inside a network-isolated document", async () => {
  const html = await buildTerminalDocument();
  expect(html).toContain("connect-src data:");
  expect(html).toContain("default-src 'none'");
  expect(html.match(/data:application\/wasm;base64,/g)).toHaveLength(2);
  expect(html).not.toMatch(/<script[^>]+src=/i);
});

it("returns live terminal reports without responding during replay or in a read-only terminal", async () => {
  const html = await buildTerminalDocument();
  const messages = [];
  const canvas = {
    addEventListener() {},
    getContext: () => ({ fillStyle: "#000000" }),
  };
  const input = { addEventListener() {} };
  const window = {
    ReactNativeWebView: { postMessage: (value) => messages.push(JSON.parse(value)) },
  };
  NodeVM.runInNewContext(html.match(/<script>(.*)<\/script>/s)[1], {
    document: {
      body: { style: {}, addEventListener() {} },
      querySelector: (tag) => (tag === "canvas" ? canvas : input),
    },
    fetch,
    ResizeObserver: class {
      observe() {}
    },
    requestAnimationFrame() {},
    TextDecoder,
    TextEncoder,
    window,
  });

  const config = {
    readOnly: false,
    palette: [],
    foregroundColor: "#ffffff",
    backgroundColor: "#000000",
    cursor: "#ffffff",
  };
  await window.terminalCommand({ type: "configure", config });
  await window.terminalCommand({ type: "write", data: "\x1b[6n", reset: true, id: 1 });
  await window.terminalCommand({ type: "write", data: "\x1b[6n", reset: false, id: 2 });
  await window.terminalCommand({ type: "configure", config: { ...config, readOnly: true } });
  await window.terminalCommand({ type: "write", data: "\x1b[6n", reset: false, id: 3 });

  expect(messages).toEqual([
    { type: "ready" },
    { type: "written", id: 1 },
    { type: "input", data: "\x1b[1;1R" },
    { type: "written", id: 2 },
    { type: "written", id: 3 },
  ]);
});

it("copies a dragged multiline selection and all scrollback from a read-only terminal", async () => {
  const html = await buildTerminalDocument();
  const messages = [];
  const frames = [];
  let longPress;
  let focusRequests = 0;
  const element = () => {
    const listeners = new Map();
    return {
      style: {},
      hidden: true,
      addEventListener: (type, listener) => listeners.set(type, listener),
      dispatch: (type, event) => listeners.get(type)?.(event),
    };
  };
  const canvas = {
    ...element(),
    clientWidth: 164,
    clientHeight: 52,
    getBoundingClientRect: () => ({ left: 0, top: 0 }),
    getContext: () => context,
    setPointerCapture() {},
  };
  const context = new Proxy(
    {
      canvas,
      fillStyle: "#000000",
      getTransform: () => ({ a: 1, d: 1 }),
      measureText: () => ({ width: 8, actualBoundingBoxAscent: 10, actualBoundingBoxDescent: 2 }),
    },
    { get: (target, name) => target[name] ?? (() => {}) },
  );
  const input = { ...element(), blur() {}, focus: () => focusRequests++ };
  const toolbar = { ...element(), offsetHeight: 44 };
  const start = element();
  const end = element();
  const copy = element();
  const selectAll = element();
  const elements = {
    canvas,
    textarea: input,
    "#selection-actions": toolbar,
    "#selection-start": start,
    "#selection-end": end,
    "#selection-copy": copy,
    "#selection-all": selectAll,
  };
  const window = {
    ReactNativeWebView: { postMessage: (value) => messages.push(JSON.parse(value)) },
  };
  NodeVM.runInNewContext(html.match(/<script>(.*)<\/script>/s)[1], {
    document: { body: element(), querySelector: (selector) => elements[selector] },
    fetch,
    ResizeObserver: class {
      observe() {}
    },
    requestAnimationFrame: (callback) => frames.push(callback),
    setTimeout: (callback) => {
      longPress = callback;
      return 1;
    },
    clearTimeout: () => {
      longPress = undefined;
    },
    TextDecoder,
    TextEncoder,
    window,
  });

  const config = {
    readOnly: false,
    fontSize: 12,
    sharedGrid: [],
    palette: [],
    foregroundColor: "#ffffff",
    backgroundColor: "#000000",
    cursor: "#ffffff",
    copyLabel: "Copy",
    selectAllLabel: "Select all",
  };
  await window.terminalCommand({ type: "configure", config });
  const output = "old line\r\nleft 漢字\r\nnext row\r\nlast line";
  await window.terminalCommand({ type: "write", data: output, reset: true, id: 1 });
  frames.shift()();
  const pointer = (clientX, clientY) => ({
    button: 0,
    isPrimary: true,
    pointerId: 1,
    clientX,
    clientY,
    preventDefault() {},
  });
  canvas.dispatch("pointerdown", pointer(100, 10));
  canvas.dispatch("pointerup", pointer(100, 10));
  canvas.dispatch("click");
  expect(focusRequests).toBe(1);

  const swipe = (from, to) => {
    canvas.dispatch("pointerdown", pointer(100, from));
    canvas.dispatch("pointermove", pointer(100, to));
    canvas.dispatch("pointerup", pointer(100, to));
    canvas.dispatch("click");
    frames.shift()();
  };
  swipe(10, 26);
  expect(longPress).toBeUndefined();
  expect(focusRequests).toBe(1);
  await window.terminalCommand({ type: "capture" });
  expect(messages.at(-1)?.data).toMatch(/^old line\n/);
  swipe(26, 10);

  await window.terminalCommand({ type: "configure", config: { ...config, readOnly: true } });
  frames.shift()();
  const holdWord = () => {
    canvas.dispatch("pointerdown", pointer(54, 10));
    expect(longPress).toBeTypeOf("function");
    longPress();
    canvas.dispatch("pointerup", pointer(54, 10));
    frames.shift()();
  };
  holdWord();
  expect(toolbar.hidden).toBe(false);
  const handleX = Number.parseFloat(end.style.left);
  const handleY = Number.parseFloat(end.style.top);
  end.dispatch("pointerdown", pointer(handleX, handleY));
  canvas.dispatch("pointermove", pointer(handleX - 24, handleY + 16));
  canvas.dispatch("pointerup", pointer(handleX - 24, handleY + 16));
  copy.dispatch("click");
  expect(messages.at(-1)).toEqual({ type: "copy", data: "漢字\nnext" });

  holdWord();
  selectAll.dispatch("click");
  copy.dispatch("click");
  expect(messages.at(-1)).toEqual({ type: "copy", data: output.replaceAll("\r", "") });
});
