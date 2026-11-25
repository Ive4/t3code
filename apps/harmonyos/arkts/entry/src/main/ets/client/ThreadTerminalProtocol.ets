export const DEFAULT_THREAD_TERMINAL_ID = 'term-1';
const MAX_HISTORY_BYTES = 512 * 1024;
const MAX_WRITE_LENGTH = 65536;
const SEQUENCE_GROUND = 0;
const SEQUENCE_ESCAPE = 1;
const SEQUENCE_ESCAPE_INTERMEDIATE = 2;
const SEQUENCE_CSI = 3;
const SEQUENCE_DCS = 4;
const SEQUENCE_SOS_PM_APC = 5;
const SEQUENCE_OSC = 6;

interface TerminalSession {
  threadId: string;
  terminalId: string;
}

export interface ThreadTerminalTarget extends TerminalSession {
  operate: boolean;
  cwd?: string;
  worktreePath?: string | null;
  cols?: number;
  rows?: number;
  resume?: boolean;
  restartIfNotRunning?: boolean;
}

export interface NativeThreadTerminalSummary extends TerminalSession {
  cwd: string;
  worktreePath: string | null;
  status: string;
  pid: number | null;
  exitCode: number | null;
  exitSignal: number | null;
  label: string;
  updatedAt: string;
  hasRunningSubprocess: boolean;
}

export interface NativeTerminalUpdate {
  kind: 'snapshot' | 'output' | 'cleared' | 'exited' | 'closed' | 'error' | 'activity';
  status: string;
  history?: string;
  data?: string;
  cols?: number;
  rows?: number;
  exitCode?: number | null;
  exitSignal?: number | null;
  message?: string;
  label?: string;
  hasRunningSubprocess?: boolean;
}

interface TerminalSnapshot extends TerminalSession {
  status: string;
  history: string;
  cols?: number;
  rows?: number;
  sequence?: number;
  exitCode: number | null;
  exitSignal: number | null;
  label: string;
  error?: string;
}

interface TerminalEvent extends TerminalSession {
  type: string;
  snapshot?: TerminalSnapshot;
  sequence?: number;
  data?: string;
  cols?: number;
  rows?: number;
  exitCode?: number | null;
  exitSignal?: number | null;
  message?: string;
  label?: string;
  hasRunningSubprocess?: boolean;
}

interface TerminalMetadataEvent {
  type: string;
  terminals?: NativeThreadTerminalSummary[];
}

interface TerminalAttachInput extends TerminalSession {
  cwd?: string;
  worktreePath?: string | null;
  cols?: number;
  rows?: number;
  resume?: boolean;
  restartIfNotRunning?: boolean;
  maxHistoryBytes: number;
}

interface TerminalWriteInput extends TerminalSession {
  data: string;
  binary?: boolean;
  reply?: boolean;
}

interface TerminalResizeInput extends TerminalSession {
  cols: number;
  rows: number;
}

interface TerminalCloseInput extends TerminalSession {
  deleteHistory?: boolean;
}

export interface ThreadTerminalRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: Object;
  headers: string[][];
}

function validId(value: string): boolean {
  return typeof value === 'string' && value.length > 0 && value.trim() === value && !value.includes('\0');
}

function validTerminalId(value: string): boolean {
  return validId(value) && value.length <= 128;
}

function validStatus(status: string): boolean {
  return status === 'starting' || status === 'running' || status === 'exited' || status === 'error';
}

function validExit(value: number | null | undefined): boolean {
  return value === null || Number.isSafeInteger(value);
}

function validSize(value: number | undefined, limit: number): boolean {
  return value !== undefined && Number.isSafeInteger(value) && value > 0 && value <= limit;
}

function validOptionalGrid(cols: number | undefined, rows: number | undefined): boolean {
  return (cols === undefined || validSize(cols, 1000)) && (rows === undefined || validSize(rows, 500));
}

function validSequence(value: number | undefined): boolean {
  return value === undefined || (Number.isSafeInteger(value) && value >= 0);
}

