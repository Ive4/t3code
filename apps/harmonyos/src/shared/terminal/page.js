import { GHOSTTY_CELL_WIDE, GhosttyTerminalCore } from "../../../../web/src/terminal/ghostty/core";
import {
  measureGhosttyCell,
  renderGhosttySnapshot,
  terminalGridSize,
} from "../../../../web/src/terminal/ghostty/renderer";

const canvas = document.querySelector("canvas");
const input = document.querySelector("textarea");
const selectionActions = document.querySelector("#selection-actions");
const copyButton = document.querySelector("#selection-copy");
const selectAllButton = document.querySelector("#selection-all");
const handles = {
  start: document.querySelector("#selection-start"),
  end: document.querySelector("#selection-end"),
};
const context = canvas.getContext("2d");
const post = (event) => {
  const message =
    config?.arktsBridge && config.epoch != null ? { ...event, epoch: config.epoch } : event;
  // oxlint-disable-next-line unicorn/require-post-message-target-origin -- the native ArkWeb proxy accepts one serialized message
  window.ReactNativeWebView.postMessage(JSON.stringify(message));
};
const padding = 2;
let core;
let config;
let metrics;
let grid;
let viewportGrid;
let rowsOnCanvas = [];
let scheduled = false;
let fullRender = true;
let previousCursorY = null;
let selectionActive = false;
let gesture;
let holdTimer;
let suppressTap = false;
let replaying = false;

function color(css) {
  context.fillStyle = css;
  const hex = context.fillStyle.slice(1);
  return {
    r: parseInt(hex.slice(0, 2), 16),
    g: parseInt(hex.slice(2, 4), 16),
    b: parseInt(hex.slice(4, 6), 16),
  };
}

function theme() {
  return {
    foreground: color(config.foregroundColor),
    background: color(config.backgroundColor),
    cursor: color(config.cursor),
    palette: config.palette.map(color),
  };
}

function draw() {
  if (scheduled || !core) return;
  scheduled = true;
  requestAnimationFrame(() => {
    scheduled = false;
    const snapshot = core.snapshot();
    rowsOnCanvas = snapshot.rowData;
    renderGhosttySnapshot({
      context,
      snapshot,
      metrics,
      fontSize: config.fontSize,
      fontFamily: "monospace",
      padding,
      forceFull: fullRender,
      cursorOn: true,
      previousCursorY,
    });
    updateSelectionControls();
    previousCursorY = snapshot.cursorY;
    fullRender = false;
  });
}

function layout() {
  if (!core) return;
  const width = canvas.clientWidth;
  const height = canvas.clientHeight;
  if (!width || !height) return;
  const scale = window.devicePixelRatio || 1;
  canvas.width = Math.round(width * scale);
  canvas.height = Math.round(height * scale);
  context.scale(scale, scale);
  metrics = measureGhosttyCell(context, config.fontSize, "monospace");
  const measured = terminalGridSize(width, height, metrics, padding);
  const cols = Math.min(400, measured.cols),
    rows = Math.min(200, measured.rows);
  viewportGrid = {
    cols: Math.min(cols, config.sharedGrid[0] || cols),
    rows: Math.min(rows, config.sharedGrid[1] || rows),
  };
  core.resize(viewportGrid.cols, viewportGrid.rows, metrics.width, metrics.height);
  if (!grid || grid.cols !== cols || grid.rows !== rows) {
    grid = { cols, rows };
    post({ type: "resize", cols, rows });
  }
  fullRender = true;
  draw();
}

function send(data) {
  if (!config.readOnly && data) post({ type: "input", data });
}

function respond(data) {
  if (!config.arktsBridge) {
    send(data);
  } else if (!replaying && !config.readOnly && data) {
    post({ type: "input", data, reply: true });
  }
}

function compareCells(a, b) {
  return a.y - b.y || a.x - b.x;
}

function selectionRange() {
  const range = selectionActive ? core.selectionRange() : null;
  if (!range || compareCells(range.start, range.end) <= 0) return range;
  return { start: range.end, end: range.start };
}

function isWideTail(x, y) {
  return rowsOnCanvas[y]?.cells[x]?.wide === GHOSTTY_CELL_WIDE.spacerTail;
}

function setSelection(anchor, extent) {
  const forward = compareCells(anchor, extent) <= 0;
  const start = forward ? anchor : extent;
  const end = forward ? extent : anchor;
  const first = core.screenPointToViewport(start.x, start.y);
  const last = core.screenPointToViewport(end.x, end.y);
  const startX = first && isWideTail(first.x, first.y) ? start.x - 1 : start.x;
  const endX = last && isWideTail(last.x + 1, last.y) ? end.x + 1 : end.x;
  core.setSelection({ x: startX, y: start.y, tag: 2 }, { x: endX, y: end.y, tag: 2 });
}

