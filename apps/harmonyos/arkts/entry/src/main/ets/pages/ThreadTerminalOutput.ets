export const TERMINAL_RENDER_CHUNK = 16 * 1024;
export const TERMINAL_RENDER_HISTORY = 512 * 1024;
export const THREAD_TERMINAL_CONTEXT_MAX_CHARS = 64_000;
const THREAD_TERMINAL_CAPTURE_MAX_ROWS = 500;

export interface ThreadTerminalOutputCursor {
  revision: number;
  position: number;
  replayUntil: number;
}

export interface ThreadTerminalOutputFrame {
  cursor: ThreadTerminalOutputCursor;
  data: string;
  reset: boolean;
  replay: boolean;
}

export class ThreadTerminalOutput {
  private revision: number = 0;
  private history: string = '';
  private start: number = 0;
  private end: number = 0;
  private snapshotEnd: number = 0;
  private listeners: Set<() => void> = new Set<() => void>();

  reset(history: string): void {
    this.revision++;
    this.end = history.length;
    this.snapshotEnd = this.end;
    this.retain(history);
    this.notify();
  }

  append(data: string): void {
    if (!data) return;
    this.end += data.length;
    this.retain(this.history + data);
    this.notify();
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  isSnapshotRendered(cursor?: ThreadTerminalOutputCursor): boolean {
    return cursor !== undefined && cursor.revision === this.revision && cursor.position >= cursor.replayUntil;
  }

  read(cursor?: ThreadTerminalOutputCursor): ThreadTerminalOutputFrame | undefined {
    const newRevision = cursor === undefined || cursor.revision !== this.revision;
    const missedOutput = cursor !== undefined && !newRevision && cursor.position < this.start;
    const reset = newRevision || missedOutput;
    const position = reset ? this.start : (cursor?.position ?? this.start);
    if (!reset && position >= this.end) return undefined;

    const replayUntil = cursor === undefined || missedOutput ? this.end :
      newRevision ? this.snapshotEnd : cursor.replayUntil;
    const replay = position < replayUntil;
    const limit = replay ? replayUntil : this.end;
    const start = position - this.start;
    let end = Math.min(limit - this.start, start + TERMINAL_RENDER_CHUNK);
    const last = this.history.charCodeAt(end - 1);
    if (end < this.history.length && last >= 0xd800 && last <= 0xdbff) end--;
    return {
      cursor: { revision: this.revision, position: this.start + end, replayUntil },
      data: this.history.slice(start, end),
      reset,
      replay,
    };
  }

  private retain(data: string): void {
    let offset = Math.max(0, data.length - TERMINAL_RENDER_HISTORY);
    const first = data.charCodeAt(offset);
    if (offset > 0 && first >= 0xdc00 && first <= 0xdfff) offset++;
    this.history = data.slice(offset);
    this.start = this.end - this.history.length;
  }

  private notify(): void {
    this.listeners.forEach((listener: () => void) => listener());
  }
}

export interface ThreadTerminalMessage {
  type: string;
  epoch?: number;
  id?: number;
  data?: string;
  reply?: boolean;
  cols?: number;
  rows?: number;
}

export interface ThreadTerminalAttachment {
  terminalId: string;
  terminalLabel: string;
  lineStart: number;
  lineEnd: number;
  text: string;
}

export interface ThreadTerminalContextRecord extends ThreadTerminalAttachment {
  version: 1;
  kind: 'terminal';
  contextId: string;
  label: string;
}

export function threadTerminalCaptureLines(text: string): string[] | undefined {
  if (text.length > TERMINAL_RENDER_HISTORY) return undefined;
  const lines = text.replace(/\n+$/, '').split('\n');
  return lines.length <= THREAD_TERMINAL_CAPTURE_MAX_ROWS ? lines : undefined;
}

export function threadTerminalSelectionText(lines: string[], start: number, end: number): string {
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 1 || end < start || end > lines.length) {
    return '';
  }
  return lines.slice(start - 1, end).join('\n');
}

export function threadTerminalContextRecord(contextId: string,
  selection: ThreadTerminalAttachment): ThreadTerminalContextRecord {
  if (!/^[a-z0-9_-]{1,128}$/i.test(contextId) || !selection.terminalId || selection.terminalId.length > 128 ||
    selection.terminalId.trim() !== selection.terminalId || !Number.isSafeInteger(selection.lineStart) ||
    !Number.isSafeInteger(selection.lineEnd) || selection.lineStart < 1 || selection.lineEnd < selection.lineStart ||
    selection.lineEnd > THREAD_TERMINAL_CAPTURE_MAX_ROWS || selection.terminalLabel.length > 128 ||
    !selection.text.trim() || selection.text.length > THREAD_TERMINAL_CONTEXT_MAX_CHARS) {
    throw new Error('选中的终端输出无效。');
  }
  const terminalLabel = selection.terminalLabel.trim() || selection.terminalId;
  return {
    version: 1, kind: 'terminal', contextId,
    terminalId: selection.terminalId, terminalLabel: `${terminalLabel} (visible output)`,
    label: `${terminalLabel} · visible lines ${selection.lineStart}–${selection.lineEnd}`,
    lineStart: selection.lineStart, lineEnd: selection.lineEnd, text: selection.text,
  };
}

export function threadTerminalContextReference(record: ThreadTerminalContextRecord): string {
  const label = record.label.replace(/[[\]\\\r\n]/g, ' ').replace(/\s+/g, ' ').trim();
  return `[${label}](t3-context://v1/terminal/${record.contextId})`;
}

export function readThreadTerminalMessage(serialized: string): ThreadTerminalMessage | undefined {
  try {
    const message = JSON.parse(serialized) as ThreadTerminalMessage | null;
    if (message === null) return undefined;
    switch (message.type) {
      case 'ready':
      case 'failed':
        return message;
      case 'written':
        return Number.isSafeInteger(message.id) ? message : undefined;
      case 'capture':
        return Number.isSafeInteger(message.id) && (message.id ?? 0) > 0 &&
          typeof message.data === 'string' ? message : undefined;
      case 'resize':
        return Number.isInteger(message.cols) && Number.isInteger(message.rows) &&
          (message.cols ?? 0) > 0 && (message.cols ?? 0) <= 400 &&
          (message.rows ?? 0) > 0 && (message.rows ?? 0) <= 200 ? message : undefined;
      case 'input':
      case 'copy':
      case 'paste':
        return typeof message.data === 'string' && message.data.length > 0 ? message : undefined;
      default:
        return undefined;
    }
  } catch (_) {
    return undefined;
  }
}
