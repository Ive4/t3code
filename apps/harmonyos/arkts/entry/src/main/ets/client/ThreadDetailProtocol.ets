import { REQUEST_ID, validProviderInstanceId } from './T3Protocol';
import { ThreadAgentsProjection } from './ThreadAgentsProtocol';
import type { NativeThreadSubagentRun, NativeThreadTurnSubagents } from './ThreadAgentsProtocol';
import { backgroundPullRequestIsWatched, hasNativeThreadBackgroundWork, isPersistentThreadBackgroundTool,
  readBackgroundPullRequestIdentity, readThreadBackgroundTasks } from './ThreadBackgroundWorkProtocol';
import type { NativeThreadBackgroundPullRequestWatch } from './ThreadBackgroundWorkProtocol';
import { ThreadCheckpointProjection } from './ThreadCheckpointProtocol';
import type { NativeThreadCheckpointSummary } from './ThreadCheckpointProtocol';
import { readProjectedThreadForkSource, supportsProjectedThreadFork } from './ThreadForkProtocol';
import type { NativeThreadForkSource } from './ThreadForkProtocol';
import { readThreadCitationPreview } from './ThreadCitationProtocol';
import { readThreadRuntimeMode } from './ThreadLaunchProtocol';
import type { ThreadLaunchRuntimeMode, ThreadLaunchSelection } from './ThreadLaunchProtocol';
import { readThreadModelSelection, threadModelSelectionsEqual } from './ThreadModelOptionProtocol';

export interface NativeThreadWork {
  id: string;
  threadId: string;
  runId?: string;
  type: string;
  wantsOutput: boolean;
  title: string;
  detail: string;
  status: string;
  timestamp: string;
}

export interface NativeThreadApprovalOption {
  decision: string;
  label: string;
  warning?: string;
}

export interface NativeThreadApproval {
  id: string;
  prompt: string;
  reason: string;
  options: NativeThreadApprovalOption[];
  canRespond: boolean;
  supportsFeedback: boolean;
}

export interface NativeThreadUserInputOption {
  label: string;
  description: string;
  value?: string;
  preview?: string;
}

export interface NativeThreadUserInputQuestion {
  id: string;
  header: string;
  question: string;
  options: NativeThreadUserInputOption[];
  multiSelect?: boolean;
  allowCustomAnswer?: boolean;
  initialAnswer?: string;
  required?: boolean;
}

export interface NativeThreadUserInput {
  id: string;
  questions: NativeThreadUserInputQuestion[];
  canRespond: boolean;
  dismissible: boolean;
  reason: string;
  stopRunId: string;
}

export interface NativeThreadUserInputDraft {
  selected?: string[];
  custom?: string;
}

type NativeThreadUserInputAnswer = string | string[];
export type NativeThreadUserInputAnswers = Record<string, NativeThreadUserInputAnswer>;

export interface NativeQueuedMessage {
  runId: string;
  messageId: string;
  text: string;
  attachments: string[];
  sender: string;
  canEdit: boolean;
  canSendNow: boolean;
  targetRunId: string;
  revision: number;
}

export interface NativeThreadDetail {
  title: string;
  modelLabel: string;
  modelSelection?: ThreadLaunchSelection;
  runtimeMode?: ThreadLaunchRuntimeMode;
  canSwitchProvider: boolean;
  worktreePath: string;
  activeRunId: string;
  backgroundStopRunId: string;
  backgroundStopWatches: NativeThreadBackgroundPullRequestWatch[];
  runBusy: boolean;
  queuedCount: number;
  queueHeld: boolean;
  queuedMessages: NativeQueuedMessage[];
  queueEditBlocked: boolean;
  approval: NativeThreadApproval | undefined;
  userInput?: NativeThreadUserInput;
  work: NativeThreadWork[];
  activityIds: string[];
  checkpoints: NativeThreadCheckpointSummary[];
  subagents?: NativeThreadTurnSubagents;
}

interface ThreadModel {
  instanceId?: string;
  provider?: string;
  model: string;
  options?: Object;
}

interface ThreadRecord {
  id: string;
  title: string;
  modelSelection?: ThreadModel;
  runtimeMode?: string;
  worktreePath?: string | null;
  activeProviderThreadId?: string | null;
  historyOrigin?: string;
  archivedAt?: string | null;
  deletedAt?: string | null;
  pullRequests?: Object[];
}

interface RunRecord extends NativeThreadSubagentRun {
  threadId: string;
  queueHeld?: boolean;
  queuePosition?: number | null;
  providerThreadId?: string | null;
  userMessageId?: string;
  activeAttemptId?: string | null;
  freshContext?: boolean;
  outputSchema?: Object;
}

interface QueueAttachmentRecord {
  name: string;
}

interface GuestMessageRecord {
  name: string;
  text: string;
}

interface QueueMessageContext {
  guest?: GuestMessageRecord;
}

interface QueueLinkedSender {
  title: string;
}

interface QueueMessageRecord {
  id: string;
  threadId: string;
  role: string;
  text: string;
  updatedAt: string;
  createdBy?: string;
  scheduledTaskId?: string;
  linkedSender?: QueueLinkedSender;
  attachments?: QueueAttachmentRecord[];
  context?: QueueMessageContext;
  delegatedCompletion?: Object;
  notification?: Object;
}

interface SessionCapabilities {
  supportsProviderSwitchingViaHandoff: boolean;
}

interface TurnCapabilities {
  supportsActiveSteering: boolean;
  supportsInterrupt: boolean;
  supportsSteeringByInterruptRestart: boolean;
}

interface ProviderCapabilities {
  sessions: SessionCapabilities;
  turns?: TurnCapabilities;
}

interface ProviderSessionRecord {
  id: string;
  status: string;
  capabilities: ProviderCapabilities;
}

interface DetachedSessionRecord {
  providerSessionId: string;
}

interface ProviderThreadRecord {
  id: string;
  appThreadId: string | null;
  providerInstanceId: string;
  providerSessionId: string | null;
  status: string;
  firstRunOrdinal: number | null;
  nativeThreadRef: Object | null;
  pendingBackgroundTasks?: Object[];
}

interface ProviderTurnRecord {
  id: string;
  runAttemptId: string | null;
  status: string;
}

interface RuntimeResponseCapability {
  type: string;
  reason?: string;
  supportsFeedback?: boolean;
}

