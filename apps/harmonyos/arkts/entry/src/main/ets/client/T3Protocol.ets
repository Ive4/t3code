import type { ThreadLaunchSelection } from './ThreadLaunchProtocol';
import { readThreadBackgroundTasks } from './ThreadBackgroundWorkProtocol';
import type { NativeThreadBackgroundTask } from './ThreadBackgroundWorkProtocol';
import type { NativeThreadForkSource } from './ThreadForkProtocol';
import type { UploadedThreadAttachment } from './ThreadAttachmentProtocol';

interface ThreadShellPendingRequest {
  kind: string;
  createdAt: string;
}

interface NativeThreadLineage {
  parentThreadId?: string | null;
  relationshipToParent?: string | null;
  sideChat?: boolean;
  workflowStep?: boolean;
}

export interface NativeThread {
  id: string;
  title: string;
  environmentKey?: string;
  environmentLabel?: string;
  projectId?: string;
  projectTitle?: string;
  workspaceRoot?: string;
  worktreePath?: string;
  lineage?: NativeThreadLineage;
  createdAt?: string;
  updatedAt?: string;
  archivedAt?: string | null;
  deletedAt?: string | null;
  settledOverride?: 'settled' | 'active' | null;
  settledAt?: string | null;
  unsettledAt?: string | null;
  pinnedAt?: string | null;
  pinOrderKey?: string | null;
  activeOrderKey?: string | null;
  snoozedAt?: string | null;
  snoozedUntil?: string | null;
  status?: string;
  activityRunStatus?: string | null;
  activeRunId?: string | null;
  latestRunId?: string | null;
  latestRunRequestedAt?: string | null;
  latestRunStartedAt?: string | null;
  latestRunCompletedAt?: string | null;
  latestUserMessageAt?: string | null;
  lastVisitedAt?: string | null;
  pendingRuntimeRequest?: ThreadShellPendingRequest | null;
  pendingGuestMessageCount?: number;
  pendingBackgroundTasks?: NativeThreadBackgroundTask[];
}

export interface NativeMessage {
  id: string;
  role: string;
  text: string;
  streaming?: boolean;
  createdAt?: string;
  threadId?: string;
  runId?: string;
  context?: ThreadMessageContext;
  forkSource?: NativeThreadForkSource;
  attachments?: NativeThreadAttachment[];
  attachmentNames?: string[];
}

export type NativeThreadAttachment = UploadedThreadAttachment;

export interface RpcExit {
  _tag: string;
  value?: Object;
}

export interface RpcFrame {
  _tag: string;
  requestId?: string | number;
  values?: ThreadStreamItem[];
  exit?: RpcExit;
}

interface ThreadEvent {
  threadId?: string;
  type: string;
  payload: Object;
}

interface ThreadMessageProjection {
  messages: NativeMessage[];
  thread?: NativeThread;
}

export interface ThreadStreamItem {
  kind: string;
  snapshotSequence?: number;
  historyCursor?: string | null;
  hasMoreHistory?: boolean;
  projection?: ThreadMessageProjection;
  sequence?: number;
  event?: ThreadEvent;
}

interface OrchestrationProject {
  id: string;
  title: string;
  workspaceRoot?: string;
}

interface ShellSnapshot {
  threads: NativeThread[];
  projects?: OrchestrationProject[];
}

export interface RpcRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: Object;
  headers: string[][];
}

interface DispatchMode {
  type: string;
}

interface MessageDispatch {
  type: string;
  commandId: string;
  messageId: string;
  threadId: string;
  creationSource: string;
  createdBy: string;
  text: string;
  dispatchMode: DispatchMode;
  attachments: UploadedThreadAttachment[];
  modelSelection?: ThreadLaunchSelection;
  context?: ThreadMessageContext;
}

export interface ThreadMessageContext {
  version: number;
  records: Object[];
}

interface ThreadSubscription {
  threadId: string;
  afterSequence?: number;
  acceptBoundedSnapshot: boolean;
  requestCompletionMarker: boolean;
}

export const REQUEST_ID = '1';
export const ORCHESTRATION_PROTOCOL = '2';

