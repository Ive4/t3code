import { common } from '@kit.AbilityKit';
import { url, util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';

import {
  ORCHESTRATION_PROTOCOL, REQUEST_ID, dispatchRequest,
  exchangeBody, mergeMessages, readMessage, readMessages, readThreads, subscribeRequest,
} from './T3Protocol';
import type {
  NativeMessage, NativeThread, NativeThreadAttachment, RpcFrame, ThreadMessageContext, ThreadStreamItem,
} from './T3Protocol';
import {
  composerPathSearchRequest, composerProviderCatalogRequest, matchComposerPullRequests,
  readComposerProjectRepository, readComposerProviderCatalog,
} from './ComposerCatalogProtocol';
import type { NativeComposerProviderCatalog, NativeComposerScope } from './ComposerCatalogProtocol';
import { EnvironmentStore, summarizeEnvironment } from './EnvironmentStore';
import { AccountNetworkError, AccountSessionExpiredError } from './AccountProtocol';
import type { EnvironmentSummary, SavedEnvironment } from './EnvironmentStore';
import type { EnvironmentResponseLimits, RelayConnection } from './NativeRelay';
import { isRelayRouteUnavailable } from './NativeRelay';
import { modelCatalogSettingsWriteAllowed, modelCatalogUpdateRequest,
  readUpdatedModelCatalogPreferences } from './ModelCatalogPreferences';
import type { ModelCatalogPreferenceKind, NativeModelCatalogPreferences } from './ModelCatalogPreferences';
import { T3Socket } from './T3Socket';
import {
  ThreadDetailProjection, backgroundPullRequestStopRequest, backgroundWorkStopRequest,
  cancelQueuedRunRequest, dismissUserInputRequest, editQueuedRunRequest, interruptRequest,
  modelSelectionRequest, promoteQueuedRunRequest, readThreadWorkDetail, respondApprovalRequest, respondUserInputRequest,
  resumeQueueRequest, runtimeModeSelectionRequest, startQueuedRunRequest,
  threadWorkDetailRequest,
} from './ThreadDetailProtocol';
import type { NativeThreadDetail, NativeThreadUserInputAnswers } from './ThreadDetailProtocol';
import type { NativeThreadBackgroundPullRequestWatch } from './ThreadBackgroundWorkProtocol';
import { readThreadCheckpointDiff, threadCheckpointDiffRequest } from './ThreadCheckpointProtocol';
import type { NativeThreadCheckpointDiff } from './ThreadCheckpointProtocol';
import {
  ThreadForkTargetPendingError, ThreadForkUnconfirmedError, attachThreadReplyForkSource,
  readConfirmedThreadFork, readThreadForkReceipt, threadForkFromReplyRequest,
} from './ThreadForkProtocol';
import type { NativeThreadForkAttempt, NativeThreadForkSource } from './ThreadForkProtocol';
import { readThreadHistory, threadHistoryPath } from './ThreadHistoryProtocol';
import type { NativeThreadHistory } from './ThreadHistoryProtocol';
import { DeviceApprovalClient } from './DeviceApprovalClient';
import type { DeviceApprovalOutcome } from './DeviceApprovalClient';
import type { ConnectDeviceApprovalTarget } from './ConnectDeviceApprovals';
import { readEnvironmentMaintenance, readMaintenanceProviders, refreshEnvironmentProvidersRequest,
  updateEnvironmentProviderRequest } from './EnvironmentMaintenanceProtocol';
import type { EnvironmentMaintenanceProvider, EnvironmentMaintenanceSnapshot } from './EnvironmentMaintenanceProtocol';
import {
  pullRequestActivityRequest, pullRequestDetailRequest, pullRequestDiffBody, pullRequestListRequest,
  readPullRequestDetail, readPullRequestDiff, readPullRequestDiscussion, readPullRequestFileDiff, readPullRequestPage,
} from './PullRequestProtocol';
import { pullRequestMetadataRequest, readPullRequestMetadata } from './PullRequestMetadataProtocol';
import type { NativePullRequestMetadataKind, NativePullRequestMetadataPage } from './PullRequestMetadataProtocol';
import { pullRequestCompletionOptionsRequest, readPullRequestCompletionOptions } from './PullRequestReferenceProtocol';
import type {
  NativePullRequestCompletionOptions, NativePullRequestComposerTrigger,
} from './PullRequestReferenceProtocol';
import {
  generatePullRequestGuideRequest, pullRequestGuideRequest, pullRequestGuidesEnabled, readPullRequestGuide,
} from './PullRequestGuideProtocol';
import type { NativePullRequestGuideResult } from './PullRequestGuideProtocol';
import { pullRequestFilterOptionsRequest, readPullRequestFilterOptions } from './PullRequestFilterOptionsProtocol';
import type {
  NativePullRequestFilterMode, NativePullRequestFilterCandidate, NativePullRequestFilterCandidatePage,
} from './PullRequestFilterOptionsProtocol';
import type {
  NativePullRequestDetail, NativePullRequestDiff, NativePullRequestDiscussion, NativePullRequestFile, NativePullRequestPage,
  NativePullRequestQuery, NativePullRequestRef, NativePullRequestRow,
} from './PullRequestProtocol';
import {
  issueCandidatesRequest, issueDetailRequest, issueListRequest, readIssueCandidates, readIssueDetail, readIssuePage,
  supportsIssues,
} from './IssueProtocol';
import type {
  NativeIssueCandidates, NativeIssueDetail, NativeIssueFilters, NativeIssuePage, NativeIssueRef, NativeIssueScope,
} from './IssueProtocol';
import {
  readWorkspaceUsageLimits, readWorkspaceUsageSummary, workspaceUsageLimitsRequest, workspaceUsageSummaryRequest,
} from './WorkspaceUsageProtocol';
import type { NativeUsageAccount, NativeUsageSummary } from './WorkspaceUsageProtocol';
import {
  canMintLinkedEnvironmentPairing, linkEnvironmentRequest, linkedEnvironmentHealth, linkedEnvironmentPairingBody,
  linkedClientPairingRequest, linkedEnvironmentsRequest, linkedThreadHistoryRequest, linkedThreadItemRequest,
  linkedThreadReadError, linkedThreadRequest,
  LINKED_ENVIRONMENT_PAIRING_PATH, readLinkedClientPairing, readLinkedEnvironmentPairingCode, readLinkedEnvironments,
  readUnlinkEnvironmentResult, supportsLinkedEnvironmentPairing, supportsLinkedEnvironments, unlinkEnvironmentRequest,
} from './LinkedEnvironmentProtocol';
import type { LinkedEnvironmentBatchResult, LinkedEnvironmentCandidate, NativeLinkedEnvironment,
  NativePeerLinkAccess, UnlinkEnvironmentResult }
  from './LinkedEnvironmentProtocol';
import { readThreadSearchMatches, searchThreadsRequest } from './ThreadSearchProtocol';
import type { NativeThreadSearchMatch } from './ThreadSearchProtocol';
import { readThreadReview, readThreadReviewPatch, threadReviewRequest } from './ThreadReviewProtocol';
import type { NativeThreadReview, NativeThreadReviewFile, NativeThreadReviewPatch } from './ThreadReviewProtocol';
import { projectBrowseRequest, projectManagementRequest, readManagedProject, readManagedProjects,
  readProjectFolderListing, supportsProjectOrganization } from './ProjectManagementProtocol';
import type { NativeManagedProject, NativeProjectFolderListing, ProjectManagementChange,
  ProjectManagementSnapshot } from './ProjectManagementProtocol';
import { archivedThreadSnapshotRequest, threadLifecycleRequest, threadVisitRequest } from './ThreadLifecycleProtocol';
import type { ThreadLifecycleAction } from './ThreadLifecycleProtocol';
import {
  readThreadGitCommitProgress, readThreadGitRefName, readThreadGitRefs, readThreadGitStatus,
  readThreadGitPullResult, readThreadGitPushProgress, threadGitPullRequest, threadGitPushRequest,
  threadGitBranchMetadataRequest, threadGitCommitRequest, threadGitCreateRefRequest, threadGitRefsRequest,
  threadGitStatusRequest, threadGitSwitchRefRequest,
} from './ThreadGitProtocol';
import type { NativeThreadGitCommitResult, NativeThreadGitPullResult, NativeThreadGitPushResult,
  NativeThreadGitRefs, NativeThreadGitStatus, ThreadGitRefKind } from './ThreadGitProtocol';
import { readThreadTerminals, ThreadTerminalConnection } from './ThreadTerminalConnection';
import type { NativeTerminalUpdate, NativeThreadTerminalSummary, ThreadTerminalTarget } from './ThreadTerminalProtocol';
import type { ThreadAttachmentEnvironment, UploadedThreadAttachment } from './ThreadAttachmentProtocol';
import { requestThreadAttachmentAssetUrl } from './ThreadAttachmentAssetProtocol';
import type { ThreadAttachmentAssetUrl, ThreadAttachmentDisposition } from './ThreadAttachmentAssetProtocol';
import {
  listThreadFilesRequest, readThreadFile, readThreadFileDirectory, readThreadFileRequest,
  readThreadFileSearch, searchThreadFilesRequest,
} from './ThreadFilesProtocol';
import type { NativeThreadFile, NativeThreadFileDirectory, NativeThreadFileEntry } from './ThreadFilesProtocol';
import {
  launchThreadRequest, readLaunchedThreadId,
  readThreadLaunchOptions, readThreadLaunchScratchProject, readThreadModelSettings, threadLaunchConfigRequest,
  threadLaunchScratchRequest,
} from './ThreadLaunchProtocol';
import type {
  ThreadLaunchOptions, ThreadLaunchProject, ThreadLaunchProvider, ThreadLaunchRuntimeMode, ThreadLaunchSelection,
  ThreadLaunchScratch, ThreadLaunchWorkspaceStrategy, ThreadModelSettings,
} from './ThreadLaunchProtocol';
import { withThreadModelOptionDefaults } from './ThreadModelOptionProtocol';
import type { ThreadModelOptionSelection } from './ThreadModelOptionProtocol';

export type { NativeMessage, NativeThread } from './T3Protocol';

export type ConnectManagedEnvironment = (environmentId: string) => Promise<RelayConnection>;

interface CachedThreadModelSettings {
  session: SavedEnvironment;
  projectId: string;
  cwd?: string;
  readAt: number;
  settings: ThreadModelSettings;
}

interface CachedComposerCatalog {
  session: SavedEnvironment;
  projectId: string;
  cwd: string;
  expiresAt: number;
  selection: NativeComposerProviderCatalog;
}

interface CachedComposerLinks {
  session: SavedEnvironment;
  expiresAt: number;
  result: Promise<LinkedEnvironmentSnapshot>;
}

export interface ThreadLaunchAttempt {
  commandId: string;
  threadId: string;
  messageId: string;
}

export interface ThreadSendAttempt {
  commandId: string;
  messageId: string;
}

export function createThreadSendAttempt(): ThreadSendAttempt {
  return { commandId: util.generateRandomUUID(), messageId: util.generateRandomUUID() };
}

export function createThreadForkAttempt(): NativeThreadForkAttempt {
  return { commandId: util.generateRandomUUID(), targetThreadId: util.generateRandomUUID() };
}

export class ThreadCommandRejectedError extends Error {}

export interface LinkedThreadConnection {
  status: 'manual' | 'paired' | 'unreachable';
  address: string;
}

export interface ThreadTerminalHandle {
  write: (data: string, reply?: boolean, binary?: boolean) => Promise<void>;
  resize: (cols: number, rows: number) => Promise<void>;
  clear: () => Promise<void>;
  close: () => Promise<void>;
  dispose: () => void;
}

export function createThreadTerminalId(): string {
  return 'term-' + util.generateRandomUUID();
}

export function createThreadLaunchAttempt(): ThreadLaunchAttempt {
  return {
    commandId: util.generateRandomUUID(),
    threadId: util.generateRandomUUID(),
    messageId: util.generateRandomUUID(),
  };
}

interface PairingTarget {
  origin: string;
  credential: string;
}

interface EnvironmentDescriptor {
  environmentId: string;
  label: string;
  orchestrationProtocolVersion?: number;
}

interface TokenResponse {
  access_token: string;
}

interface ThreadLinkSnapshot {
  projection?: ThreadLinkProjection;
}

interface ThreadLinkProjection {
  thread?: NativeThread;
}

interface ThreadLinkProjectSnapshot {
  projects?: ThreadLinkProject[];
}

interface ThreadLinkProject {
  id: string;
  title: string;
  workspaceRoot: string;
}

interface TicketResponse {
  ticket: string;
}

export interface ThreadPermissions {
  operate: boolean;
  readFiles: boolean;
  gitWrite: boolean;
  terminalRead: boolean;
  terminalOperate: boolean;
}

interface EnvironmentSessionAuth {
  serverUpdateScope?: string;
}

interface EnvironmentSessionPermissions {
  authenticated: boolean;
  scopes?: string[];
  permissions?: string[];
  auth?: EnvironmentSessionAuth;
}

interface EnvironmentMaintenanceState {
  session: SavedEnvironment;
  snapshot: EnvironmentMaintenanceSnapshot;
  permissions: string[];
  legacyOperate: boolean;
}

export interface LinkedEnvironmentSnapshot {
  links: NativeLinkedEnvironment[];
  canManage: boolean;
}

interface PreparedEnvironmentRoute {
  session: SavedEnvironment;
  transport?: RelayConnection;
}

interface AuthAccessRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: Record<string, string>;
  headers: string[][];
}