interface RuntimeRequestRecord {
  id: string;
  kind: string;
  status: string;
  createdAt: string;
  responseCapability: RuntimeResponseCapability;
}

interface ToolFailure {
  message?: string;
}

interface TurnItemRecord {
  id: string;
  threadId: string;
  runId?: string | null;
  type: string;
  status: string;
  messageId?: string;
  providerThreadId?: string | null;
  streaming?: boolean;
  title?: string | null;
  startedAt?: string | null;
  updatedAt: string;
  input?: string;
  output?: string;
  outputOmitted?: boolean;
  exitCode?: number;
  outputIndicatesFailure?: boolean;
  fileName?: string;
  additions?: number;
  deletions?: number;
  failure?: ToolFailure;
  requestId?: string;
  prompt?: string;
  reason?: string;
  options?: NativeThreadApprovalOption[];
  questions?: NativeThreadUserInputQuestion[];
}

interface VisibleTurnItemRecord {
  item: TurnItemRecord;
  sourceThreadId: string;
  sourceItemId: string;
  visibility: string;
}

interface ThreadDetailSnapshot {
  thread: ThreadRecord;
  runs: RunRecord[];
  runtimeRequests: RuntimeRequestRecord[];
  turnItems: TurnItemRecord[];
  visibleTurnItems: VisibleTurnItemRecord[];
  messages?: QueueMessageRecord[];
  providerThreads?: ProviderThreadRecord[];
  providerSessions?: ProviderSessionRecord[];
  providerTurns?: ProviderTurnRecord[];
  subagents?: Object[];
}

interface ProjectedWork {
  row: NativeThreadWork;
  updatedAt: string;
}

interface BackgroundTurnItem {
  runId?: string | null;
  pending: boolean;
  updatedAt: string;
}

interface ThreadControlCommand {
  type: string;
  commandId: string;
  threadId: string;
  runId?: string;
  queuedRunId?: string;
  targetRunId?: string;
  text?: string;
  holdQueue?: boolean;
  host?: string;
  repository?: string;
  number?: number;
  watching?: boolean;
  requestId?: string;
  decision?: string;
  feedback?: string;
  answers?: NativeThreadUserInputAnswers;
  modelSelection?: ThreadLaunchSelection;
  runtimeMode?: ThreadLaunchRuntimeMode;
}

interface ThreadControlRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: ThreadControlCommand;
  headers: string[][];
}

interface BackgroundStopCapabilities {
  threadStop?: boolean;
}

interface BackgroundStopEnvironment {
  capabilities?: BackgroundStopCapabilities;
}

interface BackgroundStopConfig {
  environment?: BackgroundStopEnvironment;
}

const INTERRUPTIBLE_RUNS = new Set<string>(['preparing', 'starting', 'running']);
const BACKGROUND_SETTLED_RUNS = new Set<string>(['cancelled', 'completed', 'failed', 'interrupted', 'waiting']);
const BACKGROUND_TURN_ITEMS = new Set<string>(['command_execution', 'dynamic_tool', 'subagent']);
const ACTIVE_BACKGROUND_ITEMS = new Set<string>(['pending', 'running', 'waiting']);
const NO_BACKGROUND_WATCHES: NativeThreadBackgroundPullRequestWatch[] = [];
const ATTACHMENT_ONLY_PROMPT =
  '[User attached one or more files without additional text. Respond using the conversation context and the attached files.]';
const APPROVAL_KINDS = new Set<string>(['command', 'file-read', 'file-change', 'mcp-elicitation', 'permission']);
const APPROVAL_DECISIONS = new Set<string>(['accept', 'acceptForSession', 'acceptAlways', 'decline', 'cancel']);
const DEFAULT_APPROVAL_OPTIONS: NativeThreadApprovalOption[] = [
  { decision: 'accept', label: '允许一次' },
  { decision: 'acceptForSession', label: '本次会话允许' },
  { decision: 'decline', label: '拒绝' },
];

function nonEmpty(value: string | null | undefined): boolean {
  return typeof value === 'string' && value.length > 0;
}

function sameQueueRow(left: NativeQueuedMessage, right: NativeQueuedMessage): boolean {
  return left.runId === right.runId && left.messageId === right.messageId && left.text === right.text &&
    left.sender === right.sender && left.canEdit === right.canEdit && left.canSendNow === right.canSendNow &&
    left.targetRunId === right.targetRunId && left.attachments.length === right.attachments.length &&
    left.attachments.every((name: string, index: number): boolean => name === right.attachments[index]);
}

export function queuedMessageEditorText(text: string): string {
  return text.replace(/^Ultrathink:\s*/i, '') === ATTACHMENT_ONLY_PROMPT
    ? text.slice(0, -ATTACHMENT_ONLY_PROMPT.length).trimEnd() : text;
}

export function queuedMessageSubmissionText(text: string, hasAttachments: boolean): string {
  if (!hasAttachments) return text;
  const trimmed = text.trim();
  if (!trimmed) return ATTACHMENT_ONLY_PROMPT;
  return /^Ultrathink:\s*$/i.test(trimmed) ? `Ultrathink:\n${ATTACHMENT_ONLY_PROMPT}` : text;
}

export function queuedMessagePreview(text: string): string {
  if (text.replace(/^Ultrathink:\s*/i, '') === ATTACHMENT_ONLY_PROMPT) return '';
  return text.replace(/!?\[([^\[\]\r\n]{0,512})\]\(t3-context:\/\/v1\/[^\s)]{1,200}\)/g, '$1')
    .replace(/\[Assistant quote\]\((t3-citation:\/\/v1\/[^\s)]+)\)/g,
      (source: string, href: string): string => readThreadCitationPreview(href) ?? source)
    .trim();
}

function controlRequest(payload: ThreadControlCommand): ThreadControlRequest {
  return { _tag: 'Request', id: REQUEST_ID, tag: 'orchestration.dispatchCommand', payload, headers: [] };
}

export function interruptRequest(commandId: string, threadId: string, runId: string): ThreadControlRequest {
  return controlRequest({ type: 'run.interrupt', commandId, threadId, runId, holdQueue: true });
}

