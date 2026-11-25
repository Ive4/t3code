import type { DeviceApprovalOutcome, DeviceApprovalRequest } from './RelayProtocol';
import { readDeviceApprovalRequest, readDeviceApprovalSnapshot } from './RelayProtocol';
import type { RpcFrame } from './T3Protocol';
import { REQUEST_ID } from './T3Protocol';
import { T3Socket } from './T3Socket';

const SNAPSHOT_TIMEOUT_MS = 15000;
const RECONNECT_DELAYS_MS = [1000, 2000, 4000];
const MAX_RECONNECT_DELAY_MS = 30000;

export interface ConnectDeviceApprovalTarget {
  key: string;
  label: string;
  socketAddress: () => Promise<string>;
  approve: (pairingLinkId: string, isCurrent: () => boolean) => Promise<DeviceApprovalOutcome>;
  deny: (pairingLinkId: string, isCurrent: () => boolean) => Promise<DeviceApprovalOutcome>;
}

export interface ConnectDeviceApprovalPrompt {
  environmentKey: string;
  environmentLabel: string;
  pairingLinkId: string;
  verificationCode: string;
  deviceLabel: string;
}

interface AccessEvent {
  version: number;
  revision: number;
  type: string;
  payload: Object;
}

interface PairingLinkId {
  id: string;
}

interface ApprovalSettings {
  requireConnectDeviceApproval?: boolean;
}

interface ConfigPayload {
  settings: ApprovalSettings;
}

interface ConfigEvent {
  version: number;
  type: string;
  config?: ConfigPayload;
  payload?: ConfigPayload;
}

interface AccessStream {
  id: string;
  revision: number;
}

interface StreamAttempt {
  socket: T3Socket;
  timer: number;
  configReady: boolean;
  nextAccessId: number;
  access?: AccessStream;
}

interface ApprovalWatcher {
  target: ConnectDeviceApprovalTarget;
  attempt?: StreamAttempt;
  retryTimer: number;
  retries: number;
  pending: Map<string, PendingApproval>;
}

interface PendingApproval {
  watcher: ApprovalWatcher;
  prompt: ConnectDeviceApprovalPrompt;
  order: number;
  deferred: boolean;
  settled: boolean;
  answering: boolean;
}

export class ConnectDeviceApprovals {
  private readonly onPrompt: (prompt: ConnectDeviceApprovalPrompt | undefined) => void;
  private readonly watchers: Map<string, ApprovalWatcher> = new Map<string, ApprovalWatcher>();
  private showing: PendingApproval | undefined;
  private order: number = 0;

  constructor(onPrompt: (prompt: ConnectDeviceApprovalPrompt | undefined) => void) {
    this.onPrompt = onPrompt;
  }

  setTargets(targets: ConnectDeviceApprovalTarget[]): void {
    const desired = new Map<string, ConnectDeviceApprovalTarget>();
    for (const target of targets) desired.set(target.key, target);
    for (const watcher of this.watchers.values()) {
      const key = watcher.target.key;
      if (desired.get(key) === watcher.target) continue;
      this.watchers.delete(key);
      clearTimeout(watcher.retryTimer);
      this.closeAttempt(watcher);
    }
    for (const target of desired.values()) {
      if (this.watchers.has(target.key)) continue;
      const watcher: ApprovalWatcher = {
        target,
        retryTimer: -1,
        retries: 0,
        pending: new Map<string, PendingApproval>(),
      };
      this.watchers.set(target.key, watcher);
      this.open(watcher);
    }
    this.showNext();
  }

  defer(prompt: ConnectDeviceApprovalPrompt): void {
    const current = this.showing;
    if (current?.prompt !== prompt || current.answering) return;
    current.deferred = true;
    this.showNext();
  }

