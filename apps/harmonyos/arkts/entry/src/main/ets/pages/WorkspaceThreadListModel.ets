import type { NativeThread } from '../client/T3Protocol';
import { threadHasUnread, threadLifecycleState } from '../client/ThreadLifecycleProtocol';
import type { UiLanguage } from './UiLanguage';

export type WorkspaceThreadSection = 'pinned' | 'attention' | 'working' | 'unread' | 'recent' | 'snoozed' | 'settled';
export type WorkspaceThreadRowStatus = 'ready' | 'approval' | 'input' | 'request' | 'working' | 'waiting' |
  'failed' | 'woke' | 'snoozed' | 'settled' | 'archived';

export interface WorkspaceThreadListEntry {
  kind: 'thread' | 'section' | 'shelf';
  key: string;
  section: WorkspaceThreadSection;
  thread?: NativeThread;
  count: number;
}

const SECTIONS: WorkspaceThreadSection[] = ['pinned', 'attention', 'working', 'unread', 'recent', 'snoozed', 'settled'];

function threadTime(value: string | null | undefined): number {
  return Date.parse(value ?? '');
}

export function workspaceThreadRowStatus(thread: NativeThread, now: number): WorkspaceThreadRowStatus {
  const lifecycle = threadLifecycleState(thread, now);
  if (lifecycle === 'snoozed' || lifecycle === 'settled' || lifecycle === 'archived') return lifecycle;
  const request = thread.pendingRuntimeRequest;
  if (request) return request.kind === 'user_input' ? 'input' : 'approval';
  if ((thread.pendingGuestMessageCount ?? 0) > 0) return 'request';

  const status = thread.activityRunStatus ?? thread.status;
  if (status === 'preparing' || status === 'queued' || status === 'starting' || status === 'running') return 'working';
  if (status === 'waiting') return 'waiting';
  if (status === 'failed') {
    const failedAt = threadTime(thread.latestRunCompletedAt ?? thread.latestRunStartedAt ?? thread.latestRunRequestedAt);
    if (!Number.isFinite(failedAt) || !(threadTime(thread.lastVisitedAt) >= failedAt)) return 'failed';
  }

  const wokeAt = threadTime(thread.snoozedUntil);
  if (thread.lastVisitedAt !== undefined && wokeAt <= now && !(threadTime(thread.lastVisitedAt) >= wokeAt)) {
    return 'woke';
  }
  return 'ready';
}

function threadSection(thread: NativeThread, now: number): WorkspaceThreadSection {
  const lifecycle = threadLifecycleState(thread, now);
  if (lifecycle === 'pinned' || lifecycle === 'snoozed' || lifecycle === 'settled') return lifecycle;
  const status = workspaceThreadRowStatus(thread, now);
  if (status === 'working' || status === 'waiting') return 'working';
  if (status === 'approval' || status === 'input' || status === 'request' || status === 'failed' || status === 'woke') {
    return 'attention';
  }
  return threadHasUnread(thread) ? 'unread' : 'recent';
}

function threadEntry(thread: NativeThread, section: WorkspaceThreadSection): WorkspaceThreadListEntry {
  return {
    kind: 'thread', section, thread, count: 0,
    key: JSON.stringify([thread.environmentKey ?? '', thread.id]),
  };
}

export function workspaceThreadListEntries(threads: NativeThread[], now: number, flat: boolean,
  expandedSections: WorkspaceThreadSection[]): WorkspaceThreadListEntry[] {
  const entries: WorkspaceThreadListEntry[] = [];
  const groups = new Map<WorkspaceThreadSection, NativeThread[]>();
  for (const thread of threads) {
    if (thread.archivedAt) continue;
    const section = threadSection(thread, now);
    if (flat) {
      entries.push(threadEntry(thread, section));
      continue;
    }
    const rows = groups.get(section);
    if (rows) rows.push(thread);
    else groups.set(section, [thread]);
  }

  for (const section of SECTIONS) {
    const rows = groups.get(section);
    if (!rows) continue;
    const shelf = section === 'working' || section === 'snoozed' || section === 'settled';
    if (section !== 'pinned') {
      entries.push({ kind: shelf ? 'shelf' : 'section', key: section, section, count: rows.length });
    }
    if (!shelf || expandedSections.includes(section)) {
      for (const thread of rows) entries.push(threadEntry(thread, section));
    }
  }
  return entries;
}

export function workspaceThreadTimeLabel(thread: NativeThread, language: UiLanguage, now: number): string {
  const status = workspaceThreadRowStatus(thread, now);
  const time = threadTime(status === 'working' || status === 'waiting'
    ? (thread.latestRunStartedAt ?? thread.latestRunRequestedAt ?? thread.updatedAt)
    : (status === 'settled' ? thread.settledAt ?? thread.updatedAt : thread.updatedAt ?? thread.createdAt));
  if (!Number.isFinite(time)) return '';
  if (status === 'snoozed') {
    const wake = threadTime(thread.snoozedUntil);
    if (Number.isFinite(wake)) return compactTime(Math.max(0, wake - now), language);
  }
  return compactTime(Math.max(0, now - time), language);
}

function compactTime(elapsed: number, language: UiLanguage): string {
  const minutes = Math.max(1, Math.floor(elapsed / 60_000));
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);
  if (days > 0) return `${days}${language === 'zh' ? '天' : 'd'}`;
  if (hours > 0) return `${hours}${language === 'zh' ? '小时' : 'h'}`;
  return `${minutes}${language === 'zh' ? '分' : 'm'}`;
}