export function backgroundWorkStopRequest(commandId: string, threadId: string, config: Object,
  fallbackRunId?: string): ThreadControlRequest | undefined {
  if (!nonEmpty(commandId) || !nonEmpty(threadId)) return undefined;
  if ((config as BackgroundStopConfig)?.environment?.capabilities?.threadStop === true) {
    return controlRequest({ type: 'thread.stop', commandId, threadId });
  }
  return fallbackRunId ? interruptRequest(commandId, threadId, fallbackRunId) : undefined;
}

export function backgroundPullRequestStopRequest(commandId: string, threadId: string,
  watch: NativeThreadBackgroundPullRequestWatch): ThreadControlRequest {
  return controlRequest({ type: 'thread.pull-request.watch', commandId, threadId,
    host: watch.host, repository: watch.repository, number: watch.number, watching: false });
}

export function resumeQueueRequest(commandId: string, threadId: string): ThreadControlRequest {
  return controlRequest({ type: 'queue.resume', commandId, threadId });
}

export function startQueuedRunRequest(commandId: string, threadId: string, runId: string): ThreadControlRequest {
  return controlRequest({ type: 'queued-run.start', commandId, threadId, runId });
}

export function promoteQueuedRunRequest(commandId: string, threadId: string,
  queuedRunId: string, targetRunId: string): ThreadControlRequest {
  return controlRequest({ type: 'queued-message.promote-to-steer', commandId, threadId, queuedRunId, targetRunId });
}

export function cancelQueuedRunRequest(commandId: string, threadId: string, runId: string): ThreadControlRequest {
  return controlRequest({ type: 'queued-run.cancel', commandId, threadId, runId });
}

export function editQueuedRunRequest(commandId: string, threadId: string, runId: string,
  text: string): ThreadControlRequest {
  if (!text.trim()) throw new Error('排队消息不能为空。');
  return controlRequest({ type: 'queued-run.edit', commandId, threadId, runId, text });
}

export function modelSelectionRequest(commandId: string, threadId: string,
  modelSelection: ThreadLaunchSelection): ThreadControlRequest {
  if (!validProviderInstanceId(modelSelection.instanceId) || !modelSelection.model.trim()) {
    throw new Error('请选择可用的模型。');
  }
  return controlRequest({ type: 'thread.model-selection.set', commandId, threadId, modelSelection });
}

export function runtimeModeSelectionRequest(commandId: string, threadId: string,
  runtimeMode: ThreadLaunchRuntimeMode): ThreadControlRequest {
  if (readThreadRuntimeMode(runtimeMode) === undefined) throw new Error('请选择可用的运行模式。');
  return controlRequest({ type: 'thread.runtime-mode.set', commandId, threadId, runtimeMode });
}

export function respondApprovalRequest(commandId: string, threadId: string, requestId: string,
  decision: string, feedback?: string): ThreadControlRequest {
  if (!APPROVAL_DECISIONS.has(decision)) throw new Error('审批选项无效。');
  const command: ThreadControlCommand = { type: 'runtime-request.respond', commandId, threadId, requestId, decision };
  if (feedback !== undefined) {
    const text = feedback.trim();
    if (decision !== 'decline' || !text) throw new Error('仅可在拒绝审批时发送非空反馈。');
    command.feedback = text;
  }
  return controlRequest(command);
}

export function respondUserInputRequest(commandId: string, threadId: string, requestId: string,
  answers: NativeThreadUserInputAnswers): ThreadControlRequest {
  return controlRequest({ type: 'runtime-request.respond', commandId, threadId, requestId, answers });
}

export function dismissUserInputRequest(commandId: string, threadId: string,
  requestId: string): ThreadControlRequest {
  return controlRequest({ type: 'thread.user-input.dismiss', commandId, threadId, requestId });
}

export function userInputOptionValue(option: NativeThreadUserInputOption): string {
  return option.value ?? option.label.trim();
}

export function userInputCustomAnswer(question: NativeThreadUserInputQuestion,
  draft: NativeThreadUserInputDraft | undefined): string {
  return question.allowCustomAnswer === false ? '' : draft?.custom ?? question.initialAnswer ?? '';
}

export function buildUserInputAnswers(questions: NativeThreadUserInputQuestion[],
  drafts: Map<string, NativeThreadUserInputDraft>,
  messageResponse: boolean = false): NativeThreadUserInputAnswers | undefined {
  // A provider may use __proto__ as a question ID. Seed an own property before writing it.
  const answers: NativeThreadUserInputAnswers = questions.some((question) => question.id === '__proto__')
    ? JSON.parse('{"__proto__":""}') as NativeThreadUserInputAnswers : {};
  let hasAnswer = false;
  for (const question of questions) {
    const draft = drafts.get(question.id);
    const custom = userInputCustomAnswer(question, draft);
    const editorAnswer = !messageResponse && question.initialAnswer !== undefined && question.allowCustomAnswer !== false;
    if (custom.trim() || (editorAnswer && custom.length > 0)) {
      answers[question.id] = question.initialAnswer === undefined ? custom.trim() : custom;
      hasAnswer = true;
      continue;
    }
    const offered = new Set<string>(question.options.map(userInputOptionValue));
    const selected = Array.from(new Set<string>(draft?.selected)).filter((value: string): boolean => offered.has(value));
    if (selected.length > 0) {
      const answer = question.multiSelect ? selected : selected[0];
      const blank = question.multiSelect ? selected.some((value: string): boolean => !value.trim()) : !selected[0].trim();
      if (messageResponse && blank && question.required !== false) return undefined;
      answers[question.id] = messageResponse && blank ? '' : answer;
      hasAnswer = hasAnswer || !blank;
    } else if (question.required === false || editorAnswer) {
      answers[question.id] = '';
    } else {
      return undefined;
    }
  }
  return messageResponse && !hasAnswer ? undefined : answers;
}

interface ThreadWorkDetailReply {
  item?: TurnItemRecord | null;
}

interface ThreadWorkDetailInput {
  threadId: string;
  itemId: string;
}

interface ThreadWorkDetailRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: ThreadWorkDetailInput;
  headers: string[][];
}

export function threadWorkDetailRequest(threadId: string, itemId: string): ThreadWorkDetailRequest {
  return { _tag: 'Request', id: REQUEST_ID, tag: 'orchestration.getTurnItem',
    payload: { threadId, itemId }, headers: [] };
}

function workCommandText(item: TurnItemRecord): string {
  return [item.input ?? '', item.output ?? ''].filter((part: string): boolean => part.length > 0).join('\n');
}