  async respond(prompt: ConnectDeviceApprovalPrompt, approve: boolean): Promise<DeviceApprovalOutcome | 'stale'> {
    const current = this.showing;
    if (current?.prompt !== prompt || current.answering || !this.isPending(current)) return 'stale';
    const watcher = current.watcher;
    const access = watcher.attempt?.access;
    if (!access || access.revision === 0) throw new Error('正在重新连接审批环境。请稍后重试。');
    const isCurrent = (): boolean => this.showing === current && this.isPending(current) &&
      watcher.attempt?.access === access;

    current.answering = true;
    try {
      const send = approve ? watcher.target.approve : watcher.target.deny;
      const result = await send(prompt.pairingLinkId, isCurrent);
      if (watcher.attempt?.access !== access) return 'stale';
      current.settled = true;
      this.showNext();
      return result;
    } catch (error) {
      if (!this.isPending(current)) return 'stale';
      throw error as Error;
    } finally {
      current.answering = false;
    }
  }

  private open(watcher: ApprovalWatcher): void {
    if (this.watchers.get(watcher.target.key) !== watcher) return;
    const attempt: StreamAttempt = { socket: new T3Socket(), timer: -1, configReady: false, nextAccessId: 2 };
    watcher.attempt = attempt;
    const fail = (): void => this.retry(watcher, attempt);
    attempt.timer = setTimeout(fail, SNAPSHOT_TIMEOUT_MS);
    void watcher.target.socketAddress().then(async (address: string): Promise<void> => {
      if (watcher.attempt !== attempt) return;
      await attempt.socket.open(address, (frame: RpcFrame): void => this.receive(watcher, attempt, frame), fail);
      if (watcher.attempt !== attempt) return;
      await attempt.socket.send('{"_tag":"Request","id":"' + REQUEST_ID +
        '","tag":"subscribeServerConfig","payload":{"workspaceSnapshotsOnDemand":true},"headers":[]}');
    }).catch(fail);
  }

  private closeAttempt(watcher: ApprovalWatcher): void {
    const attempt = watcher.attempt;
    watcher.attempt = undefined;
    if (!attempt) return;
    clearTimeout(attempt.timer);
    attempt.socket.close();
  }

  private retry(watcher: ApprovalWatcher, attempt: StreamAttempt): void {
    if (watcher.attempt !== attempt) return;
    this.closeAttempt(watcher);
    const delay = RECONNECT_DELAYS_MS[watcher.retries] ?? MAX_RECONNECT_DELAY_MS;
    if (watcher.retries < RECONNECT_DELAYS_MS.length) {
      watcher.retries++;
    } else {
      watcher.pending.clear();
      this.showNext();
    }
    watcher.retryTimer = setTimeout((): void => this.open(watcher), delay);
  }

  private receive(watcher: ApprovalWatcher, attempt: StreamAttempt, frame: RpcFrame): void {
    if (watcher.attempt !== attempt) return;
    if (frame._tag === 'Defect' || frame._tag === 'ClientProtocolError') {
      this.retry(watcher, attempt);
      return;
    }
    const requestId = String(frame.requestId);
    const access = attempt.access;
    if (requestId !== REQUEST_ID && requestId !== access?.id) return;
    if (frame._tag === 'Exit') {
      this.retry(watcher, attempt);
      return;
    }
    if (frame._tag !== 'Chunk') return;

    try {
      if (!Array.isArray(frame.values)) throw new Error('环境返回的设备审批数据无效。');
      for (const value of frame.values) {
        if (requestId === REQUEST_ID) {
          this.applyConfig(watcher, attempt, value as Object as ConfigEvent);
        } else if (access) {
          this.applyAccess(watcher, attempt, access, value as Object as AccessEvent);
        }
      }
      this.send(watcher, attempt, '{"_tag":"Ack","requestId":"' + requestId + '"}');
      this.showNext();
    } catch (_) {
      this.retry(watcher, attempt);
    }
  }

  private send(watcher: ApprovalWatcher, attempt: StreamAttempt, message: string): void {
    void attempt.socket.send(message).catch((): void => this.retry(watcher, attempt));
  }

