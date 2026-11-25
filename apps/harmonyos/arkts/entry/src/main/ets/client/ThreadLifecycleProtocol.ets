import { REQUEST_ID } from './T3Protocol';
import type { NativeThread } from './T3Protocol';

export type ThreadLifecycleAction = 'rename' | 'pin' | 'unpin' | 'mark-unread' | 'settle' | 'unsettle' |
  'snooze' | 'unsnooze' | 'archive' | 'unarchive' | 'delete';

export type ThreadLifecycleState = 'active' | 'pinned' | 'snoozed' | 'settled' | 'archived';

interface ThreadLifecycleCommand {
  type: string;
  commandId: string;
  threadId: string;
  title?: string;
  reason?: string;
  snoozedUntil?: string;
  visitedAt?: string;
  opened?: boolean;
}

interface ThreadLifecycleRpcRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: Object;
  headers: string[][];
}

function dispatchLifecycle(command: ThreadLifecycleCommand): ThreadLifecycleRpcRequest {
  return {
    _tag: 'Request', id: REQUEST_ID, tag: 'orchestration.dispatchCommand', payload: command, headers: [],
  };
}

function timestamp(value: string | null | undefined): number {
  return value ? Date.parse(value) : NaN;
}

function requireTimestamp(value: string | undefined): string {
  const time = timestamp(value);
  if (!Number.isFinite(time)) throw new Error('请选择有效的时间。');
  return new Date(time).toISOString();
}

export function threadLifecycleRequest(commandId: string, threadId: string, action: ThreadLifecycleAction,
  value?: string): ThreadLifecycleRpcRequest {
  const command: ThreadLifecycleCommand = {
    type: action === 'rename' ? 'thread.metadata.update' : 'thread.' + action, commandId, threadId,
  };
  if (action === 'rename') {
    const title = value?.trim();
    if (!title) throw new Error('会话标题不能为空。');
    command.title = title;
  } else if (action === 'snooze') {
    command.snoozedUntil = requireTimestamp(value);
  } else if (action === 'unsettle' || action === 'unsnooze') {
    command.reason = 'user';
  }
  return dispatchLifecycle(command);
}

export function threadVisitRequest(commandId: string, threadId: string, visitedAt: string): ThreadLifecycleRpcRequest {
  return dispatchLifecycle({
    type: 'thread.visit', commandId, threadId, visitedAt: requireTimestamp(visitedAt), opened: true,
  });
}

export function archivedThreadSnapshotRequest(): ThreadLifecycleRpcRequest {
  const payload: Record<string, string> = {};
  return {
    _tag: 'Request', id: REQUEST_ID, tag: 'orchestration.getArchivedShellSnapshot', payload, headers: [],
  };
}

function raisedHandWhileSnoozed(thread: NativeThread): boolean {
  if ((thread.pendingGuestMessageCount ?? 0) > 0) return true;
  const snoozedAt = timestamp(thread.snoozedAt);
  const request = thread.pendingRuntimeRequest;
  if (request && (request.kind !== 'user_input' || !(timestamp(request.createdAt) <= snoozedAt))) return true;
  return thread.status === 'failed' &&
    (!Number.isFinite(snoozedAt) || timestamp(thread.latestRunCompletedAt) > snoozedAt);
}

export function threadLifecycleState(thread: NativeThread, nowMs: number): ThreadLifecycleState {
  if (thread.archivedAt) return 'archived';
  if (timestamp(thread.snoozedUntil) > nowMs && !raisedHandWhileSnoozed(thread)) return 'snoozed';
  if (thread.settledOverride === 'settled') return 'settled';
  return thread.pinnedAt ? 'pinned' : 'active';
}

export function threadHasUnread(thread: NativeThread): boolean {
  if (thread.lastVisitedAt === undefined) return false;
  const completed = thread.status === 'completed' || (thread.status === 'idle' && !!thread.latestRunId);
  if (!completed) return false;
  const completedAt = timestamp(thread.latestRunCompletedAt === undefined ? thread.updatedAt : thread.latestRunCompletedAt);
  return Number.isFinite(completedAt) && !(timestamp(thread.lastVisitedAt) >= completedAt);
}