export function readThreadWorkDetail(value: Object, threadId: string, itemId: string): string {
  const item = (value as ThreadWorkDetailReply)?.item;
  if (!item || item.threadId !== threadId || item.id !== itemId || item.type !== 'command_execution') {
    throw new Error('环境未返回对应的命令输出。');
  }
  return workCommandText(item);
}

function workRow(item: TurnItemRecord, previous: NativeThreadWork | undefined): NativeThreadWork | undefined {
  let title: string;
  let detail: string;
  let status = item.status;
  if (item.type === 'command_execution') {
    title = item.title || '执行命令';
    detail = workCommandText(item);
    const failed = item.exitCode === undefined ? item.outputIndicatesFailure === true : item.exitCode !== 0;
    if (status === 'completed' && failed) status = 'failed';
  } else if (item.type === 'file_change') {
    title = item.title || '文件变更';
    detail = item.fileName ?? '';
    if (typeof item.additions === 'number') detail += ` +${item.additions}`;
    if (typeof item.deletions === 'number') detail += ` -${item.deletions}`;
  } else if (item.type === 'error') {
    title = item.title || '运行错误';
    detail = item.failure?.message ?? '';
  } else {
    return undefined;
  }
  return {
    id: item.id,
    threadId: item.threadId,
    runId: item.runId ?? undefined,
    type: item.type,
    wantsOutput: item.outputOmitted === true,
    title,
    detail,
    status,
    timestamp: previous?.timestamp ?? item.startedAt ?? item.updatedAt,
  };
}

function threadActivityId(item: TurnItemRecord): string | undefined {
  switch (item.type) {
    case 'user_message':
    case 'assistant_message': return item.messageId ? 'message:' + item.messageId : undefined;
    case 'command_execution':
    case 'file_change':
    case 'error': return 'work:' + item.id;
    default: return undefined;
  }
}

export function readThreadActivityIds(items: Object[]): string[] {
  const ids = new Set<string>();
  for (const value of items) {
    const item = (value as VisibleTurnItemRecord).item;
    if (!item) continue;
    const id = threadActivityId(item);
    if (id) ids.add(id);
  }
  return Array.from(ids);
}

export function readHistoricalThreadWork(items: Object[]): NativeThreadWork[] {
  const work: NativeThreadWork[] = [];
  for (const visible of items) {
    const item = (visible as VisibleTurnItemRecord).item;
    if (!item || !nonEmpty(item.updatedAt) || typeof item.status !== 'string') continue;
    const row = workRow(item, undefined);
    if (row !== undefined) work.push(row);
  }
  return work;
}

export class ThreadDetailProjection {
  private readonly threadId: string;
  private readonly checkpointProjection: ThreadCheckpointProjection;
  private readonly agentsProjection: ThreadAgentsProjection;
  private title: string = '';
  private modelLabel: string = '';
  private modelSelection: ThreadLaunchSelection | undefined = undefined;
  private runtimeMode: ThreadLaunchRuntimeMode | undefined = undefined;
  private activeProviderThreadId: string | null = null;
  private historyOrigin: string | undefined = undefined;
  private worktreePath: string = '';
  private threadClosed: boolean = false;
  private readonly runs = new Map<string, RunRecord>();
  private readonly messages = new Map<string, QueueMessageRecord>();
  private queuedMessages: NativeQueuedMessage[] = [];
  private queueRevision: number = 0;
  private readonly providerThreads = new Map<string, ProviderThreadRecord>();
  private readonly providerSessions = new Map<string, ProviderSessionRecord>();
  private readonly runningProviderTurns = new Map<string, string>();
  private readonly forkAssistantItems = new Map<string, VisibleTurnItemRecord>();
  private forkSources?: Map<string, NativeThreadForkSource> = undefined;
  private readonly work = new Map<string, ProjectedWork>();
  private readonly activityIds = new Set<string>();
  private readonly backgroundTurnItems = new Map<string, BackgroundTurnItem>();
  private backgroundStopWatches: NativeThreadBackgroundPullRequestWatch[] = NO_BACKGROUND_WATCHES;
  private readonly runtimeRequests = new Map<string, RuntimeRequestRecord>();
  private readonly requestItems = new Map<string, TurnItemRecord>();
  private projectedUserInput: NativeThreadUserInput | undefined = undefined;

  constructor(threadId: string) {
    this.threadId = threadId;
    this.checkpointProjection = new ThreadCheckpointProjection(threadId);
    this.agentsProjection = new ThreadAgentsProjection(threadId);
  }

  reset(value: Object): void {
    const snapshot = value as ThreadDetailSnapshot;
    if (!snapshot?.thread || snapshot.thread.id !== this.threadId) return;
    this.runs.clear();
    this.messages.clear();
    this.providerThreads.clear();
    this.providerSessions.clear();
    this.runningProviderTurns.clear();
    this.forkAssistantItems.clear();
    this.forkSources = undefined;
    this.work.clear();
    this.activityIds.clear();
    this.backgroundTurnItems.clear();
    this.backgroundStopWatches = NO_BACKGROUND_WATCHES;
    this.runtimeRequests.clear();
    this.requestItems.clear();
    this.checkpointProjection.reset(value);
    this.agentsProjection.reset(snapshot.subagents);
    this.updateThread(snapshot.thread);
    if (Array.isArray(snapshot.runs)) {
      for (const run of snapshot.runs) this.updateRun(run);
    }
    if (Array.isArray(snapshot.messages)) {
      for (const message of snapshot.messages) this.updateMessage(message);
    }
    if (Array.isArray(snapshot.providerThreads)) {
      for (const thread of snapshot.providerThreads) this.providerThreads.set(thread.id, thread);
    }
    if (Array.isArray(snapshot.providerSessions)) {
      for (const session of snapshot.providerSessions) this.providerSessions.set(session.id, session);
    }
    if (Array.isArray(snapshot.providerTurns)) {
      for (const turn of snapshot.providerTurns) this.updateProviderTurn(turn);
    }
    if (Array.isArray(snapshot.runtimeRequests)) {
      for (const request of snapshot.runtimeRequests) this.updateRuntimeRequest(request);
    }
    if (Array.isArray(snapshot.visibleTurnItems)) {
      for (const visible of snapshot.visibleTurnItems) {
        this.updateTurnItem(visible?.item, true);
        this.updateReplyForkItem(visible);
      }
    }
    if (Array.isArray(snapshot.turnItems)) {
      for (const item of snapshot.turnItems) {
        this.updateTurnItem(item);
        this.updateLocalReplyForkItem(item);
      }
    }
  }

