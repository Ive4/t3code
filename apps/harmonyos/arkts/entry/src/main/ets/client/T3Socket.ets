import { util } from '@kit.ArkTS';
import { webSocket } from '@kit.NetworkKit';
import type { RpcFrame } from './T3Protocol';

const OPEN_TIMEOUT_MS = 12000;
const PING_INTERVAL_MS = 10000;
const SERVER_SILENCE_MS = 30000;

export class T3Socket {
  private native: webSocket.WebSocket = webSocket.createWebSocket();
  private disposed: boolean = false;
  private openingTimer: number = -1;
  private pingTimer: number = -1;
  private rejectOpen: ((error: Error) => void) | undefined;

  open(address: string, onFrame: (frame: RpcFrame) => void, onError: (error: Error) => void): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      if (this.disposed) {
        reject(new Error('会话连接已关闭。'));
        return;
      }
      this.rejectOpen = reject;
      let lastFrameAt = Date.now();
      const fail = (error: Error): void => {
        if (this.disposed) return;
        const starting = this.rejectOpen !== undefined;
        this.rejectOpen?.(error);
        this.rejectOpen = undefined;
        this.close();
        if (!starting) onError(error);
      };
      this.openingTimer = setTimeout(() => fail(new Error('连接环境超时。')), OPEN_TIMEOUT_MS);
      this.native.on('open', (error) => {
        if (error) {
          fail(new Error('无法打开环境的会话连接。'));
          return;
        }
        if (this.disposed) return;
        clearTimeout(this.openingTimer);
        this.rejectOpen = undefined;
        this.pingTimer = setInterval(() => {
          if (Date.now() - lastFrameAt >= SERVER_SILENCE_MS) {
            fail(new Error('环境的会话连接已超时。'));
            return;
          }
          void this.send('{"_tag":"Ping"}').catch(() => fail(new Error('环境的会话连接已断开。')));
        }, PING_INTERVAL_MS);
        resolve();
      });
      this.native.on('message', (error, message) => {
        if (this.disposed) return;
        if (error || message === undefined) {
          fail(new Error('无法读取环境的会话数据。'));
          return;
        }
        try {
          const raw = typeof message === 'string'
            ? message
            : util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(message));
          const value: Object = JSON.parse(raw) as Object;
          const frames = Array.isArray(value) ? value as RpcFrame[] : [value as RpcFrame];
          lastFrameAt = Date.now();
          for (const frame of frames) {
            if (!frame || typeof frame._tag !== 'string') throw new Error('无效的会话数据。');
            onFrame(frame);
          }
        } catch (error) {
          fail(new Error('无法读取环境的会话数据。'));
        }
      });
      this.native.on('close', () => fail(new Error('环境的会话连接已断开。')));
      this.native.on('error', () => fail(new Error('无法保持与环境的会话连接。')));
      void this.native.connect(address).then((accepted: boolean) => {
        if (!accepted) fail(new Error('无法连接到环境。'));
      }).catch(() => fail(new Error('无法连接到环境。')));
    });
  }

  async send(message: string): Promise<void> {
    if (this.disposed || !(await this.native.send(message))) throw new Error('无法写入环境的会话连接。');
  }

  close(): void {
    if (this.disposed) return;
    this.disposed = true;
    clearTimeout(this.openingTimer);
    clearInterval(this.pingTimer);
    this.rejectOpen?.(new Error('会话连接已关闭。'));
    this.rejectOpen = undefined;
    this.native.off('open');
    this.native.off('message');
    this.native.off('close');
    this.native.off('error');
    void this.native.close().catch(() => {});
  }
}