function sessionFor(target: ThreadTerminalTarget, writable: boolean = false): TerminalSession {
  if (!validId(target.threadId) || !validTerminalId(target.terminalId)) throw new Error('任务终端标识无效。');
  if (writable && !target.operate) throw new Error('此连接只有读取终端的权限。');
  return { threadId: target.threadId, terminalId: target.terminalId };
}

function request(id: string, tag: string, payload: Object): ThreadTerminalRequest {
  return { _tag: 'Request', id, tag, payload, headers: [] };
}

export function threadTerminalStreamRequest(id: string, target: ThreadTerminalTarget,
  reconnect: boolean): ThreadTerminalRequest {
  const session = sessionFor(target);
  if (!target.operate) return request(id, 'terminal.observe', session);
  if ((target.cwd !== undefined && !validId(target.cwd)) ||
    (target.worktreePath !== undefined && target.worktreePath !== null && !validId(target.worktreePath)) ||
    !validOptionalGrid(target.cols, target.rows)) {
    throw new Error('任务终端的工作目录或尺寸无效。');
  }
  const payload: TerminalAttachInput = {
    threadId: session.threadId, terminalId: session.terminalId, cwd: target.cwd, worktreePath: target.worktreePath,
    cols: target.cols, rows: target.rows, maxHistoryBytes: MAX_HISTORY_BYTES,
    resume: reconnect ? true : target.resume,
    restartIfNotRunning: reconnect || target.resume ? undefined : target.restartIfNotRunning,
  };
  return request(id, 'terminal.attach', payload);
}

export function threadTerminalWriteRequest(id: string, target: ThreadTerminalTarget, data: string,
  binary?: boolean, reply?: boolean): ThreadTerminalRequest {
  const session = sessionFor(target, true);
  if (data.length === 0 || data.length > MAX_WRITE_LENGTH) throw new Error('终端输入长度无效。');
  const payload: TerminalWriteInput = { threadId: session.threadId, terminalId: session.terminalId, data, binary, reply };
  return request(id, 'terminal.write', payload);
}

export function chunkThreadTerminalWrite(data: string): string[] {
  if (data.length === 0) throw new Error('终端输入长度无效。');
  const chunks: string[] = [];
  let start = 0;
  while (start < data.length) {
    let end = Math.min(start + MAX_WRITE_LENGTH, data.length);
    const last = data.charCodeAt(end - 1);
    if (end < data.length && last >= 0xd800 && last <= 0xdbff) end--;
    chunks.push(data.slice(start, end));
    start = end;
  }
  return chunks;
}

export function threadTerminalResizeRequest(id: string, target: ThreadTerminalTarget, cols: number,
  rows: number): ThreadTerminalRequest {
  const session = sessionFor(target, true);
  if (!validSize(cols, 1000) || !validSize(rows, 500)) throw new Error('终端尺寸无效。');
  const payload: TerminalResizeInput = { threadId: session.threadId, terminalId: session.terminalId, cols, rows };
  return request(id, 'terminal.resize', payload);
}

export function threadTerminalClearRequest(id: string, target: ThreadTerminalTarget): ThreadTerminalRequest {
  return request(id, 'terminal.clear', sessionFor(target, true));
}

export function threadTerminalCloseRequest(id: string, target: ThreadTerminalTarget,
  deleteHistory?: boolean): ThreadTerminalRequest {
  const session = sessionFor(target, true);
  const payload: TerminalCloseInput = { threadId: session.threadId, terminalId: session.terminalId, deleteHistory };
  return request(id, 'terminal.close', payload);
}

export function threadTerminalMetadataRequest(id: string): ThreadTerminalRequest {
  const payload: Record<string, string> = {};
  return request(id, 'subscribeTerminalMetadata', payload);
}