  apply(type: string, payload: Object): boolean {
    switch (type) {
      case 'thread.created':
      case 'thread.archived':
      case 'thread.unarchived':
      case 'thread.deleted':
      case 'thread.metadata-updated':
      case 'thread.pull-request-synced':
      case 'thread.model-selection-updated':
      case 'thread.runtime-mode-updated':
      case 'thread.provider-switched':
        return this.updateThread(payload as ThreadRecord);
      case 'thread.pull-request-link-updated':
        return this.updateBackgroundWatch(payload);
      case 'run.created':
      case 'run.updated':
        return this.updateRun(payload as RunRecord);
      case 'subagent.updated':
        return this.agentsProjection.update(payload);
      case 'message.updated':
        return this.updateMessage(payload as QueueMessageRecord) || this.checkpointProjection.updateAssistant(payload);
      case 'checkpoint-scope.created':
        return this.checkpointProjection.updateScope(payload);
      case 'checkpoint.captured':
        return this.checkpointProjection.updateCheckpoint(payload);
      case 'provider-thread.updated':
        return this.updateProviderThread(payload as ProviderThreadRecord);
      case 'provider-session.attached':
      case 'provider-session.updated':
        return this.updateProviderSession(payload as ProviderSessionRecord);
      case 'provider-session.detached':
        if (!this.providerSessions.delete((payload as DetachedSessionRecord).providerSessionId)) return false;
        this.forkSources = undefined;
        return true;
      case 'provider-turn.updated':
        return this.updateProviderTurn(payload as ProviderTurnRecord);
      case 'turn-item.updated': {
        const item = payload as TurnItemRecord;
        const changed = this.updateTurnItem(item);
        return this.updateLocalReplyForkItem(item) || changed;
      }
      case 'runtime-request.updated':
        return this.updateRuntimeRequest(payload as RuntimeRequestRecord);
      default:
        return false;
    }
  }

  replyForkSources(): Map<string, NativeThreadForkSource> {
    if (this.forkSources !== undefined) return this.forkSources;
    const sources = new Map<string, NativeThreadForkSource>();
    for (const row of this.forkAssistantItems.values()) {
      const runId = row.item.runId;
      const messageId = row.item.messageId;
      const run = row.sourceThreadId === this.threadId && runId ? this.runs.get(runId) : undefined;
      if (run && run.status !== 'completed' && run.status !== 'waiting' && run.status !== 'failed' &&
        run.status !== 'interrupted' && run.status !== 'cancelled') continue;
      const providerId = row.item.providerThreadId;
      const sessionId = providerId ? this.providerThreads.get(providerId)?.providerSessionId : undefined;
      const capability = sessionId ? this.providerSessions.get(sessionId)?.capabilities : undefined;
      const source = readProjectedThreadForkSource(row, capability);
      if (source && messageId) sources.set(messageId, source);
    }
    this.forkSources = sources;
    return sources;
  }

  private updateLocalReplyForkItem(item: TurnItemRecord): boolean {
    if (item?.type !== 'assistant_message' || item.threadId !== this.threadId) return false;
    const row: VisibleTurnItemRecord = { item, sourceThreadId: this.threadId, sourceItemId: item.id, visibility: 'local' };
    return this.updateReplyForkItem(row);
  }

  private updateReplyForkItem(row?: VisibleTurnItemRecord): boolean {
    const item = row?.item;
    const messageId = item?.messageId;
    if (!row || !item || item.type !== 'assistant_message' || !messageId || !item.id || !item.updatedAt ||
      row.sourceThreadId !== item.threadId || row.sourceItemId !== item.id ||
      (row.visibility === 'local' ? item.threadId !== this.threadId :
        row.visibility !== 'inherited' || item.threadId === this.threadId)) return false;
    const previous = this.forkAssistantItems.get(messageId)?.item;
    if (previous && previous.updatedAt > item.updatedAt) return false;
    if (previous && previous.id === item.id && previous.threadId === item.threadId && previous.runId === item.runId &&
      previous.status === item.status && previous.streaming === item.streaming &&
      previous.providerThreadId === item.providerThreadId) {
      previous.updatedAt = item.updatedAt;
      return false;
    }
    const source: TurnItemRecord = {
      id: item.id, type: item.type, threadId: item.threadId, status: item.status, runId: item.runId, messageId,
      updatedAt: item.updatedAt, streaming: item.streaming, providerThreadId: item.providerThreadId,
    };
    this.forkAssistantItems.set(messageId, {
      item: source, sourceThreadId: row.sourceThreadId, sourceItemId: row.sourceItemId, visibility: row.visibility,
    });
    this.forkSources = undefined;
    return true;
  }

  view(): NativeThreadDetail {
    let activeRunId: string = '';
    let backgroundActiveRunId: string = '';
    let lastRun: RunRecord | undefined;
    let interruptibleOrdinal: number = -1;
    let activeRun: RunRecord | undefined;
    const queuedRuns: RunRecord[] = [];
    let queueHeld: boolean = false;
    for (const run of this.runs.values()) {
      lastRun = run;
      if (run.status === 'queued') {
        queuedRuns.push(run);
        queueHeld = queueHeld || run.queueHeld === true;
      } else if (INTERRUPTIBLE_RUNS.has(run.status) || run.status === 'waiting') {
        backgroundActiveRunId = run.id;
        if (activeRun === undefined || run.ordinal > activeRun.ordinal) activeRun = run;
        if (run.status !== 'waiting' && run.ordinal > interruptibleOrdinal) {
          interruptibleOrdinal = run.ordinal;
          activeRunId = run.id;
        }
      }
    }
    const backgroundStopRunId = backgroundActiveRunId || (lastRun && BACKGROUND_SETTLED_RUNS.has(lastRun.status) &&
      this.hasProjectedBackgroundWork() ? lastRun.id : '');
    const providerSession = this.providerSession(activeRun);
    return {
      title: this.title,
      modelLabel: this.modelLabel,
      modelSelection: this.modelSelection,
      runtimeMode: this.runtimeMode,
      canSwitchProvider: this.canSwitchProvider(activeRun, providerSession),
      worktreePath: this.worktreePath,
      activeRunId,
      backgroundStopRunId: this.threadClosed ? '' : backgroundStopRunId,
      backgroundStopWatches: this.threadClosed ? NO_BACKGROUND_WATCHES : this.backgroundStopWatches,
      runBusy: activeRun !== undefined,
      queuedCount: queuedRuns.length,
      queueHeld,
      queuedMessages: this.queueRows(queuedRuns, activeRun, providerSession?.capabilities?.turns),
      queueEditBlocked: Array.from(this.runtimeRequests.values()).some((request: RuntimeRequestRecord): boolean =>
        request.kind === 'user_input' && request.status === 'pending'),
      approval: this.pendingApproval(),
      userInput: this.pendingUserInput(activeRun?.id ?? ''),
      work: Array.from(this.work.values(), (work: ProjectedWork): NativeThreadWork => work.row),
      activityIds: Array.from(this.activityIds),
      checkpoints: this.checkpointProjection.view(),
      subagents: this.agentsProjection.view(this.runs.values()),
    };
  }