function updateSelectionControls() {
  const range = selectionRange();
  selectionActive = Boolean(range);
  const start = range && core.screenPointToViewport(range.start.x, range.start.y);
  const end = range && core.screenPointToViewport(range.end.x, range.end.y);
  for (const [edge, cell] of [
    ["start", start],
    ["end", end],
  ]) {
    const handle = handles[edge];
    handle.hidden = !cell;
    if (!cell) continue;
    const x = padding + (cell.x + (edge === "end" ? 1 : 0)) * metrics.width;
    const y = padding + (cell.y + 1) * metrics.height;
    handle.style.left = `${Math.min(canvas.clientWidth - 8, Math.max(8, x))}px`;
    handle.style.top = `${Math.min(canvas.clientHeight - 8, y + 8)}px`;
  }
  selectionActions.hidden = !range || gesture?.kind === "word" || gesture?.kind === "handle";
  if (selectionActions.hidden) return;
  const above = padding + (start?.y ?? 0) * metrics.height - selectionActions.offsetHeight - 4;
  const below = padding + ((end?.y ?? viewportGrid.rows - 1) + 1) * metrics.height + 22;
  const maxTop = Math.max(0, canvas.clientHeight - selectionActions.offsetHeight);
  selectionActions.style.top = `${above >= 0 ? above : Math.min(below, maxTop)}px`;
}

function redrawAll() {
  fullRender = true;
  draw();
}

function clearSelection() {
  core.clearSelection();
  selectionActive = false;
  redrawAll();
}

function cellAt(clientX, clientY) {
  const bounds = canvas.getBoundingClientRect();
  const x = Math.floor((clientX - bounds.left - padding) / metrics.width);
  const y = Math.floor((clientY - bounds.top - padding) / metrics.height);
  return {
    x: Math.min(viewportGrid.cols - 1, Math.max(0, x)),
    y: Math.min(viewportGrid.rows - 1, Math.max(0, y)),
  };
}

function startGesture(event, edge) {
  if (!event.isPrimary || event.button !== 0 || !viewportGrid || gesture) return;
  const { clientX, clientY, pointerId } = event;
  canvas.setPointerCapture(pointerId);
  suppressTap = Boolean(edge);
  if (edge) {
    const range = selectionRange();
    const cell = range?.[edge];
    const viewport = cell && core.screenPointToViewport(cell.x, cell.y);
    if (!viewport) return;
    const bounds = canvas.getBoundingClientRect();
    gesture = {
      kind: "handle",
      pointerId,
      fixedEdge: edge === "start" ? "end" : "start",
      offsetX: clientX - bounds.left - padding - (viewport.x + 0.5) * metrics.width,
      offsetY: clientY - bounds.top - padding - (viewport.y + 0.5) * metrics.height,
      cell: viewport,
    };
    draw();
    return;
  }
  gesture = { kind: "pending", pointerId, clientX, clientY, scrollY: clientY };
  if (event.pointerType === "mouse") return;
  holdTimer = setTimeout(() => {
    const cell = cellAt(clientX, clientY);
    core.clearSelection();
    core.selectWord(cell.x - Number(isWideTail(cell.x, cell.y)), cell.y);
    selectionActive = true;
    const base = selectionRange();
    selectionActive = Boolean(base);
    suppressTap = true;
    if (base) {
      setSelection(base.start, base.end);
      gesture = {
        kind: "word",
        pointerId,
        base,
        cell,
        fixedEdge: "start",
        anchorRow: base.start.y,
        offsetX: 0,
        offsetY: 0,
      };
      input.blur();
    }
    redrawAll();
  }, 500);
}

function extendSelection(event, drag) {
  const cell = cellAt(event.clientX - drag.offsetX, event.clientY - drag.offsetY);
  if (compareCells(cell, drag.cell) === 0) return;
  const range = selectionRange();
  const end = core.viewportPointToScreen(cell.x, cell.y);
  if (!range || !end) return;
  let anchor = range[drag.fixedEdge];
  if (drag.kind === "word") {
    const rowShift = anchor.y - drag.anchorRow;
    drag.base.start.y += rowShift;
    drag.base.end.y += rowShift;
    anchor = compareCells(end, drag.base.start) < 0 ? drag.base.end : drag.base.start;
    drag.anchorRow = anchor.y;
  }
  setSelection(anchor, end);
  drag.cell = cell;
  drag.fixedEdge = compareCells(anchor, end) <= 0 ? "start" : "end";
  redrawAll();
}

canvas.addEventListener("pointerdown", (event) => startGesture(event));
canvas.addEventListener("pointermove", (event) => {
  if (gesture?.pointerId !== event.pointerId) return;
  if (gesture.kind === "word" || gesture.kind === "handle") {
    extendSelection(event, gesture);
    return;
  }
  if (gesture.kind === "pending") {
    if (Math.hypot(event.clientX - gesture.clientX, event.clientY - gesture.clientY) < 8) return;
    clearTimeout(holdTimer);
    gesture.kind = "scroll";
    suppressTap = true;
  }
  const delta = Math.trunc((gesture.scrollY - event.clientY) / metrics.height);
  if (!delta) return;
  gesture.scrollY -= delta * metrics.height;
  core.scroll(delta);
  redrawAll();
});

