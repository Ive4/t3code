import type { RpcFrame } from './T3Protocol';
import { T3Socket } from './T3Socket';
import {
  ThreadTerminalProjection, chunkThreadTerminalWrite, readThreadTerminalMetadata, threadTerminalClearRequest,
  threadTerminalCloseRequest, threadTerminalMetadataRequest, threadTerminalResizeRequest, threadTerminalStreamRequest,
  threadTerminalWriteRequest,
} from './ThreadTerminalProtocol';
import type {
  NativeTerminalUpdate, NativeThreadTerminalSummary, ThreadTerminalRequest, ThreadTerminalTarget,
} from './ThreadTerminalProtocol';

const STREAM_ID = '1';
const NETWORK_TIMEOUT_MS = 15000;
const RECONNECT_DELAYS_MS = [1000, 2000, 4000];

interface TerminalRpcError {
  _tag: string;
  cwd?: string;
}

interface TerminalRpcFailure {
  _tag: string;
  error?: TerminalRpcError;
}

interface TerminalRpcExit {
  _tag: string;
  cause?: TerminalRpcFailure[];
}

interface TerminalRpcFrame {
  _tag: string;
  requestId?: string | number;
  values?: Object[];
  exit?: TerminalRpcExit;
}

interface PendingCommand {
  complete: () => void;
  fail: (error: Error) => void;
}

interface TerminalAttempt {
  socket: T3Socket;
  projection: ThreadTerminalProjection;
  ready: boolean;
  timer: number;
  processVersion: number;
}

function changedEnvironment(): Error {
  return new Error('环境连接已更换。');
}

function terminalRpcError(exit: TerminalRpcExit | undefined, fallback: string): Error {
  const error = exit?.cause?.find((failure: TerminalRpcFailure): boolean => failure._tag === 'Fail')?.error;
  switch (error?._tag) {
    case 'EnvironmentAuthorizationError': return new Error('当前连接缺少终端权限。');
    case 'TerminalSessionLookupError': return new Error('此终端会话已不存在。');
    case 'TerminalNotRunningError': return new Error('终端进程没有运行。');
    case 'TerminalCwdNotFoundError':
    case 'TerminalCwdNotDirectoryError': return new Error('终端的工作目录不可用。' + (error.cwd ?? ''));
    default: return new Error(fallback);
  }
}

function isProtocolError(frame: TerminalRpcFrame): boolean {
  return frame._tag === 'Defect' || frame._tag === 'ClientProtocolError';
}

function ackStream(socket: T3Socket): Promise<void> {
  return socket.send('{"_tag":"Ack","requestId":"' + STREAM_ID + '"}');
}

export async function readThreadTerminals(socketAddress: () => Promise<string>, isCurrent: () => boolean,
  threadId: string): Promise<NativeThreadTerminalSummary[]> {
  const socket = new T3Socket();
  let timer = -1;
  let complete = false;
  const failure = '无法读取任务终端列表。';
  try {
    return await new Promise<NativeThreadTerminalSummary[]>((resolve, reject) => {
      timer = setTimeout(() => reject(new Error(failure)), NETWORK_TIMEOUT_MS);
      void socketAddress().then(async (address: string): Promise<void> => {
        if (complete || !isCurrent()) throw changedEnvironment();
        await socket.open(address, (raw: RpcFrame): void => {
          if (complete) return;
          if (!isCurrent()) {
            reject(changedEnvironment());
            return;
          }
          try {
            const frame = raw as Object as TerminalRpcFrame;
            if (isProtocolError(frame) || (String(frame.requestId) === STREAM_ID && frame._tag === 'Exit')) {
              reject(terminalRpcError(frame.exit, failure));
              return;
            }
            if (String(frame.requestId) !== STREAM_ID || frame._tag !== 'Chunk') return;
            if (!Array.isArray(frame.values)) throw new Error(failure);
            for (const value of frame.values) {
              const terminals = readThreadTerminalMetadata(value, threadId);
              if (terminals !== undefined) {
                resolve(terminals);
                return;
              }
            }
            void ackStream(socket).catch(reject);
          } catch (error) {
            reject(error as Error);
          }
        }, reject);
        if (complete || !isCurrent()) throw changedEnvironment();
        await socket.send(JSON.stringify(threadTerminalMetadataRequest(STREAM_ID)));
      }).catch(reject);
    });
  } finally {
    complete = true;
    clearTimeout(timer);
    socket.close();
  }
}