  private updateThread(thread: ThreadRecord): boolean {
    if (thread?.id !== this.threadId || typeof thread.title !== 'string') return false;
    const model = typeof thread.modelSelection?.model === 'string' ? thread.modelSelection.model : '';
    const selection = readThreadModelSelection(thread.modelSelection);
    const runtimeMode = readThreadRuntimeMode(thread.runtimeMode);
    const worktree = typeof thread.worktreePath === 'string' ? thread.worktreePath : '';
    const providerThreadId = thread.activeProviderThreadId ?? null;
    const threadClosed = thread.archivedAt != null || thread.deletedAt != null;
    const watchesChanged = this.resetBackgroundWatches(thread.pullRequests);
    if (this.title === thread.title && this.modelLabel === model && this.worktreePath === worktree &&
      threadModelSelectionsEqual(this.modelSelection, selection) &&
      this.runtimeMode === runtimeMode &&
      this.activeProviderThreadId === providerThreadId && this.historyOrigin === thread.historyOrigin &&
      this.threadClosed === threadClosed) return watchesChanged;
    this.title = thread.title;
    this.modelLabel = model;
    this.modelSelection = selection;
    this.runtimeMode = runtimeMode;
    this.activeProviderThreadId = providerThreadId;
    this.historyOrigin = thread.historyOrigin;
    this.worktreePath = worktree;
    this.threadClosed = threadClosed;
    return true;
  }

  private updateRun(run: RunRecord): boolean {
    if (run?.threadId !== this.threadId || !nonEmpty(run.id) ||
      typeof run.ordinal !== 'number' || typeof run.status !== 'string') return false;
    const previous = this.runs.get(run.id);
    if (previous?.status === run.status && previous.ordinal === run.ordinal &&
      previous.queueHeld === run.queueHeld && previous.providerThreadId === run.providerThreadId &&
      previous.queuePosition === run.queuePosition && previous.userMessageId === run.userMessageId &&
      previous.activeAttemptId === run.activeAttemptId && previous.freshContext === run.freshContext &&
      previous.startedAt === run.startedAt &&
      (previous.outputSchema === undefined) === (run.outputSchema === undefined)) return false;
    this.runs.set(run.id, run);
    if (!previous || previous.status !== run.status || previous.ordinal !== run.ordinal || previous.startedAt !== run.startedAt) {
      this.agentsProjection.invalidate();
    }
    if (previous?.status !== run.status) this.forkSources = undefined;
    return true;
  }

  private updateMessage(message: QueueMessageRecord): boolean {
    if (message?.threadId !== this.threadId || message.role !== 'user' || !nonEmpty(message.id) ||
      typeof message.text !== 'string' || !nonEmpty(message.updatedAt)) return false;
    const previous = this.messages.get(message.id);
    if (previous !== undefined && previous.updatedAt > message.updatedAt) return false;
    this.messages.set(message.id, message);
    return true;
  }

  private updateProviderTurn(turn: ProviderTurnRecord): boolean {
    if (!turn || !nonEmpty(turn.id)) return false;
    if (turn.status !== 'running' || !turn.runAttemptId) return this.runningProviderTurns.delete(turn.id);
    if (this.runningProviderTurns.get(turn.id) === turn.runAttemptId) return false;
    this.runningProviderTurns.set(turn.id, turn.runAttemptId);
    return true;
  }

  private queueRows(queuedRuns: RunRecord[], activeRun: RunRecord | undefined,
    capabilities: TurnCapabilities | undefined): NativeQueuedMessage[] {
    const activeMessage = activeRun?.userMessageId ? this.messages.get(activeRun.userMessageId) : undefined;
    const skipsCompaction = activeMessage?.text.trim().toLowerCase() === '/compact' &&
      (activeMessage.attachments?.length ?? 0) === 0;
    const canSteer = activeRun !== undefined &&
      (skipsCompaction || this.canSteerRun(activeRun, capabilities));
    const rows: NativeQueuedMessage[] = [];
    queuedRuns.sort((left: RunRecord, right: RunRecord): number =>
      (left.queuePosition ?? left.ordinal) - (right.queuePosition ?? right.ordinal) || left.ordinal - right.ordinal);
    for (const run of queuedRuns) {
      const message = run.userMessageId ? this.messages.get(run.userMessageId) : undefined;
      if (message?.delegatedCompletion !== undefined || message?.notification !== undefined) continue;
      const guest = message?.context?.guest;
      const canPromote = !this.threadClosed && canSteer &&
        (skipsCompaction || (run.freshContext !== true && run.outputSchema === undefined));
      const targetRunId = canPromote ? activeRun?.id ?? '' : '';
      const attachments = message !== undefined && Array.isArray(message.attachments)
        ? message.attachments.map((attachment: QueueAttachmentRecord): string => attachment?.name ?? '')
          .filter((name: string): boolean => nonEmpty(name))
        : [];
      const sender = guest?.name ?? (message?.scheduledTaskId ? '自动化' :
        message?.createdBy === 'agent' ? (message.linkedSender?.title || '代理') :
        message?.createdBy === 'system' ? 'T3 Code' : '');
      const row: NativeQueuedMessage = {
        runId: run.id,
        messageId: run.userMessageId ?? '',
        text: guest?.text ?? message?.text ?? '',
        attachments,
        sender,
        canEdit: message !== undefined && guest === undefined,
        canSendNow: !this.threadClosed && (activeRun === undefined || targetRunId.length > 0),
        targetRunId,
        revision: 0,
      };
      const previous = this.queuedMessages[rows.length];
      if (previous !== undefined && sameQueueRow(row, previous)) {
        rows.push(previous);
      } else {
        row.revision = ++this.queueRevision;
        rows.push(row);
      }
    }
    if (rows.length !== this.queuedMessages.length || !rows.every((row: NativeQueuedMessage, index: number): boolean =>
      row === this.queuedMessages[index])) this.queuedMessages = rows;
    return this.queuedMessages;
  }