const NETWORK_TIMEOUT_MS = 15000;
const SEND_TIMEOUT_MS = 60000;
// Escaped JSON can exceed the provider's 32 MiB raw patch limit.
const PULL_REQUEST_FILE_DIFF_LIMITS: EnvironmentResponseLimits = { readTimeout: SEND_TIMEOUT_MS,
  maxLimit: 64 * 1024 * 1024 };
const LONG_RPC_TIMEOUT_MS = 10 * 60 * 1000 + NETWORK_TIMEOUT_MS;
const THREAD_RECONNECT_DELAYS_MS = [1000, 2000, 4000];
type ThreadUpdate = (messages: NativeMessage[], detail: NativeThreadDetail, historyCursor?: string) => void;

interface BackgroundShellRows {
  threads: NativeThread[];
}

interface BackgroundShellSnapshot extends BackgroundShellRows {
  snapshotSequence: number;
  archivedThreads?: NativeThread[];
}

interface BackgroundShellSeed {
  sequence: number;
  threads: NativeThread[];
  archivedThreads: NativeThread[];
}

interface BackgroundShellItem extends ThreadStreamItem {
  snapshot?: BackgroundShellSnapshot;
  resolvedRepositoryIdentityRoots?: string[];
  thread?: NativeThread;
  threadId?: string;
}

interface BackgroundShellInput {
  afterSequence?: number;
  requestCompletionMarker: boolean;
}

interface BackgroundShellRequest {
  _tag: string;
  id: string;
  tag: string;
  headers: string[][];
  payload: BackgroundShellInput;
}

function readBackgroundShellRows(rows: NativeThread[]): NativeThread[] {
  const snapshot: BackgroundShellRows = { threads: rows };
  return readThreads(snapshot);
}

function isEnvironmentUrl(address: url.URL): boolean {
  return !!address.hostname && !address.username && !address.password && /^(https?|wss?):$/.test(address.protocol);
}

function canTryAnotherEnvironmentRoute(error: Error): boolean {
  return error instanceof EnvironmentRouteUnavailableError || error instanceof AccountNetworkError ||
    isRelayRouteUnavailable(error);
}

export function linkedEnvironmentOrigin(address: string): string | undefined {
  try {
    const parsed = url.URL.parseURL(address);
    const host = parsed.hostname.toLowerCase().replace(/\.$/, '');
    if (!/^https?:$/.test(parsed.protocol) || parsed.username || parsed.password || !host ||
      host === 'localhost' || host.endsWith('.localhost') || host === '[::1]' || host === '::1' ||
      host === '0.0.0.0' || /^127\./.test(host)) return undefined;
    return parsed.protocol + '//' + parsed.host;
  } catch (_) {
    return undefined;
  }
}