export function validProviderInstanceId(value: string | undefined): boolean {
  return typeof value === 'string' && /^[a-zA-Z][a-zA-Z0-9_-]{0,63}$/.test(value);
}

export function exchangeBody(credential: string): string {
  return 'grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Atoken-exchange' +
    '&subject_token=' + encodeURIComponent(credential) +
    '&subject_token_type=urn%3At3%3Aparams%3Aoauth%3Atoken-type%3Aenvironment-bootstrap' +
    '&requested_token_type=urn%3Aietf%3Aparams%3Aoauth%3Atoken-type%3Aaccess_token' +
    '&client_label=T3%20Code%20HarmonyOS&client_device_type=mobile&client_os=HarmonyOS';
}

export function dispatchRequest(commandId: string, messageId: string, threadId: string, text: string,
  queue: boolean = false, modelSelection?: ThreadLaunchSelection,
  attachments: UploadedThreadAttachment[] = [], context?: ThreadMessageContext): RpcRequest {
  const payload: MessageDispatch = {
    type: 'message.dispatch',
    commandId,
    messageId,
    threadId,
    creationSource: 'mobile',
    createdBy: 'user',
    text,
    dispatchMode: { type: queue ? 'queue_after_active' : 'start_immediately' },
    attachments,
  };
  if (modelSelection !== undefined) payload.modelSelection = modelSelection;
  if (context && context.records.length > 0) payload.context = context;
  return { _tag: 'Request', id: REQUEST_ID, tag: 'orchestration.dispatchCommand', payload, headers: [] };
}

export function subscribeRequest(threadId: string, afterSequence?: number): RpcRequest {
  const payload: ThreadSubscription = {
    threadId,
    acceptBoundedSnapshot: true,
    requestCompletionMarker: true,
  };
  if (afterSequence !== undefined) payload.afterSequence = afterSequence;
  return { _tag: 'Request', id: REQUEST_ID, tag: 'orchestration.subscribeThread', payload, headers: [] };
}

function nullableString(value: string | null | undefined): string | null | undefined {
  return value === null || typeof value === 'string' ? value : undefined;
}

export function readThreads(value: Object): NativeThread[] {
  const snapshot = value as ShellSnapshot;
  if (!snapshot || !Array.isArray(snapshot.threads)) throw new Error('环境返回的会话列表无效。');
  const projects = new Map<string, OrchestrationProject>();
  if (Array.isArray(snapshot.projects)) {
    for (const project of snapshot.projects) {
      if (project && typeof project.id === 'string' && typeof project.title === 'string') {
        projects.set(project.id, project);
      }
    }
  }
  return snapshot.threads.filter((row: NativeThread) =>
    row && typeof row.id === 'string' && row.id.length > 0 && typeof row.title === 'string' &&
      !(typeof row.deletedAt === 'string' && row.deletedAt.length > 0),
  ).map((row: NativeThread): NativeThread => ({
    id: row.id,
    title: row.title,
    projectId: row.projectId,
    projectTitle: row.projectId ? projects.get(row.projectId)?.title : undefined,
    workspaceRoot: row.projectId ? projects.get(row.projectId)?.workspaceRoot : undefined,
    worktreePath: typeof row.worktreePath === 'string' && row.worktreePath ? row.worktreePath : undefined,
    lineage: row.lineage,
    createdAt: typeof row.createdAt === 'string' ? row.createdAt : undefined,
    updatedAt: row.updatedAt,
    archivedAt: nullableString(row.archivedAt),
    settledOverride: row.settledOverride === 'settled' || row.settledOverride === 'active' ||
      row.settledOverride === null ? row.settledOverride : undefined,
    settledAt: nullableString(row.settledAt),
    unsettledAt: nullableString(row.unsettledAt),
    pinnedAt: nullableString(row.pinnedAt),
    pinOrderKey: nullableString(row.pinOrderKey),
    activeOrderKey: nullableString(row.activeOrderKey),
    snoozedAt: nullableString(row.snoozedAt),
    snoozedUntil: nullableString(row.snoozedUntil),
    status: typeof row.status === 'string' ? row.status : undefined,
    activityRunStatus: nullableString(row.activityRunStatus),
    activeRunId: nullableString(row.activeRunId),
    latestRunId: nullableString(row.latestRunId),
    latestRunRequestedAt: nullableString(row.latestRunRequestedAt),
    latestRunStartedAt: nullableString(row.latestRunStartedAt),
    latestRunCompletedAt: nullableString(row.latestRunCompletedAt),
    latestUserMessageAt: nullableString(row.latestUserMessageAt),
    lastVisitedAt: nullableString(row.lastVisitedAt),
    pendingRuntimeRequest: row.pendingRuntimeRequest &&
      typeof row.pendingRuntimeRequest.kind === 'string' &&
      typeof row.pendingRuntimeRequest.createdAt === 'string' ? row.pendingRuntimeRequest : null,
    pendingGuestMessageCount: typeof row.pendingGuestMessageCount === 'number' ? row.pendingGuestMessageCount : undefined,
    pendingBackgroundTasks: readThreadBackgroundTasks(row.pendingBackgroundTasks, row.id),
  }));
}