  private canSteerRun(run: RunRecord, capabilities: TurnCapabilities | undefined): boolean {
    const supportsSteering = capabilities !== undefined && (capabilities.supportsActiveSteering ||
      (capabilities.supportsInterrupt && capabilities.supportsSteeringByInterruptRestart));
    if (run.status === 'preparing' || run.status === 'starting') return capabilities === undefined || supportsSteering;
    if (run.status !== 'running' || !supportsSteering || !run.activeAttemptId) return false;
    for (const attemptId of this.runningProviderTurns.values()) {
      if (attemptId === run.activeAttemptId) return true;
    }
    return false;
  }

  private updateProviderThread(thread: ProviderThreadRecord): boolean {
    if (!thread || !nonEmpty(thread.id)) return false;
    const previous = this.providerThreads.get(thread.id);
    this.providerThreads.set(thread.id, thread);
    const placeholder = thread.status === 'not_loaded' && thread.firstRunOrdinal === null &&
      thread.nativeThreadRef === null && thread.providerSessionId === null;
    const activatesThread = thread.appThreadId === this.threadId && !placeholder &&
      this.activeProviderThreadId !== thread.id;
    if (activatesThread) this.activeProviderThreadId = thread.id;
    if (previous?.providerSessionId !== thread.providerSessionId) this.forkSources = undefined;
    return activatesThread || !previous || previous.appThreadId !== thread.appThreadId ||
      previous.providerInstanceId !== thread.providerInstanceId ||
      previous.providerSessionId !== thread.providerSessionId ||
      this.providerHasBackgroundWork(previous) !== this.providerHasBackgroundWork(thread);
  }

  private updateProviderSession(session: ProviderSessionRecord): boolean {
    if (!session || !nonEmpty(session.id)) return false;
    const previous = this.providerSessions.get(session.id);
    this.providerSessions.set(session.id, session);
    const forkChanged = supportsProjectedThreadFork(previous?.capabilities) !== supportsProjectedThreadFork(session.capabilities);
    if (forkChanged) this.forkSources = undefined;
    const previousTurns = previous?.capabilities?.turns;
    const turns = session.capabilities?.turns;
    return !previous || forkChanged || previous.status !== session.status ||
      previous.capabilities?.sessions?.supportsProviderSwitchingViaHandoff !==
      session.capabilities?.sessions?.supportsProviderSwitchingViaHandoff ||
      previousTurns?.supportsActiveSteering !== turns?.supportsActiveSteering ||
      previousTurns?.supportsInterrupt !== turns?.supportsInterrupt ||
      previousTurns?.supportsSteeringByInterruptRestart !== turns?.supportsSteeringByInterruptRestart;
  }

  private providerSession(activeRun: RunRecord | undefined): ProviderSessionRecord | undefined {
    const providerThreadId = activeRun?.providerThreadId ?? this.activeProviderThreadId;
    let attached = providerThreadId === null
      ? undefined
      : this.providerThreads.get(providerThreadId);
    if (attached === undefined) {
      for (const thread of this.providerThreads.values()) {
        if (thread.appThreadId === this.threadId && thread.providerSessionId !== null) {
          attached = thread;
          break;
        }
      }
    }
    const sessionId = attached?.providerSessionId;
    let session: ProviderSessionRecord | undefined;
    if (sessionId != null) {
      session = this.providerSessions.get(sessionId);
    } else {
      for (const candidate of this.providerSessions.values()) {
        if (candidate.status !== 'stopped' && candidate.status !== 'error') session = candidate;
      }
    }
    return session;
  }

  private canSwitchProvider(activeRun: RunRecord | undefined, session: ProviderSessionRecord | undefined): boolean {
    if (!this.modelSelection) return false;
    if (session !== undefined) return session.capabilities?.sessions?.supportsProviderSwitchingViaHandoff === true;
    if (activeRun !== undefined) return false;
    if (this.historyOrigin === 'v1_import' || this.runs.size === 0) return true;
    const saved = this.activeProviderThreadId === null ? undefined : this.providerThreads.get(this.activeProviderThreadId);
    return saved?.appThreadId === this.threadId && saved.providerInstanceId === this.modelSelection.instanceId;
  }

  private updateTurnItem(item: TurnItemRecord | undefined, allowInherited: boolean = false): boolean {
    if (!item || (!allowInherited && item.threadId !== this.threadId) || !nonEmpty(item.id) ||
      !nonEmpty(item.updatedAt) || !nonEmpty(item.status)) return false;
    if (item.type === 'approval_request' || item.type === 'user_input_request') {
      const requestId = item.requestId;
      if (item.threadId !== this.threadId || !requestId) return false;
      const previous = this.requestItems.get(requestId);
      if (previous !== undefined && previous.updatedAt > item.updatedAt) return false;
      this.requestItems.set(requestId, item);
      return true;
    }
    const previous = this.work.get(item.id);
    if (previous !== undefined && previous.updatedAt > item.updatedAt) return false;
    const activityId = threadActivityId(item);
    const added = !!activityId && !this.activityIds.has(activityId);
    if (added && activityId) this.activityIds.add(activityId);
    const backgroundChanged = this.updateBackgroundTurnItem(item);
    const row = workRow(item, previous?.row);
    if (!row) return backgroundChanged || added;
    this.work.set(item.id, { row, updatedAt: item.updatedAt });
    return true;
  }