export function readThreadTerminalMetadata(value: Object, threadId: string): NativeThreadTerminalSummary[] | undefined {
  const event = value as TerminalMetadataEvent;
  if (event?.type !== 'snapshot') return undefined;
  if (!Array.isArray(event.terminals)) throw new Error('环境返回的终端列表无效。');
  const terminals: NativeThreadTerminalSummary[] = [];
  for (const terminal of event.terminals) {
    if (terminal?.threadId !== threadId) continue;
    if (!validTerminalId(terminal.terminalId) || !validId(terminal.cwd) ||
      (terminal.worktreePath !== null && !validId(terminal.worktreePath)) || !validStatus(terminal.status) ||
      (terminal.pid !== null && !validSize(terminal.pid, Number.MAX_SAFE_INTEGER)) ||
      !validExit(terminal.exitCode) || !validExit(terminal.exitSignal) ||
      typeof terminal.label !== 'string' || terminal.label.length > 128 || typeof terminal.updatedAt !== 'string' ||
      typeof terminal.hasRunningSubprocess !== 'boolean') {
      throw new Error('环境返回的终端列表无效。');
    }
    terminals.push(terminal);
  }
  return terminals;
}

function nextSequenceState(state: number, unit: number): number {
  if (unit === 0x1b) return SEQUENCE_ESCAPE;
  if (state === SEQUENCE_GROUND || unit === 0x18 || unit === 0x1a) return SEQUENCE_GROUND;
  let mode = state & 7;
  if (unit < 0x80) {
    switch (mode) {
      case SEQUENCE_ESCAPE:
        if (unit < 0x20 || unit === 0x7f) return mode;
        if (unit < 0x30) return SEQUENCE_ESCAPE_INTERMEDIATE;
        if (unit === 0x5b) return SEQUENCE_CSI;
        if (unit === 0x5d) return SEQUENCE_OSC;
        if (unit === 0x50) return SEQUENCE_DCS;
        return unit === 0x58 || unit === 0x5e || unit === 0x5f ? SEQUENCE_SOS_PM_APC : SEQUENCE_GROUND;
      case SEQUENCE_ESCAPE_INTERMEDIATE:
        return unit >= 0x30 && unit !== 0x7f ? SEQUENCE_GROUND : mode;
      case SEQUENCE_CSI:
        return unit >= 0x40 && unit !== 0x7f ? SEQUENCE_GROUND : mode;
      case SEQUENCE_OSC:
        return unit === 0x07 ? SEQUENCE_GROUND : mode;
      default:
        return mode;
    }
  }
  if (mode === SEQUENCE_OSC) return mode;
  if (unit >= 0xd800 && unit <= 0xdbff) return mode | (unit << 3);
  let codePoint = unit;
  if (unit >= 0xdc00 && unit <= 0xdfff) {
    if (state < 8) return mode;
    codePoint = 0x10000 + (((state >> 3) - 0xd800) << 10) + (unit - 0xdc00);
  }
  for (let shift = codePoint > 0xffff ? 12 : codePoint > 0x7ff ? 6 : 0; shift >= 0; shift -= 6) {
    const byte = 0x80 | ((codePoint >> shift) & 0x3f);
    if (byte >= 0xa0) continue;
    if (byte === 0x9d) return SEQUENCE_OSC;
    if (byte === 0x90) mode = SEQUENCE_DCS;
    else if (byte === 0x9b) mode = SEQUENCE_CSI;
    else if (byte === 0x98 || byte >= 0x9e) mode = SEQUENCE_SOS_PM_APC;
    else return SEQUENCE_GROUND;
  }
  return mode;
}

function boundedHistory(history: string): string {
  if (history.length <= Math.floor(MAX_HISTORY_BYTES / 3)) return history;
  let start = history.length;
  let bytes = 0;
  while (start > 0) {
    let position = start - 1;
    const unit = history.charCodeAt(position);
    let width = unit < 0x80 ? 1 : unit < 0x800 ? 2 : 3;
    if (unit >= 0xdc00 && unit <= 0xdfff && position > 0) {
      const previous = history.charCodeAt(position - 1);
      if (previous >= 0xd800 && previous <= 0xdbff) {
        position--;
        width = 4;
      }
    }
    if (bytes + width > MAX_HISTORY_BYTES) break;
    bytes += width;
    start = position;
  }
  // Mirror retainedTerminalHistory in the contracts when an observer receives a larger snapshot.
  if (start > 0) {
    const escape = history.lastIndexOf('\u001b', start - 1);
    if (escape >= 0) {
      let position = escape + 1;
      let state = SEQUENCE_ESCAPE;
      while (position < history.length && state !== SEQUENCE_GROUND) {
        state = nextSequenceState(state, history.charCodeAt(position++));
      }
      start = Math.max(start, position);
    }
  }
  return history.slice(start);
}