  private applyConfig(watcher: ApprovalWatcher, attempt: StreamAttempt, event: ConfigEvent): void {
    if (event?.version !== 1 || (!attempt.configReady && event.type !== 'snapshot')) {
      throw new Error('环境返回的设备审批设置无效。');
    }
    if (event.type !== 'snapshot' && event.type !== 'settingsUpdated') return;
    const settings = event.type === 'snapshot' ? event.config?.settings : event.payload?.settings;
    if (!settings || typeof settings !== 'object') throw new Error('环境返回的设备审批设置无效。');
    attempt.configReady = true;

    if (settings.requireConnectDeviceApproval === true) {
      if (attempt.access) return;
      const access: AccessStream = { id: String(attempt.nextAccessId++), revision: 0 };
      attempt.access = access;
      clearTimeout(attempt.timer);
      attempt.timer = setTimeout((): void => this.retry(watcher, attempt), SNAPSHOT_TIMEOUT_MS);
      this.send(watcher, attempt, '{"_tag":"Request","id":"' + access.id +
        '","tag":"subscribeAuthAccess","payload":{},"headers":[]}');
    } else {
      const access = attempt.access;
      attempt.access = undefined;
      clearTimeout(attempt.timer);
      watcher.retries = 0;
      watcher.pending.clear();
      if (access) this.send(watcher, attempt, '{"_tag":"Interrupt","requestId":"' + access.id + '"}');
    }
  }

  private applyAccess(watcher: ApprovalWatcher, attempt: StreamAttempt, access: AccessStream, event: AccessEvent): void {
    if (event?.version !== 1 || !Number.isSafeInteger(event.revision) || event.revision < 1) {
      throw new Error('环境返回的设备申请版本无效。');
    }
    if (event.revision <= access.revision) return;
    if (event.type === 'snapshot') {
      const requests = readDeviceApprovalSnapshot(event);
      const previous = watcher.pending;
      watcher.pending = new Map<string, PendingApproval>();
      for (const request of requests) {
        const existing = previous.get(request.pairingLinkId);
        this.offer(watcher, request, access.revision === 0 && existing?.deferred ? undefined : existing);
      }
      clearTimeout(attempt.timer);
      watcher.retries = 0;
    } else {
      if (access.revision === 0 || event.revision !== access.revision + 1) {
        throw new Error('设备审批状态需要重新同步。');
      }
      if (event.type === 'pairingLinkUpserted' || event.type === 'pairingLinkRemoved') {
        const link = event.payload as PairingLinkId;
        if (typeof link?.id !== 'string' || !link.id || link.id.trim() !== link.id) {
          throw new Error('环境返回的设备申请标识无效。');
        }
        const request = event.type === 'pairingLinkUpserted' ? readDeviceApprovalRequest(event.payload) : undefined;
        if (request) {
          this.offer(watcher, request, watcher.pending.get(link.id));
        } else {
          watcher.pending.delete(link.id);
        }
      }
    }
    access.revision = event.revision;
  }

  private offer(watcher: ApprovalWatcher, request: DeviceApprovalRequest, existing?: PendingApproval): void {
    if (existing?.prompt.verificationCode === request.verificationCode &&
      (existing === this.showing || existing.settled || existing.prompt.deviceLabel === request.deviceLabel)) {
      watcher.pending.set(request.pairingLinkId, existing);
      return;
    }
    const prompt: ConnectDeviceApprovalPrompt = {
      environmentKey: watcher.target.key,
      environmentLabel: watcher.target.label,
      pairingLinkId: request.pairingLinkId,
      verificationCode: request.verificationCode,
      deviceLabel: request.deviceLabel,
    };
    watcher.pending.set(request.pairingLinkId, {
      watcher,
      prompt,
      order: existing?.order ?? ++this.order,
      deferred: false,
      settled: false,
      answering: false,
    });
  }

  private isPending(approval: PendingApproval): boolean {
    const watcher = approval.watcher;
    return !approval.settled && !approval.deferred && this.watchers.get(watcher.target.key) === watcher &&
      watcher.pending.get(approval.prompt.pairingLinkId) === approval;
  }

  private showNext(): void {
    const previous = this.showing;
    if (previous && this.isPending(previous)) return;
    let next: PendingApproval | undefined;
    for (const watcher of this.watchers.values()) {
      if ((watcher.attempt?.access?.revision ?? 0) === 0) continue;
      for (const approval of watcher.pending.values()) {
        if (this.isPending(approval) && (!next || approval.order < next.order)) next = approval;
      }
    }
    this.showing = next;
    if (previous !== next) this.onPrompt(next?.prompt);
  }
}
