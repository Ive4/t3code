import { REQUEST_ID } from './T3Protocol';
import type { NativeMessage, NativeThread } from './T3Protocol';

export interface NativeThreadForkSource {
  sourceThreadId: string;
  runId: string;
}

export interface NativeThreadForkAttempt {
  commandId: string;
  targetThreadId: string;
}

interface ThreadForkRunPoint {
  type: string;
  runId: string;
}

interface ThreadForkCommand {
  type: string;
  commandId: string;
  createdBy: string;
  creationSource: string;
  sourceThreadId: string;
  targetThreadId: string;
  sourcePoint: ThreadForkRunPoint;
  title?: string;
}

interface ThreadForkRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: ThreadForkCommand;
  headers: string[][];
}

interface ThreadForkReceipt {
  sequence: number;
}

interface ThreadForkOrigin {
  type: string;
  threadId?: string;
  runId?: string;
}

interface ThreadForkTarget extends NativeThread {
  forkedFrom?: ThreadForkOrigin | null;
}

interface ThreadForkProviderThreads {
  canForkThread: boolean;
  canForkFromTurn: boolean;
}

interface ThreadForkProviderIdentity {
  nativeThreadIds: string;
}

interface ThreadForkProviderContext {
  supportsFullThreadHandoff: boolean;
}

interface ThreadForkProviderCapabilities {
  threads?: ThreadForkProviderThreads;
  identity?: ThreadForkProviderIdentity;
  context?: ThreadForkProviderContext;
}

interface ForkAssistantItem {
  id: string;
  threadId: string;
  type: string;
  status: string;
  messageId?: string;
  runId?: string | null;
  streaming?: boolean;
}

interface ProjectedForkAssistantItem {
  sourceThreadId: string;
  sourceItemId: string;
  visibility: string;
  item: ForkAssistantItem;
}

export class ThreadForkUnconfirmedError extends Error {}
export class ThreadForkTargetPendingError extends Error {}

function validIdentifier(value: string | undefined | null): boolean {
  return typeof value === 'string' && value.length > 0 && value.trim() === value &&
    !/[\u0000-\u001f\u007f]/.test(value) && value !== '.' && value !== '..';
}

export function threadForkFromReplyRequest(source: NativeThreadForkSource, attempt: NativeThreadForkAttempt,
  title?: string): ThreadForkRequest {
  if (!validIdentifier(source.sourceThreadId) || !validIdentifier(source.runId) || !validIdentifier(attempt.commandId) ||
    !validIdentifier(attempt.targetThreadId) || attempt.targetThreadId === source.sourceThreadId) {
    throw new Error('此回复缺少有效的分叉来源。');
  }
  const payload: ThreadForkCommand = {
    type: 'thread.fork', commandId: attempt.commandId, createdBy: 'user', creationSource: 'mobile',
    sourceThreadId: source.sourceThreadId, targetThreadId: attempt.targetThreadId,
    sourcePoint: { type: 'run', runId: source.runId },
  };
  if (title?.trim()) payload.title = title.trim();
  return { _tag: 'Request', id: REQUEST_ID, tag: 'orchestration.dispatchCommand', payload, headers: [] };
}

export function readThreadForkReceipt(value?: Object): boolean {
  const result = value as ThreadForkReceipt | undefined;
  const sequence = result?.sequence ?? -1;
  return Number.isSafeInteger(sequence) && sequence >= 0;
}

export function readConfirmedThreadFork(value: Object, source: NativeThreadForkSource,
  attempt: NativeThreadForkAttempt): NativeThread | undefined {
  const thread = value as ThreadForkTarget;
  const origin = thread?.forkedFrom;
  if (thread?.id !== attempt.targetThreadId || thread.deletedAt || thread.archivedAt ||
    typeof thread.title !== 'string' || !validIdentifier(thread.projectId) ||
    thread.lineage?.relationshipToParent !== 'fork' || thread.lineage.parentThreadId !== source.sourceThreadId ||
    thread.lineage.sideChat === true || origin?.type !== 'run' || origin.threadId !== source.sourceThreadId ||
    origin.runId !== source.runId) return undefined;
  return thread;
}

export function supportsProjectedThreadFork(value?: Object): boolean {
  const capabilities = value as ThreadForkProviderCapabilities | undefined;
  if (!capabilities) return true;
  const strength = capabilities.identity?.nativeThreadIds;
  const nativeDenied = capabilities.threads?.canForkThread === false ||
    capabilities.threads?.canForkFromTurn === false || (strength !== undefined && strength !== 'strong');
  return !nativeDenied || capabilities.context?.supportsFullThreadHandoff !== false;
}

export function readProjectedThreadForkSource(value: Object, capabilities?: Object): NativeThreadForkSource | undefined {
  const row = value as ProjectedForkAssistantItem;
  const item = row?.item;
  const runId = item?.runId;
  if (!item || item.type !== 'assistant_message' || item.status !== 'completed' || item.streaming === true ||
    !runId || !validIdentifier(runId) || !validIdentifier(item.messageId) ||
    !validIdentifier(row.sourceThreadId) || row.sourceThreadId !== item.threadId ||
    !validIdentifier(row.sourceItemId) || row.sourceItemId !== item.id ||
    (row.visibility !== 'local' && row.visibility !== 'inherited') ||
    !supportsProjectedThreadFork(capabilities)) return undefined;
  return { sourceThreadId: row.sourceThreadId, runId };
}

export function attachThreadReplyForkSource(message: NativeMessage, source?: NativeThreadForkSource): NativeMessage {
  const available = source && message.role === 'assistant' && message.streaming !== true &&
    message.threadId === source.sourceThreadId && message.runId === source.runId ? source : undefined;
  if (message.forkSource?.sourceThreadId === available?.sourceThreadId &&
    message.forkSource?.runId === available?.runId) return message;
  const updated: NativeMessage = {
    id: message.id, role: message.role, text: message.text, streaming: message.streaming,
    createdAt: message.createdAt,
  };
  if (message.threadId !== undefined) updated.threadId = message.threadId;
  if (message.runId !== undefined) updated.runId = message.runId;
  if (message.context !== undefined) updated.context = message.context;
  if (message.attachments !== undefined) updated.attachments = message.attachments;
  if (message.attachmentNames !== undefined) updated.attachmentNames = message.attachmentNames;
  if (available !== undefined) updated.forkSource = available;
  return updated;
}