function environmentOrigin(address: string): string {
  const host = address.trim();
  const local = /^(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?(?:\/|$)/.test(host) || host.startsWith('[');
  try {
    const parsed = url.URL.parseURL(host.includes('://') ? host : (local ? 'http://' : 'https://') + host);
    if (isEnvironmentUrl(parsed)) {
      const scheme = parsed.protocol === 'ws:' ? 'http:' : parsed.protocol === 'wss:' ? 'https:' : parsed.protocol;
      return scheme + '//' + parsed.host;
    }
  } catch (_) {}
  throw new Error('请输入有效的 T3 环境地址。');
}

function parsePairingTarget(raw: string): PairingTarget {
  let address = url.URL.parseURL(raw.trim());
  if (/^t3code(?:-[a-z]+)?:$/.test(address.protocol) && address.host === 'pair' &&
    (address.pathname === '' || address.pathname === '/')) {
    const nested = address.params.get('pairingUrl')?.trim();
    if (!nested) throw new Error('配对链接缺少环境地址。');
    address = url.URL.parseURL(nested);
  }
  if (!isEnvironmentUrl(address)) throw new Error('请输入有效的 T3 环境配对链接。');
  const fragment = new url.URLParams(address.hash.slice(1));
  const credential = fragment.get('token')?.trim() || address.params.get('token')?.trim();
  if (!credential) throw new Error('配对链接缺少一次性配对码。');
  const hostedTarget = address.params.get('host')?.trim();
  if (hostedTarget) {
    const host = hostedTarget.replace(/^\/+/, '');
    address = url.URL.parseURL(/^[a-z][a-z\d+.-]*:\/\//i.test(host) ? host : `https://${host}`);
    if (!isEnvironmentUrl(address)) throw new Error('请输入有效的 T3 环境配对链接。');
  }
  const scheme = address.protocol === 'ws:' ? 'http:' : address.protocol === 'wss:' ? 'https:' : address.protocol;
  return { origin: `${scheme}//${address.host}`, credential };
}

class EnvironmentRouteUnavailableError extends Error {}

async function requestJson<T>(origin: string, path: string, method: http.RequestMethod, token?: string,
  body?: string, contentType: string = 'application/x-www-form-urlencoded',
  limits?: EnvironmentResponseLimits): Promise<T> {
  const headers: Record<string, string> = { 'x-t3-orchestration-protocol': ORCHESTRATION_PROTOCOL };
  if (token) headers['authorization'] = 'Bearer ' + token;
  if (body !== undefined) headers['content-type'] = contentType;
  const request = http.createHttp();
  try {
    let response: http.HttpResponse;
    try {
      const options: http.HttpRequestOptions = {
        method,
        header: headers,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: NETWORK_TIMEOUT_MS,
        readTimeout: limits?.readTimeout ?? NETWORK_TIMEOUT_MS,
        maxRedirects: 0,
      };
      if (limits) options.maxLimit = limits.maxLimit;
      response = await request.request(origin + path, options);
    } catch (error) {
      throw new EnvironmentRouteUnavailableError('无法访问 T3 环境。请检查网络和环境地址。');
    }
    if (response.responseCode < 200 || response.responseCode >= 300) {
      if (path === '/oauth/token' && (response.responseCode === 401 || response.responseCode === 400)) {
        throw new Error('配对码失效。请从环境重新生成配对链接。');
      }
      if (response.responseCode === 401) throw new Error('环境授权已失效，请重新配对。');
      if (response.responseCode === 403) throw new Error('此连接缺少执行操作所需的环境权限。');
      if ([502, 503, 504].includes(response.responseCode)) {
        throw new EnvironmentRouteUnavailableError(`环境暂时不可用（HTTP ${response.responseCode}）。`);
      }
      throw new Error(`环境请求未成功（HTTP ${response.responseCode}）。`);
    }
    if (typeof response.result !== 'string') throw new Error('环境返回的数据格式无效。');
    try {
      return JSON.parse(response.result) as T;
    } catch (error) {
      throw new Error('环境返回了无法解析的数据。');
    }
  } finally {
    request.destroy();
  }
}

export class T3Client {
  private store: EnvironmentStore;
  private context: common.UIAbilityContext;
  private session: SavedEnvironment | undefined;
  private modelSettingsCache?: CachedThreadModelSettings = undefined;
  private composerCatalog?: CachedComposerCatalog = undefined;
  private composerLinks?: CachedComposerLinks = undefined;
  private managed: RelayConnection | undefined;
  private sessionUpdate: Promise<void> | undefined;
  private resolveSessionUpdate: (() => void) | undefined;
  private watchers: Set<() => void> = new Set<() => void>();
  private backgroundShellSeed?: BackgroundShellSeed;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.store = new EnvironmentStore(context);
  }

  currentEnvironment(): EnvironmentSummary | undefined {
    return this.session ? summarizeEnvironment(this.session) : undefined;
  }

  listEnvironments(accountId?: string): Promise<EnvironmentSummary[]> {
    return this.store.list(accountId);
  }

  private requireSession(): SavedEnvironment {
    if (this.session === undefined) throw new Error('请先配对 T3 环境。');
    return this.session;
  }

  private requireComposerEnvironment(scope: NativeComposerScope): SavedEnvironment {
    const session = this.requireSession();
    if (!scope.environmentKey || this.currentEnvironment()?.key !== scope.environmentKey) {
      throw new Error('环境连接已更换。');
    }
    return session;
  }

  private startSessionUpdate(): void {
    if (this.sessionUpdate) throw new Error('正在更新环境连接。');
    this.sessionUpdate = new Promise<void>((resolve) => {
      this.resolveSessionUpdate = () => resolve();
    });
  }

  private finishSessionUpdate(): void {
    const resolve = this.resolveSessionUpdate;
    this.resolveSessionUpdate = undefined;
    this.sessionUpdate = undefined;
    resolve?.();
  }

  private stopWatchers(): void {
    for (const stop of this.watchers) stop();
  }

  private useSession(session: SavedEnvironment | undefined, managed?: RelayConnection): void {
    this.stopWatchers();
    this.backgroundShellSeed = undefined;
    this.composerCatalog = undefined;
    this.composerLinks = undefined;
    this.session = session;
    this.managed = managed;
  }

  async restore(accountId?: string, connectManaged?: ConnectManagedEnvironment): Promise<boolean> {
    this.startSessionUpdate();
    try {
      const session = await this.store.active(accountId);
      if (session?.accountId !== undefined) {
        if (this.managed && this.session?.environmentId === session.environmentId &&
          this.session?.accountId === session.accountId) return true;
        if (!connectManaged) return false;
        try {
          this.useSession(session, await this.prepareSavedConnection(session, connectManaged));
        } catch (error) {
          if (!canTryAnotherEnvironmentRoute(error as Error)) throw error as Error;
          const prepared = await this.preparePreferredRoute(session, true, accountId, connectManaged, error as Error);
          await this.store.saveAndSelect(prepared.session);
          this.useSession(prepared.session, prepared.transport);
        }
      } else if (!session || !this.session || this.session.accountId !== undefined ||
        this.session.environmentId !== session.environmentId || this.session.origin !== session.origin ||
        this.session.token !== session.token || this.session.label !== session.label) {
        this.useSession(session);
      }
      return session !== undefined;
    } finally {
      this.finishSessionUpdate();
    }
  }

  async select(key: string, accountId?: string, connectManaged?: ConnectManagedEnvironment,
    verify: boolean = false): Promise<void> {
    this.startSessionUpdate();
    try {
      const session = await this.store.get(key, accountId);
      const transport = await this.prepareSavedConnection(session, connectManaged, verify);
      await this.store.saveAndSelect(session);
      this.useSession(session, transport);
    } finally {
      this.finishSessionUpdate();
    }
  }

  async reconnectEnvironment(key: string, accountId?: string, connectManaged?: ConnectManagedEnvironment): Promise<void> {
    this.startSessionUpdate();
    try {
      const session = await this.store.get(key, accountId);
      const prepared = await this.preparePreferredRoute(session, false, accountId, connectManaged);
      await this.store.saveAndSelect(prepared.session);
      this.useSession(prepared.session, prepared.transport);
    } finally {
      this.finishSessionUpdate();
    }
  }

  private async preparePreferredRoute(requested: SavedEnvironment, onlyAlternatives: boolean, accountId?: string,
    connectManaged?: ConnectManagedEnvironment, initialError?: Error): Promise<PreparedEnvironmentRoute> {
    const key = summarizeEnvironment(requested).key;
    const alternatives = (await this.store.list(accountId)).filter((entry) =>
      entry.enabled && entry.key !== key && entry.environmentId === requested.environmentId);
    let lastError = initialError ?? new Error('环境连接不可用。');
    const keys = alternatives.map((entry) => entry.key);
    if (!onlyAlternatives) keys.unshift(key);
    for (const routeKey of keys) {
      const session = routeKey === key ? requested : await this.store.get(routeKey, accountId);
      try {
        const transport = await this.prepareSavedConnection(session, connectManaged, true);
        return { session, transport };
      } catch (error) {
        if (!canTryAnotherEnvironmentRoute(error as Error)) throw error as Error;
        lastError = error as Error;
      }
    }
    throw lastError;
  }

  private async prepareSavedConnection(session: SavedEnvironment, connectManaged?: ConnectManagedEnvironment,
    verify: boolean = false): Promise<RelayConnection | undefined> {
    if (session.enabled === false) throw new Error('环境已停用。');
    let transport: RelayConnection | undefined;
    if (session.accountId !== undefined) {
      if (!connectManaged) throw new Error('请先登录 T3 账户。');
      transport = await connectManaged(session.environmentId);
      this.checkManagedTransport(session.environmentId, transport);
    }
    if (verify) {
      const status = transport
        ? await transport.request('/api/auth/session') as EnvironmentSessionPermissions
        : await requestJson<EnvironmentSessionPermissions>(session.origin, '/api/auth/session',
            http.RequestMethod.GET, session.token);
      if (status?.authenticated !== true) throw new Error('环境授权已失效。请重新配对。');
      const address = await this.socketAddressFor(session, transport);
      const socket = new T3Socket();
      try {
        await socket.open(address, () => {}, () => {});
      } catch (_) {
        throw new EnvironmentRouteUnavailableError('无法建立环境的 WebSocket 连接。');
      } finally {
        socket.close();
      }
    }
    return transport;
  }

  private checkManagedTransport(environmentId: string, transport: RelayConnection): void {
    if (transport.environmentId !== environmentId ||
      transport.orchestrationProtocolVersion !== Number(ORCHESTRATION_PROTOCOL)) {
      throw new Error('T3 Connect 环境与当前会话协议不兼容。');
    }
  }

  async connectManaged(environmentId: string, accountId: string,
    connect: ConnectManagedEnvironment): Promise<void> {
    this.startSessionUpdate();
    try {
      const saved = await this.store.getManaged(environmentId, accountId);
      if (saved?.enabled === false) throw new Error('环境已停用。');
      const transport = await connect(environmentId);
      this.checkManagedTransport(environmentId, transport);
      const session: SavedEnvironment = {
        environmentId,
        label: saved?.label ?? transport.label,
        origin: transport.origin,
        accountId,
      };
      await this.store.saveAndSelect(session);
      this.useSession(session, transport);
    } finally {
      this.finishSessionUpdate();
    }
  }

  async updateEnvironment(key: string, label: string, address?: string, accountId?: string): Promise<void> {
    const normalizedLabel = label.trim();
    if (!normalizedLabel) throw new Error('请输入环境名称。');
    this.startSessionUpdate();
    try {
      const session = await this.store.get(key, accountId);
      let origin = session.origin;
      if (address !== undefined && !session.accountId) {
        origin = environmentOrigin(address);
        if (origin !== session.origin) {
          const descriptor = await requestJson<EnvironmentDescriptor>(origin, '/.well-known/t3/environment',
            http.RequestMethod.GET);
          if (descriptor?.environmentId !== session.environmentId ||
            descriptor.orchestrationProtocolVersion !== Number(ORCHESTRATION_PROTOCOL)) {
            throw new Error('新地址必须指向同一个兼容的 T3 环境。');
          }
        }
      }
      const updated: SavedEnvironment = {
        accountId: session.accountId, environmentId: session.environmentId, label: normalizedLabel,
        origin, token: session.token, enabled: session.enabled, routeId: session.routeId,
      };
      await this.store.update(updated);
      if (this.currentEnvironment()?.key === key) this.useSession(updated, this.managed);
    } finally {
      this.finishSessionUpdate();
    }
  }

  async setEnvironmentEnabled(key: string, enabled: boolean, accountId?: string): Promise<void> {
    this.startSessionUpdate();
    try {
      const session = await this.store.get(key, accountId);
      session.enabled = enabled;
      const fallback = await this.store.update(session);
      if (!enabled && this.currentEnvironment()?.key === key) this.useSession(fallback);
    } finally {
      this.finishSessionUpdate();
    }
  }

  async removeEnvironment(key: string, accountId?: string): Promise<void> {
    this.startSessionUpdate();
    try {
      const fallback = await this.store.remove(key, accountId);
      if (this.currentEnvironment()?.key === key) {
        this.useSession(fallback);
      }
    } finally {
      this.finishSessionUpdate();
    }
  }

  async moveEnvironmentRoute(key: string, delta: number, accountId?: string): Promise<void> {
    this.startSessionUpdate();
    try {
      await this.store.moveRoute(key, delta, accountId);
    } finally {
      this.finishSessionUpdate();
    }
  }

  async removeEnvironmentRoute(key: string, accountId?: string,
    connectManaged?: ConnectManagedEnvironment): Promise<void> {
    this.startSessionUpdate();
    try {
      const active = this.currentEnvironment()?.key === key ? this.session : undefined;
      if (!active) {
        await this.store.removeRoute(key, accountId);
        return;
      }
      const next = await this.preparePreferredRoute(active, true, accountId, connectManaged).catch(() => undefined);
      const replacementKey = next ? summarizeEnvironment(next.session).key : undefined;
      await this.store.removeRoute(key, accountId, replacementKey);
      this.useSession(next?.session, next?.transport);
    } finally {
      this.finishSessionUpdate();
    }
  }

  async signOutOfEnvironments(accountId: string): Promise<void> {
    while (this.sessionUpdate) await this.sessionUpdate;
    this.startSessionUpdate();
    try {
      if (this.session?.accountId === accountId) this.useSession(undefined);
      await this.store.removeAccount(accountId);
      if (!this.session) this.useSession(await this.store.active());
    } finally {
      this.finishSessionUpdate();
    }
  }

  async pairAddress(address: string, code: string, expectedEnvironmentId?: string): Promise<boolean> {
    const host = address.trim();
    const credential = code.trim();
    if (!host || !credential) throw new Error('请输入服务器地址和配对码。');
    return this.pair(environmentOrigin(host) + '/pair#token=' + encodeURIComponent(credential), expectedEnvironmentId);
  }

  async pair(link: string, expectedEnvironmentId?: string): Promise<boolean> {
    this.startSessionUpdate();
    try {
      let target: PairingTarget;
      try {
        target = parsePairingTarget(link);
      } catch (error) {
        throw new Error('请输入包含一次性配对码的 T3 环境链接。');
      }
      const descriptor = await requestJson<EnvironmentDescriptor>(target.origin, '/.well-known/t3/environment',
        http.RequestMethod.GET);
      if (!descriptor || typeof descriptor.environmentId !== 'string' || typeof descriptor.label !== 'string') {
        throw new Error('此地址未返回有效的 T3 环境信息。');
      }
      if (descriptor.orchestrationProtocolVersion !== Number(ORCHESTRATION_PROTOCOL)) {
        throw new Error('当前环境的会话协议版本不兼容。请更新环境后再配对。');
      }
      if (expectedEnvironmentId !== undefined && descriptor.environmentId !== expectedEnvironmentId) {
        throw new Error('备用线路必须指向同一个环境。');
      }
      const response = await requestJson<TokenResponse>(target.origin, '/oauth/token', http.RequestMethod.POST,
        undefined, exchangeBody(target.credential));
      if (!response || typeof response.access_token !== 'string' || response.access_token.length === 0) {
        throw new Error('环境未返回访问凭据。');
      }
      const session: SavedEnvironment = {
        origin: target.origin,
        environmentId: descriptor.environmentId,
        label: descriptor.label,
        token: response.access_token,
      };
      const saved = await this.store.savePairedDirect(session, expectedEnvironmentId === undefined);
      const active = expectedEnvironmentId === undefined || this.currentEnvironment()?.key === summarizeEnvironment(saved).key;
      if (active) this.useSession(saved);
      return active;
    } finally {
      this.finishSessionUpdate();
    }
  }

  async environmentRequest(path: string, method: string = 'GET', body?: string,
    limits?: EnvironmentResponseLimits): Promise<Object> {
    if (!/^\/(?!\/)/.test(path) || /[\\#\s]/.test(path)) throw new Error('环境请求路径无效。');
    if (method !== 'GET' && method !== 'POST') throw new Error('环境请求方法无效。');
    const session = this.requireSession();
    const response = this.managed
      ? await this.managed.request(path, method, body, limits)
      : await requestJson<Object>(session.origin, path, method as http.RequestMethod, session.token, body,
          'application/json', limits);
    if (this.session !== session) throw new Error('环境连接已更换。');
    return response;
  }

  async listThreads(): Promise<NativeThread[]> {
    const answer = await this.environmentRequest('/api/orchestration/shell');
    const snapshot = answer as BackgroundShellSnapshot;
    const threads = readThreads(answer);
    if (Number.isSafeInteger(snapshot.snapshotSequence) && snapshot.snapshotSequence >=
      (this.backgroundShellSeed?.sequence ?? 0)) {
      this.backgroundShellSeed = {
        sequence: snapshot.snapshotSequence,
        threads,
        archivedThreads: Array.isArray(snapshot.archivedThreads) ?
          readBackgroundShellRows(snapshot.archivedThreads) : [],
      };
    }
    return threads;
  }

  async listEnvironmentThreads(key: string, accountId?: string,
    connectManaged?: ConnectManagedEnvironment): Promise<NativeThread[]> {
    const session = await this.store.get(key, accountId);
    if (session.enabled === false) throw new Error('环境已停用。');
    const path = '/api/orchestration/shell';
    if (!session.accountId) {
      return readThreads(await requestJson<Object>(session.origin, path, http.RequestMethod.GET, session.token));
    }
    if (!connectManaged) throw new Error('请先登录 T3 账户。');
    const transport = await connectManaged(session.environmentId);
    this.checkManagedTransport(session.environmentId, transport);
    return readThreads(await transport.request(path, 'GET'));
  }

  async searchEnvironmentThreads(query: string, key: string, accountId?: string,
    connectManaged?: ConnectManagedEnvironment): Promise<NativeThreadSearchMatch[]> {
    const current = this.session;
    if (current && this.currentEnvironment()?.key === key) return this.searchThreadMessages(query);
    const session = await this.store.get(key, accountId);
    if (session.enabled === false) return [];
    const transient = new T3Client(this.context);
    if (session.accountId) {
      if (!connectManaged) throw new Error('请先登录 T3 账户。');
      const transport = await connectManaged(session.environmentId);
      this.checkManagedTransport(session.environmentId, transport);
      transient.useSession(session, transport);
    } else {
      transient.useSession(session);
    }
    return transient.searchThreadMessages(query);
  }

  private async searchThreadMessages(query: string): Promise<NativeThreadSearchMatch[]> {
    const session = this.requireSession();
    const response = await this.rpc(searchThreadsRequest(query), '无法搜索会话。请检查环境连接和读取权限。',
      false, undefined, NETWORK_TIMEOUT_MS);
    if (!response.exit?.value) throw new Error('环境未返回会话搜索结果。');
    return readThreadSearchMatches(response.exit.value, session.environmentId);
  }

  async listArchivedThreads(): Promise<NativeThread[]> {
    const frame = await this.rpc(archivedThreadSnapshotRequest(), '无法读取归档会话。请检查环境和读取权限。');
    if (!frame.exit?.value) throw new Error('环境未返回归档会话。');
    return readThreads(frame.exit.value);
  }

  async changeThreadLifecycle(threadId: string, action: ThreadLifecycleAction, value?: string): Promise<void> {
    await this.rpc(threadLifecycleRequest(util.generateRandomUUID(), threadId, action, value),
      '无法更新会话。请检查会话状态和环境权限。');
  }

  async visitThread(threadId: string, visitedAt: string): Promise<void> {
    const session = this.requireSession();
    if (!(await this.threadPermissions()).operate) throw new Error('此连接只有会话读取权限。');
    if (session !== this.session) throw new Error('环境连接已更换。');
    await this.rpc(threadVisitRequest(util.generateRandomUUID(), threadId, visitedAt), '无法更新会话的已读状态。');
  }

  async readThreadLinkTarget(threadId: string): Promise<NativeThread> {
    const path = '/api/orchestration/threads/' + encodeURIComponent(threadId) + '/bounded?deferWork=1';
    const response = await this.environmentRequest(path) as ThreadLinkSnapshot;
    const thread = response?.projection?.thread;
    if (!thread || thread.id !== threadId || typeof thread.title !== 'string') {
      throw new Error('链接中的会话不存在或不可用。');
    }
    if (thread.projectId) {
      const session = this.requireSession();
      const snapshot = await this.environmentRequest('/api/projects').catch(() => undefined) as
        ThreadLinkProjectSnapshot | undefined;
      if (session !== this.session) throw new Error('环境连接已更换。');
      const project = snapshot && Array.isArray(snapshot.projects) ? snapshot.projects.find((entry) =>
        entry?.id === thread.projectId) : undefined;
      if (project && typeof project.title === 'string' && typeof project.workspaceRoot === 'string') {
        thread.projectTitle = project.title;
        thread.workspaceRoot = project.workspaceRoot;
      }
    }
    return thread;
  }

  async forkThreadFromReply(environmentKey: string, source: NativeThreadForkSource,
    attempt: NativeThreadForkAttempt, title?: string): Promise<NativeThread> {
    const session = this.requireSession();
    if (!environmentKey || this.currentEnvironment()?.key !== environmentKey) throw new Error('环境连接已更换。');
    const request = threadForkFromReplyRequest(source, attempt, title);
    const permissions = await this.threadPermissions();
    if (session !== this.session) throw new Error('环境连接已更换。');
    if (!permissions.operate) throw new Error('此连接缺少分叉会话的权限。');
    let accepted = false;
    let rejection: ThreadCommandRejectedError | undefined;
    try {
      const response = await this.rpc(request, '环境拒绝从此回复分叉。请检查回复状态和环境权限。',
        false, undefined, SEND_TIMEOUT_MS);
      accepted = readThreadForkReceipt(response.exit?.value);
    } catch (error) {
      if (error instanceof ThreadCommandRejectedError) rejection = error;
    }
    if (session !== this.session) throw new Error('环境连接已更换。');
    const target = await this.readThreadLinkTarget(attempt.targetThreadId).catch(() => undefined);
    if (session !== this.session) throw new Error('环境连接已更换。');
    const thread = target ? readConfirmedThreadFork(target, source, attempt) : undefined;
    if (thread) {
      thread.environmentKey = environmentKey;
      thread.environmentLabel = session.label;
      return thread;
    }
    if (rejection) throw rejection;
    if (accepted) throw new ThreadForkTargetPendingError('分叉已创建，暂未读取到目标会话。重新连接后可再试。');
    throw new ThreadForkUnconfirmedError('无法确认分叉结果。请重新连接并检查会话列表。');
  }

  async projectManagementSnapshot(): Promise<ProjectManagementSnapshot> {
    const session = this.requireSession();
    const projects = this.environmentRequest('/api/projects');
    const config = this.rpc(threadLaunchConfigRequest(), '无法读取环境项目能力。',
      false, undefined, NETWORK_TIMEOUT_MS).catch(() => undefined);
    const permissions = this.threadPermissions().catch(() => undefined);
    const results = await Promise.all([projects, config, permissions]);
    if (session !== this.session) throw new Error('环境连接已更换。');
    const snapshot = results[0] as Object;
    const options = results[1] as RpcFrame | undefined;
    const access = results[2] as ThreadPermissions | undefined;
    const value = options?.exit?.value;
    return {
      projects: readManagedProjects(snapshot, value),
      canOperate: access?.operate === true,
      canOrganize: value !== undefined && supportsProjectOrganization(value),
    };
  }

  async browseProjectFolders(path: string): Promise<NativeProjectFolderListing> {
    const frame = await this.rpc(projectBrowseRequest(path), '无法浏览主机目录。请检查路径和文件读取权限。',
      false, undefined, NETWORK_TIMEOUT_MS);
    return readProjectFolderListing(frame.exit?.value);
  }

  async changeProject(change: ProjectManagementChange): Promise<NativeManagedProject> {
    const session = this.requireSession();
    if (!(await this.threadPermissions()).operate) throw new Error('此连接缺少管理项目的权限。');
    const config = change.action !== 'rename' ?
      await this.rpc(threadLaunchConfigRequest(), '无法读取主机类型。请检查环境连接。',
        false, undefined, NETWORK_TIMEOUT_MS) : undefined;
    if (this.session !== session) throw new Error('环境连接已更换。');
    const serverConfig = config?.exit?.value;
    if (change.action !== 'rename' && change.action !== 'add' &&
      (serverConfig === undefined || !supportsProjectOrganization(serverConfig))) {
      throw new Error('当前环境不支持项目置顶或归档。');
    }
    const projectId = change.projectId ?? util.generateRandomUUID();
    const frame = await this.rpc(projectManagementRequest(util.generateRandomUUID(), projectId, change, serverConfig),
      '无法更新项目。请检查状态和权限。');
    if (!frame.exit?.value) throw new Error('环境未返回项目。');
    const project = readManagedProject(frame.exit.value);
    if (project.id !== projectId) throw new Error('环境返回了另一个项目。');
    return project;
  }

  async threadLaunchOptions(): Promise<ThreadLaunchOptions> {
    const session = this.requireSession();
    const results = await Promise.all([
      this.environmentRequest('/api/orchestration/shell'),
      this.rpc(threadLaunchConfigRequest(), '无法加载环境模型。请检查环境连接和权限。'),
    ]);
    if (session !== this.session) throw new Error('环境连接已更换。');
    const config = results[1] as RpcFrame;
    if (!config.exit?.value) throw new Error('环境未返回模型配置。');
    return readThreadLaunchOptions(results[0], config.exit.value);
  }

  async threadModelProviders(projectId: string, cwd?: string): Promise<ThreadLaunchProvider[]> {
    return (await this.threadModelSettings(projectId, cwd)).providers;
  }

  async composerModelSettings(scope: NativeComposerScope): Promise<ThreadModelSettings> {
    const session = this.requireComposerEnvironment(scope);
    const projectId = scope.projectId;
    if (!projectId) throw new Error('当前会话没有可用的项目。');
    const cached = this.modelSettingsCache;
    if (cached?.session === session && cached.projectId === projectId && cached.cwd === scope.cwd &&
      Date.now() - cached.readAt < 30_000) return cached.settings;
    return this.threadModelSettings(projectId, scope.cwd);
  }

  async readComposerProviderCatalog(scope: NativeComposerScope, instanceId: string): Promise<NativeComposerProviderCatalog> {
    const session = this.requireComposerEnvironment(scope);
    const projectId = scope.projectId;
    if (!projectId) throw new Error('当前会话没有可用的项目。');
    const request = composerProviderCatalogRequest(instanceId, scope.cwd ?? '');
    const cwd = request.payload.cwd;
    const cached = this.composerCatalog;
    if (cached?.session === session && cached.projectId === projectId && cached.cwd === cwd &&
      cached.selection.instanceId === instanceId && cached.expiresAt > Date.now()) return cached.selection;
    const settings = await this.composerModelSettings(scope);
    if (session !== this.session) throw new Error('环境连接已更换。');
    if (!settings.providers.some((provider: ThreadLaunchProvider) => provider.instanceId === instanceId)) {
      throw new Error('当前项目未启用此提供商。');
    }
    const frame = await this.rpc(request, '无法读取当前工作区的命令与技能。', false, undefined, SEND_TIMEOUT_MS);
    if (session !== this.session) throw new Error('环境连接已更换。');
    if (!frame.exit?.value) throw new Error('环境未返回命令与技能。');
    const selection = readComposerProviderCatalog(frame.exit.value, instanceId, cwd);
    this.composerCatalog = { session, projectId, cwd, selection,
      expiresAt: Date.now() + (selection.pending ? 10_000 : 5 * 60_000) };
    return selection;
  }

  async threadModelSettings(projectId: string, cwd?: string): Promise<ThreadModelSettings> {
    const session = this.requireSession();
    const frame = await this.rpc(threadLaunchConfigRequest(), '无法加载环境模型。请检查环境连接和权限。');
    if (session !== this.session) throw new Error('环境连接已更换。');
    if (!frame.exit?.value) throw new Error('环境未返回模型配置。');
    const settings = readThreadModelSettings(frame.exit.value, projectId, cwd);
    this.modelSettingsCache = { session, projectId, cwd, readAt: Date.now(), settings };
    return settings;
  }

  async threadMessageModel(projectId: string, cwd: string | undefined, draft?: ThreadLaunchSelection,
    current?: ThreadLaunchSelection): Promise<ThreadLaunchSelection | undefined> {
    const selection = draft ?? current;
    if (!selection || selection.options?.some((option: ThreadModelOptionSelection) => option.id === 'fastMode')) return draft;
    const session = this.requireSession();
    const cached = this.modelSettingsCache;
    const settings = cached && cached.session === session && cached.projectId === projectId && cached.cwd === cwd &&
      Date.now() - cached.readAt < 60_000 ? cached.settings : await this.threadModelSettings(projectId, cwd).catch(() => undefined);
    if (session !== this.session) throw new Error('环境连接已更换。');
    const model = settings?.providers.find((provider) => provider.instanceId === selection.instanceId)
      ?.models.find((item) => item.slug === selection.model);
    const resolved = withThreadModelOptionDefaults(model, selection);
    return resolved === selection ? draft : resolved;
  }

  async canWriteModelCatalogPreferences(): Promise<boolean> {
    const session = this.requireSession();
    const grant = await this.readAuthenticatedSession();
    if (session !== this.session) throw new Error('环境连接已更换。');
    return modelCatalogSettingsWriteAllowed({ authenticated: grant.authenticated, permissions: grant.permissions,
      scopes: grant.scopes, serverUpdateScope: grant.auth?.serverUpdateScope });
  }

  async updateModelCatalogPreferences(provider: string, model: string, kind: ModelCatalogPreferenceKind,
    enabled: boolean): Promise<NativeModelCatalogPreferences> {
    const session = this.requireSession();
    const request = modelCatalogUpdateRequest(provider, model, kind, enabled);
    const canWrite = await this.canWriteModelCatalogPreferences();
    if (session !== this.session) throw new Error('环境连接已更换。');
    if (!canWrite) throw new Error('环境未授权修改模型偏好。');
    const frame = await this.rpc(request, '无法更新模型偏好，请检查环境连接或配置。', false, undefined,
      NETWORK_TIMEOUT_MS);
    if (session !== this.session) throw new Error('环境连接已更换。');
    return readUpdatedModelCatalogPreferences(frame.exit?.value, provider, model, kind, enabled);
  }

  async launchThread(attempt: ThreadLaunchAttempt, project: ThreadLaunchProject, selection: ThreadLaunchSelection,
    text: string, runtimeMode: ThreadLaunchRuntimeMode = 'approval-required',
    attachments: UploadedThreadAttachment[] = [],
    workspace: ThreadLaunchWorkspaceStrategy = { type: 'root' }, context?: ThreadMessageContext): Promise<NativeThread> {
    const request = launchThreadRequest(attempt.commandId, attempt.threadId, attempt.messageId, project.id,
      selection, text, undefined, runtimeMode, attachments, workspace, context);
    const response = await this.rpc(request, '环境拒绝了新建会话。请检查项目、模型与环境权限。');
    if (!response.exit?.value) throw new Error('环境未确认新会话。请检查会话列表。');
    const id = readLaunchedThreadId(response.exit.value);
    if (id !== attempt.threadId) throw new Error('环境返回了另一个会话。请检查会话列表。');
    return {
      id, title: '新会话', projectId: project.id, projectTitle: project.title, workspaceRoot: project.workspaceRoot,
      worktreePath: workspace.type === 'existing_worktree' ? workspace.worktreePath : undefined,
    };
  }

  async openLaunchScratch(workspaceRoot: string): Promise<ThreadLaunchScratch> {
    const session = this.requireSession();
    if (!(await this.threadPermissions()).operate) throw new Error('此连接缺少创建会话的权限。');
    if (this.session !== session) throw new Error('环境连接已更换。');
    const frame = await this.rpc(threadLaunchScratchRequest(), '无法准备无项目会话。');
    if (!frame.exit?.value) throw new Error('环境未返回临时项目。');
    const project = readThreadLaunchScratchProject(frame.exit.value, workspaceRoot);
    const providers = await this.threadModelProviders(project.id, project.workspaceRoot);
    return { project, providers };
  }

  async switchThreadLaunchRef(cwd: string, refName: string): Promise<string | null> {
    const session = this.requireSession();
    if (!(await this.threadPermissions()).gitWrite) throw new Error('此连接缺少切换 Git 分支的权限。');
    if (this.session !== session) throw new Error('环境连接已更换。');
    const frame = await this.rpc(threadGitSwitchRefRequest(cwd, refName), '无法切换当前工作区分支。');
    if (!frame.exit?.value) throw new Error('环境未确认分支，请刷新后重试。');
    return readThreadGitRefName(frame.exit.value);
  }

  async readAuthAccessSnapshot(): Promise<Object> {
    const request: AuthAccessRequest = {
      _tag: 'Request', id: REQUEST_ID, tag: 'subscribeAuthAccess', payload: {}, headers: [],
    };
    const frame = await this.rpc(request, '无法读取环境的设备请求。请检查连接与权限。', true);
    const event = frame.values?.[0];
    if (!event) throw new Error('环境未返回设备请求。');
    return event;
  }

  private socketAddress(session: SavedEnvironment): Promise<string> {
    return this.socketAddressFor(session, this.managed);
  }

  private async socketAddressFor(session: SavedEnvironment, transport?: RelayConnection): Promise<string> {
    if (transport) return transport.socketAddress(ORCHESTRATION_PROTOCOL);
    const response = await requestJson<TicketResponse>(session.origin, '/api/auth/websocket-ticket/rpc',
      http.RequestMethod.POST, session.token);
    if (!response || typeof response.ticket !== 'string' || response.ticket.length === 0) {
      throw new Error('环境未返回会话连接凭据。');
    }
    return session.origin.replace(/^http/, 'ws') + '/ws?orchestrationProtocol=' + ORCHESTRATION_PROTOCOL +
      '&wsTicket=' + encodeURIComponent(response.ticket);
  }

  private async terminalSocketAddress(session: SavedEnvironment): Promise<string> {
    if (this.session !== session) throw new Error('环境连接已更换。');
    const address = await this.socketAddress(session);
    if (this.session !== session) throw new Error('环境连接已更换。');
    return address;
  }

  async listThreadTerminals(threadId: string): Promise<NativeThreadTerminalSummary[]> {
    const session = this.requireSession();
    return readThreadTerminals(() => this.terminalSocketAddress(session), () => this.session === session, threadId);
  }

  watchThreadTerminal(target: ThreadTerminalTarget, onUpdate: (update: NativeTerminalUpdate) => void,
    onError: (error: Error, reconnecting: boolean) => void): ThreadTerminalHandle {
    const session = this.requireSession();
    const connection = new ThreadTerminalConnection(() => this.terminalSocketAddress(session),
      () => this.session === session, target, onUpdate, onError);
    const stop = (): void => {
      this.watchers.delete(stop);
      connection.dispose();
    };
    this.watchers.add(stop);
    connection.start();
    return {
      write: (data: string, reply?: boolean, binary?: boolean) => connection.write(data, binary, reply),
      resize: (cols: number, rows: number) => connection.resize(cols, rows),
      clear: () => connection.clear(),
      close: () => connection.close(true),
      dispose: stop,
    };
  }

  async readThreadWork(threadId: string, itemId: string): Promise<string> {
    const reply = await this.rpc(threadWorkDetailRequest(threadId, itemId), '无法读取命令输出，请重试。');
    if (!reply.exit?.value) throw new Error('环境未返回命令输出。');
    return readThreadWorkDetail(reply.exit.value, threadId, itemId);
  }

  async readThreadCheckpointDiff(environmentKey: string, threadId: string, ordinal: number): Promise<NativeThreadCheckpointDiff> {
    const session = this.requireSession();
    if (!environmentKey || this.currentEnvironment()?.key !== environmentKey) throw new Error('环境连接已更换。');
    const request = threadCheckpointDiffRequest(threadId, ordinal);
    const grant = await this.readAuthenticatedSession();
    if (session !== this.session) throw new Error('环境连接已更换。');
    if (!(grant.permissions ?? grant.scopes)?.includes('orchestration:read')) {
      throw new Error('此连接缺少会话读取权限。');
    }
    const frame = await this.rpc(request, '无法读取此轮次的变更。请检查当前检查点和环境连接。',
      false, undefined, LONG_RPC_TIMEOUT_MS);
    if (session !== this.session) throw new Error('环境连接已更换。');
    if (!frame.exit?.value) throw new Error('环境未返回轮次变更。');
    return readThreadCheckpointDiff(frame.exit.value, request.payload);
  }

  async threadPermissions(): Promise<ThreadPermissions> {
    const session = await this.readAuthenticatedSession();
    const permissions = session.permissions ?? session.scopes;
    const scopes = Array.isArray(permissions) ? permissions : [];
    const legacy = session.permissions === undefined;
    const operate = scopes.includes('orchestration:operate');
    const terminalOperate = scopes.includes('terminal:operate');
    return {
      operate,
      readFiles: scopes.includes('filesystem:read') || (legacy && scopes.includes('orchestration:read')),
      gitWrite: scopes.includes('source-control:write') || (legacy && operate),
      terminalRead: scopes.includes('terminal:read') || (legacy && terminalOperate),
      terminalOperate,
    };
  }

  async canApproveDevices(): Promise<boolean> {
    const session = await this.readAuthenticatedSession();
    const permissions = session.permissions ?? session.scopes;
    return !!permissions?.includes('access:read') && permissions.includes('access:write');
  }

  private async environmentMaintenanceState(): Promise<EnvironmentMaintenanceState> {
    const session = this.requireSession();
    const access = await this.readAuthenticatedSession();
    const permissions = access.permissions ?? access.scopes ?? [];
    const legacyOperate = access.permissions === undefined && access.auth?.serverUpdateScope === undefined;
    if (!permissions.includes('orchestration:read')) throw new Error('此连接缺少环境读取权限。');
    if (this.session !== session) throw new Error('环境连接已更换。');
    const frame = await this.rpc(threadLaunchConfigRequest(), '无法读取环境维护状态。', false, undefined,
      NETWORK_TIMEOUT_MS);
    return { session, permissions, legacyOperate,
      snapshot: readEnvironmentMaintenance(frame.exit?.value, permissions, legacyOperate) };
  }

  async readEnvironmentMaintenance(): Promise<EnvironmentMaintenanceSnapshot> {
    return (await this.environmentMaintenanceState()).snapshot;
  }

  async refreshEnvironmentMaintenanceProviders(): Promise<EnvironmentMaintenanceSnapshot> {
    const state = await this.environmentMaintenanceState();
    if (!state.snapshot.canRefresh) throw new Error('此连接缺少刷新提供商的权限。');
    if (this.session !== state.session) throw new Error('环境连接已更换。');
    const frame = await this.rpc(refreshEnvironmentProvidersRequest(), '无法刷新提供商。', false, undefined,
      SEND_TIMEOUT_MS);
    state.snapshot.providers = readMaintenanceProviders(frame.exit?.value, state.permissions, state.legacyOperate);
    return state.snapshot;
  }

  async updateEnvironmentMaintenanceProvider(requested: EnvironmentMaintenanceProvider):
    Promise<EnvironmentMaintenanceSnapshot> {
    const state = await this.environmentMaintenanceState();
    const provider = state.snapshot.providers.find((row) => row.instanceId === requested.instanceId &&
      row.driver === requested.driver && row.latestVersion === requested.latestVersion);
    if (!provider?.canUpdate) throw new Error('提供商状态或更新权限已变更，请刷新后重试。');
    if (this.session !== state.session) throw new Error('环境连接已更换。');
    const frame = await this.rpc(updateEnvironmentProviderRequest(provider), '无法更新提供商。', false, undefined,
      LONG_RPC_TIMEOUT_MS);
    state.snapshot.providers = readMaintenanceProviders(frame.exit?.value, state.permissions, state.legacyOperate);
    return state.snapshot;
  }

  async readLinkedEnvironmentHealth(): Promise<LinkedEnvironmentSnapshot> {
    const selected = this.requireSession();
    const permissions = await this.linkedEnvironmentPermissions(selected);
    if (!permissions) return { links: [], canManage: false };
    const response = await this.rpc(linkedEnvironmentsRequest(), '无法读取关联环境。',
      false, undefined, NETWORK_TIMEOUT_MS);
    return { links: readLinkedEnvironments(response.exit?.value), canManage: permissions.includes('access:write') };
  }

  async readComposerLinkedEnvironments(scope: NativeComposerScope): Promise<LinkedEnvironmentSnapshot> {
    const session = this.requireComposerEnvironment(scope);
    let cached = this.composerLinks;
    if (cached?.session !== session || cached.expiresAt <= Date.now()) {
      cached = { session, expiresAt: Date.now() + 30_000, result: this.readLinkedEnvironmentHealth() };
      this.composerLinks = cached;
    }
    try {
      const result = await cached.result;
      if (session !== this.session) throw new Error('环境连接已更换。');
      return result;
    } catch (error) {
      if (this.composerLinks === cached) this.composerLinks = undefined;
      throw error as Error;
    }
  }

  private async linkedEnvironmentPermissions(selected: SavedEnvironment): Promise<string[] | undefined> {
    const access = await this.readAuthenticatedSession();
    const permissions = access.permissions ?? access.scopes;
    if (!permissions?.includes('access:read') || !permissions.includes('orchestration:read')) return undefined;
    if (this.session !== selected) throw new Error('环境连接已更换。');
    const config = await this.rpc(threadLaunchConfigRequest(), '无法读取关联环境设置。',
      false, undefined, NETWORK_TIMEOUT_MS);
    if (this.session !== selected) throw new Error('环境连接已更换。');
    return supportsLinkedEnvironments(config.exit?.value) ? permissions : undefined;
  }

  async linkSavedEnvironment(key: string, access: NativePeerLinkAccess, accountId?: string,
    connectManaged?: ConnectManagedEnvironment): Promise<void> {
    const source = this.requireSession();
    if (!(await this.linkedEnvironmentPermissions(source))?.includes('access:write')) {
      throw new Error('此环境未开启关联，或当前连接缺少管理权限。');
    }
    await this.linkSavedEnvironmentFrom(source, key, access, accountId, connectManaged);
  }

  async linkSavedEnvironmentBatch(keys: string[], access: NativePeerLinkAccess, accountId?: string,
    connectManaged?: ConnectManagedEnvironment, onProgress?: (result: LinkedEnvironmentBatchResult) => void):
    Promise<LinkedEnvironmentBatchResult[]> {
    const source = this.requireSession();
    const snapshot = await this.readLinkedEnvironmentHealth();
    if (!snapshot.canManage) throw new Error('此环境未开启关联，或当前连接缺少管理权限。');
    const seen = new Set<string>(snapshot.links.filter((entry) =>
      linkedEnvironmentHealth(entry, Date.now()).kind !== 'expired').map((entry) => entry.environmentId));
    const saved = await this.store.list(accountId);
    const results: LinkedEnvironmentBatchResult[] = [];
    for (const key of new Set<string>(keys)) {
      const target = saved.find((row) => row.key === key && row.enabled && row.environmentId !== source.environmentId);
      let result: LinkedEnvironmentBatchResult;
      if (this.session !== source) {
        result = { key, label: target?.label ?? '环境', status: 'failed', message: '来源环境连接已更换。' };
      } else if (!target) {
        result = { key, label: '环境', status: 'failed', message: '此环境已移除、已停用或无法作为目标。' };
      } else if (seen.has(target.environmentId)) {
        result = { key, label: target.label, status: 'linked', message: '已有活动关联。' };
      } else {
        onProgress?.({ key, label: target.label, status: 'linking' });
        try {
          await this.linkSavedEnvironmentFrom(source, key, access, accountId, connectManaged);
          seen.add(target.environmentId);
          result = { key, label: target.label, status: 'linked' };
        } catch (error) {
          const message = this.session !== source ? '来源环境连接已更换。' :
            error instanceof AccountSessionExpiredError ? 'T3 账户已过期，请重新登录后重试。' :
              canTryAnotherEnvironmentRoute(error as Error) ? '目标环境当前无法访问。' :
                '关联失败，请检查目标连接和权限。';
          result = { key, label: target.label, status: 'failed', message };
        }
      }
      results.push(result);
      onProgress?.(result);
    }
    return results;
  }

  private async linkSavedEnvironmentFrom(source: SavedEnvironment, key: string, access: NativePeerLinkAccess,
    accountId?: string, connectManaged?: ConnectManagedEnvironment): Promise<void> {
    if (this.session !== source) throw new Error('来源环境连接已更换。');
    const requested = await this.store.get(key, accountId);
    if (requested.environmentId === source.environmentId) throw new Error('不能关联当前环境。');
    const prepared = await this.preparePreferredRoute(requested, false, accountId, connectManaged);
    const target = prepared.session;
    const transport = prepared.transport;
    const peer = new T3Client(this.context);
    peer.useSession(target, transport);
    const targetAccess = await peer.readAuthenticatedSession();
    if (!canMintLinkedEnvironmentPairing(targetAccess.permissions ?? targetAccess.scopes, access)) {
      throw new Error('目标环境连接无法签发所选权限的关联配对码。');
    }
    const config = await peer.rpc(threadLaunchConfigRequest(), '无法读取目标环境的关联设置。',
      false, undefined, NETWORK_TIMEOUT_MS);
    if (!supportsLinkedEnvironmentPairing(config.exit?.value)) throw new Error('目标环境未开放关联配对。');

    const routes = await this.store.list(accountId);
    const origins = new Set<string>();
    const preferred = linkedEnvironmentOrigin(transport ? transport.currentOrigin() : target.origin);
    if (preferred) origins.add(preferred);
    for (const route of routes) {
      if (route.enabled && route.environmentId === target.environmentId) {
        const origin = linkedEnvironmentOrigin(route.origin);
        if (origin) origins.add(origin);
      }
    }
    const urls = Array.from(origins);
    if (urls.length === 0) throw new Error('目标环境没有其他主机可访问的地址。');
    if (this.session !== source) throw new Error('环境连接已更换。');
    const result = await peer.environmentRequest(LINKED_ENVIRONMENT_PAIRING_PATH, 'POST',
      linkedEnvironmentPairingBody(access));
    const code = readLinkedEnvironmentPairingCode(result, access);
    if (this.session !== source) throw new Error('环境连接已更换。');
    const candidate: LinkedEnvironmentCandidate = { key, environmentId: target.environmentId,
      label: target.label, origin: urls[0] };
    await this.rpc(linkEnvironmentRequest(candidate, code, access, urls.slice(1)),
      '无法关联目标环境。请检查目标地址和关联权限。');
  }

  async unlinkEnvironment(environmentId: string): Promise<UnlinkEnvironmentResult> {
    const source = this.requireSession();
    if (!(await this.linkedEnvironmentPermissions(source))?.includes('access:write')) {
      throw new Error('此环境未开启关联，或当前连接缺少管理权限。');
    }
    if (this.session !== source) throw new Error('环境连接已更换。');
    const response = await this.rpc(unlinkEnvironmentRequest(environmentId), '无法解除关联。');
    return readUnlinkEnvironmentResult(response.exit?.value);
  }

  async bindDeviceApprovalTarget(environment: EnvironmentSummary, accountId?: string,
    connectManaged?: ConnectManagedEnvironment): Promise<ConnectDeviceApprovalTarget | undefined> {
    const session = await this.store.get(environment.key, accountId);
    const transport = await this.prepareSavedConnection(session, connectManaged);
    const bound = new T3Client(this.context);
    bound.useSession(session, transport);
    const access = await bound.readAuthenticatedSession();
    const permissions = access.permissions ?? access.scopes;
    if (!permissions?.includes('orchestration:read') || !permissions.includes('access:read') ||
      !permissions.includes('access:write')) return undefined;

    const respond = async (id: string, approve: boolean, isCurrent: () => boolean): Promise<DeviceApprovalOutcome> => {
      const saved = await this.store.get(environment.key, accountId);
      if (!isCurrent() || saved.enabled === false || saved.origin !== session.origin || saved.token !== session.token ||
        saved.accountId !== session.accountId) return 'gone';
      if (!(await bound.canApproveDevices()) || !isCurrent()) return 'gone';
      const client = new DeviceApprovalClient(() => bound.readAuthAccessSnapshot(),
        (path: string, method?: string, body?: string) => bound.environmentRequest(path, method, body));
      return approve ? client.approve(id) : client.deny(id);
    };
    return {
      key: environment.key,
      label: environment.label,
      socketAddress: () => bound.socketAddress(session),
      approve: (id: string, isCurrent: () => boolean) => respond(id, true, isCurrent),
      deny: (id: string, isCurrent: () => boolean) => respond(id, false, isCurrent),
    };
  }

  private async readAuthenticatedSession(): Promise<EnvironmentSessionPermissions> {
    const session = await this.environmentRequest('/api/auth/session') as EnvironmentSessionPermissions;
    if (session.authenticated !== true) throw new Error('环境授权已失效，请重新连接。');
    return session;
  }

  async listThreadFiles(cwd: string, path: string): Promise<NativeThreadFileDirectory> {
    const frame = await this.rpc(listThreadFilesRequest(cwd, path), '无法读取项目目录。请检查环境连接和文件权限。');
    if (!frame.exit?.value) throw new Error('环境未返回项目目录。');
    return readThreadFileDirectory(frame.exit.value, path);
  }

  async readWorkspacePullRequests(input: NativePullRequestQuery): Promise<NativePullRequestPage> {
    const frame = await this.rpc(pullRequestListRequest(input), '无法加载拉取请求。请检查代码托管设置。',
      false, undefined, SEND_TIMEOUT_MS);
    if (!frame.exit?.value) throw new Error('环境未返回拉取请求列表。');
    return readPullRequestPage(frame.exit.value);
  }

  async searchComposerPullRequests(scope: NativeComposerScope, query: string): Promise<NativePullRequestRow[]> {
    const session = this.requireComposerEnvironment(scope);
    const projectId = scope.projectId;
    if (!projectId) return [];
    const project = readComposerProjectRepository(await this.environmentRequest('/api/projects'), projectId);
    if (session !== this.session) throw new Error('环境连接已更换。');
    if (!project) throw new Error('当前项目没有可查询拉取请求的远端仓库。');
    const target = query.trim().slice(0, 200).replace(/[\uD800-\uDBFF]$/, '').trimEnd();
    const numeric = /^\d*$/.test(target);
    const page = await this.readWorkspacePullRequests({
      projectId, state: 'all', involvement: 'all', limit: 200, query: numeric ? undefined : target,
    });
    if (session !== this.session) throw new Error('环境连接已更换。');
    let rows = matchComposerPullRequests(page.rows, project, target);
    const number = Number(target);
    if (numeric && Number.isSafeInteger(number) && number > 0 &&
      !rows.some((entry: NativePullRequestRow) => entry.number === number)) {
      const detail = await this.readWorkspacePullRequest({
        projectId, host: project.host, repository: project.repository, number,
      }).catch(() => undefined);
      if (session !== this.session) throw new Error('环境连接已更换。');
      if (detail) rows = matchComposerPullRequests([detail, ...rows], project, target);
    }
    if (rows.length === 0 && page.messages.length > 0) throw new Error(page.messages[0]);
    return rows;
  }

  async readWorkspacePullRequestFilterOptions(mode: NativePullRequestFilterMode, projectId?: string,
    query?: string): Promise<NativePullRequestFilterCandidatePage> {
    if (mode === 'projects') {
      const projects = readManagedProjects(await this.environmentRequest('/api/projects'));
      const candidates = projects.sort((left: NativeManagedProject, right: NativeManagedProject) =>
        Number(left.archived) - Number(right.archived) || Number(right.pinned) - Number(left.pinned) ||
        left.title.localeCompare(right.title)).map((entry: NativeManagedProject): NativePullRequestFilterCandidate =>
        ({ key: entry.id, title: entry.title }));
      return { candidates, truncated: false };
    }
    const frame = await this.rpc(pullRequestFilterOptionsRequest(mode, projectId, query),
      '无法读取拉取请求筛选选项。', false, undefined, SEND_TIMEOUT_MS);
    return readPullRequestFilterOptions(frame.exit?.value, mode);
  }

  async readWorkspacePullRequest(ref: NativePullRequestRef, allowStale?: boolean): Promise<NativePullRequestDetail> {
    const frame = await this.rpc(pullRequestDetailRequest(ref, allowStale), '无法读取拉取请求。',
      false, undefined, SEND_TIMEOUT_MS);
    if (!frame.exit?.value) throw new Error('环境未返回拉取请求详情。');
    return readPullRequestDetail(frame.exit.value, ref);
  }

  async readWorkspacePullRequestDiscussion(ref: NativePullRequestRef): Promise<NativePullRequestDiscussion> {
    const frame = await this.rpc(pullRequestActivityRequest(ref), '无法读取拉取请求讨论。',
      false, undefined, SEND_TIMEOUT_MS);
    if (!frame.exit?.value) throw new Error('环境未返回拉取请求讨论。');
    return readPullRequestDiscussion(frame.exit.value);
  }

  async readWorkspacePullRequestMetadata(ref: NativePullRequestRef, kind: NativePullRequestMetadataKind,
    query?: string): Promise<NativePullRequestMetadataPage> {
    const failure = kind === 'labels' ? '无法读取拉取请求标签。' : '无法读取评审人候选。';
    const frame = await this.rpc(pullRequestMetadataRequest(ref, kind, query), failure, false, undefined,
      SEND_TIMEOUT_MS);
    return readPullRequestMetadata(frame.exit?.value, kind);
  }

  async readWorkspacePullRequestCompletionOptions(ref: NativePullRequestRef,
    trigger: NativePullRequestComposerTrigger): Promise<NativePullRequestCompletionOptions> {
    const frame = await this.rpc(pullRequestCompletionOptionsRequest(ref, trigger), '无法搜索引用候选。',
      false, undefined, SEND_TIMEOUT_MS);
    return readPullRequestCompletionOptions(frame.exit?.value);
  }

  async workspacePullRequestGuidesEnabled(): Promise<boolean> {
    const frame = await this.rpc(threadLaunchConfigRequest(), '无法读取环境的审查指南设置。',
      false, undefined, NETWORK_TIMEOUT_MS);
    return pullRequestGuidesEnabled(frame.exit?.value);
  }

  async readWorkspacePullRequestGuide(ref: NativePullRequestRef): Promise<NativePullRequestGuideResult> {
    const frame = await this.rpc(pullRequestGuideRequest(ref), '无法读取拉取请求的审查指南。',
      false, undefined, SEND_TIMEOUT_MS);
    return readPullRequestGuide(frame.exit?.value);
  }

  async workspacePullRequestGuideCanGenerate(): Promise<boolean> {
    return (await this.threadPermissions()).operate;
  }

  async generateWorkspacePullRequestGuide(ref: NativePullRequestRef): Promise<NativePullRequestGuideResult> {
    const session = this.requireSession();
    const request = generatePullRequestGuideRequest(ref);
    const canGenerate = await this.workspacePullRequestGuideCanGenerate();
    if (this.session !== session) throw new Error('环境连接已更换。');
    if (!canGenerate) throw new Error('此连接缺少生成审查指南的权限。');
    const frame = await this.rpc(request, '无法启动审查指南生成。', false, undefined, SEND_TIMEOUT_MS);
    return readPullRequestGuide(frame.exit?.value);
  }

  async readWorkspacePullRequestDiff(ref: NativePullRequestRef, cursor?: string): Promise<NativePullRequestDiff> {
    return readPullRequestDiff(await this.environmentRequest('/api/pull-requests/diff', 'POST',
      pullRequestDiffBody(ref, cursor)));
  }

  async readWorkspacePullRequestFileDiff(ref: NativePullRequestRef, path: string): Promise<NativePullRequestFile | undefined> {
    return readPullRequestFileDiff(await this.environmentRequest('/api/pull-requests/diff', 'POST',
      pullRequestDiffBody(ref, undefined, path), PULL_REQUEST_FILE_DIFF_LIMITS), path);
  }

  async readWorkspaceIssues(filters: NativeIssueFilters, cursors?: Record<string, string>,
    refresh?: boolean): Promise<NativeIssuePage> {
    const session = this.requireSession();
    const config = await this.rpc(threadLaunchConfigRequest(), '无法读取工单设置。', false, undefined, NETWORK_TIMEOUT_MS);
    if (this.session !== session) throw new Error('环境连接已更换。');
    if (!supportsIssues(config.exit?.value)) {
      return { entries: [], trackers: [], errors: [], nextCursors: {}, unavailable: true };
    }
    const frame = await this.rpc(issueListRequest(filters, cursors, refresh), '无法加载工单。请检查跟踪器设置。',
      false, undefined, SEND_TIMEOUT_MS);
    return readIssuePage(frame.exit?.value);
  }

  async readWorkspaceIssue(ref: NativeIssueRef): Promise<NativeIssueDetail> {
    const frame = await this.rpc(issueDetailRequest(ref), '无法读取工单详情。', false, undefined, SEND_TIMEOUT_MS);
    return readIssueDetail(frame.exit?.value, ref);
  }

  async readWorkspaceIssueCandidates(scope: NativeIssueScope): Promise<NativeIssueCandidates> {
    const frame = await this.rpc(issueCandidatesRequest(scope), '无法读取工单筛选选项。', false, undefined,
      SEND_TIMEOUT_MS);
    return readIssueCandidates(frame.exit?.value);
  }

  async canWriteWorkspaceSourceControl(): Promise<boolean> {
    const session = await this.readAuthenticatedSession();
    return (session.permissions ?? session.scopes)?.includes('source-control:write') === true;
  }

  async readWorkspaceUsage(days: number): Promise<NativeUsageSummary> {
    const request = workspaceUsageSummaryRequest(days);
    const frame = await this.rpc(request, '无法读取用量。请检查诊断读取权限。',
      false, undefined, SEND_TIMEOUT_MS);
    return readWorkspaceUsageSummary(frame.exit?.value, request.payload);
  }

  async readWorkspaceUsageLimits(): Promise<NativeUsageAccount[]> {
    const frame = await this.rpc(workspaceUsageLimitsRequest(), '无法读取提供商限额。', false, undefined, NETWORK_TIMEOUT_MS);
    return readWorkspaceUsageLimits(frame.exit?.value);
  }

  async searchThreadFiles(cwd: string, query: string): Promise<NativeThreadFileDirectory> {
    const frame = await this.rpc(searchThreadFilesRequest(cwd, query), '无法搜索工作区文件。请检查环境连接和文件权限。');
    if (!frame.exit?.value) throw new Error('环境未返回文件搜索结果。');
    return readThreadFileSearch(frame.exit.value);
  }

  async searchComposerPaths(scope: NativeComposerScope, query: string): Promise<NativeThreadFileEntry[]> {
    const session = this.requireComposerEnvironment(scope);
    const request = composerPathSearchRequest(scope.cwd ?? '', query);
    const access = await this.readAuthenticatedSession();
    if (session !== this.session) throw new Error('环境连接已更换。');
    const permissions = access.permissions ?? access.scopes ?? [];
    const legacyRead = access.permissions === undefined && access.auth?.serverUpdateScope === undefined &&
      permissions.includes('orchestration:read');
    if (!legacyRead && !permissions.includes('filesystem:read')) throw new Error('此连接缺少工作区文件读取权限。');
    const frame = await this.rpc(request, '无法搜索工作区文件。请检查环境连接和文件权限。',
      false, undefined, NETWORK_TIMEOUT_MS);
    if (session !== this.session) throw new Error('环境连接已更换。');
    if (!frame.exit?.value) throw new Error('环境未返回文件搜索结果。');
    return readThreadFileSearch(frame.exit.value).entries.slice(0, request.payload.limit);
  }

  async threadGitStatus(cwd: string, localOnly: boolean = true): Promise<NativeThreadGitStatus> {
    const response = await this.rpc(threadGitStatusRequest(cwd, localOnly), '无法读取 Git 状态，请检查环境连接。',
      false, undefined, localOnly ? NETWORK_TIMEOUT_MS : LONG_RPC_TIMEOUT_MS);
    if (!response.exit?.value) throw new Error('环境未返回 Git 状态。');
    return readThreadGitStatus(response.exit.value);
  }

  async readThreadReview(cwd: string): Promise<NativeThreadReview> {
    const frame = await this.rpc(threadReviewRequest(cwd), '无法读取工作区改动。请检查连接与文件权限。',
      false, undefined, NETWORK_TIMEOUT_MS);
    if (!frame.exit?.value) throw new Error('环境未返回改动。');
    return readThreadReview(frame.exit.value, cwd);
  }

  async readThreadReviewFile(cwd: string, file: NativeThreadReviewFile, baseRef: string | null): Promise<NativeThreadReviewPatch> {
    const frame = await this.rpc(threadReviewRequest(cwd, file, baseRef), '无法读取文件改动。请检查连接与文件权限。',
      false, undefined, NETWORK_TIMEOUT_MS);
    if (!frame.exit?.value) throw new Error('环境未返回文件改动。');
    return readThreadReviewPatch(frame.exit.value, cwd, file);
  }

  async listThreadGitRefs(cwd: string, query: string, cursor: number | null,
    refKind: ThreadGitRefKind = 'local', refresh: boolean = !query.trim() && cursor === null): Promise<NativeThreadGitRefs> {
    const response = await this.rpc(threadGitRefsRequest(cwd, query, cursor, refKind, refresh), '无法读取当前工作区分支。');
    if (!response.exit?.value) throw new Error('环境未返回分支列表。');
    return readThreadGitRefs(response.exit.value);
  }

  private async validateGitRemoteTarget(cwd: string, refName: string): Promise<NativeThreadGitStatus> {
    const session = this.requireSession();
    if (!(await this.threadPermissions()).gitWrite) throw new Error('此连接缺少 Git 写入权限。');
    if (this.session !== session) throw new Error('环境连接已更换。');
    const status = await this.threadGitStatus(cwd);
    if (this.session !== session) throw new Error('环境连接已更换。');
    if (!status.isRepo || !refName || status.refName !== refName) {
      throw new Error('当前分支已更换，请刷新 Git 状态。');
    }
    return status;
  }

  async pullThreadGit(cwd: string, refName: string): Promise<NativeThreadGitPullResult> {
    await this.validateGitRemoteTarget(cwd, refName);
    const response = await this.rpc(threadGitPullRequest(cwd), '无法拉取分支，请检查工作区和远端。',
      false, undefined, LONG_RPC_TIMEOUT_MS);
    if (!response.exit?.value) throw new Error('环境未确认拉取结果，请刷新 Git 状态。');
    return readThreadGitPullResult(response.exit.value);
  }

  async pushThreadGit(cwd: string, refName: string, confirmedDefault: boolean,
    threadId: string, projectId?: string): Promise<NativeThreadGitPushResult> {
    const status = await this.validateGitRemoteTarget(cwd, refName);
    if (status.isDefaultRef && !confirmedDefault) throw new Error('推送默认分支前请确认。');
    if (status.hasWorkingTreeChanges) throw new Error('请先提交工作区改动。');
    const actionId = util.generateRandomUUID();
    let result: NativeThreadGitPushResult | undefined;
    await this.rpc(threadGitPushRequest(cwd, actionId, threadId, projectId),
      '环境未确认推送结果，请刷新 Git 状态确认。', true, (frame: RpcFrame): boolean => {
        for (const value of frame.values ?? []) {
          result = readThreadGitPushProgress(value, cwd, actionId) ?? result;
        }
        return result !== undefined;
      }, LONG_RPC_TIMEOUT_MS);
    if (!result) throw new Error('环境未确认推送结果，请刷新 Git 状态确认。');
    return result;
  }

  async changeThreadGitBranch(cwd: string, threadId: string, expectedWorktreePath: string | null,
    refName: string, create: boolean): Promise<void> {
    const session = this.requireSession();
    const permissions = await this.threadPermissions();
    if (!permissions.gitWrite || !permissions.operate) throw new Error('此连接缺少更改会话分支的权限。');
    if (this.session !== session) throw new Error('环境连接已更换。');
    const request = create ? threadGitCreateRefRequest(cwd, refName) : threadGitSwitchRefRequest(cwd, refName);
    const response = await this.rpc(request, create ? '无法创建分支，请检查名称和工作区状态。' :
      '无法切换分支，请检查工作区改动或分支占用状态。');
    if (!response.exit?.value) throw new Error('环境未确认分支结果，请刷新 Git 状态。');
    const branch = readThreadGitRefName(response.exit.value);
    if (this.session !== session) throw new Error('Git 分支已更改，请回到原环境确认。');
    try {
      await this.rpc(threadGitBranchMetadataRequest(util.generateRandomUUID(), threadId, branch, expectedWorktreePath),
        'Git 分支已更改，任务分支信息未能更新。请刷新确认。');
    } catch (error) {
      throw new Error('Git 分支已更改，任务分支信息未能更新。请刷新确认。');
    }
  }

  async commitThreadGit(cwd: string, message: string, filePaths: string[] | undefined,
    threadId: string, projectId?: string): Promise<NativeThreadGitCommitResult> {
    const session = this.requireSession();
    if (!(await this.threadPermissions()).gitWrite) throw new Error('此连接缺少提交代码的权限。');
    if (this.session !== session) throw new Error('环境连接已更换。');
    const actionId = util.generateRandomUUID();
    let result: NativeThreadGitCommitResult | undefined;
    await this.rpc(threadGitCommitRequest(cwd, actionId, message, filePaths, threadId, projectId),
      '环境未确认提交结果，请刷新 Git 状态确认。', true, (frame: RpcFrame): boolean => {
        for (const value of frame.values ?? []) {
          const progress = readThreadGitCommitProgress(value, cwd, actionId);
          if (progress !== undefined) {
            result = progress;
            return true;
          }
        }
        return false;
      }, LONG_RPC_TIMEOUT_MS);
    if (result === undefined) throw new Error('环境未返回提交结果，请刷新 Git 状态。');
    return result;
  }

  async readThreadFile(cwd: string, path: string): Promise<NativeThreadFile> {
    const frame = await this.rpc(readThreadFileRequest(cwd, path), '无法读取文件。请检查文件状态和环境权限。');
    if (!frame.exit?.value) throw new Error('环境未返回文件内容。');
    return readThreadFile(frame.exit.value, path);
  }

  async setThreadModel(threadId: string, selection: ThreadLaunchSelection): Promise<void> {
    const request = modelSelectionRequest(util.generateRandomUUID(), threadId, selection);
    await this.rpc(request, '无法更改会话模型。请检查模型和环境权限。');
  }

  async createThreadAttachmentAssetUrl(environmentKey: string, attachment: NativeThreadAttachment,
    disposition?: ThreadAttachmentDisposition): Promise<ThreadAttachmentAssetUrl> {
    if (!environmentKey || this.currentEnvironment()?.key !== environmentKey) throw new Error('环境连接已更换。');
    return requestThreadAttachmentAssetUrl(attachment, this.bindThreadAttachmentEnvironment(), disposition);
  }

  bindThreadAttachmentEnvironment(): ThreadAttachmentEnvironment {
    const session = this.requireSession();
    return {
      rpc: async (request: Object): Promise<Object | undefined> => {
        if (this.session !== session) throw new Error('环境连接已更换。');
        const reply = await this.rpc(request, '环境拒绝了附件请求。请检查环境连接和权限。');
        return reply.exit?.value;
      },
      origin: (): string => {
        if (this.session !== session) throw new Error('环境连接已更换。');
        return this.managed?.currentOrigin() ?? session.origin;
      },
    };
  }

  async send(threadId: string, text: string, queue: boolean = false, model?: ThreadLaunchSelection,
    attachments: UploadedThreadAttachment[] = [], attempt: ThreadSendAttempt = createThreadSendAttempt(),
    context?: ThreadMessageContext, runtimeMode?: ThreadLaunchRuntimeMode): Promise<void> {
    if (text.trim().length === 0 && attachments.length === 0) return;
    if (runtimeMode !== undefined) {
      const session = this.requireSession();
      const update = runtimeModeSelectionRequest(`${attempt.commandId}:runtime-mode`, threadId, runtimeMode);
      await this.rpc(update, '无法更改会话运行模式。请检查模型、环境权限和管理规则。');
      if (this.session !== session) throw new Error('环境连接已更换。');
    }
    const payload = dispatchRequest(attempt.commandId, attempt.messageId, threadId, text,
      queue, model, attachments, context);
    await this.rpc(payload, '环境拒绝了这条消息。请检查会话状态和环境权限。');
  }

  async interruptThread(threadId: string, runId: string): Promise<void> {
    const payload = interruptRequest(util.generateRandomUUID(), threadId, runId);
    await this.rpc(payload, '无法停止任务。请检查运行状态和环境权限。');
  }

  async stopBackgroundWork(environmentKey: string, threadId: string, runId: string,
    watches: NativeThreadBackgroundPullRequestWatch[], isCurrent: () => boolean): Promise<void> {
    const session = this.requireSession();
    if (!threadId || this.currentEnvironment()?.key !== environmentKey) throw new Error('会话环境已更换。');
    const access = await this.readAuthenticatedSession();
    if (!(access.permissions ?? access.scopes)?.includes('orchestration:operate')) {
      throw new Error('当前连接缺少停止后台工作的权限。');
    }
    const assertCurrent = (): void => {
      if (this.session !== session || !isCurrent()) throw new Error('后台工作已更换。');
    };
    assertCurrent();
    const config = await this.rpc(threadLaunchConfigRequest(), '无法读取后台工作控制能力。',
      false, undefined, NETWORK_TIMEOUT_MS);
    assertCurrent();
    if (!config.exit?.value) throw new Error('环境未返回后台工作控制能力。');
    const request = backgroundWorkStopRequest(util.generateRandomUUID(), threadId, config.exit.value, runId);
    const failure = '无法停止后台工作，请检查运行状态和权限后重试。';
    if (request) {
      await this.rpc(request, failure);
      return;
    }
    if (watches.length === 0) throw new Error('未找到可以停止的后台工作。');
    for (const watch of watches) {
      assertCurrent();
      await this.rpc(backgroundPullRequestStopRequest(util.generateRandomUUID(), threadId, watch), failure);
    }
  }

  async resumeThreadQueue(threadId: string): Promise<void> {
    const payload = resumeQueueRequest(util.generateRandomUUID(), threadId);
    await this.rpc(payload, '无法恢复队列。请检查运行状态和环境权限。');
  }

  async startQueuedRun(threadId: string, runId: string, targetRunId: string): Promise<void> {
    const commandId = util.generateRandomUUID();
    const payload = targetRunId ? promoteQueuedRunRequest(commandId, threadId, runId, targetRunId) :
      startQueuedRunRequest(commandId, threadId, runId);
    await this.rpc(payload, '无法立即发送排队消息。请检查当前运行状态。');
  }

  async editQueuedRun(threadId: string, runId: string, text: string): Promise<void> {
    const payload = editQueuedRunRequest(util.generateRandomUUID(), threadId, runId, text);
    await this.rpc(payload, '无法编辑排队消息。请检查消息是否仍在排队。');
  }

  async removeQueuedRun(threadId: string, runId: string): Promise<void> {
    const payload = cancelQueuedRunRequest(util.generateRandomUUID(), threadId, runId);
    await this.rpc(payload, '无法移除排队消息。请检查消息是否仍在排队。');
  }

  async respondThreadApproval(threadId: string, requestId: string, decision: string, feedback?: string): Promise<void> {
    const payload = respondApprovalRequest(util.generateRandomUUID(), threadId, requestId, decision, feedback);
    await this.rpc(payload, '无法提交审批。请检查请求是否仍然有效。');
  }

  async respondThreadQuestion(threadId: string, requestId: string, answers?: NativeThreadUserInputAnswers): Promise<void> {
    const commandId = util.generateRandomUUID();
    const payload = answers ? respondUserInputRequest(commandId, threadId, requestId, answers) :
      dismissUserInputRequest(commandId, threadId, requestId);
    await this.rpc(payload, '无法处理提问。请检查请求是否仍然有效。');
  }

  private async rpc(payload: Object, failure: string, expectChunk: boolean = false,
    acceptChunk?: (frame: RpcFrame) => boolean, timeoutMs?: number): Promise<RpcFrame> {
    const session = this.requireSession();
    const address = await this.socketAddress(session);
    if (this.session !== session) throw new Error('环境连接已更换。');
    const socket = new T3Socket();
    let timer = -1;
    let acceptedChunk: RpcFrame | undefined;
    try {
      return await new Promise<RpcFrame>((resolve, reject) => {
        timer = setTimeout(() => reject(new Error(expectChunk || timeoutMs !== undefined ? failure :
          '环境未确认提交。请查看会话再试。')),
          timeoutMs ?? (expectChunk ? NETWORK_TIMEOUT_MS : SEND_TIMEOUT_MS));
        void socket.open(address, (frame: RpcFrame) => {
          if (this.session !== session) {
            reject(new Error('环境连接已更换。'));
          } else if (frame._tag === 'Defect' || frame._tag === 'ClientProtocolError') {
            reject(new Error(failure));
          } else if (String(frame.requestId) === REQUEST_ID) {
            if (frame._tag === 'Chunk' && expectChunk && frame.values && frame.values.length > 0) {
              void socket.send('{"_tag":"Ack","requestId":"' + REQUEST_ID + '"}').catch(reject);
              try {
                if (acceptChunk === undefined) resolve(frame);
                else if (acceptChunk(frame)) acceptedChunk = frame;
              } catch (error) {
                reject(error as Error);
              }
            } else if (frame._tag === 'Exit') {
              if (!expectChunk && frame.exit?._tag === 'Success') resolve(frame);
              else if (acceptedChunk && frame.exit?._tag === 'Success') resolve(acceptedChunk);
              else if (frame.exit?._tag === 'Failure') reject(new ThreadCommandRejectedError(failure));
              else reject(new Error(failure));
            }
          }
        }, reject).then(() => {
          if (this.session !== session) throw new Error('环境连接已更换。');
          return socket.send(JSON.stringify(payload));
        }).catch(reject);
      });
    } finally {
      clearTimeout(timer);
      socket.close();
    }
  }

  async readOlderThreadHistory(threadId: string, cursor: string, throughEntryId?: string): Promise<NativeThreadHistory> {
    const result = await this.environmentRequest(threadHistoryPath(threadId, cursor, throughEntryId));
    return readThreadHistory(result, threadId, cursor);
  }

  watchBackgroundWork(sourceKey: string, threadId: string, onUpdate: (thread?: NativeThread) => void,
    onError: (error: Error) => void): () => void {
    const session = this.requireSession();
    if (this.currentEnvironment()?.key !== sourceKey || !threadId) throw new Error('会话环境已更换。');
    const seed = this.backgroundShellSeed;
    let sequence = seed?.sequence ?? -1;
    let current = seed?.threads.find((row) => row.id === threadId) ??
      seed?.archivedThreads.find((row) => row.id === threadId);
    let synchronized = false;
    let startupTimer = -1;
    let stopped = false;
    const socket = new T3Socket();
    const stop = (): void => {
      if (stopped) return;
      stopped = true;
      clearTimeout(startupTimer);
      socket.close();
      this.watchers.delete(stop);
    };
    const fail = (error: Error): void => {
      if (stopped) return;
      stop();
      onError(error);
    };
    const publish = (): void => {
      synchronized = true;
      clearTimeout(startupTimer);
      onUpdate(current);
    };
    const receive = (frame: RpcFrame): void => {
      if (stopped) return;
      if (frame._tag === 'Defect' || frame._tag === 'ClientProtocolError' ||
        (frame._tag === 'Exit' && String(frame.requestId) === REQUEST_ID)) {
        fail(new Error('无法同步后台工作。'));
        return;
      }
      if (frame._tag !== 'Chunk' || String(frame.requestId) !== REQUEST_ID || !Array.isArray(frame.values)) return;
      try {
        for (const value of frame.values) {
          const item = value as BackgroundShellItem;
          if (item.kind === 'snapshot' && item.resolvedRepositoryIdentityRoots === undefined) {
            const snapshot = item.snapshot;
            if (!snapshot || !Number.isSafeInteger(snapshot.snapshotSequence) || !Array.isArray(snapshot.threads)) {
              throw new Error('环境返回的后台工作快照无效。');
            }
            if (snapshot.snapshotSequence < sequence) continue;
            const row = snapshot.threads.find((entry) => entry?.id === threadId) ??
              snapshot.archivedThreads?.find((entry) => entry?.id === threadId);
            current = row ? readBackgroundShellRows([row])[0] : undefined;
            sequence = snapshot.snapshotSequence;
            publish();
          } else if (item.kind === 'synchronized' && !synchronized && seed) {
            publish();
          } else if (item.sequence !== undefined && Number.isSafeInteger(item.sequence) && item.sequence > sequence) {
            sequence = item.sequence;
            if (item.kind === 'thread.updated' && item.thread?.id === threadId) {
              current = readBackgroundShellRows([item.thread])[0];
            } else if (item.kind === 'thread.removed' && item.threadId === threadId) {
              current = undefined;
            } else {
              continue;
            }
            if (synchronized) publish();
          }
        }
        void socket.send('{"_tag":"Ack","requestId":"' + REQUEST_ID + '"}').catch(fail);
      } catch (error) {
        fail(error as Error);
      }
    };
    this.watchers.add(stop);
    void this.socketAddress(session).then(async (address) => {
      if (stopped) return;
      await socket.open(address, receive, fail);
      if (stopped) return;
      startupTimer = setTimeout(() => fail(new Error('未收到后台工作状态。')), NETWORK_TIMEOUT_MS);
      const payload: BackgroundShellInput = { requestCompletionMarker: true };
      if (seed !== undefined) payload.afterSequence = seed.sequence;
      const request: BackgroundShellRequest = {
        _tag: 'Request', id: REQUEST_ID, tag: 'orchestration.subscribeShell', headers: [], payload,
      };
      await socket.send(JSON.stringify(request));
    }).catch((error: Error) => fail(error));
    return stop;
  }

  watchThread(threadId: string, onUpdate: ThreadUpdate,
    onError: (error: Error, reconnecting: boolean) => void): () => void {
    const session = this.requireSession();
    let cancelAttempt: () => void = () => {};
    let retryTimer = -1;
    let retries = 0;
    let stopped = false;
    const stop = (): void => {
      if (stopped) return;
      stopped = true;
      clearTimeout(retryTimer);
      cancelAttempt();
      this.watchers.delete(stop);
    };
    const start = (): void => {
      if (stopped || this.session !== session) return;
      cancelAttempt = this.watchThreadOnce(session, threadId, (messages, detail, historyCursor?: string) => {
        retries = 0;
        onUpdate(messages, detail, historyCursor);
      }, (error: Error) => {
        if (stopped) return;
        const delay = THREAD_RECONNECT_DELAYS_MS[retries++];
        if (delay === undefined) {
          stop();
          onError(error, false);
        } else {
          retryTimer = setTimeout(start, delay);
          onError(error, true);
        }
      });
    };
    this.watchers.add(stop);
    start();
    return stop;
  }

  private requireLinkedThreadSource(sourceEnvironmentId: string, environmentId: string, threadId: string): SavedEnvironment {
    const session = this.requireSession();
    if (session.environmentId !== sourceEnvironmentId || environmentId === sourceEnvironmentId ||
      !environmentId.trim() || !threadId.trim()) {
      throw new Error('关联会话的来源环境已更换。');
    }
    return session;
  }

  async pairLinkedThreadEnvironment(sourceEnvironmentId: string, environmentId: string, threadId: string,
    stillOpen: () => boolean): Promise<LinkedThreadConnection> {
    const session = this.requireLinkedThreadSource(sourceEnvironmentId, environmentId, threadId);
    const grant = await this.readAuthenticatedSession();
    if (this.session !== session || !stillOpen()) throw new Error('关联会话的来源环境已更换。');
    if (!(grant.permissions ?? grant.scopes)?.includes('access:write')) return { status: 'manual', address: '' };
    let result: Object | undefined;
    try {
      const response = await this.rpc(linkedClientPairingRequest(environmentId), '无法获取关联环境的连接信息。',
        false, undefined, NETWORK_TIMEOUT_MS);
      result = response.exit?.value;
    } catch (_) {
      return { status: 'manual', address: '' };
    }
    const pairing = readLinkedClientPairing(result, environmentId, Date.now());
    const addresses = new Set<string>();
    for (const url of pairing.urls) {
      try {
        addresses.add(environmentOrigin(url));
      } catch (_) {}
    }
    const ordered = Array.from(addresses);
    const probes = ordered.map(async (address: string): Promise<string> => {
      try {
        const descriptor = await requestJson<EnvironmentDescriptor>(address, '/.well-known/t3/environment',
          http.RequestMethod.GET);
        if (descriptor.environmentId === environmentId &&
          descriptor.orchestrationProtocolVersion === Number(ORCHESTRATION_PROTOCOL)) return address;
      } catch (_) {}
      return '';
    });
    let address = '';
    for (const probe of probes) {
      address = await probe;
      if (address) break;
    }
    if (this.session !== session || !stillOpen()) throw new Error('关联会话的来源环境已更换。');
    if (!pairing.credential) return { status: 'manual', address: address || ordered[0] || '' };
    if (!address) return { status: 'unreachable', address: '' };
    try {
      await this.pairAddress(address, pairing.credential, environmentId);
      return { status: 'paired', address };
    } catch (_) {
      return { status: 'manual', address };
    }
  }

  async readLinkedThreadHistory(sourceEnvironmentId: string, environmentId: string, threadId: string,
    cursor: string): Promise<NativeThreadHistory> {
    const session = this.requireLinkedThreadSource(sourceEnvironmentId, environmentId, threadId);
    const frame = await this.rpc(linkedThreadHistoryRequest(environmentId, threadId, cursor),
      '无法读取较早的关联会话内容。', false, undefined, NETWORK_TIMEOUT_MS);
    if (this.session !== session || !frame.exit?.value) throw new Error('未收到较早的关联会话内容。');
    return readThreadHistory(frame.exit.value, threadId, cursor);
  }

  async readLinkedThreadWork(sourceEnvironmentId: string, environmentId: string, threadId: string,
    itemId: string): Promise<string> {
    const session = this.requireLinkedThreadSource(sourceEnvironmentId, environmentId, threadId);
    const frame = await this.rpc(linkedThreadItemRequest(environmentId, threadId, itemId),
      '无法读取关联会话的命令输出。', false, undefined, NETWORK_TIMEOUT_MS);
    if (this.session !== session || !frame.exit?.value) throw new Error('未收到关联会话的命令输出。');
    return readThreadWorkDetail(frame.exit.value, threadId, itemId);
  }

  watchLinkedThread(sourceEnvironmentId: string, environmentId: string, threadId: string, onUpdate: ThreadUpdate,
    onError: (error: Error) => void): () => void {
    const session = this.requireLinkedThreadSource(sourceEnvironmentId, environmentId, threadId);
    const stop = (): void => {
      cancel();
      this.watchers.delete(stop);
    };
    const cancel = this.watchThreadOnce(session, threadId, onUpdate, (error) => {
      this.watchers.delete(stop);
      onError(error);
    }, environmentId);
    this.watchers.add(stop);
    return stop;
  }

  private watchThreadOnce(session: SavedEnvironment, threadId: string,
    onUpdate: ThreadUpdate,
    onError: (error: Error) => void, linkedEnvironmentId?: string): () => void {
    const socket = new T3Socket();
    let messages: NativeMessage[] = [];
    const projection = new ThreadDetailProjection(threadId);
    let forkSources = projection.replyForkSources();
    let detail = projection.view();
    let lastSequence = -1;
    let historyCursor: string | undefined = undefined;
    let snapshotTimer: number = -1;
    let snapshotLoaded = false;
    let stopped = false;
    const stop = (): void => {
      if (stopped) return;
      stopped = true;
      clearTimeout(snapshotTimer);
      socket.close();
    };
    const fail = (error: Error): void => {
      if (stopped) return;
      stop();
      onError(error);
    };
    const onFrame = (frame: RpcFrame): void => {
      if (stopped) return;
      if (frame._tag === 'Defect' || frame._tag === 'ClientProtocolError' ||
        (frame._tag === 'Exit' && String(frame.requestId) === REQUEST_ID)) {
        fail(linkedEnvironmentId !== undefined ? linkedThreadReadError(frame.exit) : new Error('环境未能保持会话同步。'));
        return;
      }
      if (frame._tag !== 'Chunk' || String(frame.requestId) !== REQUEST_ID || !Array.isArray(frame.values)) return;
      let detailChanged = false;
      let messageChanged = false;
      let updates: NativeMessage[] = [];
      try {
        for (const item of frame.values) {
          if (item.kind === 'snapshot' && item.projection) {
            if (item.projection.thread?.id !== threadId) throw new Error('环境返回了不同会话的消息。');
            messages = readMessages(item.projection);
            projection.reset(item.projection);
            updates = [];
            lastSequence = item.snapshotSequence ?? -1;
            historyCursor = item.hasMoreHistory && typeof item.historyCursor === 'string' ? item.historyCursor : undefined;
            snapshotLoaded = true;
            clearTimeout(snapshotTimer);
            detailChanged = true;
            messageChanged = true;
          } else if (snapshotLoaded && item.kind === 'event' && item.event &&
            item.event.threadId === threadId && item.sequence !== undefined && item.sequence > lastSequence) {
            lastSequence = item.sequence;
            if (item.event.type === 'message.updated') {
              const incoming = readMessage(item.event.payload);
              if (incoming && (linkedEnvironmentId === undefined || incoming.threadId === threadId)) updates.push(incoming);
            }
            if (projection.apply(item.event.type, item.event.payload)) {
              detailChanged = true;
            }
          }
        }
        const nextForkSources = projection.replyForkSources();
        if (updates.length > 0) {
          messages = mergeMessages(messages, updates.map((message: NativeMessage): NativeMessage =>
            attachThreadReplyForkSource(message, nextForkSources.get(message.id))));
          messageChanged = true;
        }
        if (nextForkSources !== forkSources) {
          messages = messages.map((message: NativeMessage): NativeMessage =>
            attachThreadReplyForkSource(message, nextForkSources.get(message.id)));
          forkSources = nextForkSources;
          messageChanged = true;
        }
        if (detailChanged) detail = projection.view();
        void socket.send('{"_tag":"Ack","requestId":"' + REQUEST_ID + '"}').catch(fail);
        if (snapshotLoaded && (messageChanged || detailChanged)) onUpdate(messages, detail, historyCursor);
      } catch (error) {
        fail(error as Error);
      }
    };
    void this.socketAddress(session).then(async (address) => {
      if (stopped) return;
      await socket.open(address, onFrame, fail);
      if (stopped) return;
      snapshotTimer = setTimeout(() => fail(new Error('环境未及时返回会话消息。')), NETWORK_TIMEOUT_MS);
      const request = linkedEnvironmentId === undefined ? subscribeRequest(threadId) :
        linkedThreadRequest(linkedEnvironmentId, threadId);
      await socket.send(JSON.stringify(request));
    }).catch((error: Error) => fail(error));
    return stop;
  }
}