function attachmentText(value: string, limit: number): boolean {
  return typeof value === 'string' && value.length > 0 && value.length <= limit &&
    value.trim() === value && !/[\x00-\x1f\x7f]/.test(value);
}

export function readThreadAttachment(value: Object): NativeThreadAttachment | undefined {
  const attachment = value as NativeThreadAttachment;
  if (!attachment || (attachment.type !== 'image' && attachment.type !== 'file') ||
    typeof attachment.id !== 'string' || !/^[a-z0-9_-]{1,128}$/i.test(attachment.id) ||
    !attachmentText(attachment.name, 255) || !attachmentText(attachment.mimeType, 100) ||
    !Number.isSafeInteger(attachment.sizeBytes)) return undefined;
  if (attachment.type === 'image' ? !/^image\//i.test(attachment.mimeType) ||
    attachment.sizeBytes < 0 || attachment.sizeBytes > 10 * 1024 * 1024 :
    attachment.sizeBytes < 1 || attachment.sizeBytes > 50 * 1024 * 1024) return undefined;
  return { type: attachment.type, id: attachment.id, name: attachment.name,
    mimeType: attachment.mimeType, sizeBytes: attachment.sizeBytes };
}

export function readMessage(value: Object): NativeMessage | undefined {
  const message = value as NativeMessage;
  if (!message || typeof message.id !== 'string' || message.id.length === 0 ||
    typeof message.role !== 'string' || typeof message.text !== 'string') return undefined;
  const result: NativeMessage = {
    id: message.id,
    role: message.role,
    text: message.text,
    streaming: message.streaming === true,
    createdAt: typeof message.createdAt === 'string' ? message.createdAt : undefined,
  };
  if (Array.isArray(message.attachments) && message.attachments.length > 0) {
    result.attachmentNames = message.attachments.flatMap((item: NativeThreadAttachment): string[] =>
      typeof item?.name === 'string' && !!item.name.trim() ? [item.name] : []);
    const attachments: NativeThreadAttachment[] = [];
    for (const item of message.attachments) {
      const attachment = readThreadAttachment(item);
      if (attachment) attachments.push(attachment);
    }
    if (attachments.length > 0) result.attachments = attachments;
  }
  if (typeof message.threadId === 'string') result.threadId = message.threadId;
  if (typeof message.runId === 'string' && message.runId) result.runId = message.runId;
  if (message.context?.version === 1 && Array.isArray(message.context.records) && message.context.records.length <= 200) {
    result.context = message.context;
  }
  return result;
}

export function readMessages(value: Object): NativeMessage[] {
  const snapshot = value as ThreadMessageProjection;
  if (!snapshot || !Array.isArray(snapshot.messages)) throw new Error('环境返回的消息无效。');
  const messages: NativeMessage[] = [];
  for (const item of snapshot.messages) {
    const message = readMessage(item);
    if (message) messages.push(message);
  }
  return messages;
}

export function mergeMessages(messages: NativeMessage[], updated: NativeMessage[]): NativeMessage[] {
  const ordered = new Map<string, NativeMessage>();
  for (const existing of messages) ordered.set(existing.id, existing);
  for (const message of updated) ordered.set(message.id, message);
  return Array.from(ordered.values());
}