  private updateBackgroundTurnItem(item: TurnItemRecord): boolean {
    if (item.threadId !== this.threadId || !BACKGROUND_TURN_ITEMS.has(item.type)) return false;
    const previous = this.backgroundTurnItems.get(item.id);
    if (previous && previous.updatedAt > item.updatedAt) return false;
    const pending = ACTIVE_BACKGROUND_ITEMS.has(item.status) &&
      !(item.type === 'dynamic_tool' && isPersistentThreadBackgroundTool(item.input));
    this.backgroundTurnItems.set(item.id, { runId: item.runId, pending, updatedAt: item.updatedAt });
    return (previous?.pending ?? false) !== pending || (pending && previous?.runId !== item.runId);
  }

  private providerHasBackgroundWork(thread?: ProviderThreadRecord): boolean {
    return thread?.appThreadId === this.threadId &&
      hasNativeThreadBackgroundWork(readThreadBackgroundTasks(thread.pendingBackgroundTasks, this.threadId));
  }

  private hasProjectedBackgroundWork(): boolean {
    for (const thread of this.providerThreads.values()) {
      if ((!this.activeProviderThreadId || this.activeProviderThreadId === thread.id) && this.providerHasBackgroundWork(thread)) return true;
    }
    for (const item of this.backgroundTurnItems.values()) {
      if (item.pending && (!item.runId || this.runs.get(item.runId)?.status !== 'rolled_back')) return true;
    }
    return false;
  }

  private resetBackgroundWatches(values?: Object[]): boolean {
    const watches: NativeThreadBackgroundPullRequestWatch[] = [];
    if (Array.isArray(values)) {
      for (const value of values) {
        const identity = readBackgroundPullRequestIdentity(value);
        if (identity && backgroundPullRequestIsWatched(value)) watches.push(identity);
      }
    }
    if (watches.length === this.backgroundStopWatches.length && watches.every(
      (watch: NativeThreadBackgroundPullRequestWatch, index: number) => this.sameBackgroundWatch(watch, this.backgroundStopWatches[index]))) return false;
    this.backgroundStopWatches = watches;
    return true;
  }

  private sameBackgroundWatch(left: NativeThreadBackgroundPullRequestWatch,
    right: NativeThreadBackgroundPullRequestWatch): boolean {
    return left.host === right.host && left.repository === right.repository && left.number === right.number;
  }

  private updateBackgroundWatch(value: Object): boolean {
    const identity = readBackgroundPullRequestIdentity(value);
    if (!identity) return false;
    const existing = this.backgroundStopWatches.findIndex((watch: NativeThreadBackgroundPullRequestWatch) =>
      this.sameBackgroundWatch(watch, identity));
    if (backgroundPullRequestIsWatched(value)) {
      if (existing >= 0) return false;
      this.backgroundStopWatches = this.backgroundStopWatches.concat(identity);
      return true;
    }
    if (existing < 0) return false;
    this.backgroundStopWatches = this.backgroundStopWatches.filter((_, index: number) => index !== existing);
    return true;
  }

  private updateRuntimeRequest(request: RuntimeRequestRecord): boolean {
    if (!request || !nonEmpty(request.id) || (request.kind !== 'user_input' && !APPROVAL_KINDS.has(request.kind)) ||
      !nonEmpty(request.createdAt) || !request.responseCapability) return false;
    const previous = this.runtimeRequests.get(request.id);
    if (previous && previous.status !== 'pending' && request.status === 'pending') return false;
    this.runtimeRequests.set(request.id, request);
    return true;
  }

  private pendingApproval(): NativeThreadApproval | undefined {
    let pending: RuntimeRequestRecord | undefined;
    for (const request of this.runtimeRequests.values()) {
      if (request.status === 'pending' && APPROVAL_KINDS.has(request.kind) &&
        (!pending || request.createdAt < pending.createdAt)) pending = request;
    }
    if (!pending) return undefined;
    const item = this.requestItems.get(pending.id);
    let options: NativeThreadApprovalOption[] = [];
    if (item) {
      options = item.options === undefined ? DEFAULT_APPROVAL_OPTIONS.slice() :
        item.options.filter((option: NativeThreadApprovalOption): boolean =>
          option && APPROVAL_DECISIONS.has(option.decision) && nonEmpty(option.label))
          .map((option: NativeThreadApprovalOption): NativeThreadApprovalOption => {
            const choice: NativeThreadApprovalOption = { decision: option.decision, label: option.label };
            if (nonEmpty(option.warning)) choice.warning = option.warning;
            return choice;
          });
    }
    const capability = pending.responseCapability;
    const reasons = [item?.reason, capability.reason, options.find((option) => option.warning)?.warning];
    return {
      id: pending.id,
      prompt: item?.prompt || '需要审批',
      reason: reasons.filter((reason) => nonEmpty(reason)).join('\n'),
      options,
      canRespond: capability.type === 'live' && options.length > 0,
      supportsFeedback: capability.type === 'live' && capability.supportsFeedback === true,
    };
  }

  private pendingUserInput(activeRunId: string): NativeThreadUserInput | undefined {
    let pending: RuntimeRequestRecord | undefined;
    let item: TurnItemRecord | undefined;
    for (const request of this.runtimeRequests.values()) {
      if (request.kind !== 'user_input' || request.status !== 'pending' ||
        (pending !== undefined && request.createdAt >= pending.createdAt)) continue;
      const candidate = this.requestItems.get(request.id);
      if (candidate?.type !== 'user_input_request' || !Array.isArray(candidate.questions)) continue;
      pending = request;
      item = candidate;
    }
    if (!pending || !item?.questions) {
      this.projectedUserInput = undefined;
      return undefined;
    }
    const run = item.runId ? this.runs.get(item.runId) : undefined;
    const stopRunId = run && (run.status === 'waiting' || INTERRUPTIBLE_RUNS.has(run.status)) ? run.id : activeRunId;
    const capability = pending.responseCapability;
    const canRespond = capability.type === 'live' || capability.type === 'message';
    const dismissible = capability.type === 'message';
    const reason = capability.reason ?? '';
    const previous = this.projectedUserInput;
    if (previous?.id === pending.id && previous.questions === item.questions && previous.canRespond === canRespond &&
      previous.dismissible === dismissible && previous.reason === reason && previous.stopRunId === stopRunId) return previous;
    this.projectedUserInput = {
      id: pending.id,
      questions: item.questions,
      canRespond,
      dismissible,
      reason,
      stopRunId,
    };
    return this.projectedUserInput;
  }
}
