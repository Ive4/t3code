import type { NativeMessage, ThreadMessageContext } from './T3Protocol';
import { readMessage } from './T3Protocol';
import { attachThreadReplyForkSource, readProjectedThreadForkSource } from './ThreadForkProtocol';

export interface NativeThreadHistory {
  messages: NativeMessage[];
  visibleTurnItems: Object[];
  nextCursor?: string;
}

interface HistoryForkSource {
  type: string;
  status: string;
  threadId?: string;
}

interface HistoryTurnItem {
  id: string;
  threadId: string;
  runId?: string | null;
  type: string;
  messageId?: string;
  text?: string;
  textOmitted?: boolean;
  streaming?: boolean;
  attachments?: Object[];
  context?: ThreadMessageContext;
  startedAt: string | null;
  completedAt: string | null;
  updatedAt: string;
  source?: HistoryForkSource;
  targetThreadId?: string;
}

interface HistoricalMessage {
  id: string;
  threadId: string;
  runId?: string;
  role: string;
  text: string;
  streaming: boolean;
  createdAt: string;
  attachments?: Object[];
  context?: ThreadMessageContext;
}

interface HistoryTurnRow {
  position: number;
  visibility: string;
  sourceThreadId: string;
  sourceItemId: string;
  item: HistoryTurnItem;
}

interface HistoryPage {
  snapshotSequence: number;
  items: HistoryTurnRow[];
  nextCursor: string | null;
  hasMoreHistory: boolean;
}

function historyIdentifier(value: string | null | undefined): boolean {
  return typeof value === 'string' && value.length > 0 && value.trim() === value && !/[\x00-\x1f\x7f]/.test(value);
}

export function threadHistoryPath(threadId: string, cursor: string, throughEntryId?: string): string {
  if (!historyIdentifier(threadId) || threadId === '.' || threadId === '..' || !historyIdentifier(cursor) ||
    (throughEntryId !== undefined && !historyIdentifier(throughEntryId))) {
    throw new Error('会话历史标识无效。');
  }
  const path = '/api/orchestration/threads/' + encodeURIComponent(threadId) + '/history?cursor=' +
    encodeURIComponent(cursor);
  return throughEntryId === undefined ? path : path + '&throughEntryId=' + encodeURIComponent(throughEntryId);
}

function visibleInThread(row: HistoryTurnRow, threadId: string): boolean {
  const item = row?.item;
  if (!item || !Number.isSafeInteger(row.position) || row.position < 0 ||
    !historyIdentifier(item.type) || !historyIdentifier(item.threadId) ||
    !historyIdentifier(row.sourceThreadId) || !historyIdentifier(row.sourceItemId) || row.sourceItemId !== item.id) {
    return false;
  }
  if (row.visibility === 'local') {
    return row.sourceThreadId === threadId && item.threadId === threadId;
  }
  // A fork marker points to the source conversation but belongs to its target.
  const forkMarker = item.type === 'fork' && item.targetThreadId === item.threadId &&
    item.source?.type === 'run' && item.source.threadId === row.sourceThreadId;
  if (row.visibility === 'synthetic') {
    return forkMarker && item.threadId === threadId;
  }
  return row.visibility === 'inherited' && row.sourceThreadId !== threadId && item.threadId !== threadId &&
    (row.sourceThreadId === item.threadId || forkMarker);
}

export function readThreadHistory(value: Object, threadId: string, requestedCursor: string): NativeThreadHistory {
  const page = value as HistoryPage;
  if (!page || !Number.isSafeInteger(page.snapshotSequence) || page.snapshotSequence < 0 ||
    !Array.isArray(page.items) || typeof page.hasMoreHistory !== 'boolean' ||
    (page.nextCursor !== null && !historyIdentifier(page.nextCursor))) {
    throw new Error('环境返回的会话历史无效。');
  }
  if (page.hasMoreHistory && (page.nextCursor === null || page.nextCursor === requestedCursor)) {
    throw new Error('会话历史游标未推进。');
  }
  const result: NativeThreadHistory = { messages: [], visibleTurnItems: page.items };
  if (page.hasMoreHistory && page.nextCursor !== null) result.nextCursor = page.nextCursor;
  for (const row of page.items) {
    if (!visibleInThread(row, threadId)) throw new Error('环境返回了错误来源的会话历史。');
    const item = row.item;
    if ((item.type !== 'assistant_message' && item.type !== 'user_message') || item.textOmitted === true) continue;
    const createdAt = item.startedAt ?? item.completedAt ?? item.updatedAt;
    if (!Number.isFinite(Date.parse(createdAt)) || typeof item.messageId !== 'string' ||
      !historyIdentifier(item.messageId) || typeof item.text !== 'string') {
      throw new Error('环境返回的历史消息无效。');
    }
    const message: HistoricalMessage = {
      id: item.messageId,
      threadId: item.threadId,
      role: item.type === 'assistant_message' ? 'assistant' : 'user',
      text: item.text,
      streaming: item.streaming === true,
      createdAt,
      attachments: item.attachments,
      context: item.context,
    };
    if (typeof item.runId === 'string' && historyIdentifier(item.runId)) message.runId = item.runId;
    const decoded = readMessage(message);
    if (decoded) result.messages.push(attachThreadReplyForkSource(decoded, readProjectedThreadForkSource(row)));
  }
  return result;
}