export class ThreadTerminalConnection {
  private socketAddress: () => Promise<string>;
  private isCurrent: () => boolean;
  private target: ThreadTerminalTarget;
  private onUpdate: (update: NativeTerminalUpdate) => void;
  private onError: (error: Error, reconnecting: boolean) => void;
  private attempt: TerminalAttempt | undefined;
  private stopped: boolean = false;
  private retries: number = 0;
  private retryTimer: number = -1;
  private resume: boolean = false;
  private requestId: number = 1;
  private commands: Map<string, PendingCommand> = new Map<string, PendingCommand>();
  private writes: Promise<void> = Promise.resolve();

  constructor(socketAddress: () => Promise<string>, isCurrent: () => boolean, target: ThreadTerminalTarget,
    onUpdate: (update: NativeTerminalUpdate) => void, onError: (error: Error, reconnecting: boolean) => void) {
    this.socketAddress = socketAddress;
    this.isCurrent = isCurrent;
    this.target = target;
    this.onUpdate = onUpdate;
    this.onError = onError;
  }

  start(): void {
    if (this.stopped || this.attempt !== undefined || this.retryTimer !== -1 || !this.isCurrent()) return;
    let request: ThreadTerminalRequest;
    let projection: ThreadTerminalProjection;
    try {
      request = threadTerminalStreamRequest(STREAM_ID, this.target, this.resume);
      projection = new ThreadTerminalProjection(this.target);
    } catch (error) {
      this.dispose();
      this.onError(error as Error, false);
      return;
    }
    const attempt: TerminalAttempt = { socket: new T3Socket(), projection, ready: false, timer: -1, processVersion: 0 };
    this.attempt = attempt;
    const fail = (error: Error): void => this.retry(attempt, error, true);
    attempt.timer = setTimeout(() => fail(new Error('环境未及时返回终端状态。')), NETWORK_TIMEOUT_MS);
    void this.socketAddress().then(async (address: string): Promise<void> => {
      if (!this.active(attempt)) return;
      await attempt.socket.open(address, (frame: RpcFrame): void => this.handleFrame(attempt, frame), fail);
      if (!this.active(attempt)) return;
      await attempt.socket.send(JSON.stringify(request));
    }).catch(fail);
  }

  dispose(): void {
    if (this.stopped) return;
    this.stopped = true;
    clearTimeout(this.retryTimer);
    if (this.attempt) this.endAttempt(this.attempt, new Error('已离开终端。'));
  }

  async write(data: string, binary?: boolean, reply?: boolean): Promise<void> {
    const attempt = this.attachedAttempt();
    const processVersion = attempt.processVersion;
    const chunks = chunkThreadTerminalWrite(data);
    const send = this.writes.then(async (): Promise<void> => {
      for (const chunk of chunks) {
        if (processVersion !== attempt.processVersion) throw new Error('终端进程已更换。');
        await this.command(attempt, threadTerminalWriteRequest(this.nextId(), this.target, chunk, binary, reply));
      }
    });
    this.writes = send.catch((): void => {});
    return send;
  }

  async resize(cols: number, rows: number): Promise<void> {
    const attempt = this.attachedAttempt();
    await this.command(attempt, threadTerminalResizeRequest(this.nextId(), this.target, cols, rows));
  }

  async clear(): Promise<void> {
    await this.command(this.attachedAttempt(), threadTerminalClearRequest(this.nextId(), this.target));
  }