function canSnoozeThread(thread: NativeThread, status: string | undefined | null, nowMs: number): boolean {
  if (thread.pendingRuntimeRequest && thread.pendingRuntimeRequest.kind !== 'user_input') return false;
  if ((thread.pendingGuestMessageCount ?? 0) > 0) return false;
  if (status === 'queued' || status === 'preparing' || status === 'starting') return false;
  const userMessageAt = timestamp(thread.latestUserMessageAt);
  if (!(Math.abs(nowMs - userMessageAt) <= 2 * 60 * 1000)) return true;
  return [thread.latestRunRequestedAt, thread.latestRunStartedAt, thread.latestRunCompletedAt]
    .some((candidate: string | null | undefined) => timestamp(candidate) >= userMessageAt);
}

export function availableThreadLifecycleActions(thread: NativeThread, canOperate: boolean,
  nowMs: number): ThreadLifecycleAction[] {
  if (!canOperate || !thread.id || thread.deletedAt) return [];
  const state = threadLifecycleState(thread, nowMs);
  if (state === 'archived') return ['unarchive', 'delete'];
  const actions: ThreadLifecycleAction[] = ['rename'];
  if (Number.isFinite(timestamp(thread.latestRunCompletedAt))) actions.push('mark-unread');
  const status = thread.activityRunStatus ?? thread.status;
  if (state === 'snoozed') {
    actions.push('unsnooze');
  } else {
    actions.push(thread.pinnedAt ? 'unpin' : 'pin');
    actions.push(state === 'settled' ? 'unsettle' : 'settle');
    if (state !== 'settled' && canSnoozeThread(thread, status, nowMs)) actions.push('snooze');
  }
  if (status !== 'preparing' && status !== 'starting' && status !== 'running' &&
    (status !== 'queued' || thread.activeRunId === null)) actions.push('archive');
  actions.push('delete');
  return actions;
}

export interface ThreadSnoozePreset {
  label: string;
  wakeAt: string;
  minutes?: number;
}

export interface ThreadSnoozePresetLabels {
  oneHour: string;
  threeHours: string;
  thisEvening: string;
  tomorrow: string;
  nextMonday: string;
}

const DEFAULT_SNOOZE_LABELS: ThreadSnoozePresetLabels = {
  oneHour: '1 小时后',
  threeHours: '3 小时后',
  thisEvening: '今天傍晚',
  tomorrow: '明天',
  nextMonday: '下周一',
};

export function customThreadSnooze(value: string, nowMs: number): string | undefined {
  const amount = value.trim();
  if (!/^\d+$/.test(amount)) return undefined;
  const minutes = Number(amount);
  if (!Number.isSafeInteger(minutes) || minutes <= 0) return undefined;
  const wake = new Date(nowMs + minutes * 60_000);
  return Number.isFinite(wake.getTime()) ? wake.toISOString() : undefined;
}

function calendarWake(now: Date, daysAhead: number, hour: number): string {
  const date = new Date(now.getTime());
  date.setDate(date.getDate() + daysAhead);
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
}

export function threadSnoozePresets(now: Date, labels: ThreadSnoozePresetLabels =
  DEFAULT_SNOOZE_LABELS): ThreadSnoozePreset[] {
  const nowMs = now.getTime();
  const daysToMonday = (8 - now.getDay()) % 7 || 7;
  const presets: ThreadSnoozePreset[] = [
    { label: labels.oneHour, wakeAt: new Date(nowMs + 60 * 60_000).toISOString(), minutes: 60 },
    { label: labels.threeHours, wakeAt: new Date(nowMs + 180 * 60_000).toISOString(), minutes: 180 },
    { label: labels.thisEvening, wakeAt: calendarWake(now, 0, 18) },
    { label: labels.tomorrow, wakeAt: calendarWake(now, 1, 9) },
    { label: labels.nextMonday, wakeAt: calendarWake(now, daysToMonday, 9) },
  ];
  const seen = new Set<number>();
  return presets.sort((left: ThreadSnoozePreset, right: ThreadSnoozePreset) =>
    timestamp(left.wakeAt) - timestamp(right.wakeAt)).filter((preset: ThreadSnoozePreset) => {
    const wakeMs = timestamp(preset.wakeAt);
    const minute = Math.floor(wakeMs / 60_000);
    if (wakeMs <= nowMs || seen.has(minute)) return false;
    seen.add(minute);
    return true;
  });
}