export class ThreadTerminalProjection {
  private session: TerminalSession;
  private initialized: boolean = false;
  private status: string = 'starting';
  private lastSequence: number = -1;

  constructor(target: ThreadTerminalTarget) {
    this.session = sessionFor(target);
  }

  apply(value: Object): NativeTerminalUpdate | undefined {
    const event = value as TerminalEvent;
    if (!event || typeof event.type !== 'string') throw new Error('环境返回的终端事件无效。');
    if (event.type === 'snapshot' || event.type === 'restarted') {
      const snapshot = event.snapshot;
      if (!snapshot) throw new Error('环境返回的终端快照无效。');
      if (!this.matches(snapshot) || (event.type === 'restarted' && !this.matches(event))) return undefined;
      if (!validStatus(snapshot.status) || typeof snapshot.history !== 'string' || !validSequence(snapshot.sequence) ||
        !validOptionalGrid(snapshot.cols, snapshot.rows) || !validExit(snapshot.exitCode) ||
        !validExit(snapshot.exitSignal) || typeof snapshot.label !== 'string' || snapshot.label.length > 128 ||
        (snapshot.error !== undefined && typeof snapshot.error !== 'string')) {
        throw new Error('环境返回的终端快照无效。');
      }
      this.initialized = true;
      this.status = snapshot.status;
      this.lastSequence = snapshot.sequence ?? -1;
      return {
        kind: 'snapshot', status: this.status, history: boundedHistory(snapshot.history), cols: snapshot.cols,
        rows: snapshot.rows, exitCode: snapshot.exitCode, exitSignal: snapshot.exitSignal, message: snapshot.error,
        label: snapshot.label,
      };
    }
    if (!this.matches(event) || (!this.initialized && event.type !== 'closed')) return undefined;
    if (!validSequence(event.sequence)) throw new Error('环境返回的终端顺序无效。');
    if (event.sequence !== undefined && event.sequence <= this.lastSequence) return undefined;
    const update = this.applyEvent(event);
    if (event.sequence !== undefined) this.lastSequence = event.sequence;
    return update;
  }

  private matches(session: TerminalSession): boolean {
    return session.threadId === this.session.threadId && session.terminalId === this.session.terminalId;
  }

  private applyEvent(event: TerminalEvent): NativeTerminalUpdate | undefined {
    switch (event.type) {
      case 'output':
        if (typeof event.data !== 'string') throw new Error('环境返回的终端输出无效。');
        return { kind: 'output', status: this.status, data: event.data };
      case 'cleared':
        return { kind: 'cleared', status: this.status };
      case 'exited':
        if (event.exitCode === undefined || event.exitSignal === undefined ||
          !validExit(event.exitCode) || !validExit(event.exitSignal)) {
          throw new Error('环境返回的终端退出状态无效。');
        }
        this.status = 'exited';
        return { kind: 'exited', status: this.status, exitCode: event.exitCode, exitSignal: event.exitSignal };
      case 'closed':
        this.status = 'closed';
        return { kind: 'closed', status: this.status };
      case 'error':
        if (typeof event.message !== 'string' || event.message.length === 0) throw new Error('环境返回的终端异常无效。');
        this.status = 'error';
        return { kind: 'error', status: this.status, message: event.message };
      case 'activity':
        if (!validOptionalGrid(event.cols, event.rows) || typeof event.label !== 'string' ||
          event.label.length > 128 || typeof event.hasRunningSubprocess !== 'boolean') {
          throw new Error('环境返回的终端状态无效。');
        }
        return {
          kind: 'activity', status: this.status, cols: event.cols, rows: event.rows,
          label: event.label, hasRunningSubprocess: event.hasRunningSubprocess,
        };
      default:
        return undefined;
    }
  }
}