  async close(deleteHistory?: boolean): Promise<void> {
    await this.command(this.attachedAttempt(), threadTerminalCloseRequest(this.nextId(), this.target, deleteHistory));
  }

  private nextId(): string {
    return String(++this.requestId);
  }

  private attachedAttempt(): TerminalAttempt {
    if (!this.isCurrent()) throw changedEnvironment();
    if (!this.target.operate) throw new Error('此连接只有读取终端的权限。');
    if (!this.attempt?.ready || this.stopped) throw new Error('终端尚未连接。');
    return this.attempt;
  }

  private command(attempt: TerminalAttempt, request: ThreadTerminalRequest): Promise<void> {
    if (!this.active(attempt) || !attempt.ready) return Promise.reject(new Error('终端尚未连接。'));
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.commands.delete(request.id);
        reject(new Error('环境未确认终端操作。'));
      }, NETWORK_TIMEOUT_MS);
      const clear = (): void => {
        clearTimeout(timer);
        this.commands.delete(request.id);
      };
      const command: PendingCommand = {
        complete: (): void => { clear(); resolve(); },
        fail: (error: Error): void => { clear(); reject(error); },
      };
      this.commands.set(request.id, command);
      void attempt.socket.send(JSON.stringify(request)).catch((error: Error): void => {
        this.retry(attempt, error, true);
      });
    });
  }

  private active(attempt: TerminalAttempt): boolean {
    if (this.stopped || this.attempt !== attempt) return false;
    if (this.isCurrent()) return true;
    this.dispose();
    return false;
  }

  private handleFrame(attempt: TerminalAttempt, raw: RpcFrame): void {
    if (!this.active(attempt)) return;
    const frame = raw as Object as TerminalRpcFrame;
    const requestId = String(frame.requestId);
    if (isProtocolError(frame)) {
      this.retry(attempt, new Error('环境无法保持终端连接。'), false);
      return;
    }
    if (requestId !== STREAM_ID) {
      const command = this.commands.get(requestId);
      if (frame._tag === 'Exit' && command) {
        if (frame.exit?._tag === 'Success') command.complete();
        else command.fail(terminalRpcError(frame.exit, '环境未完成终端操作。'));
      }
      return;
    }
    if (frame._tag === 'Exit') {
      this.retry(attempt, terminalRpcError(frame.exit, '环境终止了终端连接。'), frame.exit?._tag !== 'Failure');
      return;
    }
    if (frame._tag !== 'Chunk') return;
    try {
      if (!Array.isArray(frame.values)) throw new Error('环境返回的终端数据无效。');
      for (const event of frame.values) {
        const update = attempt.projection.apply(event);
        if (!update) continue;
        if (update.kind === 'snapshot' || update.kind === 'closed' || update.kind === 'exited' || update.kind === 'error') {
          attempt.processVersion++;
        }
        if (!attempt.ready && (update.kind === 'snapshot' || update.kind === 'closed')) {
          attempt.ready = true;
          this.resume = true;
          this.retries = 0;
          clearTimeout(attempt.timer);
        }
        this.onUpdate(update);
        if (!this.active(attempt)) return;
      }
      void ackStream(attempt.socket).catch((error: Error): void => this.retry(attempt, error, true));
    } catch (error) {
      this.retry(attempt, error as Error, false);
    }
  }

  private endAttempt(attempt: TerminalAttempt, error: Error): void {
    this.attempt = undefined;
    clearTimeout(attempt.timer);
    attempt.socket.close();
    for (const command of this.commands.values()) command.fail(error);
  }

  private retry(attempt: TerminalAttempt, error: Error, reconnect: boolean): void {
    if (!this.active(attempt)) return;
    this.endAttempt(attempt, error);
    const delay = reconnect ? RECONNECT_DELAYS_MS[this.retries++] : undefined;
    if (delay === undefined) {
      this.dispose();
      this.onError(error, false);
      return;
    }
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      this.start();
    }, delay);
    this.onError(error, true);
  }
}