function finishGesture(event) {
  if (gesture?.pointerId !== event.pointerId) return;
  clearTimeout(holdTimer);
  gesture = undefined;
  if (selectionActive) draw();
}

canvas.addEventListener("pointerup", finishGesture);
canvas.addEventListener("pointercancel", finishGesture);
canvas.addEventListener("lostpointercapture", finishGesture);
canvas.addEventListener("click", () => {
  if (suppressTap) return;
  if (selectionActive) {
    clearSelection();
    return;
  }
  if (!config?.readOnly) input.focus();
});
for (const [edge, handle] of Object.entries(handles)) {
  handle.addEventListener("pointerdown", (event) => {
    const other = edge === "start" ? "end" : "start";
    const bounds = canvas.getBoundingClientRect();
    const distance = (control) =>
      Math.hypot(
        event.clientX - bounds.left - parseFloat(control.style.left),
        event.clientY - bounds.top - parseFloat(control.style.top),
      );
    // Choose the nearest endpoint when the touch targets overlap on short words.
    const nearest =
      !handles[other].hidden && distance(handles[other]) < distance(handle) ? other : edge;
    startGesture(event, nearest);
  });
}
document.body.addEventListener("contextmenu", (event) => event.preventDefault());
copyButton.addEventListener("click", () => {
  const data = core.selectionText();
  if (data) post({ type: "copy", data });
  clearSelection();
});
selectAllButton.addEventListener("click", () => {
  if (core.selectAll()) redrawAll();
});
input.addEventListener("keydown", (event) => {
  if (!core || event.isComposing || event.keyCode === 229) return;
  if (
    ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "v") ||
    (event.shiftKey && event.key === "Insert")
  )
    return;
  if ([...event.key].length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) return;
  const data = core.encodeKey(event);
  if (data) {
    event.preventDefault();
    send(data);
  }
});
let compositionCommit = "";
input.addEventListener("compositionstart", () => {
  compositionCommit = "";
});
input.addEventListener("input", (event) => {
  if (event.isComposing) return;
  if (
    !compositionCommit ||
    event.inputType !== "insertFromComposition" ||
    input.value !== compositionCommit
  )
    send(input.value);
  compositionCommit = "";
  input.value = "";
});
input.addEventListener("compositionend", (event) => {
  compositionCommit = input.value || event.data;
  send(compositionCommit);
  input.value = "";
});
input.addEventListener("beforeinput", (event) => {
  if (event.inputType === "insertLineBreak" || event.inputType === "deleteContentBackward") {
    event.preventDefault();
    send(event.inputType === "insertLineBreak" ? "\r" : "\x7f");
  }
});
input.addEventListener("paste", (event) => {
  event.preventDefault();
  const data = event.clipboardData?.getData("text/plain");
  if (!config.readOnly && data) post({ type: "paste", data });
});
new ResizeObserver(layout).observe(canvas);
window.terminalCommand = async (command) => {
  try {
    switch (command.type) {
      case "configure": {
        config = command.config;
        input.readOnly = config.readOnly;
        document.body.style.background = config.backgroundColor;
        document.body.style.colorScheme = config.appearanceScheme;
        copyButton.textContent = config.copyLabel;
        selectAllButton.textContent = config.selectAllLabel;
        if (!core) {
          core = await GhosttyTerminalCore.create(80, 24, 8, 16, theme(), respond);
          post({ type: "ready" });
        } else core.setTheme(theme());
        layout();
        break;
      }
      case "write":
        replaying = config.arktsBridge && command.replay;
        try {
          if (command.reset) {
            if (selectionActive) clearSelection();
            core.resetAndWrite(command.data);
          } else core.write(command.data);
        } finally {
          replaying = false;
        }
        draw();
        post({ type: "written", id: command.id });
        break;
      case "focus":
        if (!config.readOnly) input.focus();
        break;
      case "key":
        if (config.arktsBridge && !config.readOnly) {
          input.value = "";
          send(
            core.encodeKey(
              new KeyboardEvent("keydown", {
                key: command.key,
                code: command.code ?? command.key,
                ctrlKey: command.ctrlKey,
              }),
            ),
          );
        }
        break;
      case "paste":
        if (config.arktsBridge && !config.readOnly) {
          input.value = "";
          send(core.encodePaste(command.data));
        }
        break;
      case "resetInput":
        input.value = "";
        break;
      case "capture": {
        const text = core
          .snapshot()
          .rowData.map((row) => row.text.trimEnd())
          .join("\n")
          .trimEnd();
        fullRender = true;
        draw();
        post({ type: "capture", id: command.id, data: text });
        break;
      }
    }
  } catch {
    post({ type: "failed" });
  }
};
