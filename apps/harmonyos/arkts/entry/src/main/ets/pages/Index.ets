import { common } from '@kit.AbilityKit';
import { FrameCallback, KeyboardAvoidMode, LengthMetrics } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import pasteboard from '@ohos.pasteboard';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { EnvironmentSummary } from '../client/EnvironmentStore';
import { COMPOSER_COMMAND_CONTEXT_MAX_RECORDS, composerCommandContextReference,
  referencedComposerCommandContext } from '../client/ComposerCommandProtocol';
import type { ComposerCommandContextRecord, ComposerCommandTrigger } from '../client/ComposerCommandProtocol';
import type { NativeComposerScope } from '../client/ComposerCatalogProtocol';
import {
  ACCOUNT_BROWSER_TIMEOUT_MS, AccountEmailAction, AccountEmailStep, AccountIdentity, AccountMode, AccountNameUpdate,
  AccountSessionExpiredError, NativeAccount,
  NativeAccountConfig,
} from '../client/NativeAccount';
import { NativeDpop } from '../client/NativeDpop';
import {
  NativeRelay, RelayApprovalPendingError, RelayApprovalUnavailableError, RelayProofSigner,
} from '../client/NativeRelay';
import { RelayEnvironment } from '../client/RelayProtocol';
import { parseThreadLink } from '../client/ThreadLinkProtocol';
import { canSearchThreadMessages, normalizeThreadSearchQuery } from '../client/ThreadSearchProtocol';
import type { NativeThreadSearchMatch } from '../client/ThreadSearchProtocol';
import {
  ConnectManagedEnvironment, NativeMessage, NativeThread, T3Client, ThreadLaunchAttempt, ThreadPermissions,
  ThreadCommandRejectedError, ThreadSendAttempt, ThreadTerminalHandle, createThreadLaunchAttempt,
  createThreadForkAttempt, createThreadSendAttempt, createThreadTerminalId, linkedEnvironmentOrigin,
} from '../client/T3Client';
import type { NativeThreadForkAttempt, NativeThreadForkSource } from '../client/ThreadForkProtocol';
import { threadLaunchRuntimeModes, ThreadLaunchModel, ThreadLaunchOptions, ThreadLaunchProject, ThreadLaunchProvider, ThreadLaunchRuntimeMode,
  ThreadLaunchScratch, ThreadLaunchSelection, ThreadLaunchWorkspaceStrategy } from '../client/ThreadLaunchProtocol';
import { changeThreadModelOption, threadModelOptionDescriptors, threadModelSelectionForTarget,
  threadModelSelectionsEqual, withThreadModelOptionDefaults } from '../client/ThreadModelOptionProtocol';
import type { ThreadModelOptionSelection } from '../client/ThreadModelOptionProtocol';
import type { ModelCatalogPreferenceKind, NativeModelCatalogPreferences } from '../client/ModelCatalogPreferences';
import { DeviceApprovalClient, DeviceApprovalRequest } from '../client/DeviceApprovalClient';
import { ConnectDeviceApprovals } from '../client/ConnectDeviceApprovals';
import type { ConnectDeviceApprovalPrompt, ConnectDeviceApprovalTarget } from '../client/ConnectDeviceApprovals';
import type { LinkedEnvironmentBatchResult, LinkedEnvironmentCandidate, NativeLinkedEnvironment, NativePeerLinkAccess }
  from '../client/LinkedEnvironmentProtocol';
import { checkEnvironmentRelease } from '../client/EnvironmentMaintenanceProtocol';
import type { EnvironmentMaintenanceProvider, EnvironmentMaintenanceSnapshot } from '../client/EnvironmentMaintenanceProtocol';
import { defaultClientPreferences, updateClientPreference } from '../client/ClientPreferencesProtocol';
import type { ClientPreferenceKey, ClientPreferencesSnapshot, ClientPreferenceValue } from '../client/ClientPreferencesProtocol';
import { ClientPreferencesStore } from '../client/ClientPreferencesStore';
import type { EnvironmentPreferencesSnapshot } from '../client/EnvironmentPreferencesProtocol';
import type { NativeProviderSummary } from '../client/ProvidersProtocol';
import type { NativeScheduledTask } from '../client/ScheduledTasksProtocol';
import { AccountView } from './AccountView';
import { AddEnvironmentView } from './AddEnvironmentView';
import { EnvironmentDetails } from './EnvironmentDetails';
import { EnvironmentRoutesView } from './EnvironmentRoutesView';
import { LinkedEnvironmentsView } from './LinkedEnvironmentsView';
import { DeviceApprovalPendingView, DeviceApprovalView } from './DeviceApprovalView';
import { ThreadLaunchView } from './ThreadLaunchView';
import { ProjectAddWizard } from './ProjectAddWizard';
import { ThreadDetailApproval, ThreadDetailApprovalOption, ThreadDetailComposer } from './ThreadDetailComposer';
import { readThreadComposerSuggestions } from './ThreadComposerCatalog';
import type { ThreadComposerSuggestion } from './ThreadComposerSuggestions';
import { NativeThreadDetail, NativeThreadWork, readHistoricalThreadWork, readThreadActivityIds }
  from '../client/ThreadDetailProtocol';
import type { NativeThreadUserInputAnswers } from '../client/ThreadDetailProtocol';
import type { NativeThreadCheckpointDiff, NativeThreadCheckpointSummary } from '../client/ThreadCheckpointProtocol';
import { createThreadFileReviewCommentRecord } from '../client/ThreadReviewCommentDraftProtocol';
import type { NativeThreadFileReviewCommentTarget } from '../client/ThreadReviewCommentDraftProtocol';
import type { AccountDeviceSession } from '../client/NativeAccount';
import { mergeMessages } from '../client/T3Protocol';
import type { NativeThreadAttachment } from '../client/T3Protocol';
import { isPdfThreadAttachment, isTextThreadAttachment, isVideoThreadAttachment, MAX_ATTACHMENT_ACTION_BYTES,
  NativeThreadAttachmentPreviewRequest, removeThreadAttachmentPreview,
  threadAttachmentPreviewKind } from '../client/NativeThreadAttachmentPreview';
import type { NativeThreadAttachmentPreview } from '../client/NativeThreadAttachmentPreview';
import { ThreadAttachmentFileActions } from '../client/ThreadAttachmentFileActions';
import type { ThreadAttachmentActionFile } from '../client/ThreadAttachmentFileActions';
import { availableThreadLifecycleActions, ThreadLifecycleAction, threadHasUnread, threadLifecycleState }
  from '../client/ThreadLifecycleProtocol';
import { ThreadListActions } from './ThreadListActions';
import { NativeThreadFile, NativeThreadFileDirectory, NativeThreadFileEntry } from '../client/ThreadFilesProtocol';
import { ThreadDetailFiles } from './ThreadDetailFiles';
import { ThreadDetailHeader } from './ThreadDetailHeader';
import { ThreadModelPicker } from './ThreadModelPicker';
import { ThreadGitStatus } from './ThreadGitStatus';
import { ThreadReview } from './ThreadReview';
import type { NativeThreadReview, NativeThreadReviewFile, NativeThreadReviewPatch } from '../client/ThreadReviewProtocol';
import { canPullThreadGit, canPushThreadGit } from '../client/ThreadGitProtocol';
import type { NativeThreadGitCommitResult, NativeThreadGitPullResult, NativeThreadGitPushResult,
  NativeThreadGitRefs, NativeThreadGitStatus, ThreadGitRefKind } from '../client/ThreadGitProtocol';
import { NativeThreadAttachments } from '../client/NativeThreadAttachments';
import type { PickedThreadAttachment, UploadedThreadAttachment } from '../client/ThreadAttachmentProtocol';
import { serializeThreadCitation } from '../client/ThreadCitationProtocol';
import type { NativeThreadCitation, ThreadCitationSelector } from '../client/ThreadCitationProtocol';
import { ThreadCitationSheet } from './ThreadCitationSheet';
import { DEFAULT_THREAD_TERMINAL_ID } from '../client/ThreadTerminalProtocol';
import type { NativeTerminalUpdate, NativeThreadTerminalSummary, ThreadTerminalTarget } from '../client/ThreadTerminalProtocol';
import { ThreadTerminal, ThreadTerminalOutput } from './ThreadTerminal';
import type { ThreadTerminalSession } from './ThreadTerminal';
import { threadTerminalContextRecord, threadTerminalContextReference } from './ThreadTerminalOutput';
import type { ThreadTerminalAttachment, ThreadTerminalContextRecord } from './ThreadTerminalOutput';
import { ThreadMessageRow, ThreadWorkGroupToggle, ThreadWorkRow } from './ThreadMessageRow';
import { ThreadAttachmentPreview } from './ThreadAttachmentPreview';
import { ThreadReviewCommentEditor } from './ThreadReviewCommentEditor';
import { ThreadSideChatsRow } from './ThreadSideChatsRow';
import type { ThreadSideChatItem } from './ThreadSideChatsRow';
import { LinkedThreadView } from './LinkedThreadView';
import { ThreadAgentsSheet } from './ThreadAgentsSheet';
import type { ThreadAgentSheetRow } from './ThreadAgentsSheet';
import type { NativeThreadSubagent } from '../client/ThreadAgentsProtocol';
import { ThreadBackgroundWorkSheet, ThreadBackgroundWorkStatus } from './ThreadBackgroundWork';
import { hasNativeThreadBackgroundWork } from '../client/ThreadBackgroundWorkProtocol';
import type { NativeThreadBackgroundTask } from '../client/ThreadBackgroundWorkProtocol';
import { LinkedThreadUnavailableError } from '../client/LinkedEnvironmentProtocol';
import { WorkspaceChatRow, WorkspaceComposeButton, WorkspaceDock, WorkspaceHeader, WorkspaceSharedTab, WorkspaceTab,
  WorkspaceThreadSectionTitle, WorkspaceThreadShelf, WorkspaceThreadSwipeAction, workspaceHeaderColor,
  workspaceForegroundColor, workspaceMutedColor, workspaceSurfaceColor } from './WorkspaceChrome';
import type { WorkspaceFilterGroup, WorkspaceFilterOption } from './WorkspaceChrome';
import { workspaceThreadListEntries, workspaceThreadRowStatus, workspaceThreadTimeLabel } from './WorkspaceThreadListModel';
import type { WorkspaceThreadListEntry, WorkspaceThreadSection } from './WorkspaceThreadListModel';
import { readUiLanguagePreference, resolveUiLanguage, uiText } from './UiLanguage';
import type { UiLanguage, UiLanguagePreference } from './UiLanguage';
import { WorkspaceSettings } from './WorkspaceSettings';
import type { WorkspaceSettingsPage } from './WorkspaceSettings';
import { WorkspaceSettingsDetail } from './WorkspaceSettingsDetail';
import { WorkspaceDataPages } from './WorkspaceDataPages';
import { WorkspacePullRequestDetail } from './WorkspacePullRequests';
import { WorkspaceIssueDetail } from './WorkspaceIssues';
import { WorkspaceUsageAccount } from './WorkspaceUsage';
import type { NativePullRequestQuery, NativePullRequestRef, NativePullRequestRow } from '../client/PullRequestProtocol';
import type { NativePullRequestMetadataKind } from '../client/PullRequestMetadataProtocol';
import type { NativePullRequestComposerTrigger } from '../client/PullRequestReferenceProtocol';
import type { NativePullRequestFilterMode } from '../client/PullRequestFilterOptionsProtocol';
import type { NativeIssueEntry, NativeIssueFilters, NativeIssueRef, NativeIssueScope } from '../client/IssueProtocol';
import type { NativeUsageAccount, NativeUsageLimitWindow } from '../client/WorkspaceUsageProtocol';
import { ProjectManagementView } from './ProjectManagementView';
import type { NativeManagedProject, NativeProjectFolderListing, ProjectManagementChange, ProjectManagementSnapshot }
  from '../client/ProjectManagementProtocol';

class ListData<T> implements IDataSource {
  protected rows: T[] = [];
  protected listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): T {
    return this.rows[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  replace(rows: T[]): void {
    this.rows = rows;
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }
}

interface FeedValue {
  id: string;
  timestamp: string;
  message?: NativeMessage;
  work?: NativeThreadWork;
  workGroup?: NativeThreadWork[];
  checkpoint?: NativeThreadCheckpointSummary;
}

interface WorkspaceProjectChoice {
  key: string;
  title: string;
  environmentKey: string;
}

interface ThreadListLoad {
  threads: NativeThread[];
  error: string;
}

interface ApprovalBinding {
  fingerprint: string;
  environmentId: string;
  target: ConnectDeviceApprovalTarget;
}

interface WorkspaceSearchResult {
  environmentKey: string;
  matches: NativeThreadSearchMatch[];
  error: string;
}

const MAX_THREAD_ATTACHMENTS = 100;
const MAX_MESSAGE_CHARS = 120000;

interface DraftThreadQuote {
  text: string;
  markup: string;
}

interface PendingThreadSend {
  modelSelection?: ThreadLaunchSelection;
  fingerprint: string;
  attempt: ThreadSendAttempt;
  attachments: UploadedThreadAttachment[];
  queue: boolean;
}

interface ThreadReturnPoint {
  thread: NativeThread;
  index: number;
  messageId?: string;
}

interface BackgroundWorkStop {
  taskIds: Set<string>;
  timer: number;
}

@Observed
class FeedEntry {
  id: string;
  message?: NativeMessage;
  work?: NativeThreadWork;
  workGroup?: NativeThreadWork[];
  checkpoint?: NativeThreadCheckpointSummary;

  constructor(value: FeedValue) {
    this.id = value.id;
    this.message = value.message;
    this.work = value.work;
    this.workGroup = value.workGroup;
    this.checkpoint = value.checkpoint;
  }
}

function orderThreadFeed(values: FeedValue[], activityIds: string[]): void {
  values.sort((left, right) => left.timestamp.localeCompare(right.timestamp));
  const byId = new Map<string, FeedValue>();
  for (const entry of values) byId.set(entry.id, entry);
  const ordered: FeedValue[] = [];
  const known = new Set<string>();
  for (const id of activityIds) {
    const entry = byId.get(id);
    if (entry && !known.has(id)) {
      ordered.push(entry);
      known.add(id);
    }
  }
  let next = 0;
  for (let index = 0; index < values.length; index++) {
    if (known.has(values[index].id)) values[index] = ordered[next++];
  }
}

function groupThreadCommands(values: FeedValue[]): FeedValue[] {
  const rows: FeedValue[] = [];
  for (const value of values) {
    const prior = rows[rows.length - 1];
    const command = value.work;
    const first = prior?.workGroup?.[0] ?? prior?.work;
    if (command?.type === 'command_execution' && first?.type === 'command_execution' && command.runId &&
      first.runId === command.runId && first.threadId === command.threadId) {
      if (prior.workGroup) prior.workGroup.push(command);
      else rows[rows.length - 1] = {
        id: 'work-group:' + first.id, timestamp: prior.timestamp, workGroup: [first, command],
      };
    } else {
      rows.push(value);
    }
  }
  return rows;
}

class ThreadFeedData extends ListData<FeedEntry> {
  indexOfId(id: string): number {
    return this.rows.findIndex((entry: FeedEntry) => entry.id === id);
  }

  replace(rows: FeedEntry[]): void {
    this.rows = rows;
    const reload: DataReloadOperation = { type: DataOperationType.RELOAD };
    this.listeners.forEach((listener: DataChangeListener) => listener.onDatasetChange([reload]));
  }

  update(messages: NativeMessage[], work: NativeThreadWork[], checkpoints: NativeThreadCheckpointSummary[],
    activityIds: string[]): boolean {
    const byAssistant = new Map<string, NativeThreadCheckpointSummary>();
    const lastReplyByRun = new Map<string, string>();
    if (checkpoints.some((checkpoint: NativeThreadCheckpointSummary) => !checkpoint.assistantMessageId)) {
      for (const message of messages) {
        if (message.role === 'assistant' && message.threadId && message.runId) {
          lastReplyByRun.set(JSON.stringify([message.threadId, message.runId]), message.id);
        }
      }
    }
    for (const checkpoint of checkpoints) {
      const id = checkpoint.assistantMessageId ?? lastReplyByRun.get(JSON.stringify([checkpoint.threadId, checkpoint.runId]));
      if (id && (checkpoint.status === 'ready' || checkpoint.repositories.length > 0) &&
        (checkpoint.files.length > 0 || checkpoint.repositories.length > 0)) byAssistant.set(id, checkpoint);
    }
    const values: FeedValue[] = messages.map((message: NativeMessage): FeedValue => ({
      id: 'message:' + message.id, timestamp: message.createdAt ?? '', message,
      checkpoint: message.role === 'assistant' && !message.streaming ? byAssistant.get(message.id) : undefined,
    }));
    for (const record of work) {
      values.push({ id: 'work:' + record.id, timestamp: record.timestamp, work: record });
    }
    if (work.length > 0 || activityIds.length > 0) orderThreadFeed(values, activityIds);
    const previousRows = this.rows;
    const byId = new Map<string, FeedEntry>();
    for (const entry of previousRows) byId.set(entry.id, entry);
    let changed = false;
    const rows = groupThreadCommands(values).map((value: FeedValue): FeedEntry => {
      const entry = byId.get(value.id);
      if (!entry) return new FeedEntry(value);
      if (entry.message !== value.message) {
        entry.message = value.message;
        changed = true;
      }
      if (entry.work !== value.work) {
        entry.work = value.work;
        changed = true;
      }
      const savedGroup = entry.workGroup;
      const group = value.workGroup;
      if (savedGroup?.length !== group?.length ||
        (group !== undefined && group.some((work: NativeThreadWork, index: number) => work !== savedGroup?.[index]))) {
        entry.workGroup = group;
        changed = true;
      }
      if (entry.checkpoint !== value.checkpoint) {
        entry.checkpoint = value.checkpoint;
        changed = true;
      }
      return entry;
    });
    const prefix = previousRows.length === 0 ? 0 : rows.indexOf(previousRows[0]);
    if (prefix < 0 || previousRows.some((row, index) => row !== rows[prefix + index])) {
      this.replace(rows);
      return true;
    }
    if (rows.length > previousRows.length) {
      this.rows = rows;
      const adds: DataAddOperation[] = [];
      if (prefix > 0) adds.push({ type: DataOperationType.ADD, index: 0, count: prefix });
      const firstNew = prefix + previousRows.length;
      if (rows.length > firstNew) {
        adds.push({ type: DataOperationType.ADD, index: firstNew, count: rows.length - firstNew });
      }
      this.listeners.forEach((listener: DataChangeListener) => listener.onDatasetChange(adds));
      return true;
    }
    return changed;
  }
}

@Component
struct CurrentFeedRow {
  @ObjectLink entry: FeedEntry;
  @Prop language: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  @Prop isLastAssistant: boolean = false;
  @Prop expanded: boolean = false;
  @Prop expandedCodes: number[] = [];
  @Prop workOutput: string | undefined = undefined;
  @Prop loadingWork: boolean = false;
  @Prop quoteEnabled: boolean = false;
  @Prop citationEnabled: boolean = false;
  @Prop checkpointEnabled: boolean = false;
  @Prop forkEnabled: boolean = false;
  @Prop forkBusy: boolean = false;
  onToggle: () => void = () => {};
  onToggleCode: (blockIndex: number) => void = () => {};
  onQuote: (messageId: string, selector: ThreadCitationSelector) => void = () => {};
  onOpenCitation: (citation: NativeThreadCitation) => void = () => {};
  onOpenAttachment: (message: NativeMessage, attachment: NativeThreadAttachment) => void = () => {};
  onOpenCheckpoint: (checkpoint: NativeThreadCheckpointSummary) => void = () => {};
  onFork: (source: NativeThreadForkSource, messageId: string) => void = () => {};

  build() {
    if (this.entry.message) {
      ThreadMessageRow({
        message: this.entry.message,
        language: this.language,
        dark: this.dark,
        isLastAssistant: this.isLastAssistant,
        expanded: this.expanded,
        expandedCodeBlocks: this.expandedCodes,
        attachmentNames: this.entry.message.attachmentNames ?? [],
        quoteEnabled: this.quoteEnabled,
        citationEnabled: this.citationEnabled,
        attachmentEnabled: this.citationEnabled,
        checkpoint: this.entry.checkpoint,
        checkpointEnabled: this.checkpointEnabled,
        forkEnabled: this.forkEnabled,
        forkBusy: this.forkBusy,
        onQuote: (messageId: string, selector: ThreadCitationSelector) => this.onQuote(messageId, selector),
        onOpenCitation: (citation: NativeThreadCitation) => this.onOpenCitation(citation),
        onOpenAttachment: (attachment: NativeThreadAttachment) => {
          const message = this.entry.message;
          if (message) this.onOpenAttachment(message, attachment);
        },
        onOpenCheckpoint: (checkpoint: NativeThreadCheckpointSummary) => this.onOpenCheckpoint(checkpoint),
        onFork: (source: NativeThreadForkSource) => {
          const messageId = this.entry.message?.id;
          if (messageId) this.onFork(source, messageId);
        },
        onToggle: () => this.onToggle(),
        onToggleCode: (blockIndex: number) => this.onToggleCode(blockIndex),
      })
    } else if (this.entry.work) {
      ThreadWorkRow({
        language: this.language,
        dark: this.dark,
        rowId: this.entry.work.id,
        title: this.entry.work.title,
        detail: this.workOutput ?? this.entry.work.detail,
        loading: this.loadingWork,
        expandable: this.entry.work.wantsOutput,
        status: this.entry.work.status,
        expanded: this.expanded,
        onToggle: () => this.onToggle(),
      })
    }
  }
}

class AfterLayout extends FrameCallback {
  private callback: () => void;

  constructor(callback: () => void) {
    super();
    this.callback = callback;
  }

  onIdle(_timeLeftInNano: number): void {
    this.callback();
  }
}

interface LinkedThreadTarget {
  environmentId: string;
  threadId: string;
  title: string;
  label: string;
  sourceEnvironmentId: string;
  sourceLabel: string;
}

interface LinkedDirectReturn {
  sourceEnvironmentId: string;
  sourceThreadId: string;
  sourceMessageId?: string;
  sourceIndex: number;
  environmentId: string;
  threadId: string;
}

function errorMessage(error: Error, fallback: string): string {
  return error.message?.trim() || fallback;
}

@Entry
@Component
struct Index {
  @StorageLink('t3.arkts.pairingLink') @Watch('showIncomingPairing') private incomingPairing: string = '';
  @StorageLink('t3.arkts.foreground') @Watch('handleForegroundChange') private appInForeground: boolean = false;
  @StorageLink('t3.arkts.keyboardVisible') private keyboardVisible: boolean = false;
  @StorageLink('t3.arkts.systemLanguage') private systemLanguage: string = 'zh-CN';
  @StorageLink('t3.arkts.darkAppearance') private darkAppearance: boolean = false;
  @StorageLink('t3.arkts.accountCallback') @Watch('handleAccountCallback') private accountCallback: string = '';
  @StorageLink('t3.arkts.threadLink') @Watch('handleIncomingThread') private incomingThreadLink: string = '';
  @State private restoring: boolean = true;
  @State private openingThreadLink: boolean = false;
  @State private workspaceTab: WorkspaceTab = 'threads';
  @State private workspaceSharedTab: WorkspaceSharedTab = 'pullRequests';
  @State private languagePreference: UiLanguagePreference = 'system';
  @State private workspacePullRequest: NativePullRequestRow | undefined = undefined;
  @State private workspaceIssue: NativeIssueEntry | undefined = undefined;
  @State private workspaceSourceControlCanWrite: boolean = false;
  @State private workspaceUsageAccount: NativeUsageAccount | undefined = undefined;
  @State private workspaceUsageWindow: NativeUsageLimitWindow | undefined = undefined;
  @State private workspaceDetailEnvironmentKey: string = '';
  @State private workspaceDataBackRequest: number = 0;
  private workspaceSourceControlPermissionRequest: number = 0;
  @State private pullRequestsQuery: string = '';
  @State private pullRequestsSearchOpen: boolean = false;
  @State private issuesQuery: string = '';
  @State private issuesSearchOpen: boolean = false;
  @State private searchOpen: boolean = false;
  @State private threadQuery: string = '';
  @State private threadSearchLoading: boolean = false;
  @State private threadSearchError: string = '';
  @State private threadSearchMatches: Map<string, NativeThreadSearchMatch> = new Map();
  @State private projectFilter: string = '';
  @State private workspaceEnvironmentFilter: string = '';
  @State private expandedThreadShelves: WorkspaceThreadSection[] = [];
  @State private composeButtonExpanded: boolean = true;
  @State private threadProjects: WorkspaceProjectChoice[] = [];
  @State private threadListCanWrite: boolean = false;
  @State private threadListActionTarget: NativeThread | undefined = undefined;
  @State private threadListStartWithSnooze: boolean = false;
  @State private threadListActionBusy: boolean = false;
  @State private threadListActionError: string = '';
  @State private showArchivedThreads: boolean = false;
  @State private showProjects: boolean = false;
  @State private projectMutationBusy: boolean = false;
  @State private projectBackRequest: number = 0;
  @State private projectManagementAddedId: string = '';
  @State private projectWizardOrigin: '' | 'launch' | 'projects' = '';
  @State private projectWizardBackRequest: number = 0;
  @State private projectWizardError: string = '';
  private projectWizardEnvironmentKey: string = '';
  private automaticApprovals: ConnectDeviceApprovals | undefined;
  private approvalBindings: Map<string, ApprovalBinding> = new Map();
  private automaticApprovalGeneration: number = 0;
  private automaticApprovalRetry: number = -1;
  private automaticApprovalPrompt: ConnectDeviceApprovalPrompt | undefined;
  private automaticApprovalDialog: number | undefined;
  private presentingAutomaticApproval: boolean = false;
  @State private answeringAutomaticApproval: boolean = false;
  @State private archiveLoading: boolean = false;
  @State private archiveError: string = '';
  @State private archivedThreads: NativeThread[] = [];
  @State private settingsQuery: string = '';
  @State private settingsSearchOpen: boolean = false;
  @State private settingsEnvironmentFilter: string = '';
  @State private settingsProjectFilter: string = '';
  @State private settingsPages: WorkspaceSettingsPage[] = [];
  @State private settingsScrollOffset: number = 0;
  @State private clientPreferences: ClientPreferencesSnapshot = defaultClientPreferences();
  @State private environmentPreferences: EnvironmentPreferencesSnapshot | undefined = undefined;
  @State private providersList: NativeProviderSummary[] = [];
  @State private scheduledTasksList: NativeScheduledTask[] = [];
  private clientPreferencesStore: ClientPreferencesStore | undefined = undefined;
  private readonly settingsScroller: Scroller = new Scroller();
  private readonly workspaceScroller: Scroller = new Scroller();
  private workspaceScrollOffset: number = 0;
  private languageSave: Promise<void> = Promise.resolve();
  private languageRevision: number = 0;
  @State private showThreadLaunch: boolean = false;
  @State private threadLaunchBackRequest: number = 0;
  @State private threadLaunchAddedProjectId: string = '';
  @State private threadLaunchOptions: ThreadLaunchOptions | undefined = undefined;
  @State private loadingThreadLaunch: boolean = false;
  @State private creatingThread: boolean = false;
  @State private threadLaunchError: string = '';
  @State private threadLaunchCanOpenScratch: boolean = false;
  @State private threadLaunchCanWriteGit: boolean = false;
  @State private threadLaunchCanReadFiles: boolean = false;
  @State private threadLaunchWorkspaceBusy: boolean = false;
  @State private threadLaunchAttachments: PickedThreadAttachment[] = [];
  @State private pickingLaunchAttachments: boolean = false;
  private threadLaunchEnvironmentKey: string = '';
  private threadLaunchScratchRoot: string = '';
  private readonly threadLaunchWorktreeRoots: Set<string> = new Set<string>();
  @State private showAccount: boolean = false;
  @State private accountConnectProfileOpen: boolean = false;
  @State private showConnectOnboarding: boolean = false;
  @State private savingConnectPreference: boolean = false;
  @State private connectOnboardingError: string = '';
  @State private accountConfigured: boolean = false;
  @State private accountIdentity: AccountIdentity | undefined = undefined;
  @State private accountBusy: boolean = false;
  @State private accountSigningOut: boolean = false;
  @State private accountPending: boolean = false;
  @State private accountError: string = '';
  @State private emailStep: AccountEmailStep | undefined = undefined;
  @State private relayConfigured: boolean = false;
  @State private relayRows: RelayEnvironment[] = [];
  @State private relayLoading: boolean = false;
  @State private relayHasListed: boolean = false;
  @State private relayError: string = '';
  @State private relayRestoreError: string = '';
  @State private relayConnectingId: string = '';
  @State private deregisteringEnvironmentId: string = '';
  @State private deregisterError: string = '';
  @State private approvalEnvironmentId: string = '';
  @State private approvalEnvironmentLabel: string = '';
  @State private approvalCode: string = '';
  @State private approvalPendingError: string = '';
  @State private showApprovals: boolean = false;
  @State private canApproveDevices: boolean = false;
  @State private approvalsBusy: boolean = false;
  @State private approvalError: string = '';
  @State private approvalNotice: string = '';
  @State private approvals: DeviceApprovalRequest[] = [];
  @State private connected: boolean = false;
  @State private pairing: boolean = false;
  @State private scanning: boolean = false;
  @State private showPairing: boolean = false;
  @State private addingEnvironment: boolean = false;
  @State private pairLink: string = '';
  @State private pairError: string = '';
  @State private environments: EnvironmentSummary[] = [];
  @State private environmentDetails: EnvironmentSummary | undefined = undefined;
  private environmentDetailsFromSettings: boolean = false;
  @State private showEnvironmentRoutes: boolean = false;
  @State private environmentRouteNotice: string = '';
  @State private linkedEnvironmentHealth: NativeLinkedEnvironment[] = [];
  @State private linkedEnvironmentCanManage: boolean = false;
  @State private linkedEnvironmentLoading: boolean = false;
  @State private linkedEnvironmentError: string = '';
  @State private linkedEnvironmentNotice: string = '';
  @State private linkedEnvironmentBatch: LinkedEnvironmentBatchResult[] = [];
  @State private linkedEnvironmentSourceKey: string = '';
  private linkedEnvironmentRequest: number = 0;
  @State private maintenanceSnapshot: EnvironmentMaintenanceSnapshot | undefined = undefined;
  @State private maintenanceLoading: boolean = false;
  @State private maintenanceBusy: boolean = false;
  @State private maintenanceError: string = '';
  @State private maintenanceNotice: string = '';
  @State private maintenanceRelease: string | null | undefined = undefined;
  private maintenanceRequest: number = 0;
  private maintenanceSourceKey: string = '';
  @State private environmentKey: string = '';
  @State private refreshing: boolean = false;
  @State private listError: string = '';
  @State private threadCount: number = 0;
  @State private selected: NativeThread | undefined = undefined;
  @State private loadingMessages: boolean = false;
  @State private messageCount: number = 0;
  @State private expandedMessages: string[] = [];
  @State private expandedCodeBlocks: Map<string, number[]> = new Map<string, number[]>();
  @State private workOutput: Map<string, string> = new Map<string, string>();
  @State private loadingWork: string[] = [];
  @State private threadDetail: NativeThreadDetail | undefined = undefined;
  @State private backgroundTasks: NativeThreadBackgroundTask[] = [];
  @State private showBackgroundWork: boolean = false;
  @State private backgroundWorkWaiting: boolean = false;
  @State private backgroundWorkReady: boolean = false;
  @State private backgroundWorkError: string = '';
  @State private backgroundChildOpening: string = '';
  @State private backgroundStopping: boolean = false;
  private backgroundLatestRunId: string = '';
  private backgroundWatchGeneration: number = 0;
  private backgroundUnsubscribe?: () => void;
  private readonly backgroundStopRequests = new Map<string, BackgroundWorkStop>();
  @State private showThreadAgents: boolean = false;
  @State private openingThreadAgent: string = '';
  @State private threadAgentsError: string = '';
  @State private linkedThreadTarget: LinkedThreadTarget | undefined = undefined;
  @State private linkedThreadFullscreen: boolean = false;
  @State private linkedThreadLoading: boolean = false;
  @State private linkedThreadError: string = '';
  @State private linkedThreadTitle: string = '';
  @State private linkedThreadMessages: NativeMessage[] = [];
  @State private linkedThreadWork: NativeThreadWork[] = [];
  @State private linkedThreadWorking: boolean = false;
  @State private linkedThreadConnecting: boolean = false;
  @State private linkedThreadConnectionError: string = '';
  @State private linkedPairingManual: boolean = false;
  @State private linkedPairingAddress: string = '';
  @State private linkedPairingLink: string = '';
  private linkedPairingReturnFullscreen: boolean = false;
  private linkedDirectReturn: LinkedDirectReturn | undefined = undefined;
  @State private linkedThreadHistoryCursor: string | undefined = undefined;
  @State private linkedThreadHistoryLoading: boolean = false;
  @State private linkedThreadHistoryError: string = '';
  private linkedThreadSnapshotCursor: string | undefined = undefined;
  private linkedThreadRecentMessages: NativeMessage[] = [];
  private linkedThreadOlderMessages: NativeMessage[] = [];
  private linkedThreadRecentWork: NativeThreadWork[] = [];
  private linkedThreadOlderWork: Map<string, NativeThreadWork> = new Map();
  private linkedThreadUnsubscribe: (() => void) | undefined = undefined;
  private linkedThreadGeneration: number = 0;
  private pendingLinkedThreadTarget: LinkedThreadTarget | undefined = undefined;
  @State private threadAccess: string = 'checking';
  @State private threadCanReadFiles: boolean = false;
  @State private threadCanWriteGit: boolean = false;
  @State private threadCanReadTerminal: boolean = false;
  @State private threadCanOperateTerminal: boolean = false;
  @State private showThreadModel: boolean = false;
  @State private citationPreview?: NativeThreadCitation = undefined;
  @State private previewAttachment?: NativeThreadAttachment = undefined;
  @State private previewContent?: NativeThreadAttachmentPreview = undefined;
  @State private previewAttachmentLoading: boolean = false;
  @State private previewAttachmentError: string = '';
  @State private previewActionBusy: boolean = false;
  @State private threadModelProviders: ThreadLaunchProvider[] = [];
  @State private threadModelDraft: ThreadLaunchSelection | undefined = undefined;
  @State private threadModelPending: ThreadLaunchSelection | undefined = undefined;
  @State private threadModelPendingPrompt: string | undefined = undefined;
  @State private threadModelParameterId: string = '';
  @State private threadModelCatalog?: NativeModelCatalogPreferences = undefined;
  @State private threadModelCatalogCanWrite: boolean = false;
  @State private showThreadRuntime: boolean = false;
  @State private threadRuntimeDraft: ThreadLaunchRuntimeMode | undefined = undefined;
  @State private threadRuntimeCeiling: ThreadLaunchRuntimeMode | undefined = undefined;
  @State private threadModelLoading: boolean = false;
  @State private threadModelApplying: boolean = false;
  @State private threadModelError: string = '';
  @State private showThreadFiles: boolean = false;
  @State private showThreadGit: boolean = false;
  @State private showThreadReview: boolean = false;
  @State private threadReviewCheckpoint?: NativeThreadCheckpointSummary = undefined;
  @State private threadReviewCommentTarget?: NativeThreadFileReviewCommentTarget = undefined;
  @State private threadReviewComment: string = '';
  @State private threadReviewCommentError: string = '';
  @State private replyForkBusyMessage: string = '';
  @State private sideChats: ThreadSideChatItem[] = [];
  @State private showThreadTerminal: boolean = false;
  @State private terminalSessions: ThreadTerminalSession[] = [];
  @State private terminalId: string = '';
  @State private terminalCwd: string = '';
  @State private terminalStatus: string = '';
  @State private terminalLoading: boolean = false;
  @State private terminalError: string = '';
  @State private terminalCols: number = 0;
  @State private terminalRows: number = 0;
  @State private threadGitPane: string = 'status';
  @State private threadGitLoading: boolean = false;
  @State private threadGitMutation: boolean = false;
  @State private threadGitError: string = '';
  @State private threadGitStatus: NativeThreadGitStatus | undefined = undefined;
  @State private filesDirectory: string = '';
  @State private filesEntries: NativeThreadFileEntry[] = [];
  @State private filesPreview: NativeThreadFile | undefined = undefined;
  @State private filesBusy: boolean = false;
  @State private filesTruncated: boolean = false;
  @State private filesError: string = '';
  @State private filesSearchOpen: boolean = false;
  @State private threadActionBusy: boolean = false;
  @State private watchError: string = '';
  @State private threadReconnecting: boolean = false;
  @State private historyCursor: string | undefined = undefined;
  @State private historyBusy: boolean = false;
  @State private historyError: string = '';
  @State private draft: string = '';
  @State private draftAttachments: PickedThreadAttachment[] = [];
  @State private draftQuotes: DraftThreadQuote[] = [];
  @State private draftTerminalContexts: ThreadTerminalContextRecord[] = [];
  @State private pickingAttachments: boolean = false;
  @State private sending: boolean = false;
  @State private sendError: string = '';

  private client: T3Client | undefined = undefined;
  private context: common.UIAbilityContext | undefined;
  private account: NativeAccount | undefined;
  private relay: NativeRelay | undefined;
  private callbackTimer: number = -1;
  private emailRequest: number = 0;
  private emailInFlight: boolean = false;
  private relayRequest: number = 0;
  private savingAccountProfile: boolean = false;
  private deregisteredRelayLinks: Map<string, string> = new Map();
  private threadLaunchGeneration: number = 0;
  private threadLaunchFingerprint: string = '';
  private threadLaunchUploaded: UploadedThreadAttachment[] | undefined;
  private threadLaunchAttempt: ThreadLaunchAttempt | undefined;
  private threads: ListData<WorkspaceThreadListEntry> = new ListData<WorkspaceThreadListEntry>();
  private allThreads: NativeThread[] = [];
  private messages: ThreadFeedData = new ThreadFeedData();
  private messageScroller: Scroller = new Scroller();
  private drafts: Map<string, Map<string, string>> = new Map<string, Map<string, string>>();
  private commandContextDrafts: Map<string, Map<string, ComposerCommandContextRecord[]>> = new Map();
  private unsubscribe: (() => void) | undefined = undefined;
  private watchGeneration: number = 0;
  private threadViewGeneration: number = 0;
  private filesGeneration: number = 0;
  private fileTarget: string = '';
  private firstVisibleThreadIndex: number = -1;
  private resumeThreadIndex: number = -1;
  private threadPermissionsRequest: number = 0;
  private threadListRequest: number = 0;
  private threadSearchRequest: number = 0;
  private threadSearchTimer: number = -1;
  private pendingMessageJump: string = '';
  private pendingApprovalThreadLink: string = '';
  private pendingApprovalMessageId?: string = undefined;
  private incomingCitationLink: string = '';
  private incomingCitationMessageId?: string = undefined;
  private archiveRequest: number = 0;
  private previewRequest?: NativeThreadAttachmentPreviewRequest = undefined;
  private previewActionRequest?: NativeThreadAttachmentPreviewRequest = undefined;
  private previewActionUri?: string = undefined;
  private attachmentActions: ThreadAttachmentFileActions = new ThreadAttachmentFileActions();
  private previewGallery: NativeThreadAttachment[] = [];
  private threadModelRequest: number = 0;
  private threadGitRequest: number = 0;
  private terminalRequest: number = 0;
  private terminalRequestedCols: number = 0;
  private terminalRequestedRows: number = 0;
  private terminalOutput = new ThreadTerminalOutput();
  private terminalConnection: ThreadTerminalHandle | undefined = undefined;
  private terminalSelection: Map<string, string> = new Map();
  private historyRequest: number = 0;
  private historySnapshotCursor: string | undefined = undefined;
  private recentMessages: NativeMessage[] = [];
  private recentWork: NativeThreadWork[] = [];
  private recentCheckpoints: NativeThreadCheckpointSummary[] = [];
  private historyMessages: NativeMessage[] = [];
  private historyWork: Map<string, NativeThreadWork> = new Map();
  private historyActivityIds: string[] = [];
  private recentActivityIds: string[] = [];
  @State private lastAssistantFeedId: string = '';
  private modelDrafts: Map<string, Map<string, ThreadLaunchSelection>> = new Map();
  private modelOptionMemory: Map<string, ThreadModelOptionSelection[]> = new Map();
  private runtimeDrafts: Map<string, Map<string, ThreadLaunchRuntimeMode>> = new Map();
  private attachmentDrafts: Map<string, Map<string, PickedThreadAttachment[]>> = new Map();
  private quoteDrafts: Map<string, Map<string, DraftThreadQuote[]>> = new Map();
  private terminalContextDrafts: Map<string, Map<string, ThreadTerminalContextRecord[]>> = new Map();
  private pendingThreadSends: Map<string, Map<string, PendingThreadSend>> = new Map();
  private readonly replyForkAttempts = new Map<string, NativeThreadForkAttempt>();
  private readonly threadReturnPoints = new Map<string, ThreadReturnPoint>();

  aboutToAppear(): void {
    const uiContext = this.getUIContext();
    uiContext.setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    const host = uiContext.getHostContext();
    if (!host) {
      this.restoring = false;
      this.pairError = '无法启动连接';
      return;
    }
    this.context = host as common.UIAbilityContext;
    this.clientPreferencesStore = new ClientPreferencesStore(this.context);
    void this.restoreLanguagePreference();
    void this.restoreClientPreferences();
    this.client = new T3Client(this.context);
    this.automaticApprovals = new ConnectDeviceApprovals((prompt: ConnectDeviceApprovalPrompt | undefined) => {
      this.automaticApprovalPrompt = prompt;
      this.closeAutomaticApprovalDialog();
      void this.presentAutomaticApproval();
    });
    this.configureAccount(this.context);
    this.showIncomingPairing();
    void this.restore().then(() => this.restoreAccount()).then(() => this.handleIncomingThread());
  }

  private uiLanguage(): UiLanguage {
    return resolveUiLanguage(this.languagePreference, this.systemLanguage);
  }

  private copy(chinese: string, english: string): string {
    return uiText(this.uiLanguage(), chinese, english);
  }

  private async restoreLanguagePreference(): Promise<void> {
    const context = this.context;
    if (!context) return;
    const revision = this.languageRevision;
    try {
      const store = await preferences.getPreferences(context, { name: 'arkts-workspace-ui' });
      const saved = await store.get('language', 'system');
      if (revision === this.languageRevision && typeof saved === 'string') {
        this.languagePreference = readUiLanguagePreference(saved);
      }
    } catch (_) {}
  }

  private selectLanguagePreference(value: UiLanguagePreference): void {
    const context = this.context;
    if (!context || value === this.languagePreference) return;
    const revision = ++this.languageRevision;
    this.languagePreference = value;
    this.languageSave = this.languageSave.then(async () => {
      if (revision !== this.languageRevision) return;
      const store = await preferences.getPreferences(context, { name: 'arkts-workspace-ui' });
      await store.put('language', value);
      await store.flush();
    }).catch(() => {
      if (revision === this.languageRevision) {
        this.getUIContext().getPromptAction().showToast({
          message: this.copy('无法保存语言设置', 'Could not save the language preference'),
        });
      }
    });
  }

  aboutToDisappear(): void {
    this.closeAttachmentPreview();
    this.closeLinkedThreadView();
    this.stopAutomaticApprovals();
    this.leaveThreadTerminal();
    this.stopWatching();
    this.stopBackgroundWatch();
    for (const request of this.backgroundStopRequests.values()) clearTimeout(request.timer);
    this.backgroundStopRequests.clear();
    clearTimeout(this.callbackTimer);
    clearTimeout(this.threadSearchTimer);
    this.threadSearchRequest++;
  }

  onBackPress(): boolean {
    if (this.previewAttachment) {
      this.closeAttachmentPreview();
      return true;
    }
    if (this.citationPreview) {
      this.citationPreview = undefined;
      return true;
    }
    if (this.linkedThreadTarget) {
      if (this.linkedThreadConnecting) return true;
      if (this.linkedPairingManual) this.backFromLinkedPairing();
      else if (this.linkedThreadFullscreen) this.linkedThreadFullscreen = false;
      else this.closeLinkedThreadView();
      return true;
    }
    if (this.showThreadAgents) {
      this.closeThreadAgents();
      return true;
    }
    if (this.showBackgroundWork) {
      this.closeBackgroundWork();
      return true;
    }
    if (this.projectWizardOrigin) {
      if (!this.projectMutationBusy) this.projectWizardBackRequest++;
      return true;
    }
    if (this.showProjects) {
      if (!this.projectMutationBusy) this.projectBackRequest++;
      return true;
    }
    if (this.threadListActionTarget) {
      if (!this.threadListActionBusy) this.threadListActionTarget = undefined;
      return true;
    }
    if (this.showArchivedThreads && !this.selected) {
      this.showArchivedThreads = false;
      this.archiveRequest++;
      return true;
    }
    if (this.environmentDetails && this.showPairing && !this.showAccount && !this.approvalEnvironmentId) {
      if (!this.pairing && !this.scanning) {
        this.pairError = '';
        if (this.addingEnvironment) {
          this.addingEnvironment = false;
          this.pairLink = '';
        } else if (this.showEnvironmentRoutes) {
          this.showEnvironmentRoutes = false;
        } else {
          this.backFromEnvironmentDetails();
        }
      }
      return true;
    }
    if (this.showThreadTerminal) {
      this.leaveThreadTerminal();
      return true;
    }
    if (this.showThreadReview) {
      if (this.threadReviewCommentTarget) {
        this.closeThreadReviewComment();
        return true;
      }
      this.closeThreadReview();
      return true;
    }
    if (this.showThreadGit) {
      if (!this.threadGitMutation) {
        if (this.threadGitPane !== 'status') this.threadGitPane = 'status';
        else this.closeThreadGit();
      }
      return true;
    }
    if (this.showThreadModel) {
      if (!this.threadModelApplying) {
        if (this.threadModelParameterId) this.threadModelParameterId = '';
        else if (this.showThreadRuntime) this.showThreadRuntime = false;
        else this.closeThreadModel();
      }
      return true;
    }
    if (this.showThreadFiles) {
      this.backFromThreadFiles();
      return true;
    }
    if (this.showThreadLaunch) {
      if (!this.creatingThread && !this.threadLaunchWorkspaceBusy) this.threadLaunchBackRequest++;
      return true;
    }
    if (this.approvalEnvironmentId) {
      if (!this.pairing) this.clearPendingApproval();
      return true;
    }
    if (this.showApprovals) {
      if (!this.approvalsBusy) this.showApprovals = false;
      return true;
    }
    if (this.showConnectOnboarding) {
      if (!this.pairing && !this.savingConnectPreference) this.showConnectOnboarding = false;
      return true;
    }
    if (this.showAccount) {
      if (this.accountConnectProfileOpen && this.accountIdentity) {
        this.accountConnectProfileOpen = false;
        return true;
      }
      this.accountConnectProfileOpen = false;
      if (this.emailStep || this.emailInFlight) this.cancelAccount();
      this.showAccount = false;
      if (!this.connected || this.showPairing) void this.loadRelayEnvironments();
      return true;
    }
    if (this.selected) {
      const linkedParent = this.linkedDirectReturn;
      if (linkedParent && linkedParent.threadId === this.selected.id &&
        linkedParent.environmentId === this.client?.currentEnvironment()?.environmentId) {
        if (!this.pairing) void this.returnToLinkedSource(linkedParent);
        return true;
      }
      const key = JSON.stringify([this.environmentKey, this.selected.id]);
      const parent = this.threadReturnPoints.get(key);
      if (parent) {
        this.threadReturnPoints.delete(key);
        this.openWorkspaceThread(parent.thread);
        this.resumeThreadIndex = parent.index;
        this.pendingMessageJump = parent.messageId ?? '';
        return true;
      }
      this.closeThread();
      return true;
    }
    if (this.showPairing && !this.pairing) {
      if (this.addingEnvironment) {
        this.addingEnvironment = false;
        this.pairLink = '';
        this.pairError = '';
      } else {
        this.showPairing = false;
        this.closeEnvironmentDetails();
      }
      return true;
    }
    if (this.pairing) return true;
    if (this.workspaceDataDetailsOpen()) {
      if (this.workspaceUsageAccount) this.closeWorkspaceDataDetails();
      else this.workspaceDataBackRequest++;
      return true;
    }
    if (this.workspaceTab === 'settings') {
      if (this.settingsPages.length > 0) this.settingsPages = this.settingsPages.slice(0, -1);
      else if (this.settingsSearchOpen || this.settingsQuery) this.closeSettingsSearch();
      else this.selectWorkspaceTab('threads');
      return true;
    }
    if (this.workspaceTab !== 'threads') {
      if (this.workspaceDataSearchOpen() || this.workspaceDataQuery()) this.closeWorkspaceDataSearch();
      else this.selectWorkspaceTab('threads');
      return true;
    }
    if (this.searchOpen || this.threadQuery) {
      this.closeThreadSearch();
      return true;
    }
    return false;
  }

  private configureAccount(context: common.UIAbilityContext): void {
    const resources = context.resourceManager;
    try {
      const config: NativeAccountConfig = {
        publishableKey: resources.getStringByNameSync('clerk_publishable_key'),
        jwtTemplate: resources.getStringByNameSync('clerk_jwt_template'),
      };
      const relayUrl = resources.getStringByNameSync('relay_url');
      if (config.publishableKey && config.jwtTemplate) {
        this.account = new NativeAccount(context, config);
        this.accountConfigured = true;
      }
      if (relayUrl && this.account) {
        const dpop = new NativeDpop(context);
        const signer: RelayProofSigner = {
          proof: (method: string, target: string, accessToken?: string) => dpop.proof(method, target, accessToken),
          thumbprint: () => dpop.thumbprint(),
        };
        this.relay = new NativeRelay(relayUrl, signer);
        this.relayConfigured = true;
      }
    } catch (_) {
      this.accountError = '无法加载 T3 账户配置。';
    }
  }

  private async restoreAccount(): Promise<void> {
    if (!this.account || this.accountBusy || this.accountPending) return;
    this.accountBusy = true;
    this.accountError = '';
    try {
      const previous = this.accountIdentity;
      this.accountIdentity = await this.account.restore();
      if (previous && !this.accountIdentity) await this.clearAccountEnvironmentState(previous.userId);
      await this.loadEnvironments();
      if (this.showPairing || this.showAccount) void this.loadRelayEnvironments();
      if (this.accountIdentity && this.relay && !this.pairing && !this.sending) {
        try {
          await this.client?.restore(this.accountIdentity.userId, this.managedConnector(this.accountIdentity));
          this.relayRestoreError = '';
          await this.applyCurrentEnvironment(false);
        } catch (error) {
          if (!this.handleExpiredAccount(error as Error) && !this.showApprovalError(error as Error)) {
            this.relayRestoreError = errorMessage(error as Error, '无法恢复 T3 Connect 环境');
          }
        }
      }
    } catch (error) {
      this.accountError = errorMessage(error as Error, '无法检查 T3 账户');
    } finally {
      this.accountBusy = false;
      this.handleAccountCallback();
    }
  }

  private async startAccount(mode: AccountMode): Promise<void> {
    if (!this.account || !this.context || this.accountBusy || this.accountPending) return;
    if (this.emailStep) this.cancelAccount();
    this.accountBusy = true;
    this.accountError = '';
    try {
      const portal = await this.account.start(mode);
      this.accountPending = true;
      this.callbackTimer = setTimeout(() => {
        this.cancelAccount();
        this.accountError = '登录已超时，请重试。';
      }, ACCOUNT_BROWSER_TIMEOUT_MS);
      await this.context.startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: portal,
      });
    } catch (error) {
      this.cancelAccount();
      this.accountError = errorMessage(error as Error, '无法打开账户登录');
    } finally {
      this.accountBusy = false;
      this.handleAccountCallback();
    }
  }

  private cancelAccount(): void {
    clearTimeout(this.callbackTimer);
    if (this.emailInFlight) {
      this.emailRequest++;
      this.emailInFlight = false;
      this.accountBusy = false;
    }
    this.emailStep = undefined;
    this.accountPending = false;
    this.accountCallback = '';
    this.accountError = '';
    try {
      this.account?.cancel();
    } catch (error) {
      this.accountError = errorMessage(error as Error, '无法清除登录请求');
    }
    this.handleIncomingThread();
  }

  private handleAccountCallback(): void {
    if (!this.account || this.restoring || !this.accountCallback) return;
    if (this.emailStep || this.emailInFlight) {
      this.accountCallback = '';
      return;
    }
    if (this.accountBusy) return;
    const callback = this.accountCallback;
    this.accountCallback = '';
    this.showAccount = true;
    void this.completeAccount(callback);
  }

  private async completeAccount(callback: string): Promise<void> {
    const account = this.account;
    if (!account) return;
    this.accountBusy = true;
    this.accountError = '';
    try {
      const identity = await account.complete(callback);
      clearTimeout(this.callbackTimer);
      this.accountPending = false;
      await this.acceptAccountIdentity(identity);
    } catch (error) {
      this.accountError = errorMessage(error as Error, '无法完成登录');
    } finally {
      this.accountBusy = false;
      this.handleAccountCallback();
      this.handleIncomingThread();
    }
  }

  private async acceptAccountIdentity(identity: AccountIdentity): Promise<void> {
    const previous = this.accountIdentity;
    this.accountIdentity = identity;
    if (previous && previous.userId !== identity.userId) {
      await this.clearAccountEnvironmentState(previous.userId);
    }
    await this.loadEnvironments();
    if (this.showPairing || this.showAccount) void this.loadRelayEnvironments();
    if (previous?.userId !== identity.userId) void this.offerConnectOnboarding(identity);
  }

  private async offerConnectOnboarding(identity: AccountIdentity): Promise<void> {
    if (!this.relay || !this.context) return;
    let optedOut = false;
    try {
      const store = await preferences.getPreferences(this.context, { name: 'arkts-connect-ui' });
      optedOut = await store.get('skip-connect-' + identity.userId, false) === true;
    } catch (_) {}
    if (optedOut || this.accountIdentity?.sessionId !== identity.sessionId || !this.showAccount ||
      this.incomingThreadLink || this.openingThreadLink) return;
    this.connectOnboardingError = '';
    this.showConnectOnboarding = true;
    void this.loadRelayEnvironments();
  }

  private async skipConnectOnboarding(): Promise<void> {
    const identity = this.accountIdentity;
    if (!this.context || !identity || this.savingConnectPreference || this.pairing) return;
    this.savingConnectPreference = true;
    this.connectOnboardingError = '';
    try {
      const store = await preferences.getPreferences(this.context, { name: 'arkts-connect-ui' });
      await store.put('skip-connect-' + identity.userId, true);
      await store.flush();
      if (this.accountIdentity?.sessionId === identity.sessionId) this.showConnectOnboarding = false;
    } catch (error) {
      this.connectOnboardingError = errorMessage(error as Error, '无法保存引导设置');
    } finally {
      this.savingConnectPreference = false;
    }
  }

  private async continueWithEmail(action: AccountEmailAction): Promise<void> {
    const account = this.account;
    if (!account || this.accountBusy || this.accountPending) return;
    const request = ++this.emailRequest;
    this.emailInFlight = true;
    this.accountBusy = true;
    this.accountError = '';
    try {
      const step = await account.email(action);
      if (request !== this.emailRequest) return;
      if (step.kind === 'complete' && step.identity) {
        this.emailStep = undefined;
        await this.acceptAccountIdentity(step.identity);
      } else {
        this.emailStep = step;
      }
    } catch (error) {
      if (request === this.emailRequest) this.accountError = errorMessage(error as Error, '无法完成邮箱登录');
    } finally {
      if (request === this.emailRequest) {
        this.emailInFlight = false;
        this.accountBusy = false;
        this.handleIncomingThread();
      }
    }
  }

  private async signOut(): Promise<void> {
    const account = this.account;
    const identity = this.accountIdentity;
    if (!account || !identity || this.accountBusy || this.pairing || this.sending || this.savingAccountProfile) return;
    this.accountBusy = true;
    this.accountSigningOut = true;
    this.stopAutomaticApprovals();
    this.accountError = '';
    this.relayRequest++;
    this.relayRows = [];
    this.relayHasListed = false;
    this.relayLoading = false;
    this.relayError = '';
    this.relay?.clear();
    try {
      await account.signOut();
    } catch (error) {
      this.accountError = errorMessage(error as Error, '无法结束服务器会话');
    } finally {
      this.accountIdentity = undefined;
      try {
        await this.clearAccountEnvironmentState(identity.userId);
      } finally {
        this.accountBusy = false;
        this.accountSigningOut = false;
        this.refreshAutomaticApprovals();
      }
    }
  }

  private async updateAccountName(identity: AccountIdentity, update: AccountNameUpdate): Promise<void> {
    const account = this.account;
    if (!account || this.savingAccountProfile || this.accountBusy || this.accountSigningOut || this.pairing ||
      this.accountIdentity?.userId !== identity.userId || this.accountIdentity?.sessionId !== identity.sessionId) {
      throw new Error('当前账号不可更新，请重新打开账号资料。');
    }
    this.savingAccountProfile = true;
    try {
      const updated = await account.updateProfileName(identity, update);
      if (this.accountIdentity?.userId === identity.userId && this.accountIdentity?.sessionId === identity.sessionId) {
        this.accountIdentity = updated;
      }
    } catch (error) {
      if (this.accountIdentity?.sessionId === identity.sessionId) this.handleExpiredAccount(error as Error);
      throw error as Error;
    } finally {
      this.savingAccountProfile = false;
      this.showIncomingPairing();
    }
  }

  private async listAccountSessions(identity: AccountIdentity): Promise<AccountDeviceSession[]> {
    const account = this.account;
    if (!account || this.accountSigningOut || this.accountIdentity?.sessionId !== identity.sessionId) {
      throw new Error('请重新打开当前账号。');
    }
    try {
      return await account.listSessions(identity);
    } catch (error) {
      if (this.accountIdentity?.sessionId === identity.sessionId) this.handleExpiredAccount(error as Error);
      throw error as Error;
    }
  }

  private async revokeAccountSession(identity: AccountIdentity, sessionId: string): Promise<void> {
    const account = this.account;
    if (!account || this.accountSigningOut || this.accountIdentity?.sessionId !== identity.sessionId) {
      throw new Error('请重新打开当前账号。');
    }
    try {
      await account.revokeSession(identity, sessionId);
    } catch (error) {
      if (this.accountIdentity?.sessionId === identity.sessionId) this.handleExpiredAccount(error as Error);
      throw error as Error;
    }
  }

  private async clearAccountEnvironmentState(accountId: string): Promise<void> {
    this.stopAutomaticApprovals();
    this.showConnectOnboarding = false;
    this.pullRequestsQuery = '';
    this.issuesQuery = '';
    this.pullRequestsSearchOpen = false;
    this.issuesSearchOpen = false;
    this.closeWorkspaceDataDetails();
    this.threadListRequest++;
    this.refreshing = false;
    this.threadSearchRequest++;
    clearTimeout(this.threadSearchTimer);
    this.threadSearchMatches = new Map();
    this.threadSearchLoading = false;
    this.threadSearchError = '';
    this.allThreads = this.allThreads.filter((thread) => thread.environmentKey?.startsWith('direct:') === true ||
      thread.environmentKey?.startsWith('direct-route:') === true);
    this.updateThreadProjects();
    this.updateThreadResults();
    this.relayRequest++;
    this.relayRows = [];
    this.relayHasListed = false;
    this.relayLoading = false;
    this.relayError = '';
    this.relayRestoreError = '';
    this.deregisterError = '';
    this.deregisteredRelayLinks.clear();
    this.relay?.clear();
    this.clearPendingApproval();
    this.showApprovals = false;
    this.approvals = [];
    for (const environment of this.environments) {
      if (environment.managed) {
        this.drafts.delete(environment.key);
        this.modelDrafts.delete(environment.key);
        this.runtimeDrafts.delete(environment.key);
        this.attachmentDrafts.delete(environment.key);
        this.quoteDrafts.delete(environment.key);
        this.terminalContextDrafts.delete(environment.key);
        this.commandContextDrafts.delete(environment.key);
        this.pendingThreadSends.delete(environment.key);
      }
    }
    try {
      await this.client?.signOutOfEnvironments(accountId);
      await this.loadEnvironments();
    } catch (error) {
      this.environments = this.environments.filter((environment) => !environment.managed);
      this.accountError = errorMessage(error as Error, '无法清除已保存的托管环境');
    }
    await this.applyCurrentEnvironment();
  }

  private managedConnector(identity: AccountIdentity): ConnectManagedEnvironment {
    return async (environmentId: string) => {
      const account = this.account;
      const relay = this.relay;
      const readToken = async (): Promise<string> => {
        if (!account || this.accountIdentity?.userId !== identity.userId) throw new Error('请重新登录 T3 账户。');
        const token = await account.readRelayToken();
        if (this.accountIdentity?.userId !== identity.userId) throw new Error('请重新登录 T3 账户。');
        return token;
      };
      if (!relay) throw new Error('当前安装包未配置 T3 Connect。');
      return relay.connectEnvironment(await readToken(), environmentId, undefined, readToken);
    };
  }

  private async loadRelayEnvironments(): Promise<void> {
    const account = this.account;
    const relay = this.relay;
    const identity = this.accountIdentity;
    if (!account || !relay || !identity || this.relayLoading || this.accountSigningOut) return;
    const request = ++this.relayRequest;
    this.relayLoading = true;
    this.relayError = '';
    try {
      const token = await account.readRelayToken();
      if (request !== this.relayRequest || this.accountIdentity?.userId !== identity.userId) return;
      await relay.listEnvironments(token, (rows: RelayEnvironment[]) => {
        if (request !== this.relayRequest) return;
        this.relayRows = rows.filter((row) => this.deregisteredRelayLinks.get(row.environmentId) !== row.linkedAt);
        this.relayHasListed = true;
      });
    } catch (error) {
      if (request !== this.relayRequest) return;
      if (!this.handleExpiredAccount(error as Error)) {
        this.relayError = errorMessage(error as Error, '无法加载 T3 Connect 环境');
      }
    } finally {
      if (request === this.relayRequest) this.relayLoading = false;
    }
  }

  private openAccount(): void {
    this.deregisterError = '';
    this.accountConnectProfileOpen = false;
    this.showAccount = true;
    void this.loadRelayEnvironments();
  }

  private async deregisterRelayEnvironment(environment: RelayEnvironment): Promise<void> {
    const account = this.account;
    const relay = this.relay;
    const client = this.client;
    const identity = this.accountIdentity;
    if (!this.showAccount || !account || !relay || !client || !identity || this.pairing ||
      this.accountBusy || this.sending || this.deregisteringEnvironmentId) return;
    if (!this.relayRows.some((entry) => entry.environmentId === environment.environmentId &&
      entry.linkedAt === environment.linkedAt)) return;
    this.deregisteringEnvironmentId = environment.environmentId;
    this.deregisterError = '';
    this.pairing = true;
    let revoked = false;
    try {
      const token = await account.readRelayToken();
      if (this.accountIdentity?.userId !== identity.userId) return;
      await relay.deregisterEnvironment(token, environment.environmentId);
      revoked = true;
      this.deregisteredRelayLinks.set(environment.environmentId, environment.linkedAt);
      this.relayRequest++;
      this.relayLoading = false;
      this.relayRows = this.relayRows.filter((entry) => entry.environmentId !== environment.environmentId);
      const saved = this.environments.find((entry) =>
        entry.managed && entry.environmentId === environment.environmentId);
      if (saved) {
        await client.removeEnvironment(saved.key, identity.userId);
        this.clearEnvironmentDrafts(saved.key);
      }
      await this.loadEnvironments();
      await this.applyCurrentEnvironment(false);
    } catch (error) {
      if (!this.handleExpiredAccount(error as Error)) {
        this.deregisterError = errorMessage(error as Error, revoked ? '已注销服务器，无法清理本机连接' : '无法注销服务器');
      }
    } finally {
      this.deregisteringEnvironmentId = '';
      this.pairing = false;
      if (revoked) void this.loadRelayEnvironments();
      this.showIncomingPairing();
    }
  }

  private handleExpiredAccount(error: Error): boolean {
    const identity = this.accountIdentity;
    if (!(error instanceof AccountSessionExpiredError) || !identity) return false;
    this.accountIdentity = undefined;
    this.accountError = error.message;
    void this.clearAccountEnvironmentState(identity.userId);
    return true;
  }

  private clearPendingApproval(): void {
    this.approvalEnvironmentId = '';
    this.approvalEnvironmentLabel = '';
    this.approvalCode = '';
    this.approvalPendingError = '';
    this.pendingApprovalThreadLink = '';
    this.pendingApprovalMessageId = undefined;
  }

  private showApprovalError(error: Error): boolean {
    if (error instanceof RelayApprovalPendingError || error instanceof RelayApprovalUnavailableError) {
      this.approvalEnvironmentId = error.environmentId;
      this.approvalEnvironmentLabel = error.environmentLabel;
      this.approvalCode = error.verificationCode;
      this.approvalPendingError = error instanceof RelayApprovalUnavailableError ? error.message : '';
      return true;
    }
    if (this.approvalEnvironmentId) {
      this.approvalPendingError = errorMessage(error, '无法刷新设备审批。');
      return true;
    }
    return false;
  }

  private async loadApprovals(): Promise<void> {
    const client = this.deviceApprovalClient();
    if (!client || this.approvalsBusy) return;
    this.approvalsBusy = true;
    this.approvalError = '';
    try {
      this.approvals = await client.list();
    } catch (error) {
      this.approvalError = errorMessage(error as Error, '无法加载待审批的设备');
    } finally {
      this.approvalsBusy = false;
    }
  }

  private deviceApprovalClient(): DeviceApprovalClient | undefined {
    const client = this.client;
    const key = this.environmentKey;
    if (!client || !key || !this.canApproveDevices) return undefined;
    return new DeviceApprovalClient(async (): Promise<Object> => this.boundApprovalRequest(key, () => {
      return client.readAuthAccessSnapshot();
    }), async (path: string, method?: string, body?: string): Promise<Object> => this.boundApprovalRequest(key, () => {
      return client.environmentRequest(path, method, body);
    }));
  }

  private async refreshDeviceApprovalAccess(): Promise<void> {
    const client = this.client;
    const key = this.environmentKey;
    if (!client || !key) return;
    try {
      const allowed = await client.canApproveDevices();
      if (key === this.environmentKey) this.canApproveDevices = allowed;
    } catch (error) {
      if (key !== this.environmentKey) return;
      this.canApproveDevices = false;
      this.handleExpiredAccount(error as Error);
    }
  }

  private async boundApprovalRequest(key: string, request: () => Promise<Object>): Promise<Object> {
    if (this.environmentKey !== key) throw new Error('环境连接已更换。');
    const response = await request();
    if (this.environmentKey !== key) throw new Error('环境连接已更换。');
    return response;
  }

  private async answerApproval(pairingLinkId: string, approve: boolean): Promise<void> {
    const client = this.deviceApprovalClient();
    if (!client || this.approvalsBusy) return;
    this.approvalsBusy = true;
    this.approvalError = '';
    this.approvalNotice = '';
    try {
      const result = approve ? await client.approve(pairingLinkId) : await client.deny(pairingLinkId);
      this.approvals = this.approvals.filter((request) => request.pairingLinkId !== pairingLinkId);
      this.approvalNotice = result === 'gone' ? '该申请已被处理或失效。' : approve ? '已批准设备。' : '已拒绝设备。';
    } catch (error) {
      this.approvalError = errorMessage(error as Error, '无法处理此设备申请');
    } finally {
      this.approvalsBusy = false;
    }
  }

  private stopAutomaticApprovals(): void {
    this.automaticApprovalGeneration++;
    clearTimeout(this.automaticApprovalRetry);
    this.automaticApprovalRetry = -1;
    this.approvalBindings.clear();
    this.automaticApprovalPrompt = undefined;
    this.closeAutomaticApprovalDialog();
    this.automaticApprovals?.setTargets([]);
  }

  private handleForegroundChange(): void {
    this.refreshAutomaticApprovals();
    if (this.selected) {
      if (this.appInForeground) this.watchBackgroundTasks();
      else this.stopBackgroundWatch();
    }
    if (this.linkedThreadTarget && !this.linkedPairingManual) {
      if (this.appInForeground) this.watchLinkedThreadView();
      else this.stopLinkedThreadView();
    }
    if (this.appInForeground && this.showPairing && !this.pairing && !this.addingEnvironment) {
      void this.refreshLinkedEnvironmentHealth();
      if (this.environmentDetails) void this.refreshEnvironmentMaintenance();
    }
  }

  private refreshAutomaticApprovals(): void {
    if (!this.appInForeground) {
      this.stopAutomaticApprovals();
      return;
    }
    this.bindAutomaticApprovals();
  }

  private bindAutomaticApprovals(): void {
    const client = this.client;
    const coordinator = this.automaticApprovals;
    if (!client || !coordinator || !this.appInForeground || this.accountSigningOut) return;
    clearTimeout(this.automaticApprovalRetry);
    this.automaticApprovalRetry = -1;
    const generation = ++this.automaticApprovalGeneration;
    const identity = this.accountIdentity;
    const bindings = new Map<string, ApprovalBinding>();
    const connector = identity ? this.managedConnector(identity) : undefined;
    for (const environment of this.environments) {
      if (!environment.enabled) continue;
      const fingerprint = JSON.stringify([environment.origin, environment.label,
        environment.managed ? identity?.sessionId : undefined]);
      const existing = this.approvalBindings.get(environment.key);
      if (existing?.fingerprint === fingerprint) {
        bindings.set(environment.key, existing);
        continue;
      }
      void client.bindDeviceApprovalTarget(environment, identity?.userId, connector).then((target) => {
        if (target && generation === this.automaticApprovalGeneration) {
          bindings.set(target.key, { fingerprint, target, environmentId: environment.environmentId });
          coordinator.setTargets(this.approvalTargets(bindings));
        }
      }).catch(() => {
        if (generation === this.automaticApprovalGeneration && this.automaticApprovalRetry === -1) {
          this.automaticApprovalRetry = setTimeout(() => this.bindAutomaticApprovals(), 30000);
        }
      });
    }
    this.approvalBindings = bindings;
    coordinator.setTargets(this.approvalTargets(bindings));
  }

  private approvalTargets(bindings: Map<string, ApprovalBinding>): ConnectDeviceApprovalTarget[] {
    const selected = new Map<string, ConnectDeviceApprovalTarget>();
    const activeKey = this.client?.currentEnvironment()?.key;
    for (const binding of bindings.values()) {
      if (!selected.has(binding.environmentId) || binding.target.key === activeKey) {
        selected.set(binding.environmentId, binding.target);
      }
    }
    return Array.from(selected.values());
  }

  private async presentAutomaticApproval(): Promise<void> {
    const prompt = this.automaticApprovalPrompt;
    const coordinator = this.automaticApprovals;
    if (!prompt || !coordinator || !this.appInForeground || this.presentingAutomaticApproval ||
      this.accountSigningOut) return;
    this.presentingAutomaticApproval = true;
    const action = this.getUIContext().getPromptAction();
    try {
      const id = await action.openCustomDialog({
        builder: () => { this.AutomaticApprovalDialog(prompt); },
        autoCancel: false,
        onWillDismiss: (dismiss) => {
          if (this.automaticApprovalPrompt === prompt) {
            if (this.answeringAutomaticApproval) return;
            this.automaticApprovalDialog = undefined;
            dismiss.dismiss();
            coordinator.defer(prompt);
          } else {
            dismiss.dismiss();
          }
        },
      });
      if (this.appInForeground && this.automaticApprovalPrompt === prompt) {
        this.automaticApprovalDialog = id;
      } else {
        action.closeCustomDialog(id);
      }
    } catch (_) {
      if (this.appInForeground && this.automaticApprovalPrompt === prompt) {
        this.getUIContext().getPromptAction().showToast({ message: '设备审批未完成，请到环境中查看申请。' });
        coordinator.defer(prompt);
      }
    } finally {
      this.presentingAutomaticApproval = false;
      if (this.automaticApprovalPrompt !== prompt) void this.presentAutomaticApproval();
    }
  }

  private closeAutomaticApprovalDialog(): void {
    const id = this.automaticApprovalDialog;
    this.automaticApprovalDialog = undefined;
    if (id !== undefined) this.getUIContext().getPromptAction().closeCustomDialog(id);
  }

  private async answerAutomaticApproval(prompt: ConnectDeviceApprovalPrompt, approve?: boolean): Promise<void> {
    const coordinator = this.automaticApprovals;
    if (!coordinator || !this.appInForeground || this.automaticApprovalPrompt !== prompt ||
      this.answeringAutomaticApproval) return;
    if (approve === undefined) {
      coordinator.defer(prompt);
      return;
    }
    this.answeringAutomaticApproval = true;
    try {
      const outcome = await coordinator.respond(prompt, approve);
      if (outcome === 'gone' && this.appInForeground) {
        this.getUIContext().getPromptAction().showToast({ message: '该申请已被处理或失效。' });
      }
    } catch (_) {
      if (this.appInForeground && this.automaticApprovalPrompt === prompt) {
        this.getUIContext().getPromptAction().showToast({ message: '设备审批未完成，请重试。' });
      }
    } finally {
      this.answeringAutomaticApproval = false;
    }
  }

  @Builder
  private AutomaticApprovalDialog(prompt: ConnectDeviceApprovalPrompt) {
    Column({ space: 12 }) {
      Text('T3 Connect 设备审批').fontSize(20).fontWeight(FontWeight.Medium)
      Text(prompt.environmentLabel + ' · ' + prompt.deviceLabel).fontSize(16)
      Text('验证码 ' + prompt.verificationCode).fontSize(18).fontWeight(FontWeight.Medium)
      Text('请先核对申请设备上的验证码。').fontColor($r('sys.color.font_secondary'))
      if (this.answeringAutomaticApproval) LoadingProgress().width(20).height(20).accessibilityText('正在处理审批')
      Row({ space: 8 }) {
        Button('稍后', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick(() => { void this.answerAutomaticApproval(prompt); })
        Button('拒绝', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick(() => { void this.answerAutomaticApproval(prompt, false); })
        Button('批准').onClick(() => { void this.answerAutomaticApproval(prompt, true); })
      }.enabled(!this.answeringAutomaticApproval).justifyContent(FlexAlign.End).width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(24)
    .borderRadius(24)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  private async useRelayEnvironment(environmentId: string): Promise<void> {
    const client = this.client;
    const identity = this.accountIdentity;
    if (!client || !identity || this.pairing || this.accountBusy || this.sending) return;
    this.pairing = true;
    this.relayConnectingId = environmentId;
    this.pairError = '';
    try {
      await client.connectManaged(environmentId, identity.userId, this.managedConnector(identity));
      this.relayRestoreError = '';
      if (this.showConnectOnboarding) {
        this.showConnectOnboarding = false;
        this.showAccount = false;
        this.selectWorkspaceTab('threads');
      }
      const linkedThread = this.approvalEnvironmentId === environmentId ? this.pendingApprovalThreadLink : '';
      const messageId = this.pendingApprovalMessageId;
      this.clearPendingApproval();
      await this.loadEnvironments();
      this.showPairing = false;
      await this.applyCurrentEnvironment();
      if (this.selected && !this.unsubscribe) this.watchThread();
      if (linkedThread && !this.incomingThreadLink) {
        if (messageId) {
          this.incomingCitationLink = linkedThread;
          this.incomingCitationMessageId = messageId;
        }
        this.incomingThreadLink = linkedThread;
      }
    } catch (error) {
      if (!this.handleExpiredAccount(error as Error) && !this.showApprovalError(error as Error)) {
        this.pairError = errorMessage(error as Error, '无法连接 T3 Connect 环境');
      }
    } finally {
      this.relayConnectingId = '';
      this.pairing = false;
      this.showIncomingPairing();
    }
  }

  private showIncomingPairing(): void {
    if (!this.incomingPairing) {
      this.handleIncomingThread();
      return;
    }
    if (this.pairing || this.scanning || this.sending || this.creatingThread || this.threadListActionBusy ||
      this.threadLaunchWorkspaceBusy || this.projectMutationBusy || this.threadGitMutation ||
      (this.selected && this.threadActionBusy)) return;
    this.pairLink = this.incomingPairing;
    this.incomingPairing = '';
    if (this.showEnvironmentRoutes && this.addingEnvironment) return;
    this.showAccount = false;
    this.showConnectOnboarding = false;
    this.showProjects = false;
    this.showArchivedThreads = false;
    this.threadListActionTarget = undefined;
    this.showApprovals = false;
    this.clearPendingApproval();
    this.closeThreadLaunch();
    this.closeEnvironmentDetails();
    this.closeWorkspaceDataDetails();
    this.pairError = '';
    this.closeThread();
    this.showPairing = true;
    this.addingEnvironment = true;
  }

  private handleIncomingThread(): void {
    if (!this.incomingThreadLink || !this.client || this.restoring || this.pairing || this.accountBusy ||
      this.accountPending || this.accountSigningOut || this.creatingThread || this.sending || this.threadActionBusy ||
      this.threadListActionBusy || this.threadGitMutation || this.threadLaunchWorkspaceBusy || this.projectMutationBusy) return;
    const uri = this.incomingThreadLink;
    const target = parseThreadLink(uri);
    const messageId = this.incomingCitationLink === uri ? this.incomingCitationMessageId : undefined;
    this.incomingCitationMessageId = undefined;
    this.incomingCitationLink = '';
    this.incomingThreadLink = '';
    if (target) void this.openLinkedThread(target.environmentId, target.threadId, uri, messageId);
  }

  private async openLinkedThread(environmentId: string, threadId: string, uri: string, messageId?: string): Promise<void> {
    const client = this.client;
    if (!client) return;
    if (client.currentEnvironment()?.environmentId === environmentId && this.selected?.id === threadId) {
      if (messageId) await this.jumpToThreadMessage(messageId);
      return;
    }
    this.pairing = true;
    this.openingThreadLink = true;
    this.pairError = '';
    try {
      if (client.currentEnvironment()?.environmentId !== environmentId) {
        const identity = this.accountIdentity;
        const saved = await client.listEnvironments(identity?.userId);
        const environment = saved.find((entry) => entry.environmentId === environmentId && entry.enabled);
        if (environment) {
          await client.reconnectEnvironment(environment.key, identity?.userId, identity ? this.managedConnector(identity) : undefined);
        } else if (saved.some((entry) => entry.environmentId === environmentId)) {
          throw new Error('请先启用此任务所在的环境。');
        } else if (identity && this.relay) {
          await client.connectManaged(environmentId, identity.userId, this.managedConnector(identity));
        } else {
          throw new Error('请先配对此任务所在的环境。');
        }
        await this.loadEnvironments();
        await this.applyCurrentEnvironment();
      }
      const thread = this.allThreads.find((entry) =>
        entry.id === threadId && entry.environmentKey === this.environmentKey) ?? await client.readThreadLinkTarget(threadId);
      this.closeThreadLaunch();
      this.closeEnvironmentDetails();
      this.showPairing = false;
      this.showAccount = false;
      this.showConnectOnboarding = false;
      this.showProjects = false;
      this.showArchivedThreads = false;
      this.threadListActionTarget = undefined;
      this.showApprovals = false;
      this.clearPendingApproval();
      this.selectWorkspaceTab('threads');
      this.openWorkspaceThread(thread);
      if (messageId) this.pendingMessageJump = messageId;
    } catch (error) {
      if (error instanceof RelayApprovalPendingError || error instanceof RelayApprovalUnavailableError) {
        this.showApprovalError(error as Error);
        this.pendingApprovalThreadLink = uri;
        this.pendingApprovalMessageId = messageId;
      } else if (!this.handleExpiredAccount(error as Error)) {
        this.getUIContext().getPromptAction().showToast({
          message: errorMessage(error as Error, '无法打开链接中的会话'),
        });
      }
    } finally {
      this.openingThreadLink = false;
      this.pairing = false;
      this.showIncomingPairing();
    }
  }

  private async restore(): Promise<void> {
    const client = this.client;
    if (!client) return;
    try {
      await client.restore();
      await this.loadEnvironments();
      await this.applyCurrentEnvironment(false);
    } catch (error) {
      this.pairError = errorMessage(error as Error, '无法恢复连接');
    } finally {
      this.restoring = false;
    }
  }

  private async scanPairingCode(linked: boolean = false): Promise<void> {
    const context = this.context;
    if (!context || this.scanning || this.pairing) return;
    this.scanning = true;
    try {
      const result = await scanBarcode.startScanForResult(context, { scanTypes: [scanCore.ScanType.QR_CODE] });
      if (result.originalValue) {
        if (linked) {
          if (this.linkedPairingManual) {
            this.linkedPairingLink = result.originalValue;
            this.linkedThreadConnectionError = '';
          }
        } else {
          this.pairLink = result.originalValue;
          this.pairError = '';
        }
      }
    } catch (error) {
      // Scan Kit uses this result for closing the scanner without a code.
      if ((error as BusinessError).code !== 1000500002) {
        if (linked) this.linkedThreadConnectionError = '无法扫描配对码，可以手动输入链接。';
        else this.pairError = '无法扫描配对码，可以手动输入链接。';
      }
    } finally {
      this.scanning = false;
      this.showIncomingPairing();
    }
  }

  private async pair(address: string, code: string): Promise<void> {
    const client = this.client;
    if (!client || this.scanning || this.pairing || this.sending || this.refreshing || this.accountSigningOut) return;
    this.pairing = true;
    this.pairError = '';
    const expectedEnvironmentId = this.showEnvironmentRoutes ? this.environmentDetails?.environmentId : undefined;
    try {
      const active = address.trim() || code.trim()
        ? await client.pairAddress(address, code, expectedEnvironmentId)
        : await client.pair(this.pairLink.trim(), expectedEnvironmentId);
      this.stopAutomaticApprovals();
      this.pairLink = '';
      this.addingEnvironment = false;
      if (expectedEnvironmentId) this.environmentRouteNotice = '已保存配对线路。';
      await this.loadEnvironments();
      if (active) {
        this.closeWorkspaceDataDetails();
        await this.applyCurrentEnvironment();
      }
    } catch (error) {
      this.pairError = errorMessage(error as Error, '配对失败');
    } finally {
      this.pairing = false;
      this.showIncomingPairing();
    }
  }

  private async loadEnvironments(): Promise<void> {
    const client = this.client;
    if (!client) return;
    const accountId = this.accountIdentity?.userId;
    const environments = await client.listEnvironments(accountId);
    if (client !== this.client || accountId !== this.accountIdentity?.userId) return;
    this.environments = environments;
    this.refreshAutomaticApprovals();
    if (this.environmentDetails) {
      const details = this.environmentDetails;
      this.environmentDetails = this.environments.find((entry) => entry.key === details.key) ??
        this.environments.find((entry) => entry.environmentId === details.environmentId);
      if (!this.environmentDetails) this.showEnvironmentRoutes = false;
      if (!this.maintenanceBusy) void this.refreshEnvironmentMaintenance();
    }
    if (this.showPairing) void this.refreshLinkedEnvironmentHealth();
  }

  private async applyCurrentEnvironment(waitForThreads: boolean = true): Promise<void> {
    const current = this.client?.currentEnvironment();
    const key = current?.key ?? '';
    if (this.environmentKey !== key) {
      this.closeWorkspaceDataDetails();
      this.closeProjectWizard();
      this.threadListRequest++;
      this.refreshing = false;
      this.canApproveDevices = false;
      this.approvals = [];
      this.approvalNotice = '';
      this.showApprovals = false;
      this.closeThread();
      this.allThreads = [];
      this.threadSearchMatches = new Map();
      this.threadSearchLoading = false;
      this.threadSearchError = '';
      this.threadSearchRequest++;
      clearTimeout(this.threadSearchTimer);
      this.threadListCanWrite = false;
      this.threadListActionTarget = undefined;
      this.showArchivedThreads = false;
      this.archiveRequest++;
      this.archivedThreads = [];
      this.projectFilter = '';
      this.threadProjects = [];
      this.updateThreadResults();
      this.listError = '';
    }
    this.environmentKey = key;
    this.connected = current !== undefined;
    if (this.connected && this.showPairing) void this.refreshDeviceApprovalAccess();
    if (this.connected) {
      const refresh = this.refreshThreads();
      if (waitForThreads) await refresh;
    }
  }

  private async manageEnvironment(key: string, remove: boolean, stayInSettings: boolean = false,
    useBackup: boolean = true): Promise<void> {
    const client = this.client;
    if (!client || this.pairing || this.sending || this.accountSigningOut) return;
    this.pairing = true;
    this.pairError = '';
    this.environmentRouteNotice = '';
    try {
      const identity = this.accountIdentity;
      if (remove) {
        await client.removeEnvironment(key, identity?.userId);
        this.clearEnvironmentDrafts(key);
      } else {
        const connector = identity ? this.managedConnector(identity) : undefined;
        if (useBackup) await client.reconnectEnvironment(key, identity?.userId, connector);
        else await client.select(key, identity?.userId, connector, true);
        const active = client.currentEnvironment();
        if (active && active.environmentId === this.environmentDetails?.environmentId) this.environmentDetails = active;
        if (active && active.key !== key) {
          this.environmentRouteNotice = active.managed ? '已使用 T3 Connect 备用连接。' : '已使用直连备用连接。';
        }
        if (client.currentEnvironment()?.managed) this.relayRestoreError = '';
        if (!stayInSettings) this.showPairing = false;
      }
      await this.loadEnvironments();
      await this.applyCurrentEnvironment();
    } catch (error) {
      if (!this.handleExpiredAccount(error as Error) && !this.showApprovalError(error as Error)) {
        this.pairError = errorMessage(error as Error, '无法更新连接');
      }
    } finally {
      this.pairing = false;
      this.showIncomingPairing();
    }
  }

  private clearEnvironmentDrafts(key: string): void {
    this.drafts.delete(key);
    this.modelDrafts.delete(key);
    this.runtimeDrafts.delete(key);
    this.attachmentDrafts.delete(key);
    this.quoteDrafts.delete(key);
    this.terminalContextDrafts.delete(key);
    this.commandContextDrafts.delete(key);
    this.pendingThreadSends.delete(key);
  }

  private closeEnvironmentDetails(): void {
    this.environmentDetailsFromSettings = false;
    this.clearEnvironmentMaintenance();
    this.linkedEnvironmentRequest++;
    this.linkedEnvironmentSourceKey = '';
    this.linkedEnvironmentHealth = [];
    this.linkedEnvironmentCanManage = false;
    this.linkedEnvironmentLoading = false;
    this.linkedEnvironmentError = '';
    this.linkedEnvironmentNotice = '';
    this.linkedEnvironmentBatch = [];
    this.environmentRouteNotice = '';
    this.showEnvironmentRoutes = false;
    this.environmentDetails = undefined;
    this.pairError = '';
  }

  private clearEnvironmentMaintenance(): void {
    this.maintenanceRequest++;
    this.maintenanceSourceKey = '';
    this.maintenanceSnapshot = undefined;
    this.maintenanceLoading = false;
    this.maintenanceError = '';
    this.maintenanceNotice = '';
    this.maintenanceRelease = undefined;
  }

  private applyEnvironmentMaintenance(snapshot: EnvironmentMaintenanceSnapshot): void {
    if (this.maintenanceSnapshot?.version !== snapshot.version) this.maintenanceRelease = undefined;
    this.maintenanceSnapshot = snapshot;
  }

  private async refreshEnvironmentMaintenance(): Promise<void> {
    const client = this.client;
    const active = client?.currentEnvironment();
    if (!client || !active || active.environmentId !== this.environmentDetails?.environmentId) {
      this.clearEnvironmentMaintenance();
      return;
    }
    if (this.maintenanceSourceKey !== active.key) {
      this.clearEnvironmentMaintenance();
      this.maintenanceSourceKey = active.key;
    }
    const request = ++this.maintenanceRequest;
    this.maintenanceLoading = true;
    this.maintenanceError = '';
    try {
      const snapshot = await client.readEnvironmentMaintenance();
      if (request === this.maintenanceRequest && active.key === client.currentEnvironment()?.key) {
        this.applyEnvironmentMaintenance(snapshot);
      }
    } catch (error) {
      if (request === this.maintenanceRequest) {
        this.maintenanceSnapshot = undefined;
        this.maintenanceError = errorMessage(error as Error, '无法读取主机维护状态');
      }
    } finally {
      if (request === this.maintenanceRequest) this.maintenanceLoading = false;
    }
  }

  private async runEnvironmentMaintenance(action: 'check' | 'refresh' | 'update',
    provider?: EnvironmentMaintenanceProvider): Promise<void> {
    const client = this.client;
    const active = client?.currentEnvironment();
    if (!client || !active || this.pairing || this.maintenanceLoading || this.accountSigningOut ||
      this.maintenanceSourceKey !== active.key || active.environmentId !== this.environmentDetails?.environmentId) return;
    this.pairing = true;
    this.maintenanceBusy = true;
    this.maintenanceError = '';
    this.maintenanceNotice = '';
    const request = ++this.maintenanceRequest;
    try {
      let snapshot: EnvironmentMaintenanceSnapshot;
      let latest: string | null | undefined = undefined;
      if (action === 'check') {
        snapshot = await client.readEnvironmentMaintenance();
        if (!snapshot.canCheck) throw new Error('此环境当前无法检查更新。');
        latest = await checkEnvironmentRelease(snapshot.version);
      } else if (action === 'refresh') {
        snapshot = await client.refreshEnvironmentMaintenanceProviders();
      } else {
        if (!provider) throw new Error('请选择需要更新的提供商。');
        snapshot = await client.updateEnvironmentMaintenanceProvider(provider);
      }
      if (request === this.maintenanceRequest && active.key === client.currentEnvironment()?.key) {
        this.applyEnvironmentMaintenance(snapshot);
        if (action === 'check') this.maintenanceRelease = latest;
        if (action === 'refresh') this.maintenanceNotice = '已刷新提供商状态。';
      }
    } catch (error) {
      if (request === this.maintenanceRequest && !this.handleExpiredAccount(error as Error)) {
        this.maintenanceError = errorMessage(error as Error, '无法完成主机维护操作');
      }
    } finally {
      this.maintenanceBusy = false;
      this.pairing = false;
      this.showIncomingPairing();
    }
  }

  private backFromEnvironmentDetails(): void {
    const returnToSettings = this.environmentDetailsFromSettings;
    this.closeEnvironmentDetails();
    if (returnToSettings) this.showPairing = false;
    else void this.refreshLinkedEnvironmentHealth();
  }

  private async refreshLinkedEnvironmentHealth(): Promise<void> {
    const request = ++this.linkedEnvironmentRequest;
    this.linkedEnvironmentCanManage = false;
    this.linkedEnvironmentLoading = false;
    this.linkedEnvironmentError = '';
    const client = this.client;
    const active = client?.currentEnvironment();
    const detail = this.environmentDetails;
    const key = client && active && this.showPairing && (!detail || detail.environmentId === active.environmentId)
      ? active.key : '';
    if (key !== this.linkedEnvironmentSourceKey) {
      this.linkedEnvironmentSourceKey = key;
      this.linkedEnvironmentHealth = [];
      this.linkedEnvironmentBatch = [];
      this.linkedEnvironmentNotice = '';
    }
    if (!client || !key) return;
    this.linkedEnvironmentLoading = true;
    try {
      const snapshot = await client.readLinkedEnvironmentHealth();
      if (request === this.linkedEnvironmentRequest && key === client.currentEnvironment()?.key) {
        this.linkedEnvironmentHealth = snapshot.links;
        this.linkedEnvironmentCanManage = snapshot.canManage;
      }
    } catch (error) {
      if (request === this.linkedEnvironmentRequest) {
        this.linkedEnvironmentError = errorMessage(error as Error, '无法读取关联环境');
      }
    } finally {
      if (request === this.linkedEnvironmentRequest) this.linkedEnvironmentLoading = false;
    }
  }

  private environmentRouteRows(): EnvironmentSummary[] {
    const id = this.environmentDetails?.environmentId;
    return this.environments.filter((entry) => entry.environmentId === id);
  }

  private visibleEnvironmentRows(): EnvironmentSummary[] {
    const rows = new Map<string, EnvironmentSummary>();
    for (const route of this.environments) {
      const current = rows.get(route.environmentId);
      if (!current || route.key === this.environmentKey || (!current.enabled && route.enabled)) {
        rows.set(route.environmentId, route);
      }
    }
    return Array.from(rows.values());
  }

  private linkedEnvironmentCandidates(): LinkedEnvironmentCandidate[] {
    if (!this.linkedEnvironmentCanManage) return [];
    const sourceId = this.client?.currentEnvironment()?.environmentId;
    const existing = new Set(this.linkedEnvironmentHealth.filter((link) =>
      link.status !== 'expired' && link.expiresAtMs > Date.now()).map((link) => link.environmentId));
    const candidates: LinkedEnvironmentCandidate[] = [];
    for (const route of this.environments) {
      if (!route.enabled || route.environmentId === sourceId ||
        existing.has(route.environmentId)) continue;
      const origin = linkedEnvironmentOrigin(route.origin);
      if (!origin) continue;
      candidates.push({ key: route.key, environmentId: route.environmentId, label: route.label, origin });
      existing.add(route.environmentId);
    }
    return candidates;
  }

  private batchLinkAvailable(): boolean {
    if (!this.linkedEnvironmentCanManage) return false;
    const source = this.client?.currentEnvironment();
    return !!source && source.key === this.linkedEnvironmentSourceKey &&
      this.visibleEnvironmentRows().filter((row) => row.environmentId !== source.environmentId).length >= 2;
  }

  private async linkEnvironmentBatch(keys: string[], access: NativePeerLinkAccess): Promise<void> {
    const client = this.client;
    const sourceKey = client?.currentEnvironment()?.key;
    if (!client || !sourceKey || !this.showPairing || this.environmentDetails || this.pairing ||
      this.accountSigningOut || !this.batchLinkAvailable()) return;
    const candidates = this.linkedEnvironmentCandidates().filter((row) => keys.includes(row.key));
    if (candidates.length === 0) return;

    this.pairing = true;
    this.linkedEnvironmentError = '';
    this.linkedEnvironmentBatch = candidates.map((row): LinkedEnvironmentBatchResult =>
      ({ key: row.key, label: row.label, status: 'pending' }));
    const identity = this.accountIdentity;
    try {
      await client.linkSavedEnvironmentBatch(candidates.map((row) => row.key), access, identity?.userId,
        identity ? this.managedConnector(identity) : undefined, (result: LinkedEnvironmentBatchResult) => {
          if (sourceKey !== this.linkedEnvironmentSourceKey) return;
          this.linkedEnvironmentBatch = this.linkedEnvironmentBatch.map((row) => row.key === result.key ? result : row);
        });
      if (sourceKey === this.linkedEnvironmentSourceKey) await this.refreshLinkedEnvironmentHealth();
    } catch (error) {
      if (sourceKey === this.linkedEnvironmentSourceKey && !this.handleExpiredAccount(error as Error)) {
        this.linkedEnvironmentBatch = this.linkedEnvironmentBatch.map((row): LinkedEnvironmentBatchResult =>
          ({ key: row.key, label: row.label, status: 'failed', message: '无法读取来源环境或确认管理权限。' }));
      }
    } finally {
      this.pairing = false;
      this.showIncomingPairing();
    }
  }

  private async changeLinkedEnvironment(key: string, access?: NativePeerLinkAccess): Promise<void> {
    const client = this.client;
    if (!client || this.pairing || this.accountSigningOut || !this.linkedEnvironmentCanManage ||
      client.currentEnvironment()?.environmentId !== this.environmentDetails?.environmentId) return;
    this.pairing = true;
    this.linkedEnvironmentError = '';
    this.linkedEnvironmentNotice = '';
    try {
      if (access) {
        const identity = this.accountIdentity;
        await client.linkSavedEnvironment(key, access, identity?.userId,
          identity ? this.managedConnector(identity) : undefined);
        this.linkedEnvironmentNotice = '已关联环境。';
      } else {
        const result = await client.unlinkEnvironment(key);
        this.linkedEnvironmentNotice = result.removed && result.endedThere !== true
          ? '已移除关联。目标环境可能仍有会话，可在该环境的访问设置中撤销。' : '关联已移除。';
      }
      await this.refreshLinkedEnvironmentHealth();
    } catch (error) {
      if (!this.handleExpiredAccount(error as Error)) {
        this.linkedEnvironmentError = errorMessage(error as Error, '无法更新关联环境');
      }
    } finally {
      this.pairing = false;
      this.showIncomingPairing();
    }
  }

  private async changeEnvironmentRoute(key: string, delta?: number): Promise<void> {
    const client = this.client;
    if (!client || this.pairing || this.accountSigningOut ||
      !this.environmentRouteRows().some((entry) => entry.key === key)) return;
    this.pairing = true;
    this.pairError = '';
    this.environmentRouteNotice = '';
    try {
      const identity = this.accountIdentity;
      if (delta === undefined) {
        const removingActive = key === client.currentEnvironment()?.key;
        await client.removeEnvironmentRoute(key, identity?.userId, identity ? this.managedConnector(identity) : undefined);
        if (removingActive && !client.currentEnvironment()) {
          this.environmentRouteNotice = '已移除线路，未能连接此环境的其他线路。';
        }
        this.clearEnvironmentDrafts(key);
      } else {
        await client.moveEnvironmentRoute(key, delta, identity?.userId);
      }
      await this.loadEnvironments();
      if (this.environmentKey !== (client.currentEnvironment()?.key ?? '')) await this.applyCurrentEnvironment();
    } catch (error) {
      this.pairError = errorMessage(error as Error, '无法更新连接线路');
    } finally {
      this.pairing = false;
      this.showIncomingPairing();
    }
  }

  private async updateEnvironmentDetails(label: string, address?: string, enabled?: boolean): Promise<void> {
    const client = this.client;
    const details = this.environmentDetails;
    if (!client || !details || this.pairing) return;
    this.pairing = true;
    this.pairError = '';
    try {
      const accountId = this.accountIdentity?.userId;
      if (enabled === undefined) await client.updateEnvironment(details.key, label, address, accountId);
      else await client.setEnvironmentEnabled(details.key, enabled, accountId);
      await this.loadEnvironments();
      await this.applyCurrentEnvironment();
    } catch (error) {
      this.pairError = errorMessage(error as Error, '无法更新连接');
    } finally {
      this.pairing = false;
      this.showIncomingPairing();
    }
  }

  private async refreshThreads(replaceInFlight: boolean = false): Promise<void> {
    const client = this.client;
    if (!client || (this.refreshing && !replaceInFlight) || !this.connected) return;
    const request = ++this.threadListRequest;
    this.refreshing = true;
    this.listError = '';
    void client.threadPermissions().then((permissions) => {
      if (request === this.threadListRequest) this.threadListCanWrite = permissions.operate;
    }).catch(() => {
      if (request === this.threadListRequest) this.threadListCanWrite = false;
    });
    try {
      const current = client.currentEnvironment();
      if (!current) return;
      const targets = this.workspaceEnvironments(current);
      const identity = this.accountIdentity;
      const loads = targets.map(async (environment: EnvironmentSummary): Promise<ThreadListLoad> => {
        try {
          const threads = environment.key === current.key ? await client.listThreads() :
            await client.listEnvironmentThreads(environment.key, identity?.userId,
              identity ? this.managedConnector(identity) : undefined);
          for (const thread of threads) {
            thread.environmentKey = environment.key;
            thread.environmentLabel = environment.label;
          }
          return { threads, error: '' };
        } catch (error) {
          if (request === this.threadListRequest && environment.key === current.key &&
            this.handleExpiredAccount(error as Error)) return { threads: [], error: '' };
          const message = errorMessage(error as Error, this.copy('无法加载会话', 'Could not load chats'));
          return { threads: [], error: targets.length > 1 ? environment.label + ' · ' + message : message };
        }
      });
      if (targets.length > 1) {
        const first = await loads[0];
        if (request !== this.threadListRequest) return;
        if (first.threads.length > 0) {
          const pending = new Set(targets.slice(1).map((target: EnvironmentSummary) => target.key));
          const cached = this.allThreads.filter((thread: NativeThread) => pending.has(thread.environmentKey ?? ''));
          this.setWorkspaceThreads(first.threads.concat(cached));
        }
      }
      const results = await Promise.all(loads);
      if (request !== this.threadListRequest) return;
      this.listError = results.find((result) => result.error.length > 0)?.error ?? '';
      this.setWorkspaceThreads(results.flatMap((result: ThreadListLoad) => result.threads));
      if (this.threadQuery) this.scheduleThreadSearch();
    } catch (error) {
      if (request === this.threadListRequest && !this.handleExpiredAccount(error as Error)) {
        this.listError = errorMessage(error as Error, this.copy('无法加载会话', 'Could not load chats'));
      }
    } finally {
      if (request === this.threadListRequest) this.refreshing = false;
    }
  }

  private setWorkspaceThreads(threads: NativeThread[]): void {
    this.allThreads = threads;
    this.updateSideChats();
    this.updateThreadProjects();
    this.updateThreadResults();
  }

  private workspaceEnvironments(current: EnvironmentSummary): EnvironmentSummary[] {
    const targets: EnvironmentSummary[] = [current];
    const seen = new Set<string>([current.environmentId]);
    for (const environment of this.environments) {
      if (!environment.enabled || seen.has(environment.environmentId)) continue;
      seen.add(environment.environmentId);
      targets.push(environment);
    }
    const selected = targets.find((target: EnvironmentSummary) => target.environmentId === this.workspaceEnvironmentFilter);
    return selected ? [selected] : targets;
  }

  private threadSearchKey(thread: NativeThread): string {
    return JSON.stringify([thread.environmentKey ?? this.environmentKey, thread.id]);
  }

  private threadTitleMatches(thread: NativeThread, query: string): boolean {
    return thread.title.toLowerCase().includes(query) || thread.projectTitle?.toLowerCase().includes(query) === true;
  }

  private updateThreadResults(): void {
    const query = this.threadQuery.trim().toLowerCase();
    const now = Date.now();
    const scopedEnvironment = this.workspaceEnvironmentFilter ?
      this.visibleEnvironmentRows().find((row: EnvironmentSummary) =>
        row.enabled && row.environmentId === this.workspaceEnvironmentFilter) : undefined;
    const visible = this.allThreads.filter((thread) =>
      thread.lineage?.sideChat !== true &&
      (!scopedEnvironment || thread.environmentKey === scopedEnvironment.key) &&
      (!this.projectFilter || this.threadProjectKey(thread) === this.projectFilter) &&
      (!query || this.threadTitleMatches(thread, query) || this.threadSearchMatches.has(this.threadSearchKey(thread))));
    visible.sort((left: NativeThread, right: NativeThread) => {
      const leftPinned = threadLifecycleState(left, now) === 'pinned';
      const rightPinned = threadLifecycleState(right, now) === 'pinned';
      if (leftPinned !== rightPinned) return leftPinned ? -1 : 1;
      return leftPinned && left.pinOrderKey && right.pinOrderKey ? left.pinOrderKey.localeCompare(right.pinOrderKey) : 0;
    });
    const entries = workspaceThreadListEntries(visible, now, query.length > 0, this.expandedThreadShelves);
    this.threads.replace(entries);
    this.threadCount = entries.length;
  }

  private threadProjectKey(thread: NativeThread): string {
    return JSON.stringify([thread.environmentKey ?? this.environmentKey, thread.projectId ?? '']);
  }

  private updateThreadProjects(): void {
    const projects = new Map<string, WorkspaceProjectChoice>();
    const multipleEnvironments = this.workspaceEnvironmentFilter.length === 0 && this.visibleEnvironmentRows().length > 1;
    for (const thread of this.allThreads) {
      if (!thread.projectId || !thread.projectTitle) continue;
      const key = this.threadProjectKey(thread);
      if (!projects.has(key)) {
        const title = multipleEnvironments && thread.environmentLabel ?
          thread.projectTitle + ' · ' + thread.environmentLabel : thread.projectTitle;
        projects.set(key, { key, title, environmentKey: thread.environmentKey ?? this.environmentKey });
      }
    }
    this.threadProjects = Array.from(projects.values());
    if (this.projectFilter && !projects.has(this.projectFilter)) this.projectFilter = '';
  }

  private async openListedThread(thread: NativeThread): Promise<void> {
    const client = this.client;
    if (!client || this.pairing) return;
    if (!this.showArchivedThreads) this.rememberWorkspaceScroll();
    const query = this.threadQuery.trim().toLowerCase();
    const messageId = query && !this.threadTitleMatches(thread, query) ?
      this.threadSearchMatches.get(this.threadSearchKey(thread))?.messageId : undefined;
    if (!thread.environmentKey || thread.environmentKey === this.environmentKey) {
      this.openWorkspaceThread(thread);
      this.pendingMessageJump = messageId ?? '';
      return;
    }
    this.pairing = true;
    this.listError = '';
    try {
      const identity = this.accountIdentity;
      await client.select(thread.environmentKey, identity?.userId, identity ? this.managedConnector(identity) : undefined);
      await this.applyCurrentEnvironment(false);
      this.openWorkspaceThread(thread);
      this.pendingMessageJump = messageId ?? '';
    } catch (error) {
      if (!this.handleExpiredAccount(error as Error) && !this.showApprovalError(error as Error)) {
        this.listError = errorMessage(error as Error, '无法打开此会话的环境');
      }
    } finally {
      this.pairing = false;
      this.showIncomingPairing();
    }
  }

  private canOperateThreadRow(thread: NativeThread): boolean {
    return this.threadListCanWrite && (!thread.environmentKey || thread.environmentKey === this.environmentKey);
  }

  private openThreadListActions(thread: NativeThread, snooze: boolean = false): void {
    if (this.threadListActionBusy || !this.canOperateThreadRow(thread)) return;
    this.threadListStartWithSnooze = snooze;
    this.threadListActionError = '';
    this.threadListActionTarget = thread;
  }

  private async updateThreadLifecycle(action: ThreadLifecycleAction, value?: string, row?: NativeThread): Promise<void> {
    const client = this.client;
    const thread = row ?? this.threadListActionTarget;
    if (!client || !thread || !this.canOperateThreadRow(thread) || this.threadListActionBusy || this.pairing ||
      !availableThreadLifecycleActions(thread, true, Date.now()).includes(action)) return;
    this.threadListActionBusy = true;
    this.threadListActionError = '';
    try {
      await client.changeThreadLifecycle(thread.id, action, value);
      this.threadListActionTarget = undefined;
      await this.refreshThreads();
      if (this.showArchivedThreads) await this.loadArchivedThreads();
    } catch (error) {
      const message = errorMessage(error as Error, this.copy('无法更新会话', 'Could not update the chat'));
      if (row) this.listError = message;
      else this.threadListActionError = message;
    } finally {
      this.threadListActionBusy = false;
      this.showIncomingPairing();
    }
  }

  private async loadArchivedThreads(): Promise<void> {
    if (!this.client || !this.connected) return;
    const request = ++this.archiveRequest;
    this.archiveLoading = true;
    this.archiveError = '';
    try {
      const archived = await this.client.listArchivedThreads();
      if (request === this.archiveRequest) this.archivedThreads = archived;
    } catch (error) {
      if (request === this.archiveRequest) this.archiveError = errorMessage(error as Error, '无法读取归档会话');
    } finally {
      if (request === this.archiveRequest) this.archiveLoading = false;
    }
  }

  private openWorkspaceThread(thread: NativeThread): void {
    this.openThread(thread);
    const client = this.client;
    if (!client || !threadHasUnread(thread)) return;
    const visitedAt = thread.latestRunCompletedAt ?? thread.updatedAt;
    if (!visitedAt) return;
    const key = this.environmentKey;
    void client.visitThread(thread.id, visitedAt).then(() => {
      if (key !== this.environmentKey) return;
      const row = this.allThreads.find((entry) => entry.id === thread.id && entry.environmentKey === key);
      if (row && (!row.lastVisitedAt || row.lastVisitedAt < visitedAt)) {
        row.lastVisitedAt = visitedAt;
        if (!this.selected) this.updateThreadResults();
      }
    }).catch(() => {});
  }

  private searchThreads(query: string): void {
    this.threadQuery = query;
    this.threadSearchMatches = new Map();
    this.updateThreadResults();
    this.scheduleThreadSearch();
  }

  private scheduleThreadSearch(): void {
    clearTimeout(this.threadSearchTimer);
    const request = ++this.threadSearchRequest;
    const query = normalizeThreadSearchQuery(this.threadQuery);
    this.threadSearchError = '';
    this.threadSearchLoading = this.connected && canSearchThreadMessages(query);
    if (!this.threadSearchLoading) return;
    this.threadSearchTimer = setTimeout(() => { void this.loadThreadSearch(query, request); }, 120);
  }

  private async loadThreadSearch(query: string, request: number): Promise<void> {
    const client = this.client;
    const current = client?.currentEnvironment();
    if (!client || !current || request !== this.threadSearchRequest) return;
    const identity = this.accountIdentity;
    const results = await Promise.all(this.workspaceEnvironments(current).map(
      async (environment: EnvironmentSummary): Promise<WorkspaceSearchResult> => {
        try {
          const matches = await client.searchEnvironmentThreads(query, environment.key, identity?.userId,
            identity ? this.managedConnector(identity) : undefined);
          return { environmentKey: environment.key, matches, error: '' };
        } catch (error) {
          return {
            environmentKey: environment.key, matches: [],
            error: errorMessage(error as Error, '无法搜索会话正文'),
          };
        }
      }));
    if (request !== this.threadSearchRequest) return;
    const matches = new Map<string, NativeThreadSearchMatch>();
    for (const result of results) {
      for (const match of result.matches) {
        matches.set(JSON.stringify([result.environmentKey, match.threadId]), match);
      }
    }
    this.threadSearchMatches = matches;
    this.threadSearchError = results.find((result) => !!result.error)?.error ?? '';
    this.threadSearchLoading = false;
    this.updateThreadResults();
  }

  private closeThreadSearch(): void {
    this.searchOpen = false;
    this.searchThreads('');
  }

  private closeSettingsSearch(): void {
    this.settingsSearchOpen = false;
    this.settingsQuery = '';
    this.settingsScrollOffset = 0;
  }

  private rememberSettingsScroll(): void {
    if (this.workspaceTab === 'settings' && this.settingsPages.length === 0) {
      this.settingsScrollOffset = this.settingsScroller.currentOffset()?.yOffset ?? 0;
    }
  }

  private async restoreClientPreferences(): Promise<void> {
    const store = this.clientPreferencesStore;
    if (!store) return;
    try {
      this.clientPreferences = await store.load();
    } catch (_) {}
  }

  private updateClientPreferenceEntry(key: ClientPreferenceKey, value: ClientPreferenceValue): void {
    const next = updateClientPreference(this.clientPreferences, key, value);
    this.clientPreferences = next;
    const store = this.clientPreferencesStore;
    if (store) {
      void store.save(next).catch(() => {
        this.getUIContext().getPromptAction().showToast({
          message: this.copy('无法保存客户端设置', 'Could not save client preference'),
        });
      });
    }
  }

  private async loadEnvironmentSettingsSection(page: WorkspaceSettingsPage): Promise<void> {
    const client = this.client;
    if (!client || !this.connected) return;
    try {
      if (page === 'thread-preferences' || page === 'source-control' || page === 'worktrees' ||
        page === 'maintenance' || page === 'labs') {
        this.environmentPreferences = await client.readEnvironmentPreferences();
      } else if (page === 'providers') {
        this.providersList = await client.listProviders();
      } else if (page === 'scheduled-tasks') {
        this.scheduledTasksList = await client.listScheduledTasks();
      }
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({
        message: (error as Error).message || this.copy('无法读取环境设置', 'Could not load environment settings'),
      });
    }
  }

  private applyEnvironmentPatch(patch: Record<string, Object | null | undefined>): void {
    const client = this.client;
    if (!client || !this.connected) return;
    void client.updateEnvironmentSettings(patch).then(() => client.readEnvironmentPreferences()).then((next) => {
      this.environmentPreferences = next;
    }).catch((error: Error) => {
      this.getUIContext().getPromptAction().showToast({
        message: error.message || this.copy('无法保存环境设置', 'Could not save environment settings'),
      });
    });
  }

  private toggleProviderEnabled(instanceId: string, enabled: boolean, driver: string): void {
    const client = this.client;
    if (!client || !this.connected) return;
    void client.setProviderEnabled(instanceId, enabled, driver).then(() => client.listProviders()).then((next) => {
      this.providersList = next;
    }).catch((error: Error) => {
      this.getUIContext().getPromptAction().showToast({
        message: error.message || this.copy('无法更新提供商状态', 'Could not update provider status'),
      });
    });
  }

  private toggleScheduledTaskEnabled(taskId: string, enabled: boolean): void {
    const client = this.client;
    if (!client || !this.connected) return;
    void client.setScheduledTaskEnabled(taskId, enabled).then(() => client.listScheduledTasks()).then((next) => {
      this.scheduledTasksList = next;
    }).catch((error: Error) => {
      this.getUIContext().getPromptAction().showToast({
        message: error.message || this.copy('无法切换定时任务', 'Could not toggle scheduled task'),
      });
    });
  }

  private runScheduledTaskNow(taskId: string): void {
    const client = this.client;
    if (!client || !this.connected) return;
    void client.runScheduledTaskNow(taskId).then(() => {
      this.getUIContext().getPromptAction().showToast({
        message: this.copy('已触发定时任务运行', 'Scheduled task triggered'),
      });
      return client.listScheduledTasks();
    }).then((next) => {
      this.scheduledTasksList = next;
    }).catch((error: Error) => {
      this.getUIContext().getPromptAction().showToast({
        message: error.message || this.copy('无法运行定时任务', 'Could not run scheduled task'),
      });
    });
  }

  private copyDiagnosticsReport(report: string): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, report);
      void pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.getUIContext().getPromptAction().showToast({
          message: this.copy('已复制诊断报告', 'Diagnostics report copied'),
        });
      });
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({
        message: this.copy('无法访问剪贴板', 'Clipboard unavailable'),
      });
    }
  }

  private openSettingsPage(page: WorkspaceSettingsPage): void {
    this.rememberSettingsScroll();
    this.settingsPages = this.settingsPages.concat([page]);
    void this.loadEnvironmentSettingsSection(page);
  }

  private selectWorkspaceTab(selection: WorkspaceTab): void {
    if (selection === this.workspaceTab) return;
    this.rememberSettingsScroll();
    if (this.workspaceTab === 'threads') this.rememberWorkspaceScroll();
    this.closeWorkspaceDataDetails();
    if (selection === 'pullRequests' || selection === 'issues') this.workspaceSharedTab = selection;
    this.workspaceTab = selection;
  }

  private rememberWorkspaceScroll(): void {
    this.workspaceScrollOffset = this.workspaceScroller.currentOffset()?.yOffset ?? 0;
  }

  private workspaceFilterGroups(forSettings: boolean): WorkspaceFilterGroup[] {
    const environmentId = forSettings ? this.settingsEnvironmentFilter : this.workspaceEnvironmentFilter;
    const projectKey = forSettings ? this.settingsProjectFilter : this.projectFilter;
    const rows = this.visibleEnvironmentRows();
    const environment = rows.find((row: EnvironmentSummary) => row.environmentId === environmentId && row.enabled);
    const environments: WorkspaceFilterOption[] = [{
      key: 'environment:', label: this.copy('所有环境', 'All environments'), selected: !environment,
    }];
    for (const row of rows) {
      if (row.enabled) environments.push({
        key: 'environment:' + row.environmentId, label: row.label, selected: row === environment,
      });
    }
    const projects: WorkspaceFilterOption[] = [{
      key: 'project:', label: this.copy('所有项目', 'All projects'), selected: projectKey.length === 0,
    }];
    for (const project of this.threadProjects) projects.push({
      key: 'project:' + project.key, label: project.title,
      selected: project.key === projectKey,
      enabled: !forSettings || !environment || project.environmentKey === environment.key,
    });
    return [
      { label: this.copy('环境', 'Environment'), options: environments },
      { label: this.copy('项目', 'Project'), options: projects },
    ];
  }

  private selectWorkspaceFilter(key: string, forSettings: boolean): void {
    if (key.startsWith('project:')) {
      const value = key.slice('project:'.length);
      if (forSettings) this.settingsProjectFilter = value;
      else if (this.projectFilter !== value) {
        this.projectFilter = value;
        this.workspaceScroller.scrollEdge(Edge.Top);
        this.updateThreadResults();
      }
    } else if (key.startsWith('environment:')) {
      const value = key.slice('environment:'.length);
      if (forSettings) {
        this.settingsEnvironmentFilter = value;
        this.settingsProjectFilter = '';
      } else if (this.workspaceEnvironmentFilter !== value) {
        this.workspaceEnvironmentFilter = value;
        this.projectFilter = '';
        this.threadSearchMatches = new Map();
        this.workspaceScroller.scrollEdge(Edge.Top);
        this.updateThreadResults();
        this.scheduleThreadSearch();
        void this.refreshThreads(true);
      }
    }
  }

  private settingsEnvironment(): EnvironmentSummary | undefined {
    return this.visibleEnvironmentRows().find((environment: EnvironmentSummary) =>
      environment.enabled && environment.environmentId === this.settingsEnvironmentFilter) ??
      this.client?.currentEnvironment();
  }

  private workspaceDataQuery(): string {
    if (this.workspaceTab === 'pullRequests') return this.pullRequestsQuery;
    return this.workspaceTab === 'issues' ? this.issuesQuery : '';
  }

  private workspaceDataSearchOpen(): boolean {
    if (this.workspaceTab === 'pullRequests') return this.pullRequestsSearchOpen;
    return this.workspaceTab === 'issues' && this.issuesSearchOpen;
  }

  private openWorkspaceDataSearch(): void {
    if (this.workspaceTab === 'pullRequests') this.pullRequestsSearchOpen = true;
    if (this.workspaceTab === 'issues') this.issuesSearchOpen = true;
  }

  private setWorkspaceDataQuery(query: string): void {
    if (this.workspaceTab === 'pullRequests') this.pullRequestsQuery = query;
    if (this.workspaceTab === 'issues') this.issuesQuery = query;
  }

  private closeWorkspaceDataSearch(): void {
    this.setWorkspaceDataQuery('');
    if (this.workspaceTab === 'pullRequests') this.pullRequestsSearchOpen = false;
    if (this.workspaceTab === 'issues') this.issuesSearchOpen = false;
  }

  private applyWorkspaceDataQuery(key: string, tab: WorkspaceSharedTab, query: string): void {
    if (this.environmentKey !== key || this.workspaceTab !== tab) return;
    if (!query) {
      this.closeWorkspaceDataSearch();
      return;
    }
    this.openWorkspaceDataSearch();
    this.setWorkspaceDataQuery(query);
  }

  private workspaceDataClient(key: string): T3Client {
    const client = this.client;
    if (!client || !key || client.currentEnvironment()?.key !== key) throw new Error('环境连接已更换。');
    return client;
  }

  private workspaceDataDetailsOpen(): boolean {
    return (this.workspaceTab === 'pullRequests' && this.workspacePullRequest !== undefined) ||
      (this.workspaceTab === 'issues' && this.workspaceIssue !== undefined) ||
      (this.workspaceTab === 'usage' && this.workspaceUsageAccount !== undefined);
  }

  private closeWorkspaceDataDetails(): void {
    this.workspaceSourceControlPermissionRequest++;
    this.workspaceDetailEnvironmentKey = '';
    this.workspacePullRequest = undefined;
    this.workspaceIssue = undefined;
    this.workspaceSourceControlCanWrite = false;
    this.workspaceUsageAccount = undefined;
    this.workspaceUsageWindow = undefined;
  }

  private async refreshWorkspaceSourceControlPermissions(key: string): Promise<void> {
    this.workspaceSourceControlCanWrite = false;
    const request = ++this.workspaceSourceControlPermissionRequest;
    try {
      const canWrite = await this.workspaceDataClient(key).canWriteWorkspaceSourceControl();
      if (this.workspaceSourceControlPermissionRequest === request) this.workspaceSourceControlCanWrite = canWrite;
    } catch {
      // Write actions require a confirmed grant from the target environment.
    }
  }

  private openEnvironments(): void {
    if (this.pairing || this.sending) return;
    this.closeEnvironmentDetails();
    this.showPairing = true;
    this.addingEnvironment = false;
    void this.loadEnvironments().catch((error: Error) => {
      this.pairError = errorMessage(error, '无法读取已配对环境');
    });
    void this.loadRelayEnvironments();
    void this.refreshDeviceApprovalAccess();
  }

  private openActiveEnvironmentDetails(): void {
    const active = this.settingsEnvironment();
    if (!active || this.pairing || this.sending) return;
    this.openEnvironments();
    this.environmentDetails = active;
    this.environmentDetailsFromSettings = true;
    void this.refreshLinkedEnvironmentHealth();
    void this.refreshEnvironmentMaintenance();
  }

  private isWorkspaceRoot(): boolean {
    return !this.restoring && !this.selected && !this.showPairing && !this.showAccount &&
      !this.showApprovals && !this.approvalEnvironmentId && !this.showThreadLaunch &&
      !this.showArchivedThreads && !this.threadListActionTarget && !this.showProjects;
  }

  private async loadProjects(): Promise<ProjectManagementSnapshot> {
    if (!this.client || !this.showProjects || !this.connected) throw new Error('请先连接环境。');
    return this.client.projectManagementSnapshot();
  }

  private async changeProject(change: ProjectManagementChange): Promise<NativeManagedProject> {
    const addingFromLaunch = change.action === 'add' && this.projectWizardOrigin === 'launch';
    if (!this.client || (!this.showProjects && !addingFromLaunch) || !this.connected || this.pairing ||
      this.projectMutationBusy) {
      throw new Error('当前环境无法更新项目。');
    }
    this.projectMutationBusy = true;
    try {
      return await this.client.changeProject(change);
    } finally {
      this.projectMutationBusy = false;
      this.showIncomingPairing();
    }
  }

  private openProjectWizard(origin: 'launch' | 'projects'): void {
    const environment = this.client?.currentEnvironment();
    if (!environment || environment.key !== this.environmentKey || this.projectMutationBusy || this.pairing ||
      (origin === 'launch' && (!this.showThreadLaunch || !this.threadListCanWrite ||
        this.threadLaunchEnvironmentKey !== environment.key)) || (origin === 'projects' && !this.showProjects)) return;
    this.projectWizardEnvironmentKey = environment.key;
    this.projectWizardError = '';
    this.projectWizardOrigin = origin;
  }

  private closeProjectWizard(): void {
    this.projectWizardOrigin = '';
    this.projectWizardError = '';
    this.projectWizardEnvironmentKey = '';
  }

  private async browseProjectWizardFolders(path: string): Promise<NativeProjectFolderListing> {
    const client = this.client;
    if (!client || !this.projectWizardOrigin || client.currentEnvironment()?.key !== this.projectWizardEnvironmentKey) {
      throw new Error('环境连接已更换，请返回后重新选择目录。');
    }
    return client.browseProjectFolders(path);
  }

  private async addProjectWizardFolder(path: string): Promise<void> {
    const origin = this.projectWizardOrigin;
    const environmentKey = this.projectWizardEnvironmentKey;
    if (!origin || this.projectMutationBusy || this.client?.currentEnvironment()?.key !== environmentKey) return;
    this.projectWizardError = '';
    try {
      const project = await this.changeProject({ action: 'add', value: path });
      if (this.projectWizardOrigin !== origin || this.client?.currentEnvironment()?.key !== environmentKey) return;
      this.closeProjectWizard();
      if (origin === 'launch') {
        this.threadLaunchAddedProjectId = project.id;
        void this.loadThreadLaunch();
      } else {
        this.projectManagementAddedId = project.id;
      }
      void this.refreshThreads(true);
    } catch (error) {
      if (this.projectWizardOrigin === origin && this.projectWizardEnvironmentKey === environmentKey) {
        this.projectWizardError = errorMessage(error as Error, this.copy('无法添加项目', 'Could not add the project'));
      }
    }
  }

  private accountSettingValue(): string {
    if (!this.accountConfigured) return this.copy('未配置', 'Not configured');
    if (this.accountIdentity) {
      return this.accountIdentity.email || this.accountIdentity.displayName || this.copy('已登录', 'Signed in');
    }
    return this.accountBusy ? this.copy('正在检查…', 'Checking…') : this.copy('登录', 'Sign in');
  }

  private async loadThreadLaunch(): Promise<void> {
    const client = this.client;
    const activeKey = client?.currentEnvironment()?.key;
    if (!client || !activeKey || this.loadingThreadLaunch || !this.connected || !this.threadListCanWrite) return;
    if (this.showThreadLaunch && this.threadLaunchEnvironmentKey !== activeKey) return;
    this.threadLaunchEnvironmentKey = activeKey;
    this.showThreadLaunch = true;
    this.loadingThreadLaunch = true;
    this.threadLaunchError = '';
    const generation = ++this.threadLaunchGeneration;
    void client.threadPermissions().then((permissions) => {
      if (generation !== this.threadLaunchGeneration) return;
      this.threadLaunchCanWriteGit = permissions.gitWrite;
      this.threadLaunchCanOpenScratch = permissions.operate;
      this.threadLaunchCanReadFiles = permissions.readFiles;
    }).catch(() => {
      if (generation !== this.threadLaunchGeneration) return;
      this.threadLaunchCanWriteGit = false;
      this.threadLaunchCanOpenScratch = false;
      this.threadLaunchCanReadFiles = false;
    });
    try {
      const options = await client.threadLaunchOptions();
      if (generation === this.threadLaunchGeneration && activeKey === client.currentEnvironment()?.key) {
        this.threadLaunchOptions = options;
      }
    } catch (error) {
      if (generation === this.threadLaunchGeneration) {
        this.threadLaunchError = errorMessage(error as Error, '无法加载项目和模型');
      }
    } finally {
      if (generation === this.threadLaunchGeneration) this.loadingThreadLaunch = false;
    }
  }

  private closeThreadLaunch(): void {
    this.closeProjectWizard();
    this.threadLaunchGeneration++;
    this.showThreadLaunch = false;
    this.loadingThreadLaunch = false;
    this.threadLaunchOptions = undefined;
    this.threadLaunchError = '';
    this.threadLaunchCanWriteGit = false;
    this.threadLaunchCanReadFiles = false;
    this.threadLaunchEnvironmentKey = '';
    this.threadLaunchScratchRoot = '';
    this.threadLaunchWorktreeRoots.clear();
    this.threadLaunchAddedProjectId = '';
    this.threadLaunchCanOpenScratch = false;
    this.threadLaunchAttempt = undefined;
    this.threadLaunchFingerprint = '';
    this.threadLaunchAttachments = [];
    this.threadLaunchUploaded = undefined;
    this.pickingLaunchAttachments = false;
  }

  private async pickLaunchAttachments(photos: boolean): Promise<void> {
    const context = this.context;
    const remaining = MAX_THREAD_ATTACHMENTS - this.threadLaunchAttachments.length;
    if (!context || !this.showThreadLaunch || this.pickingLaunchAttachments || this.creatingThread || remaining <= 0) return;
    const generation = this.threadLaunchGeneration;
    const picker = new NativeThreadAttachments(context);
    this.pickingLaunchAttachments = true;
    this.threadLaunchError = '';
    try {
      const picked = await (photos ? picker.pickPhotos(remaining) : picker.pickDocuments(remaining));
      if (generation !== this.threadLaunchGeneration) return;
      const unique = new Map<string, PickedThreadAttachment>();
      for (const attachment of this.threadLaunchAttachments.concat(picked)) unique.set(attachment.uri, attachment);
      this.threadLaunchAttachments = Array.from(unique.values());
    } catch (error) {
      if (generation === this.threadLaunchGeneration) {
        this.threadLaunchError = errorMessage(error as Error, '无法添加附件');
      }
    } finally {
      if (generation === this.threadLaunchGeneration) this.pickingLaunchAttachments = false;
    }
  }

  private async launchThread(project: ThreadLaunchProject, model: ThreadLaunchSelection, text: string,
    mode: ThreadLaunchRuntimeMode, workspace: ThreadLaunchWorkspaceStrategy,
    records: ComposerCommandContextRecord[]): Promise<void> {
    const client = this.client;
    if (!client || !this.threadListCanWrite || this.pickingLaunchAttachments || this.creatingThread || this.pairing) return;
    if (text.length > MAX_MESSAGE_CHARS) {
      this.threadLaunchError = '消息太长，请缩短后再发送。';
      return;
    }
    const environmentKey = this.threadLaunchEnvironmentKey;
    if (client.currentEnvironment()?.key !== environmentKey) {
      this.threadLaunchError = '环境连接已更换，请返回后重新打开新建会话。';
      return;
    }
    const attachments = this.threadLaunchAttachments;
    const fingerprint = JSON.stringify([environmentKey, project.id, model.instanceId, model.model, text, mode,
      attachments, workspace, records]);
    if (!this.threadLaunchAttempt || fingerprint !== this.threadLaunchFingerprint) {
      this.threadLaunchAttempt = createThreadLaunchAttempt();
      this.threadLaunchFingerprint = fingerprint;
      this.threadLaunchUploaded = undefined;
    }
    this.creatingThread = true;
    this.threadLaunchError = '';
    try {
      if (!(await client.threadPermissions()).operate || client.currentEnvironment()?.key !== environmentKey) {
        throw new Error('此连接没有创建会话的权限。');
      }
      if (!this.threadLaunchUploaded) this.threadLaunchUploaded = await this.uploadDraftAttachments(client, attachments);
      if (client.currentEnvironment()?.key !== environmentKey) throw new Error('环境连接已更换，请核对附件后重试。');
      const thread = await client.launchThread(this.threadLaunchAttempt, project, model, text, mode, this.threadLaunchUploaded,
        workspace, records.length > 0 ? { version: 1, records } : undefined);
      this.closeThreadLaunch();
      this.openThread(thread);
      void this.refreshThreads();
    } catch (error) {
      this.threadLaunchError = errorMessage(error as Error, '新建会话失败');
    } finally {
      this.creatingThread = false;
      this.showIncomingPairing();
    }
  }

  private async openLaunchScratch(workspaceRoot: string): Promise<ThreadLaunchScratch> {
    const client = this.client;
    if (!client || client.currentEnvironment()?.key !== this.threadLaunchEnvironmentKey || !this.showThreadLaunch ||
      !this.threadLaunchCanOpenScratch || this.threadLaunchWorkspaceBusy ||
      !workspaceRoot || workspaceRoot !== this.threadLaunchOptions?.scratchWorkspaceRoot) {
      throw new Error('当前环境无法准备无项目会话。');
    }
    this.threadLaunchWorkspaceBusy = true;
    try {
      const scratch = await client.openLaunchScratch(workspaceRoot);
      this.threadLaunchScratchRoot = scratch.project.workspaceRoot;
      return scratch;
    } finally {
      this.threadLaunchWorkspaceBusy = false;
      this.showIncomingPairing();
    }
  }

  private async switchLaunchRef(cwd: string, refName: string): Promise<string | null> {
    const client = this.client;
    if (!client || client.currentEnvironment()?.key !== this.threadLaunchEnvironmentKey || !this.showThreadLaunch ||
      !this.threadLaunchCanWriteGit || this.threadLaunchWorkspaceBusy ||
      !this.threadLaunchOptions?.projects.some((project) => project.workspaceRoot === cwd)) {
      throw new Error('当前工作区无法切换分支。');
    }
    this.threadLaunchWorkspaceBusy = true;
    try {
      return await client.switchThreadLaunchRef(cwd, refName);
    } finally {
      this.threadLaunchWorkspaceBusy = false;
      this.showIncomingPairing();
    }
  }

  private async loadLaunchRefs(cwd: string, query: string, cursor: number | null, kind: ThreadGitRefKind,
    refresh: boolean): Promise<NativeThreadGitRefs> {
    const client = this.client;
    if (!client || client.currentEnvironment()?.key !== this.threadLaunchEnvironmentKey ||
      !this.showThreadLaunch || !this.threadLaunchOptions?.projects.some(
      (project) => project.workspaceRoot === cwd)) throw new Error('当前项目无法读取 Git 分支。');
    const generation = this.threadLaunchGeneration;
    const refs = await client.listThreadGitRefs(cwd, query, cursor, kind, refresh);
    if (generation === this.threadLaunchGeneration && client.currentEnvironment()?.key === this.threadLaunchEnvironmentKey) {
      for (const ref of refs.refs) {
        if (ref.worktreePath) this.threadLaunchWorktreeRoots.add(ref.worktreePath);
      }
    }
    return refs;
  }

  private async loadLaunchWorkspaceProviders(projectId: string, cwd: string): Promise<ThreadLaunchProvider[]> {
    if (!this.client || this.client.currentEnvironment()?.key !== this.threadLaunchEnvironmentKey ||
      !this.showThreadLaunch || !this.threadLaunchOptions?.projects.some(
      (project) => project.id === projectId)) throw new Error(this.copy('当前工作区无法读取可用模型。', 'Could not read models in this workspace.'));
    return this.client.threadModelProviders(projectId, cwd);
  }

  private launchFileClient(cwd: string): T3Client {
    const client = this.client;
    if (!client || client.currentEnvironment()?.key !== this.threadLaunchEnvironmentKey || !this.showThreadLaunch ||
      !this.threadLaunchCanReadFiles || !cwd || (cwd !== this.threadLaunchScratchRoot && !this.threadLaunchWorktreeRoots.has(cwd) &&
        !this.threadLaunchOptions?.projects.some((project) => project.workspaceRoot === cwd))) {
      throw new Error(this.copy('当前工作区无法读取文件。', 'Could not read files in this workspace.'));
    }
    return client;
  }

  private openThread(thread: NativeThread): void {
    this.threadViewGeneration++;
    this.closeAttachmentPreview();
    this.closeLinkedThreadView();
    this.closeThreadAgents();
    this.closeBackgroundWork();
    this.citationPreview = undefined;
    this.pendingMessageJump = '';
    this.closeThreadFiles();
    this.closeThreadGit();
    this.leaveThreadTerminal();
    this.threadCanWriteGit = false;
    this.threadCanReadTerminal = false;
    this.threadCanOperateTerminal = false;
    this.closeThreadModel();
    this.clearThreadHistory();
    this.firstVisibleThreadIndex = -1;
    this.resumeThreadIndex = -1;
    this.selected = thread;
    this.backgroundTasks = thread.pendingBackgroundTasks ?? [];
    this.backgroundLatestRunId = thread.latestRunId ?? '';
    this.backgroundStopping = this.backgroundStopRequests.has(this.backgroundWorkKey(thread.id));
    this.watchBackgroundTasks();
    this.updateSideChats();
    this.messageCount = 0;
    this.expandedMessages = [];
    this.expandedCodeBlocks = new Map<string, number[]>();
    this.workOutput = new Map<string, string>();
    this.loadingWork = [];
    this.threadDetail = undefined;
    this.threadActionBusy = false;
    this.messages.replace([]);
    this.draft = this.drafts.get(this.environmentKey)?.get(thread.id) ?? '';
    this.draftAttachments = this.attachmentDrafts.get(this.environmentKey)?.get(thread.id) ?? [];
    this.draftQuotes = this.quoteDrafts.get(this.environmentKey)?.get(thread.id) ?? [];
    this.draftTerminalContexts = this.terminalContextDrafts.get(this.environmentKey)?.get(thread.id) ?? [];
    this.threadModelDraft = this.modelDrafts.get(this.environmentKey)?.get(thread.id);
    this.threadRuntimeDraft = this.runtimeDrafts.get(this.environmentKey)?.get(thread.id);
    this.sendError = '';
    this.watchThread();
  }

  private stopWatching(): void {
    this.watchGeneration++;
    this.unsubscribe?.();
    this.unsubscribe = undefined;
  }

  private closeThread(): void {
    this.threadViewGeneration++;
    this.closeAttachmentPreview();
    this.closeLinkedThreadView();
    this.linkedDirectReturn = undefined;
    this.closeThreadAgents();
    this.closeBackgroundWork();
    this.stopBackgroundWatch();
    this.backgroundTasks = [];
    this.backgroundLatestRunId = '';
    this.backgroundStopping = false;
    this.threadReturnPoints.clear();
    this.citationPreview = undefined;
    this.pendingMessageJump = '';
    this.closeThreadFiles();
    this.closeThreadGit();
    this.leaveThreadTerminal();
    this.closeThreadModel();
    this.clearThreadHistory();
    this.stopWatching();
    this.selected = undefined;
    this.sideChats = [];
  }

  private watchThread(): void {
    const client = this.client;
    const thread = this.selected;
    if (!client || !thread) return;
    this.stopWatching();
    const generation = this.watchGeneration;
    this.watchError = '';
    this.threadReconnecting = false;
    this.loadingMessages = this.messageCount === 0;
    void this.refreshThreadPermissions(client, generation);
    this.unsubscribe = client.watchThread(thread.id,
      (messages: NativeMessage[], detail: NativeThreadDetail, historyCursor?: string) => {
      if (this.watchGeneration !== generation) return;
      const followLatest = !this.showThreadFiles && !this.showThreadGit && !this.showThreadReview &&
        !this.showThreadTerminal && !this.previewAttachment &&
        (this.messageCount === 0 ? this.resumeThreadIndex < 0 : this.messageScroller.isAtEnd());
      if (historyCursor !== this.historySnapshotCursor) {
        if (this.historyMessages.length > 0 || this.historyWork.size > 0) {
          this.historyMessages = mergeMessages(this.historyMessages, this.recentMessages);
          for (const row of this.recentWork) this.historyWork.set(row.id, row);
          this.historyActivityIds = Array.from(new Set(this.historyActivityIds.concat(this.recentActivityIds)));
        }
        this.historyRequest++;
        this.historySnapshotCursor = historyCursor;
        this.historyCursor = historyCursor;
        this.historyBusy = false;
        this.historyError = '';
      }
      this.recentMessages = messages;
      this.recentWork = detail.work;
      this.recentActivityIds = detail.activityIds;
      this.recentCheckpoints = detail.checkpoints;
      const changed = this.updateThreadFeed();
      const previous = this.threadDetail;
      const previousCwd = this.threadFilesCwd();
      if (!previous || previous.title !== detail.title || previous.modelLabel !== detail.modelLabel ||
        !threadModelSelectionsEqual(previous.modelSelection, detail.modelSelection) ||
        previous.runtimeMode !== detail.runtimeMode ||
        previous.canSwitchProvider !== detail.canSwitchProvider ||
        previous.worktreePath !== detail.worktreePath ||
        previous.runBusy !== detail.runBusy || previous.activeRunId !== detail.activeRunId ||
        previous.queuedCount !== detail.queuedCount || previous.queueHeld !== detail.queueHeld ||
        previous.queuedMessages !== detail.queuedMessages || previous.queueEditBlocked !== detail.queueEditBlocked ||
        previous.approval !== detail.approval || previous.userInput !== detail.userInput ||
        previous.subagents !== detail.subagents || previous.backgroundStopRunId !== detail.backgroundStopRunId ||
        previous.backgroundStopWatches !== detail.backgroundStopWatches) {
        this.threadDetail = detail;
      }
      if (this.threadModelDraft && threadModelSelectionsEqual(this.threadModelDraft, detail.modelSelection)) {
        this.setThreadModelDraft();
      }
      if (this.showThreadFiles && previousCwd !== this.threadFilesCwd()) {
        this.filesEntries = [];
        void this.loadThreadDirectory('');
      }
      if (this.showThreadModel && previousCwd !== this.threadFilesCwd()) this.closeThreadModel();
      if (this.showThreadGit && previousCwd !== this.threadFilesCwd()) {
        this.threadGitStatus = undefined;
        void this.loadThreadGit();
      }
      this.loadingMessages = false;
      this.watchError = '';
      if (this.threadReconnecting || this.threadAccess === 'failed') {
        this.threadReconnecting = false;
        void this.refreshThreadPermissions(client, generation);
      }
      if (this.pendingMessageJump) {
        const messageId = this.pendingMessageJump;
        this.pendingMessageJump = '';
        void this.jumpToThreadMessage(messageId);
      } else if (changed && followLatest && messages.length > 0) {
        this.getUIContext().postFrameCallback(new AfterLayout(() => {
          if (this.watchGeneration === generation && !this.showThreadFiles && !this.showThreadGit && !this.showThreadReview &&
            !this.showThreadTerminal && this.messageCount > 0) {
            this.messageScroller.scrollToIndex(this.lastThreadFeedIndex(), false, ScrollAlign.END);
          }
        }));
      }
    }, (error: Error, reconnecting: boolean) => {
      if (this.watchGeneration !== generation) return;
      if (this.handleExpiredAccount(error)) return;
      if (this.showApprovalError(error)) {
        this.stopWatching();
        reconnecting = false;
      }
      this.loadingMessages = false;
      this.threadReconnecting = reconnecting;
      this.watchError = errorMessage(error, '无法更新消息');
    });
  }

  private clearThreadHistory(): void {
    this.historyRequest++;
    this.historySnapshotCursor = undefined;
    this.historyCursor = undefined;
    this.historyBusy = false;
    this.historyError = '';
    this.historyMessages = [];
    this.historyWork.clear();
    this.historyActivityIds = [];
    this.recentActivityIds = [];
    this.lastAssistantFeedId = '';
    this.recentMessages = [];
    this.recentWork = [];
    this.recentCheckpoints = [];
  }

  private threadHistoryHeaderSize(): number {
    return this.historyCursor === undefined ? 0 : 1;
  }

  private updateThreadFeed(): boolean {
    const messages = this.historyMessages.length === 0 ? this.recentMessages :
      mergeMessages(this.historyMessages, this.recentMessages);
    const work = new Map(this.historyWork);
    for (const row of this.recentWork) work.set(row.id, row);
    const activityIds = this.historyActivityIds.concat(this.recentActivityIds);
    const changed = this.messages.update(messages, Array.from(work.values()), this.recentCheckpoints, activityIds);
    this.messageCount = this.messages.totalCount();
    for (let index = this.messageCount - 1; index >= 0; index--) {
      const entry = this.messages.getData(index);
      if (entry?.message?.role === 'assistant') {
        this.lastAssistantFeedId = entry.message.streaming === true ? '' : entry.id;
        return changed;
      }
    }
    this.lastAssistantFeedId = '';
    return changed;
  }

  private async jumpToThreadMessage(messageId: string): Promise<void> {
    const generation = this.threadViewGeneration;
    const rowId = 'message:' + messageId;
    let index = this.messages.indexOfId(rowId);
    while (generation === this.threadViewGeneration && index < 0 && this.historyCursor) {
      const cursor = this.historyCursor;
      await this.loadOlderThreadHistory(messageId);
      index = this.messages.indexOfId(rowId);
      if (cursor === this.historyCursor) break;
    }
    if (generation !== this.threadViewGeneration) return;
    if (index < 0) {
      this.getUIContext().getPromptAction().showToast({ message: this.historyError || '未能定位这条历史消息。' });
      return;
    }
    this.getUIContext().postFrameCallback(new AfterLayout(() => {
      if (generation !== this.threadViewGeneration) return;
      const index = this.messages.indexOfId(rowId);
      if (index >= 0) this.messageScroller.scrollToIndex(index + this.threadHistoryHeaderSize(), false, ScrollAlign.CENTER);
    }));
  }

  private openCitation(citation: NativeThreadCitation): void {
    if (this.pairing || this.sending || this.creatingThread || this.threadActionBusy || !this.selected) return;
    this.citationPreview = citation;
  }

  private jumpToCitation(citation: NativeThreadCitation): void {
    if (this.pairing || this.sending || this.creatingThread || this.threadActionBusy || !this.selected) return;
    const uri = `t3code://threads/${encodeURIComponent(citation.environmentId)}/${encodeURIComponent(citation.threadId)}`;
    void this.openLinkedThread(citation.environmentId, citation.threadId, uri, citation.messageId);
  }

  private closeAttachmentPreview(): void {
    this.previewRequest?.cancel();
    this.previewRequest = undefined;
    void removeThreadAttachmentPreview(this.previewContent?.uri);
    this.previewContent = undefined;
    this.previewAttachment = undefined;
    this.previewAttachmentError = '';
    this.previewAttachmentLoading = false;
    this.previewGallery = [];
    this.clearAttachmentAction();
  }

  private clearAttachmentAction(): void {
    this.previewActionRequest?.cancel();
    this.previewActionRequest = undefined;
    void removeThreadAttachmentPreview(this.previewActionUri);
    this.previewActionUri = undefined;
    this.previewActionBusy = false;
  }

  private openThreadAttachment(message: NativeMessage, attachment: NativeThreadAttachment): void {
    if (!this.selected || message.threadId !== this.selected.id || this.pairing) return;
    this.getUIContext().getFocusController().clearFocus();
    this.previewGallery = message.attachments?.filter((item: NativeThreadAttachment) =>
      threadAttachmentPreviewKind(item) === 'image') ?? [];
    void this.loadAttachmentPreview(attachment);
  }

  private async loadAttachmentPreview(attachment: NativeThreadAttachment): Promise<void> {
    this.clearAttachmentAction();
    this.previewRequest?.cancel();
    this.previewRequest = undefined;
    void removeThreadAttachmentPreview(this.previewContent?.uri);
    this.previewContent = undefined;
    this.previewAttachment = attachment;
    this.previewAttachmentError = '';
    this.previewAttachmentLoading = false;
    const fullFile = isPdfThreadAttachment(attachment) || isVideoThreadAttachment(attachment);
    if (threadAttachmentPreviewKind(attachment) === 'file' && !isTextThreadAttachment(attachment) && !fullFile) return;
    const client = this.client;
    const environmentKey = this.environmentKey;
    const cacheDir = this.context?.cacheDir;
    if (!client || !cacheDir || !environmentKey) {
      this.previewAttachmentError = '请重新连接此环境后重试。';
      return;
    }
    const request = new NativeThreadAttachmentPreviewRequest();
    this.previewRequest = request;
    this.previewAttachmentLoading = true;
    try {
      const asset = await client.createThreadAttachmentAssetUrl(environmentKey, attachment);
      if (request !== this.previewRequest || environmentKey !== this.environmentKey) return;
      const content = await request.read(asset, attachment, cacheDir, fullFile);
      if (request !== this.previewRequest || environmentKey !== this.environmentKey) {
        void removeThreadAttachmentPreview(content.uri);
        return;
      }
      this.previewContent = content;
    } catch (error) {
      if (request === this.previewRequest) {
        this.previewAttachmentError = errorMessage(error as Error, '无法读取附件，请重试。');
      }
    } finally {
      if (request === this.previewRequest) this.previewAttachmentLoading = false;
    }
  }

  private adjacentPreviewAttachment(offset: number): NativeThreadAttachment | undefined {
    const index = this.previewGallery.findIndex((item: NativeThreadAttachment) => item.id === this.previewAttachment?.id);
    return index >= 0 ? this.previewGallery[index + offset] : undefined;
  }

  private retryAttachmentPreview(): void {
    if (this.previewAttachment) void this.loadAttachmentPreview(this.previewAttachment);
  }

  private stepAttachmentPreview(offset: number): void {
    if (this.previewActionBusy) return;
    const next = this.adjacentPreviewAttachment(offset);
    if (next) void this.loadAttachmentPreview(next);
  }

  private async runAttachmentAction(action: 'open' | 'share' | 'save'): Promise<void> {
    const attachment = this.previewAttachment;
    const client = this.client;
    const context = this.context;
    const environmentKey = this.environmentKey;
    if (!attachment || !client || !context || !environmentKey || this.previewActionBusy ||
      attachment.sizeBytes > MAX_ATTACHMENT_ACTION_BYTES) return;
    this.previewActionBusy = true;
    const request = new NativeThreadAttachmentPreviewRequest();
    this.previewActionRequest = request;
    try {
      let uri = this.previewContent?.uri ?? this.previewActionUri;
      if (!uri) {
        const asset = await client.createThreadAttachmentAssetUrl(environmentKey, attachment);
        if (request !== this.previewActionRequest || environmentKey !== this.environmentKey) return;
        const file = await request.read(asset, attachment, context.cacheDir, true);
        if (request !== this.previewActionRequest || environmentKey !== this.environmentKey) {
          void removeThreadAttachmentPreview(file.uri);
          return;
        }
        uri = file.uri;
        this.previewActionUri = uri;
      }
      if (!uri) throw new Error('无法准备附件文件。');
      const file: ThreadAttachmentActionFile = { uri, name: attachment.name, mimeType: attachment.mimeType };
      if (action === 'open') await this.attachmentActions.open(context, file);
      else if (action === 'share') await this.attachmentActions.share(context, file);
      else if (await this.attachmentActions.saveImage(context, file)) {
        this.getUIContext().getPromptAction().showToast({ message: '已保存到图库' });
      }
    } catch (error) {
      if (request === this.previewActionRequest) {
        this.getUIContext().getPromptAction().showToast({ message: errorMessage(error as Error, '无法操作附件') });
      }
    } finally {
      if (request === this.previewActionRequest) this.previewActionBusy = false;
    }
  }

  private async loadOlderThreadHistory(throughEntryId?: string): Promise<void> {
    const cursor = this.historyCursor;
    const client = this.client;
    const thread = this.selected;
    if (!cursor || !client || !thread || this.historyBusy) return;
    const request = ++this.historyRequest;
    this.historyBusy = true;
    this.historyError = '';
    try {
      const page = await client.readOlderThreadHistory(thread.id, cursor, throughEntryId);
      if (request !== this.historyRequest) return;
      const anchorIndex = Math.max(1, this.firstVisibleThreadIndex);
      const anchorId = this.messages.getData(anchorIndex - 1)?.id;
      const anchorOffset = anchorId ? this.messageScroller.getItemRect(anchorIndex).y : 0;
      this.historyMessages = mergeMessages(page.messages, this.historyMessages);
      for (const row of readHistoricalThreadWork(page.visibleTurnItems)) this.historyWork.set(row.id, row);
      this.historyActivityIds = Array.from(new Set(readThreadActivityIds(page.visibleTurnItems)
        .concat(this.historyActivityIds)));
      this.updateThreadFeed();
      this.historyCursor = page.nextCursor;
      if (!throughEntryId && anchorId && page.nextCursor === undefined) {
        this.getUIContext().postFrameCallback(new AfterLayout(() => {
          if (request !== this.historyRequest || this.showThreadFiles || this.showThreadGit) return;
          const index = this.messages.indexOfId(anchorId);
          if (index >= 0) {
            this.messageScroller.scrollToIndex(index, false, ScrollAlign.START, {
              extraOffset: LengthMetrics.vp(-anchorOffset),
            });
          }
        }));
      }
    } catch (error) {
      if (request === this.historyRequest && !this.handleExpiredAccount(error as Error)) {
        this.historyError = errorMessage(error as Error, '无法加载更早的活动');
      }
    } finally {
      if (request === this.historyRequest) this.historyBusy = false;
    }
  }

  private async refreshThreadPermissions(client: T3Client, generation: number): Promise<void> {
    const request = ++this.threadPermissionsRequest;
    this.threadAccess = 'checking';
    this.threadCanReadFiles = false;
    try {
      const permissions: ThreadPermissions = await client.threadPermissions();
      if (this.watchGeneration !== generation || request !== this.threadPermissionsRequest) return;
      const terminalPermissionChanged = this.threadCanOperateTerminal !== permissions.terminalOperate;
      this.threadAccess = permissions.operate ? 'allowed' : 'read-only';
      this.threadCanReadFiles = permissions.readFiles;
      this.threadCanWriteGit = permissions.gitWrite;
      this.threadCanReadTerminal = permissions.terminalRead;
      this.threadCanOperateTerminal = permissions.terminalOperate;
      if (this.showThreadTerminal) {
        if (!permissions.terminalRead && !permissions.terminalOperate) this.leaveThreadTerminal();
        else if (terminalPermissionChanged && this.terminalId) this.attachThreadTerminal(this.terminalId);
      }
    } catch (error) {
      if (this.watchGeneration !== generation || request !== this.threadPermissionsRequest) return;
      if (!this.handleExpiredAccount(error as Error)) {
        this.threadAccess = 'failed';
        this.threadCanWriteGit = false;
        this.threadCanReadTerminal = false;
        this.threadCanOperateTerminal = false;
        if (this.showThreadTerminal) this.leaveThreadTerminal();
      }
    }
  }

  private changeDraft(value: string): void {
    this.draft = value;
    if (!this.selected) return;
    const commandContexts = this.commandContextDrafts.get(this.environmentKey);
    const records = commandContexts?.get(this.selected.id);
    if (records) commandContexts?.set(this.selected.id, referencedComposerCommandContext(value, records));
    let drafts = this.drafts.get(this.environmentKey);
    if (!drafts) {
      drafts = new Map<string, string>();
      this.drafts.set(this.environmentKey, drafts);
    }
    drafts.set(this.selected.id, value);
  }

  private canPickThreadComposerModel(): boolean {
    return this.threadAccess === 'allowed' && !!this.selected?.projectId &&
      this.threadDetail?.modelSelection !== undefined && !this.watchError && !this.sending;
  }

  private threadComposerScope(): NativeComposerScope | undefined {
    if (!this.selected || this.loadingMessages || this.watchError || this.sending || this.threadAccess !== 'allowed' ||
      this.threadDetail?.approval || this.threadDetail?.userInput) return undefined;
    return { environmentKey: this.environmentKey, threadId: this.selected.id, projectId: this.selected.projectId,
      cwd: this.threadFilesCwd() || undefined };
  }

  private addCommandContext(record: ComposerCommandContextRecord): boolean {
    const scope = this.threadComposerScope();
    const threadId = scope?.threadId;
    if (!scope || !threadId) return false;
    let drafts = this.commandContextDrafts.get(scope.environmentKey);
    if (!drafts) {
      drafts = new Map();
      this.commandContextDrafts.set(scope.environmentKey, drafts);
    }
    const records = drafts.get(threadId) ?? [];
    if (records.some((item: ComposerCommandContextRecord) => item.contextId === record.contextId)) return true;
    if (records.length + this.draftTerminalContexts.length >= COMPOSER_COMMAND_CONTEXT_MAX_RECORDS) {
      this.sendError = '上下文已满，请移除一些引用后重试。';
      return false;
    }
    drafts.set(threadId, records.concat([record]));
    return true;
  }

  private async readComposerSuggestions(scope: NativeComposerScope, provider: string, trigger: ComposerCommandTrigger,
    canPickModel: boolean, canCompact: boolean): Promise<ThreadComposerSuggestion[]> {
    const client = this.client;
    if (!client || client.currentEnvironment()?.key !== scope.environmentKey) return [];
    return readThreadComposerSuggestions(client, scope, provider, trigger, canPickModel, canCompact,
      this.allThreads, this.visibleEnvironmentRows());
  }

  private async send(queue: boolean = false): Promise<void> {
    const client = this.client;
    const thread = this.selected;
    const draft = this.draft;
    const quotes = this.draftQuotes;
    const terminalContexts = this.draftTerminalContexts;
    const commandContexts = referencedComposerCommandContext(draft,
      this.commandContextDrafts.get(this.environmentKey)?.get(thread?.id ?? '') ?? []);
    const records: Object[] = terminalContexts.map((record: ThreadTerminalContextRecord): Object => record);
    for (const record of commandContexts) records.push(record);
    const text = this.messageWithQuoteContext(draft, quotes, terminalContexts);
    const attachments = this.draftAttachments;
    if (!client || !thread || (!text.trim() && attachments.length === 0) || this.sending ||
      this.pickingAttachments || this.loadingMessages || this.watchError ||
      this.threadAccess !== 'allowed') return;
    const modelDraft = this.threadModelDraft;
    const storedModel = this.threadDetail?.modelSelection;
    const modelCwd = this.threadFilesCwd() || undefined;
    const runtimeDraft = this.threadRuntimeDraft;
    const runtimeMode = runtimeDraft === this.threadDetail?.runtimeMode ? undefined : runtimeDraft;
    if (modelDraft && modelDraft.instanceId !== this.threadDetail?.modelSelection?.instanceId &&
      this.threadDetail?.canSwitchProvider !== true) {
      this.sendError = '当前会话暂不能切换提供商，请重新选择模型。';
      return;
    }
    const drafts = this.drafts.get(this.environmentKey);
    const environmentKey = this.environmentKey;
    const attachmentDrafts = this.attachmentDrafts.get(environmentKey);
    const quoteDrafts = this.quoteDrafts.get(environmentKey);
    if (text.length > MAX_MESSAGE_CHARS) {
      this.sendError = '消息或引用太长，请缩短后再发送。';
      return;
    }
    this.sending = true;
    this.sendError = '';
    let pending = this.pendingThreadSends.get(environmentKey);
    if (!pending) {
      pending = new Map();
      this.pendingThreadSends.set(environmentKey, pending);
    }
    const fingerprint = JSON.stringify([text, modelDraft, attachments, records, runtimeDraft]);
    let submission = pending.get(thread.id);
    try {
      if (submission?.fingerprint !== fingerprint) {
        const modelSelection = await client.threadMessageModel(thread.projectId ?? '', modelCwd, modelDraft, storedModel);
        const uploaded = await this.uploadDraftAttachments(client, attachments);
        submission = { fingerprint, attempt: createThreadSendAttempt(), attachments: uploaded, queue, modelSelection };
        pending.set(thread.id, submission);
      }
      if (client.currentEnvironment()?.key !== environmentKey) throw new Error('环境连接已更换，请核对附件后重试。');
      await client.send(thread.id, text, submission.queue, submission.modelSelection, submission.attachments, submission.attempt,
        { version: 1, records }, runtimeMode);
      pending.delete(thread.id);
      this.commandContextDrafts.get(environmentKey)?.delete(thread.id);
      if (terminalContexts.length > 0) {
        this.terminalContextDrafts.get(environmentKey)?.delete(thread.id);
        if (this.environmentKey === environmentKey && this.selected?.id === thread.id) this.draftTerminalContexts = [];
      }
      if (attachments.length > 0) {
        attachmentDrafts?.delete(thread.id);
        if (this.environmentKey === environmentKey && this.selected?.id === thread.id) this.draftAttachments = [];
      }
      if (quotes.length > 0) {
        quoteDrafts?.delete(thread.id);
        if (this.environmentKey === environmentKey && this.selected?.id === thread.id) this.draftQuotes = [];
      }
      if (modelDraft) {
        this.modelDrafts.get(environmentKey)?.delete(thread.id);
        if (this.environmentKey === environmentKey && this.selected?.id === thread.id) this.threadModelDraft = undefined;
      }
      if (drafts?.get(thread.id) === draft) {
        drafts?.delete(thread.id);
        if (this.environmentKey === environmentKey && this.selected?.id === thread.id) this.draft = '';
      }
    } catch (error) {
      if (error instanceof ThreadCommandRejectedError && submission?.fingerprint === fingerprint) {
        pending.delete(thread.id);
        if (client.currentEnvironment()?.key === environmentKey && submission.attachments.length > 0 && this.context) {
          const uploader = new NativeThreadAttachments(this.context);
          const environment = client.bindThreadAttachmentEnvironment();
          await Promise.all(submission.attachments.map((attachment) =>
            uploader.deletePending(attachment.id, environment).catch(() => {})));
        }
      }
      if (this.environmentKey === environmentKey && this.selected?.id === thread.id) {
        if (!this.handleExpiredAccount(error as Error)) this.sendError = errorMessage(error as Error, '发送失败');
      }
    } finally {
      this.sending = false;
      this.showIncomingPairing();
    }
  }

  private addThreadQuote(messageId: string, selector: ThreadCitationSelector): void {
    const threadId = this.selected?.id;
    const environmentId = this.client?.currentEnvironment()?.environmentId;
    if (!threadId || !environmentId || this.threadAccess !== 'allowed' || this.watchError || this.sending ||
      !this.recentMessages.concat(this.historyMessages).some((message: NativeMessage) =>
        message.id === messageId && message.threadId === threadId && message.role === 'assistant')) return;
    const markup = serializeThreadCitation(environmentId, threadId, messageId, selector);
    if (!markup || this.draftQuotes.some((quote: DraftThreadQuote) => quote.markup === markup)) return;
    const quotes = this.draftQuotes.concat({ text: selector.text, markup });
    if (this.messageWithQuoteContext(this.draft, quotes, this.draftTerminalContexts).length > MAX_MESSAGE_CHARS) {
      this.sendError = '引用太长，请缩小选区后再试。';
      return;
    }
    this.setDraftQuotes(quotes);
  }

  private messageWithQuoteContext(draft: string, quotes: DraftThreadQuote[],
    terminalContexts: ThreadTerminalContextRecord[]): string {
    if (quotes.length === 0 && terminalContexts.length === 0) return draft;
    return [draft.trimEnd(), ...quotes.map((quote: DraftThreadQuote) => quote.markup),
      ...terminalContexts.map(threadTerminalContextReference)].filter(Boolean).join('\n\n');
  }

  private setDraftQuotes(quotes: DraftThreadQuote[]): void {
    const threadId = this.selected?.id;
    if (!threadId) return;
    this.draftQuotes = quotes;
    let drafts = this.quoteDrafts.get(this.environmentKey);
    if (!drafts) {
      drafts = new Map();
      this.quoteDrafts.set(this.environmentKey, drafts);
    }
    if (quotes.length > 0) drafts.set(threadId, quotes);
    else drafts.delete(threadId);
  }

  private setDraftTerminalContexts(records: ThreadTerminalContextRecord[]): void {
    const threadId = this.selected?.id;
    if (!threadId) return;
    this.draftTerminalContexts = records;
    let drafts = this.terminalContextDrafts.get(this.environmentKey);
    if (!drafts) {
      drafts = new Map();
      this.terminalContextDrafts.set(this.environmentKey, drafts);
    }
    if (records.length > 0) drafts.set(threadId, records);
    else drafts.delete(threadId);
  }

  private attachThreadTerminalOutput(selection: ThreadTerminalAttachment): boolean {
    if (!this.showThreadTerminal || !this.selected || selection.terminalId !== this.terminalId ||
      (!this.threadCanReadTerminal && !this.threadCanOperateTerminal) ||
      this.draftTerminalContexts.length + (this.commandContextDrafts.get(this.environmentKey)?.get(this.selected.id)?.length ?? 0) >=
      COMPOSER_COMMAND_CONTEXT_MAX_RECORDS) return false;
    try {
      const record = threadTerminalContextRecord(util.generateRandomUUID(), selection);
      const updated = this.draftTerminalContexts.concat([record]);
      if (JSON.stringify(updated).length > 16000000 ||
        this.messageWithQuoteContext(this.draft, this.draftQuotes, updated).length > MAX_MESSAGE_CHARS) return false;
      this.setDraftTerminalContexts(updated);
      this.leaveThreadTerminal();
      return true;
    } catch (_) {
      return false;
    }
  }

  private async pickThreadAttachments(photos: boolean): Promise<void> {
    const context = this.context;
    if (!context || !this.selected || this.pickingAttachments || this.sending || this.threadAccess !== 'allowed') return;
    const remaining = MAX_THREAD_ATTACHMENTS - this.draftAttachments.length;
    if (remaining <= 0) return;
    const generation = this.threadViewGeneration;
    const picker = new NativeThreadAttachments(context);
    this.pickingAttachments = true;
    this.sendError = '';
    try {
      const picked = await (photos ? picker.pickPhotos(remaining) : picker.pickDocuments(remaining));
      if (this.threadViewGeneration !== generation) return;
      const unique = new Map<string, PickedThreadAttachment>();
      for (const attachment of this.draftAttachments.concat(picked)) unique.set(attachment.uri, attachment);
      this.setDraftAttachments(Array.from(unique.values()));
    } catch (error) {
      if (this.threadViewGeneration === generation) this.sendError = errorMessage(error as Error, '无法添加附件');
    } finally {
      this.pickingAttachments = false;
    }
  }

  private setDraftAttachments(attachments: PickedThreadAttachment[]): void {
    const threadId = this.selected?.id;
    if (!threadId) return;
    this.draftAttachments = attachments;
    let drafts = this.attachmentDrafts.get(this.environmentKey);
    if (!drafts) {
      drafts = new Map();
      this.attachmentDrafts.set(this.environmentKey, drafts);
    }
    if (attachments.length > 0) drafts.set(threadId, attachments);
    else drafts.delete(threadId);
  }

  private async uploadDraftAttachments(client: T3Client,
    attachments: PickedThreadAttachment[]): Promise<UploadedThreadAttachment[]> {
    if (attachments.length === 0) return [];
    const imageBytes = attachments.reduce((total: number, attachment: PickedThreadAttachment): number =>
      total + (attachment.type === 'image' ? attachment.sizeBytes : 0), 0);
    if (imageBytes > 80 * 1024 * 1024) throw new Error('图片总大小超过 80 MB，请移除部分图片后再发送。');
    const context = this.context;
    if (!context) throw new Error('无法打开附件。');
    const uploader = new NativeThreadAttachments(context);
    const environment = client.bindThreadAttachmentEnvironment();
    const uploaded: UploadedThreadAttachment[] = [];
    try {
      for (const attachment of attachments) uploaded.push(await uploader.upload(attachment, environment));
      return uploaded;
    } catch (error) {
      await Promise.all(uploaded.map((attachment) => uploader.deletePending(attachment.id, environment).catch(() => {})));
      throw error as Error;
    }
  }

  private closeThreadModel(): void {
    this.threadModelRequest++;
    this.showThreadModel = false;
    this.showThreadRuntime = false;
    this.threadModelParameterId = '';
    this.threadModelPending = undefined;
    this.threadModelPendingPrompt = undefined;
    this.threadModelCatalog = undefined;
    this.threadModelCatalogCanWrite = false;
    this.threadModelProviders = [];
    this.threadRuntimeCeiling = undefined;
    this.threadModelLoading = false;
    this.threadModelApplying = false;
    this.threadModelError = '';
  }

  private async loadThreadModels(): Promise<void> {
    const client = this.client;
    const projectId = this.selected?.projectId;
    if (!client || !projectId || this.threadModelLoading || this.threadModelApplying ||
      this.threadAccess !== 'allowed' || this.watchError) return;
    const request = ++this.threadModelRequest;
    this.showThreadModel = true;
    this.threadModelLoading = true;
    this.threadModelError = '';
    this.threadModelCatalogCanWrite = false;
    try {
      const permission = client.canWriteModelCatalogPreferences().catch(() => false);
      const settings = await client.threadModelSettings(projectId, this.threadFilesCwd() || undefined);
      if (request === this.threadModelRequest) {
        this.threadModelProviders = settings.providers;
        this.threadRuntimeCeiling = settings.maxRuntimeMode;
        this.threadModelCatalog = settings.modelCatalog;
      }
      const canWrite = await permission;
      if (request === this.threadModelRequest) this.threadModelCatalogCanWrite = canWrite;
    } catch (error) {
      if (request === this.threadModelRequest && !this.handleExpiredAccount(error as Error)) {
        this.threadModelError = errorMessage(error as Error, this.copy('无法加载模型', 'Could not load models'));
      }
    } finally {
      if (request === this.threadModelRequest) this.threadModelLoading = false;
    }
  }

  private selectThreadRuntime(mode: ThreadLaunchRuntimeMode): void {
    const thread = this.selected;
    if (!thread || !this.showThreadRuntime || this.threadAccess !== 'allowed' || this.sending ||
      this.threadModelLoading || this.threadModelApplying || this.watchError) return;
    const selection = this.displayedThreadModel();
    if (!selection) return;
    const model = this.threadModelProviders.find((provider) => provider.instanceId === selection.instanceId)?.models
      .find((entry) => entry.slug === selection.model);
    if (!threadLaunchRuntimeModes(model, this.threadRuntimeCeiling).includes(mode)) return;
    let drafts = this.runtimeDrafts.get(this.environmentKey);
    if (!drafts) {
      drafts = new Map<string, ThreadLaunchRuntimeMode>();
      this.runtimeDrafts.set(this.environmentKey, drafts);
    }
    drafts.set(thread.id, mode);
    this.threadRuntimeDraft = mode;
    this.showThreadRuntime = false;
  }

  private setThreadModelDraft(draft?: ThreadLaunchSelection): void {
    const threadId = this.selected?.id;
    if (!threadId) return;
    this.threadModelDraft = draft;
    let drafts = this.modelDrafts.get(this.environmentKey);
    if (draft !== undefined) {
      if (!drafts) {
        drafts = new Map();
        this.modelDrafts.set(this.environmentKey, drafts);
      }
      drafts.set(threadId, draft);
    } else {
      drafts?.delete(threadId);
    }
  }

  private displayedThreadModel(): ThreadLaunchSelection | undefined {
    return this.threadModelPending ?? this.threadModelDraft ?? this.threadDetail?.modelSelection;
  }

  private async changeThreadModelCatalog(provider: string, model: string, kind: ModelCatalogPreferenceKind,
    enabled: boolean): Promise<void> {
    const client = this.client;
    const target: ThreadLaunchSelection = { instanceId: provider, model };
    const entry = this.threadModelFromCatalog(target);
    if (!client || !entry || (kind === 'hidden' && entry.isCustom === true) || !this.threadModelCatalogCanWrite ||
      this.threadModelLoading || this.threadModelApplying) return;
    const request = this.threadModelRequest;
    this.threadModelApplying = true;
    this.threadModelError = '';
    try {
      const preferences = await client.updateModelCatalogPreferences(provider, model, kind, enabled);
      if (request === this.threadModelRequest) this.threadModelCatalog = preferences;
    } catch (error) {
      if (request === this.threadModelRequest && !this.handleExpiredAccount(error as Error)) {
        this.threadModelError = errorMessage(error as Error, this.copy('无法保存模型偏好', 'Could not save model preferences'));
      }
    } finally {
      if (request === this.threadModelRequest) this.threadModelApplying = false;
    }
  }

  private threadModelFromCatalog(selection?: ThreadLaunchSelection): ThreadLaunchModel | undefined {
    return this.threadModelProviders.find((provider: ThreadLaunchProvider) => provider.instanceId === selection?.instanceId)
      ?.models.find((model: ThreadLaunchModel) => model.slug === selection?.model);
  }

  private modelMemoryKey(selection: ThreadLaunchSelection): string {
    return JSON.stringify([this.environmentKey, selection.instanceId, selection.model]);
  }

  private previewThreadModel(target: ThreadLaunchSelection): void {
    if (this.threadModelLoading || this.threadModelApplying) return;
    const applied = this.threadModelDraft ?? this.threadDetail?.modelSelection;
    const pending = this.threadModelPending;
    const model = this.threadModelFromCatalog(target);
    if (!model) return;
    if (pending?.instanceId === target.instanceId && pending.model === target.model) return;
    this.threadModelPendingPrompt = undefined;
    if (applied?.instanceId === target.instanceId && applied.model === target.model) {
      this.threadModelPending = undefined;
      return;
    }
    this.threadModelPending = threadModelSelectionForTarget(target.instanceId, model, applied,
      this.modelOptionMemory.get(this.modelMemoryKey(target)));
  }

  private updateThreadModelParameter(id: string, value: string | boolean): void {
    const selection = this.displayedThreadModel();
    if (!selection || this.threadModelApplying || this.threadModelLoading || this.threadAccess !== 'allowed') return;
    const prompt = this.threadModelPendingPrompt ?? this.draft;
    const change = changeThreadModelOption(this.threadModelFromCatalog(selection), selection, id, value, prompt);
    if (!change) return;
    this.threadModelParameterId = '';
    if (this.threadModelPending) {
      this.threadModelPending = change.selection;
      this.threadModelPendingPrompt = change.prompt === this.draft ? undefined : change.prompt;
    } else {
      if (change.prompt !== this.draft) this.changeDraft(change.prompt);
      void this.applyThreadModel(change.selection, false);
    }
  }

  private savePendingThreadModel(): void {
    if (!this.threadModelPending || this.threadModelApplying || this.threadModelLoading) return;
    if (this.threadModelPendingPrompt !== undefined) this.changeDraft(this.threadModelPendingPrompt);
    void this.applyThreadModel(this.threadModelPending, true);
  }

  private async applyThreadModel(selection: ThreadLaunchSelection, close: boolean): Promise<void> {
    const client = this.client;
    const thread = this.selected;
    const detail = this.threadDetail;
    if (!client || !thread || !detail?.modelSelection || this.threadAccess !== 'allowed' ||
      this.threadModelApplying || this.threadModelLoading || this.sending || this.watchError) return;
    if (selection.instanceId !== detail.modelSelection.instanceId && !detail.canSwitchProvider) return;
    const next = withThreadModelOptionDefaults(this.threadModelFromCatalog(selection), selection);
    this.modelOptionMemory.set(this.modelMemoryKey(next), next.options ?? []);
    if (threadModelSelectionsEqual(next, detail.modelSelection)) {
      this.setThreadModelDraft();
      if (close) this.closeThreadModel();
      return;
    }
    this.setThreadModelDraft(next);
    if (next.instanceId !== detail.modelSelection.instanceId) {
      if (close) this.closeThreadModel();
      return;
    }
    const request = this.threadModelRequest;
    this.threadModelApplying = true;
    this.threadModelError = '';
    try {
      await client.setThreadModel(thread.id, next);
      if (request === this.threadModelRequest) {
        if (threadModelSelectionsEqual(next, this.threadDetail?.modelSelection)) this.setThreadModelDraft();
        if (close) this.closeThreadModel();
      }
    } catch (error) {
      if (request === this.threadModelRequest && !this.handleExpiredAccount(error as Error)) {
        this.threadModelError = errorMessage(error as Error, this.copy('无法更改模型', 'Could not change the model'));
      }
    } finally {
      if (request === this.threadModelRequest) this.threadModelApplying = false;
    }
  }

  @Builder
  private Header() {
    Row({ space: 8 }) {
      if (this.selected || this.showPairing) {
        Button('返回', { type: ButtonType.Normal })
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
          .backgroundColor(Color.Transparent)
          .height(44)
          .enabled(!this.pairing)
          .onClick(() => { this.onBackPress(); })
      }
      Text(this.selected?.title ?? (this.addingEnvironment ? '添加环境' : this.showPairing ? '环境' : 'T3 Code'))
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.showPairing && !this.addingEnvironment) {
        Button('添加环境', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44)
          .enabled(!this.pairing && !this.accountSigningOut)
          .onClick(() => {
            this.pairError = '';
            this.pairLink = '';
            this.addingEnvironment = true;
          })
      }
    }
    .height(56)
    .width('100%')
    .padding({ left: 12, right: 12 })
  }

  @Builder
  private WorkspaceCatalog() {
    Stack({ alignContent: Alignment.TopStart }) {
      WorkspaceDataPages({
        tab: this.workspaceTab === 'issues' || this.workspaceTab === 'usage' ? this.workspaceTab : 'pullRequests',
        connected: this.connected,
        environmentKey: this.environmentKey,
        environmentId: this.client?.currentEnvironment()?.environmentId ?? '',
        environmentLabel: this.client?.currentEnvironment()?.label ?? '',
        viewOwner: this.accountIdentity?.userId ?? '',
        query: this.workspaceDataQuery(),
        searchOpen: this.workspaceDataSearchOpen(),
        onSelectSharedTab: (tab: WorkspaceSharedTab) => this.selectWorkspaceTab(tab),
        onQuery: (query: string) => this.setWorkspaceDataQuery(query),
        onApplyQuery: (key: string, tab: WorkspaceSharedTab, query: string) => this.applyWorkspaceDataQuery(key, tab, query),
        onSearch: () => this.openWorkspaceDataSearch(),
        onCloseSearch: () => this.closeWorkspaceDataSearch(),
        onOpenEnvironments: () => this.openEnvironments(),
        onLoadPullRequests: async (key: string, input: NativePullRequestQuery) =>
          this.workspaceDataClient(key).readWorkspacePullRequests(input),
        onLoadPullRequestFilters: async (key: string, mode: NativePullRequestFilterMode, projectId?: string, query?: string) =>
          this.workspaceDataClient(key).readWorkspacePullRequestFilterOptions(mode, projectId, query),
        onOpenPullRequest: (key: string, row: NativePullRequestRow) => {
          if (this.environmentKey !== key || this.workspaceTab !== 'pullRequests') return;
          this.workspaceDetailEnvironmentKey = key;
          this.workspacePullRequest = row;
          void this.refreshWorkspaceSourceControlPermissions(key);
        },
        onLoadIssues: async (key: string, filters: NativeIssueFilters, cursors?: Record<string, string>, refresh?: boolean) =>
          this.workspaceDataClient(key).readWorkspaceIssues(filters, cursors, refresh),
        onLoadIssueCandidates: async (key: string, scope: NativeIssueScope) =>
          this.workspaceDataClient(key).readWorkspaceIssueCandidates(scope),
        onOpenIssue: (key: string, entry: NativeIssueEntry) => {
          if (this.environmentKey !== key || this.workspaceTab !== 'issues') return;
          this.workspaceDetailEnvironmentKey = key;
          this.workspaceIssue = entry;
          void this.refreshWorkspaceSourceControlPermissions(key);
        },
        onLoadUsage: async (key: string, days: number) => this.workspaceDataClient(key).readWorkspaceUsage(days),
        onLoadUsageLimits: async (key: string) => this.workspaceDataClient(key).readWorkspaceUsageLimits(),
        onOpenUsageAccount: (key: string, account: NativeUsageAccount, window: NativeUsageLimitWindow) => {
          if (this.environmentKey !== key || this.workspaceTab !== 'usage') return;
          this.workspaceDetailEnvironmentKey = key;
          this.workspaceUsageAccount = account;
          this.workspaceUsageWindow = window;
        },
      }).width('100%').height('100%')
        .visibility(this.workspaceDataDetailsOpen() ? Visibility.None : Visibility.Visible)
      if (this.workspacePullRequest) {
        WorkspacePullRequestDetail({
          row: this.workspacePullRequest,
          canWrite: this.workspaceSourceControlCanWrite,
          environmentId: this.client?.currentEnvironment()?.environmentId ?? this.workspaceDetailEnvironmentKey,
          viewOwner: this.accountIdentity?.userId ?? '',
          backRequest: this.workspaceDataBackRequest,
          onBack: () => this.closeWorkspaceDataDetails(),
          onLoadDetail: async (ref: NativePullRequestRef, allowStale?: boolean) =>
            this.workspaceDataClient(this.workspaceDetailEnvironmentKey).readWorkspacePullRequest(ref, allowStale),
          onLoadDiscussion: async (ref: NativePullRequestRef) =>
            this.workspaceDataClient(this.workspaceDetailEnvironmentKey).readWorkspacePullRequestDiscussion(ref),
          onLoadMetadata: async (ref: NativePullRequestRef, kind: NativePullRequestMetadataKind, query?: string) =>
            this.workspaceDataClient(this.workspaceDetailEnvironmentKey).readWorkspacePullRequestMetadata(ref, kind, query),
          onGuideEnabled: async () =>
            this.workspaceDataClient(this.workspaceDetailEnvironmentKey).workspacePullRequestGuidesEnabled(),
          onLoadGuide: async (ref: NativePullRequestRef) =>
            this.workspaceDataClient(this.workspaceDetailEnvironmentKey).readWorkspacePullRequestGuide(ref),
          onGuideCanGenerate: async () =>
            this.workspaceDataClient(this.workspaceDetailEnvironmentKey).workspacePullRequestGuideCanGenerate(),
          onGenerateGuide: async (ref: NativePullRequestRef) =>
            this.workspaceDataClient(this.workspaceDetailEnvironmentKey).generateWorkspacePullRequestGuide(ref),
          onLoadDiff: async (ref: NativePullRequestRef, cursor?: string) =>
            this.workspaceDataClient(this.workspaceDetailEnvironmentKey).readWorkspacePullRequestDiff(ref, cursor),
          onLoadFilePatch: async (ref: NativePullRequestRef, path: string) =>
            this.workspaceDataClient(this.workspaceDetailEnvironmentKey).readWorkspacePullRequestFileDiff(ref, path),
          onLoadCompletions: async (ref: NativePullRequestRef, trigger: NativePullRequestComposerTrigger) =>
            this.workspaceDataClient(this.workspaceDetailEnvironmentKey).readWorkspacePullRequestCompletionOptions(ref, trigger),
        }).width('100%').height('100%')
      } else if (this.workspaceIssue) {
        WorkspaceIssueDetail({
          environmentKey: this.workspaceDetailEnvironmentKey,
          issue: this.workspaceIssue,
          canWrite: this.workspaceSourceControlCanWrite,
          backRequest: this.workspaceDataBackRequest,
          onLoad: async (ref: NativeIssueRef) =>
            this.workspaceDataClient(this.workspaceDetailEnvironmentKey).readWorkspaceIssue(ref),
          onBack: () => this.closeWorkspaceDataDetails(),
        }).width('100%').height('100%')
      } else if (this.workspaceUsageAccount) {
        WorkspaceUsageAccount({
          account: this.workspaceUsageAccount,
          window: this.workspaceUsageWindow,
          environmentLabel: this.client?.currentEnvironment()?.label ?? '',
          onBack: () => this.closeWorkspaceDataDetails(),
        }).width('100%').height('100%')
      }
    }.width('100%').layoutWeight(1)
  }

  @Builder
  private Workspace() {
    if (this.workspaceTab === 'settings' && this.settingsPages.length > 0) {
      WorkspaceSettingsDetail({
        page: this.settingsPages[this.settingsPages.length - 1],
        language: this.uiLanguage(),
        languagePreference: this.languagePreference,
        dark: this.darkAppearance,
        connected: this.connected,
        signedIn: this.accountIdentity !== undefined,
        environmentLabel: this.settingsEnvironment()?.label ?? '',
        clientPreferences: this.clientPreferences,
        environmentPreferences: this.environmentPreferences,
        providers: this.providersList,
        scheduledTasks: this.scheduledTasksList,
        storageSummary: { cacheBytes: 0, environmentCount: this.visibleEnvironmentRows().length, clearable: false },
        crashes: [],
        onLanguage: (value: UiLanguagePreference) => this.selectLanguagePreference(value),
        onClientPreference: (key: ClientPreferenceKey, value: ClientPreferenceValue) =>
          this.updateClientPreferenceEntry(key, value),
        onEnvironmentPatch: (patch: Record<string, Object | null | undefined>) => this.applyEnvironmentPatch(patch),
        onToggleProvider: (instanceId: string, enabled: boolean, driver: string) =>
          this.toggleProviderEnabled(instanceId, enabled, driver),
        onToggleScheduledTask: (taskId: string, enabled: boolean) => this.toggleScheduledTaskEnabled(taskId, enabled),
        onRunScheduledTask: (taskId: string) => this.runScheduledTaskNow(taskId),
        onCopyDiagnostics: (report: string) => this.copyDiagnosticsReport(report),
        onBack: () => { this.onBackPress(); },
        onOpenPage: (page: WorkspaceSettingsPage) => this.openSettingsPage(page),
        onAccount: () => this.openAccount(),
        onEnvironments: () => this.openEnvironments(),
        onActiveEnvironment: () => this.openActiveEnvironmentDetails(),
      })
    } else if (this.workspaceTab === 'settings') {
      Column() {
        WorkspaceSettings({
          language: this.uiLanguage(),
          dark: this.darkAppearance,
          query: this.settingsQuery,
          searchOpen: this.settingsSearchOpen,
          accountValue: this.accountSettingValue(),
          environmentCount: this.visibleEnvironmentRows().length,
          connected: this.connected,
          showNotifications: this.relayConfigured,
          scroller: this.settingsScroller,
          scrollOffset: this.settingsScrollOffset,
          sharedTab: this.workspaceSharedTab,
          projectLabel: this.threadProjects.find((project: WorkspaceProjectChoice) =>
            project.key === this.settingsProjectFilter)?.title ?? '',
          filterGroups: this.workspaceFilterGroups(true),
          filterActive: this.settingsEnvironmentFilter.length > 0 || this.settingsProjectFilter.length > 0,
          onFilter: (key: string) => this.selectWorkspaceFilter(key, true),
          onSelectSharedTab: (tab: WorkspaceSharedTab) => this.selectWorkspaceTab(tab),
          onOpenPage: (page: WorkspaceSettingsPage) => this.openSettingsPage(page),
          onQuery: (value: string) => { this.settingsQuery = value; },
          onSearch: () => { this.settingsSearchOpen = true; },
          onCloseSearch: () => this.closeSettingsSearch(),
          onAccount: () => { this.rememberSettingsScroll(); this.openAccount(); },
          onEnvironments: () => { this.rememberSettingsScroll(); this.openEnvironments(); },
          onArchive: () => {
            this.rememberSettingsScroll();
            this.showArchivedThreads = true;
            void this.loadArchivedThreads();
          },
          onProjects: () => { this.rememberSettingsScroll(); this.showProjects = true; },
        })
      }.width('100%').layoutWeight(1)
    } else if (this.workspaceTab === 'threads') {
      WorkspaceHeader({
        language: this.uiLanguage(),
        dark: this.darkAppearance,
        title: this.client?.currentEnvironment()?.label ?? '',
        status: this.refreshing ? (this.threadCount > 0 ? this.copy('正在同步会话…', 'Syncing threads…') :
          this.copy('正在加载会话…', 'Loading threads…')) : '',
        statusProgress: this.refreshing,
        filterGroups: this.workspaceFilterGroups(false),
        filterCustomized: this.workspaceEnvironmentFilter.length > 0 || this.projectFilter.length > 0,
        query: this.threadQuery,
        searchOpen: this.searchOpen,
        onFilter: (key: string) => this.selectWorkspaceFilter(key, false),
        onQuery: (value: string) => this.searchThreads(value),
        onSearch: () => { this.searchOpen = true; },
        onCloseSearch: () => this.closeThreadSearch(),
        onEnvironment: () => this.openEnvironments(),
      })
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          if (this.connected) {
            this.ThreadList()
          } else {
            Column({ space: 14 }) {
              Text(this.copy('还没有连接环境', 'No environment connected'))
                .fontSize(18)
                .fontColor(workspaceForegroundColor(this.darkAppearance))
                .fontWeight(FontWeight.Medium)
              Button(this.copy('连接环境', 'Connect an environment'))
                .height(44)
                .onClick(() => this.openEnvironments())
            }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding(20)
          }
        }.width('100%').height('100%')
        if (!this.keyboardVisible && !this.searchOpen && this.connected && this.threadListCanWrite && !this.pairing &&
          !this.loadingThreadLaunch) {
          WorkspaceComposeButton({
            language: this.uiLanguage(),
            dark: this.darkAppearance,
            expanded: this.composeButtonExpanded,
            onCreate: () => { void this.loadThreadLaunch(); },
          }).margin({ right: 16, bottom: 16 })
        }
      }
      .width('100%').layoutWeight(1)
      .backgroundColor(workspaceSurfaceColor(this.darkAppearance))
      .borderRadius({ topLeft: 28, topRight: 28 }).clip(true)
    } else {
      this.WorkspaceCatalog()
    }
    if (!this.keyboardVisible && !this.workspaceDataDetailsOpen() &&
      (this.workspaceTab !== 'settings' || this.settingsPages.length === 0)) {
      WorkspaceDock({
        language: this.uiLanguage(),
        dark: this.darkAppearance,
        selection: this.workspaceTab,
        sharedTab: this.workspaceSharedTab,
        onSelect: (selection: WorkspaceTab) => this.selectWorkspaceTab(selection),
      })
    }
  }

  @Builder
  private Status(label: string, loading: boolean) {
    Column({ space: 12 }) {
      if (loading) {
        LoadingProgress().width(24).height(24)
      }
      Text(label)
        .fontSize(15)
        .fontColor(workspaceMutedColor(this.darkAppearance))
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .width('100%')
    .padding(20)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private Environments() {
    Scroll() {
      Column({ space: 12 }) {
        if (this.environments.length > 0) {
          Text('已配对环境')
            .fontSize(21)
            .fontWeight(FontWeight.Medium)
          ForEach(this.visibleEnvironmentRows(), (environment: EnvironmentSummary) => {
            Row({ space: 8 }) {
              Column({ space: 4 }) {
                Text(environment.label)
                  .fontSize(16)
                Text(environment.enabled ? environment.origin : '已停用')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Button(environment.key === this.environmentKey ? '当前环境' : '切换')
                .enabled(environment.enabled && environment.key !== this.environmentKey &&
                  !this.pairing && !this.accountSigningOut)
                .onClick(() => { void this.manageEnvironment(environment.key, false); })
              Button('详情', { type: ButtonType.Normal })
                .controlSize(ControlSize.SMALL)
                .enabled(!this.pairing && !this.accountSigningOut)
                .onClick(() => {
                  this.closeEnvironmentDetails();
                  this.environmentDetails = environment;
                  void this.refreshLinkedEnvironmentHealth();
                  void this.refreshEnvironmentMaintenance();
                })
            }.width('100%')
          }, (environment: EnvironmentSummary) => JSON.stringify([
            environment.key, environment.enabled, environment.label, environment.origin,
          ]))
        }
        if (this.linkedEnvironmentLoading) {
          LoadingProgress().width(22).height(22).accessibilityText('正在读取关联环境')
        }
        if (this.linkedEnvironmentError) {
          Text(this.linkedEnvironmentError).fontSize(14).fontColor($r('sys.color.font_secondary'))
          Button('重新读取关联环境', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.pairing)
            .onClick(() => { void this.refreshLinkedEnvironmentHealth(); })
        }
        if (this.batchLinkAvailable() || this.linkedEnvironmentBatch.length > 0 || this.linkedEnvironmentHealth.length > 0 ||
          this.linkedEnvironmentLoading) {
          ForEach([this.linkedEnvironmentSourceKey], (_source: string) => {
            LinkedEnvironmentsView({
              batchOnly: true,
              batchAvailable: this.batchLinkAvailable(),
              batchLoading: this.linkedEnvironmentLoading,
              batchLoadError: this.linkedEnvironmentError,
              environmentLabel: this.client?.currentEnvironment()?.label ?? '',
              links: this.linkedEnvironmentHealth,
              candidates: this.linkedEnvironmentCandidates(),
              linkBatchResults: this.linkedEnvironmentBatch,
              busy: this.pairing,
              onLinkBatch: (keys: string[], access: NativePeerLinkAccess) => { void this.linkEnvironmentBatch(keys, access); },
              onRefreshBatch: () => { void this.refreshLinkedEnvironmentHealth(); },
            })
          }, (source: string) => source)
        }
        if (this.canApproveDevices) {
          Button('设备审批', { type: ButtonType.Normal })
            .id('environment-device-approvals')
            .enabled(!this.pairing)
            .onClick(() => {
              this.approvals = [];
              this.approvalNotice = '';
              this.showApprovals = true;
              void this.loadApprovals();
            })
        }
        if (this.environments.length === 0) {
          Text('暂无已配对环境')
            .fontSize(16)
            .fontColor($r('sys.color.font_secondary'))
        }
        if (this.pairError) {
          Text(this.pairError)
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
        }
        this.RelayList()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 20, left: 20, right: 20, bottom: 20 })
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  @Builder
  private ConnectOnboarding() {
    Row({ space: 8 }) {
      Button('关闭', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .enabled(!this.pairing && !this.savingConnectPreference).onClick(() => this.onBackPress())
      Text('设置 T3 Connect').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
    }.width('100%').height(56).padding({ left: 12, right: 12 })
    Scroll() {
      Column({ space: 14 }) {
        this.RelayList()
        if (this.pairError || this.connectOnboardingError) {
          Text(this.pairError || this.connectOnboardingError)
            .fontSize(14).fontColor($r('sys.color.font_secondary'))
        }
        Button(this.savingConnectPreference ? '正在保存…' : '不再显示', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .enabled(!this.pairing && !this.savingConnectPreference)
          .onClick(() => { void this.skipConnectOnboarding(); })
      }.width('100%').padding(20).alignItems(HorizontalAlign.Start)
    }.width('100%').layoutWeight(1)
  }

  @Builder
  private RelayList() {
    Text('T3 Connect')
      .fontSize(21)
      .fontWeight(FontWeight.Medium)
      .margin({ top: 16 })
    if (!this.relayConfigured) {
      Text('当前安装包未配置 T3 Connect。').fontSize(14)
    } else if (!this.accountIdentity) {
      if (this.accountBusy && !this.accountPending) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18)
          Text('正在检查 T3 账户…').fontSize(14)
        }
      } else {
        Button('登录 T3 账户')
          .onClick(() => this.openAccount())
      }
    } else {
      if (this.relayRestoreError) {
        Text(this.relayRestoreError)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      Row({ space: 8 }) {
        if (this.relayLoading) {
          LoadingProgress().width(18).height(18)
        }
        Text(this.relayError || (!this.relayHasListed ? '正在加载 T3 Connect 环境…' :
          this.relayRows.length === 0 ? '暂无 T3 Connect 环境' : '托管环境'))
          .layoutWeight(1)
          .fontSize(14)
        Button(this.relayError ? '重试' : '刷新')
          .controlSize(ControlSize.SMALL)
          .enabled(!this.relayLoading && !this.pairing && !this.accountBusy)
          .onClick(() => { void this.loadRelayEnvironments(); })
      }.width('100%')
      ForEach(this.relayRows, (entry: RelayEnvironment) => {
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text(entry.label).fontSize(16)
            Text(this.relayAvailabilityLabel(entry))
              .fontSize(13)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Button(this.relayConnectingId === entry.environmentId ? '正在连接…' :
            this.isManagedEnvironmentDisabled(entry.environmentId) ? '已停用' : '连接')
            .controlSize(ControlSize.SMALL)
            .enabled(!this.pairing && !this.accountBusy && !this.isManagedEnvironmentDisabled(entry.environmentId))
            .onClick(() => { void this.useRelayEnvironment(entry.environmentId); })
        }.width('100%')
      }, (entry: RelayEnvironment) => entry.environmentId + ':' + entry.label + ':' + entry.availability)
    }
  }

  private isManagedEnvironmentDisabled(environmentId: string): boolean {
    return this.environments.some((entry) => entry.managed && entry.environmentId === environmentId && !entry.enabled);
  }

  private relayAvailabilityLabel(environment: RelayEnvironment): string {
    switch (environment.availability) {
      case 'online': return '在线';
      case 'offline': return '离线';
      case 'checking': return '正在检查状态…';
      default: return '状态暂不可用';
    }
  }

  @Builder
  private WorkspaceThreadRow(thread: NativeThread) {
    WorkspaceChatRow({
      title: thread.title,
      subtitle: [thread.projectTitle, this.workspaceEnvironmentFilter.length === 0 && this.environments.length > 1 ?
        thread.environmentLabel : undefined].filter(Boolean).join(' · '),
      snippet: this.threadSearchMatches.get(this.threadSearchKey(thread))?.snippet ?? '',
      timeLabel: workspaceThreadTimeLabel(thread, this.uiLanguage(), Date.now()),
      status: workspaceThreadRowStatus(thread, Date.now()),
      unread: threadHasUnread(thread),
      pinned: !!thread.pinnedAt,
      showProjectIcon: !!thread.projectId,
      showActions: this.canOperateThreadRow(thread),
      showActionButton: this.showArchivedThreads,
      language: this.uiLanguage(),
      dark: this.darkAppearance,
      onOpen: () => { void this.openListedThread(thread); },
      onActions: () => this.openThreadListActions(thread),
    })
  }

  private toggleWorkspaceShelf(section: WorkspaceThreadSection): void {
    this.expandedThreadShelves = this.expandedThreadShelves.includes(section)
      ? this.expandedThreadShelves.filter((entry: WorkspaceThreadSection) => entry !== section)
      : this.expandedThreadShelves.concat(section);
    this.updateThreadResults();
  }

  @Builder
  private WorkspaceRowSwipe(thread?: NativeThread) {
    Row({ space: 4 }) {
      if (thread && this.canOperateThreadRow(thread)) {
        if (threadLifecycleState(thread, Date.now()) === 'snoozed') {
          WorkspaceThreadSwipeAction({
            label: this.copy('唤醒', 'Wake'), icon: $r('sys.symbol.clock'), dark: this.darkAppearance,
            onAction: () => { void this.updateThreadLifecycle('unsnooze', undefined, thread); },
          })
        } else {
          if (threadLifecycleState(thread, Date.now()) === 'settled') {
            WorkspaceThreadSwipeAction({
              label: this.copy('取消收尾', 'Un-settle'), icon: $r('sys.symbol.arrow_left'), dark: this.darkAppearance,
              onAction: () => { void this.updateThreadLifecycle('unsettle', undefined, thread); },
            })
          } else {
            WorkspaceThreadSwipeAction({
              label: this.copy('收尾', 'Settle'), icon: $r('sys.symbol.checkmark'), dark: this.darkAppearance,
              onAction: () => { void this.updateThreadLifecycle('settle', undefined, thread); },
            })
          }
          if (availableThreadLifecycleActions(thread, true, Date.now()).includes('snooze')) {
            WorkspaceThreadSwipeAction({
              label: this.copy('暂缓', 'Snooze'), icon: $r('sys.symbol.clock'), dark: this.darkAppearance,
              onAction: () => this.openThreadListActions(thread, true),
            })
          }
        }
      }
    }.height('100%')
  }

  @Builder
  private ArchivedThreads() {
    Row({ space: 8 }) {
      Button('返回', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick(() => { this.onBackPress(); })
      Text('归档').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
      Button('刷新', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .enabled(this.connected && !this.archiveLoading)
        .onClick(() => { void this.loadArchivedThreads(); })
    }.width('100%').height(56).padding({ left: 12, right: 12 })
    if (this.archiveLoading || this.archiveError || this.archivedThreads.length === 0) {
      this.Status(this.archiveLoading ? '正在读取归档…' :
        this.archiveError || (this.connected ? '暂无归档会话' : '请先连接环境'), this.archiveLoading)
    } else {
      List({ space: 4 }) {
        ForEach(this.archivedThreads, (thread: NativeThread) => {
          ListItem() {
            this.WorkspaceThreadRow(thread)
          }
        }, (thread: NativeThread) => JSON.stringify([thread.environmentKey, thread.id]))
      }.width('100%').layoutWeight(1).padding({ left: 8, right: 8 })
    }
  }

  @Builder
  private ThreadList() {
    if (this.threadSearchLoading || this.threadSearchError) {
      Row({ space: 8 }) {
        if (this.threadSearchLoading) LoadingProgress().width(18).height(18)
        Text(this.threadSearchLoading ? this.copy('正在搜索会话正文…', 'Searching thread messages…') : this.threadSearchError)
          .fontSize(13).fontColor(workspaceMutedColor(this.darkAppearance)).layoutWeight(1)
        if (this.threadSearchError) {
          Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .controlSize(ControlSize.SMALL).onClick(() => this.scheduleThreadSearch())
        }
      }.width('100%').padding({ left: 14, right: 14, top: 8 })
    }
    if (this.listError) {
      Row({ space: 8 }) {
        Text(this.listError)
          .fontSize(14)
          .fontColor(workspaceMutedColor(this.darkAppearance))
          .layoutWeight(1)
        Button('重试')
          .controlSize(ControlSize.SMALL)
          .enabled(!this.refreshing)
          .onClick(() => { void this.refreshThreads(); })
      }
      .width('100%')
      .padding(14)
    }
    if (this.threadCount > 0) {
      List({ space: 2, scroller: this.workspaceScroller }) {
        LazyForEach(this.threads, (entry: WorkspaceThreadListEntry) => {
          ListItem() {
            if (entry.thread) {
              this.WorkspaceThreadRow(entry.thread)
            } else if (entry.kind === 'shelf') {
              WorkspaceThreadShelf({
                section: entry.section, count: entry.count, language: this.uiLanguage(), dark: this.darkAppearance,
                expanded: this.expandedThreadShelves.includes(entry.section),
                onToggle: () => this.toggleWorkspaceShelf(entry.section),
              })
            } else {
              WorkspaceThreadSectionTitle({ section: entry.section, language: this.uiLanguage(), dark: this.darkAppearance })
            }
          }
          .swipeAction({ end: () => { this.WorkspaceRowSwipe(entry.thread); } })
        }, (entry: WorkspaceThreadListEntry) => entry.key)
      }
      .layoutWeight(1)
      .width('100%')
      .contentEndOffset(this.threadListCanWrite && !this.keyboardVisible && !this.searchOpen ? 84 : 12)
      .padding({ left: 12, right: 12, top: 12 })
      .scrollBar(BarState.Off)
      .maintainVisibleContentPosition(true)
      .onAppear(() => {
        if (this.workspaceScrollOffset > 0) {
          this.getUIContext().postFrameCallback(new AfterLayout(() => {
            if (this.workspaceTab === 'threads' && this.isWorkspaceRoot()) {
              this.workspaceScroller.scrollTo({ xOffset: 0, yOffset: this.workspaceScrollOffset, animation: false });
            }
          }));
        }
      })
      .onScroll((offset: number, status: ScrollState) => {
        if (status !== ScrollState.Idle && Math.abs(offset) >= 1) this.composeButtonExpanded = offset < 0;
      })
    } else {
      this.Status(this.refreshing ? this.copy('正在加载会话…', 'Loading threads…') :
        this.listError ? this.copy('会话暂时不可用', 'Chats are unavailable') :
        this.threadQuery.trim() || this.projectFilter ? this.copy('没有匹配的会话', 'No matching chats') :
        this.copy('暂无会话', 'No chats yet'), this.refreshing)
    }
  }

  private threadSubtitle(): string {
    const project = this.selected?.projectTitle;
    const environment = this.client?.currentEnvironment()?.label;
    return project && environment ? `${project} · ${environment}` : (project || environment || '');
  }

  private toggleMessage(id: string): void {
    this.expandedMessages = this.expandedMessages.includes(id)
      ? this.expandedMessages.filter((entry: string) => entry !== id)
      : this.expandedMessages.concat(id);
  }

  private async toggleFeedEntry(entry: FeedEntry): Promise<void> {
    await this.toggleWorkRow(entry.id, entry.work);
  }

  private async toggleWorkRow(rowId: string, work?: NativeThreadWork): Promise<void> {
    const opening = !this.expandedMessages.includes(rowId);
    this.toggleMessage(rowId);
    const client = this.client;
    if (!opening || !work?.wantsOutput || !client || this.workOutput.has(rowId) ||
      this.loadingWork.includes(rowId)) return;
    const generation = this.threadViewGeneration;
    this.loadingWork = this.loadingWork.concat(rowId);
    this.sendError = '';
    try {
      const output = await client.readThreadWork(work.threadId, work.id);
      if (generation !== this.threadViewGeneration) return;
      const values = new Map(this.workOutput);
      values.set(rowId, output.length > 32000 ? output.slice(0, 32000) + '\n' + this.copy('输出较长，预览已截断。', 'Long output was truncated.') : output);
      this.workOutput = values;
    } catch (error) {
      if (generation === this.threadViewGeneration) this.sendError = errorMessage(error as Error, this.copy('无法读取命令输出', 'Could not read command output'));
    } finally {
      if (generation === this.threadViewGeneration) {
        this.loadingWork = this.loadingWork.filter((id: string) => id !== rowId);
      }
    }
  }

  private toggleCodeBlock(rowId: string, blockIndex: number): void {
    const previous = this.expandedCodeBlocks.get(rowId) ?? [];
    const expanded = new Map(this.expandedCodeBlocks);
    expanded.set(rowId, previous.includes(blockIndex) ?
      previous.filter((index: number) => index !== blockIndex) : previous.concat(blockIndex));
    this.expandedCodeBlocks = expanded;
  }

  private threadFilesCwd(): string {
    return this.threadWorktree() || this.selected?.workspaceRoot?.trim() || '';
  }

  private threadWorktree(): string {
    return (this.threadDetail?.worktreePath ?? this.selected?.worktreePath)?.trim() ?? '';
  }

  private async openThreadTerminal(): Promise<void> {
    const client = this.client;
    const thread = this.selected;
    if (!client || !thread || !thread.workspaceRoot || !this.threadFilesCwd() ||
      (!this.threadCanReadTerminal && !this.threadCanOperateTerminal)) return;
    if (!this.showThreadTerminal) {
      this.resumeThreadIndex = this.messageCount > 0 && !this.messageScroller.isAtEnd()
        ? this.firstVisibleThreadIndex : -1;
      this.showThreadTerminal = true;
    }
    this.terminalCwd = this.threadFilesCwd();
    this.terminalLoading = true;
    this.terminalError = '';
    const request = ++this.terminalRequest;
    try {
      if (this.threadCanReadTerminal) {
        const sessions = await client.listThreadTerminals(thread.id);
        if (request !== this.terminalRequest) return;
        this.terminalSessions = sessions.map((session: NativeThreadTerminalSummary): ThreadTerminalSession => ({
          terminalId: session.terminalId, label: session.label, cwd: session.cwd, status: session.status,
          hasRunningSubprocess: session.hasRunningSubprocess,
        }));
      }
      const lastId = this.terminalSelection.get(this.terminalSelectionKey());
      const restored = this.terminalSessions.find((entry: ThreadTerminalSession) => entry.terminalId === lastId);
      const target = restored ?? this.terminalSessions[0];
      if (target) this.attachThreadTerminal(target.terminalId);
      else if (this.threadCanOperateTerminal) {
        this.attachThreadTerminal(this.threadCanReadTerminal ? DEFAULT_THREAD_TERMINAL_ID :
          lastId ?? DEFAULT_THREAD_TERMINAL_ID);
      }
      else this.terminalLoading = false;
    } catch (error) {
      if (request === this.terminalRequest && !this.handleExpiredAccount(error as Error)) {
        this.terminalLoading = false;
        this.terminalError = errorMessage(error as Error, '无法读取任务终端');
      }
    }
  }

  private terminalSelectionKey(): string {
    return JSON.stringify([this.environmentKey, this.selected?.id ?? '']);
  }

  private attachThreadTerminal(terminalId: string, restart: boolean = false): void {
    const client = this.client;
    const thread = this.selected;
    const selectedSession = this.terminalSessions.find((entry: ThreadTerminalSession) => entry.terminalId === terminalId);
    if (!client || !thread || !this.showThreadTerminal ||
      (!this.threadCanOperateTerminal && (!this.threadCanReadTerminal || !selectedSession))) return;
    const request = ++this.terminalRequest;
    this.terminalConnection?.dispose();
    this.terminalConnection = undefined;
    this.terminalId = terminalId;
    this.terminalSelection.set(this.terminalSelectionKey(), terminalId);
    this.terminalCwd = selectedSession?.cwd || this.threadFilesCwd();
    this.terminalStatus = selectedSession?.status ?? 'starting';
    this.terminalError = '';
    this.terminalLoading = true;
    this.terminalCols = 0;
    this.terminalRows = 0;
    this.terminalOutput.reset('');
    const target: ThreadTerminalTarget = {
      threadId: thread.id,
      terminalId,
      operate: this.threadCanOperateTerminal,
      cwd: this.terminalCwd,
      worktreePath: this.threadWorktree() || null,
      cols: this.terminalRequestedCols || undefined,
      rows: this.terminalRequestedRows || undefined,
      resume: selectedSession !== undefined && !restart,
      restartIfNotRunning: restart,
    };
    try {
      this.terminalConnection = client.watchThreadTerminal(target, (update: NativeTerminalUpdate) => {
        if (request === this.terminalRequest) this.updateThreadTerminal(update);
      }, (error: Error, reconnecting: boolean) => {
        if (request !== this.terminalRequest || this.handleExpiredAccount(error)) return;
        this.terminalLoading = reconnecting;
        this.terminalError = reconnecting ? '正在重新连接终端…' : errorMessage(error, '终端连接已断开');
      });
    } catch (error) {
      this.terminalLoading = false;
      this.terminalError = errorMessage(error as Error, '无法打开任务终端');
    }
  }

  private updateThreadTerminal(update: NativeTerminalUpdate): void {
    if (update.kind === 'output') {
      this.terminalOutput.append(update.data ?? '');
      return;
    }
    if (update.cols !== undefined) this.terminalCols = update.cols;
    if (update.rows !== undefined) this.terminalRows = update.rows;
    this.terminalStatus = update.status;
    if (update.kind === 'snapshot') {
      this.terminalOutput.reset(update.history ?? '');
      this.terminalLoading = false;
      this.terminalError = update.message ?? '';
      if (!this.terminalSessions.some((entry: ThreadTerminalSession) => entry.terminalId === this.terminalId)) {
        this.terminalSessions = this.terminalSessions.concat({
          terminalId: this.terminalId, label: update.label || this.terminalId, cwd: this.terminalCwd,
          status: update.status, hasRunningSubprocess: update.hasRunningSubprocess,
        });
      }
      if (update.status === 'running' && this.terminalRequestedCols && this.terminalRequestedRows) {
        void this.applyThreadTerminalResize(this.terminalRequestedCols, this.terminalRequestedRows);
      }
    } else if (update.kind === 'cleared') {
      this.terminalOutput.reset('');
    } else if (update.kind === 'closed') {
      this.terminalLoading = false;
    } else if (update.kind === 'error') {
      this.terminalError = update.message ?? '终端暂时不可用。';
    }
    this.terminalSessions = this.terminalSessions.map((session: ThreadTerminalSession): ThreadTerminalSession => {
      if (session.terminalId !== this.terminalId) return session;
      const label = update.label || session.label;
      const hasRunningSubprocess = update.hasRunningSubprocess ?? session.hasRunningSubprocess;
      if (session.status === update.status && session.label === label &&
        session.hasRunningSubprocess === hasRunningSubprocess) return session;
      return { terminalId: session.terminalId, label, cwd: session.cwd, status: update.status, hasRunningSubprocess };
    });
  }

  private leaveThreadTerminal(): void {
    this.terminalRequest++;
    this.terminalConnection?.dispose();
    this.terminalConnection = undefined;
    this.showThreadTerminal = false;
    this.terminalSessions = [];
    this.terminalId = '';
    this.terminalCwd = '';
    this.terminalStatus = '';
    this.terminalError = '';
    this.terminalLoading = false;
    this.terminalRequestedCols = 0;
    this.terminalRequestedRows = 0;
    this.terminalOutput.reset('');
  }

  private retryThreadTerminal(): void {
    if (this.terminalId) this.attachThreadTerminal(this.terminalId, this.terminalStatus === 'exited' ||
      this.terminalStatus === 'error' || this.terminalStatus === 'closed');
    else void this.openThreadTerminal();
  }

  private async writeThreadTerminal(data: string, reply: boolean): Promise<void> {
    const terminal = this.terminalConnection;
    if (!data || !this.threadCanOperateTerminal || !terminal || this.terminalLoading) return;
    try {
      await terminal.write(data, reply);
    } catch (error) {
      if (!reply && terminal === this.terminalConnection) this.terminalError = errorMessage(error as Error, '终端输入失败');
    }
  }

  private async applyThreadTerminalResize(cols: number, rows: number): Promise<void> {
    const terminal = this.terminalConnection;
    if (!this.threadCanOperateTerminal || !terminal || this.terminalLoading || this.terminalStatus !== 'running') return;
    try {
      await terminal.resize(cols, rows);
    } catch (error) {
      if (terminal === this.terminalConnection) this.terminalError = errorMessage(error as Error, '无法调整终端大小');
    }
  }

  private resizeThreadTerminal(cols: number, rows: number): void {
    if (this.terminalRequestedCols === cols && this.terminalRequestedRows === rows) return;
    this.terminalRequestedCols = cols;
    this.terminalRequestedRows = rows;
    void this.applyThreadTerminalResize(cols, rows);
  }

  private async clearThreadTerminal(): Promise<void> {
    const terminal = this.terminalConnection;
    if (!this.threadCanOperateTerminal || !terminal || this.terminalLoading) return;
    try {
      await terminal.clear();
    } catch (error) {
      if (terminal === this.terminalConnection) this.terminalError = errorMessage(error as Error, '无法清空终端');
    }
  }

  private async closeThreadTerminal(): Promise<void> {
    const terminal = this.terminalConnection;
    if (!this.threadCanOperateTerminal || !terminal || this.terminalLoading) return;
    const terminalId = this.terminalId;
    this.terminalLoading = true;
    try {
      await terminal.close();
      if (terminal !== this.terminalConnection) return;
      this.terminalSessions = this.terminalSessions.filter((entry: ThreadTerminalSession) => entry.terminalId !== terminalId);
      this.terminalSelection.delete(this.terminalSelectionKey());
      const next = this.terminalSessions[0];
      if (next) this.attachThreadTerminal(next.terminalId);
      else this.leaveThreadTerminal();
    } catch (error) {
      if (terminal === this.terminalConnection) {
        this.terminalLoading = false;
        this.terminalError = errorMessage(error as Error, '无法结束终端');
      }
    }
  }

  private openThreadFiles(): void {
    if (!this.threadCanReadFiles || !this.threadFilesCwd()) return;
    this.resumeThreadIndex = this.messageCount > 0 && !this.messageScroller.isAtEnd()
      ? this.firstVisibleThreadIndex : -1;
    this.showThreadFiles = true;
    void this.loadThreadDirectory('');
  }

  private openThreadGit(): void {
    if (!this.threadFilesCwd()) return;
    this.resumeThreadIndex = this.messageCount > 0 && !this.messageScroller.isAtEnd()
      ? this.firstVisibleThreadIndex : -1;
    this.showThreadGit = true;
    void this.loadThreadGit();
  }

  private openThreadReview(): void {
    if (!this.threadCanReadFiles || !this.threadFilesCwd() || this.watchError) return;
    this.resumeThreadIndex = this.messageCount > 0 && !this.messageScroller.isAtEnd()
      ? this.firstVisibleThreadIndex : -1;
    this.showThreadReview = true;
  }

  private openThreadCheckpoint(checkpoint: NativeThreadCheckpointSummary): void {
    if (checkpoint.threadId !== this.selected?.id || this.watchError || this.loadingMessages) return;
    this.resumeThreadIndex = this.messageCount > 0 && !this.messageScroller.isAtEnd() ? this.firstVisibleThreadIndex : -1;
    this.threadReviewCheckpoint = checkpoint;
    this.showThreadReview = true;
  }

  private closeThreadReview(): void {
    this.closeThreadReviewComment();
    this.showThreadReview = false;
    this.threadReviewCheckpoint = undefined;
  }

  private openThreadReviewComment(target: NativeThreadFileReviewCommentTarget): void {
    if (!this.showThreadReview || !this.threadComposerScope()) return;
    this.threadReviewCommentTarget = target;
    this.threadReviewComment = '';
    this.threadReviewCommentError = '';
  }

  private closeThreadReviewComment(): void {
    this.threadReviewCommentTarget = undefined;
    this.threadReviewComment = '';
    this.threadReviewCommentError = '';
  }

  private addThreadReviewComment(comment: string): void {
    const target = this.threadReviewCommentTarget;
    if (!target || !this.threadComposerScope()) return;
    const record = createThreadFileReviewCommentRecord(util.generateRandomUUID(), target, comment);
    if (!record) {
      this.threadReviewCommentError = '请输入有效的评论，或缩短现有内容。';
      return;
    }
    const source = this.draft.trimEnd();
    const text = (source ? source + '\n\n' : '') + composerCommandContextReference(record) + ' ';
    if (text.length > MAX_MESSAGE_CHARS || !this.addCommandContext(record)) {
      this.threadReviewCommentError = '草稿或上下文已满，请缩短后重试。';
      return;
    }
    this.changeDraft(text);
    this.closeThreadReviewComment();
    this.getUIContext().getPromptAction().showToast({ message: '评论已添加到会话草稿' });
  }

  private async loadThreadCheckpoint(): Promise<NativeThreadCheckpointDiff> {
    const checkpoint = this.threadReviewCheckpoint;
    const environmentKey = this.environmentKey;
    if (!this.client || !this.showThreadReview || !checkpoint || checkpoint.threadId !== this.selected?.id) {
      throw new Error('会话已更换，请重新打开本轮变更。');
    }
    return this.client.readThreadCheckpointDiff(environmentKey, checkpoint.threadId, checkpoint.ordinal);
  }

  private async forkReply(source: NativeThreadForkSource, messageId: string): Promise<void> {
    const client = this.client;
    const selected = this.selected;
    const environmentKey = this.environmentKey;
    if (!client || !selected || !environmentKey || !this.canForkReply() || this.replyForkBusyMessage) return;
    const row = this.messages.getData(this.messages.indexOfId('message:' + messageId))?.message?.forkSource;
    if (row?.sourceThreadId !== source.sourceThreadId || row?.runId !== source.runId) return;
    const key = JSON.stringify([environmentKey, source.sourceThreadId, source.runId]);
    const attempt = this.replyForkAttempts.get(key) ?? createThreadForkAttempt();
    this.replyForkAttempts.set(key, attempt);
    const generation = this.threadViewGeneration;
    const index = this.messageCount > 0 && !this.messageScroller.isAtEnd() ? this.firstVisibleThreadIndex : -1;
    this.replyForkBusyMessage = messageId;
    try {
      const fork = await client.forkThreadFromReply(environmentKey, source, attempt, `${selected.title} 分叉`);
      this.replyForkAttempts.delete(key);
      if (this.threadViewGeneration !== generation || this.environmentKey !== environmentKey) return;
      this.threadReturnPoints.set(JSON.stringify([environmentKey, fork.id]), { thread: selected, index, messageId });
      this.openWorkspaceThread(fork);
      void this.refreshThreads();
    } catch (error) {
      if (error instanceof ThreadCommandRejectedError) this.replyForkAttempts.delete(key);
      if (this.threadViewGeneration === generation && this.environmentKey === environmentKey) {
        this.getUIContext().getPromptAction().showToast({ message: errorMessage(error as Error,
          '无法确认分叉，请重新连接后检查会话列表。') });
      }
    } finally {
      this.replyForkBusyMessage = '';
    }
  }

  private canForkReply(): boolean {
    return this.threadAccess === 'allowed' && !this.loadingMessages && !this.watchError && !this.sending &&
      !this.threadActionBusy && !this.pairing;
  }

  private closeThreadAgents(): void {
    this.pendingLinkedThreadTarget = undefined;
    this.showThreadAgents = false;
    this.openingThreadAgent = '';
    this.threadAgentsError = '';
  }

  private backgroundWorkKey(threadId: string): string {
    return JSON.stringify([this.environmentKey, threadId]);
  }

  private watchBackgroundTasks(): void {
    const client = this.client;
    const thread = this.selected;
    if (!client || !thread) return;
    this.stopBackgroundWatch();
    this.backgroundWorkWaiting = true;
    this.backgroundWorkError = '';
    const generation = this.backgroundWatchGeneration;
    const scope = this.backgroundWorkKey(thread.id);
    const fail = (error: Error): void => {
      if (this.backgroundWatchGeneration !== generation) return;
      this.backgroundUnsubscribe = undefined;
      this.backgroundWorkWaiting = false;
      this.backgroundWorkReady = false;
      this.backgroundWorkError = errorMessage(error, '无法读取后台工作。');
    };
    try {
      this.backgroundUnsubscribe = client.watchBackgroundWork(this.environmentKey, thread.id, (row?: NativeThread) => {
        if (this.backgroundWatchGeneration !== generation) return;
        const followLatest = !this.showBackgroundWork && !this.showThreadFiles && !this.showThreadGit &&
          !this.showThreadReview && !this.showThreadTerminal && this.messageCount > 0 && this.messageScroller.isAtEnd();
        const previousCount = this.backgroundTasks.length;
        this.backgroundWorkWaiting = false;
        this.backgroundWorkReady = true;
        this.backgroundWorkError = '';
        this.backgroundTasks = row?.pendingBackgroundTasks ?? [];
        this.backgroundLatestRunId = row?.latestRunId ?? '';
        const stop = this.backgroundStopRequests.get(scope);
        if (stop && stop.timer !== -1 && !this.backgroundTasks.some((task) => stop.taskIds.has(task.taskId))) {
          this.finishBackgroundStop(scope, stop);
        }
        if (followLatest && previousCount === 0 && this.backgroundTasks.length > 0) {
          this.getUIContext().postFrameCallback(new AfterLayout(() => {
            if (this.backgroundWatchGeneration === generation && this.showBackgroundWorkStatus()) {
              this.messageScroller.scrollToIndex(this.lastThreadFeedIndex(), false, ScrollAlign.END);
            }
          }));
        }
      }, fail);
    } catch (error) {
      fail(error as Error);
    }
  }

  private stopBackgroundWatch(): void {
    this.backgroundWatchGeneration++;
    this.backgroundUnsubscribe?.();
    this.backgroundUnsubscribe = undefined;
    this.backgroundWorkWaiting = false;
    this.backgroundWorkReady = false;
  }

  private showBackgroundWorkStatus(): boolean {
    return this.backgroundTasks.length > 0 && !this.loadingMessages;
  }

  private lastThreadFeedIndex(): number {
    return Math.max(0, this.messageCount - 1 + this.threadHistoryHeaderSize() + (this.showBackgroundWorkStatus() ? 1 : 0));
  }

  private openBackgroundWork(): void {
    this.getUIContext().getFocusController().clearFocus();
    this.showBackgroundWork = true;
    if (this.backgroundUnsubscribe === undefined) this.watchBackgroundTasks();
  }

  private closeBackgroundWork(): void {
    this.showBackgroundWork = false;
    this.backgroundChildOpening = '';
  }

  private async openBackgroundChild(threadId: string): Promise<void> {
    const client = this.client;
    const parent = this.selected;
    if (!client || !parent || !threadId || parent.id === threadId || !this.showBackgroundWork ||
      this.backgroundChildOpening || this.pairing || this.sending ||
      !this.backgroundTasks.some((task) => task.kind === 'subagent' && task.childThreadId === threadId)) return;
    const generation = this.threadViewGeneration;
    const environmentKey = this.environmentKey;
    this.backgroundChildOpening = threadId;
    try {
      const child = this.allThreads.find((row: NativeThread) =>
        row.id === threadId && row.environmentKey === environmentKey) ?? await client.readThreadLinkTarget(threadId);
      if (this.threadViewGeneration === generation && this.showBackgroundWork && this.backgroundChildOpening === threadId &&
        client.currentEnvironment()?.key === environmentKey) this.openRelatedThread(parent, child);
    } catch (error) {
      if (this.threadViewGeneration === generation && this.showBackgroundWork && this.backgroundChildOpening === threadId) {
        this.getUIContext().getPromptAction().showToast({
          message: errorMessage(error as Error, '无法打开后台子会话。'),
        });
      }
    } finally {
      if (this.backgroundChildOpening === threadId) this.backgroundChildOpening = '';
    }
  }

  private canStopBackgroundWork(): boolean {
    return this.threadAccess === 'allowed' && this.backgroundWorkReady && !this.pairing &&
      !this.watchError && !this.threadActionBusy && !this.sending;
  }

  private finishBackgroundStop(scope: string, request: BackgroundWorkStop): void {
    if (this.backgroundStopRequests.get(scope) !== request) return;
    clearTimeout(request.timer);
    this.backgroundStopRequests.delete(scope);
    if (this.selected && this.backgroundWorkKey(this.selected.id) === scope) this.backgroundStopping = false;
  }

  private async stopBackgroundWork(): Promise<void> {
    const client = this.client;
    const thread = this.selected;
    const detail = this.threadDetail;
    if (!client || !thread || !detail || !this.canStopBackgroundWork() || this.backgroundTasks.length === 0) return;
    const scope = this.backgroundWorkKey(thread.id);
    if (this.backgroundStopRequests.has(scope)) return;
    const generation = this.threadViewGeneration;
    const environmentKey = this.environmentKey;
    const request: BackgroundWorkStop = {
      taskIds: new Set<string>(this.backgroundTasks.map((task) => task.taskId)), timer: -1,
    };
    const sameView = (): boolean => this.threadViewGeneration === generation && this.environmentKey === environmentKey;
    const hasOriginalTasks = (): boolean => this.backgroundTasks.some((task) => request.taskIds.has(task.taskId));
    this.backgroundStopRequests.set(scope, request);
    this.backgroundStopping = true;
    try {
      const runId = detail.backgroundStopRunId ||
        (hasNativeThreadBackgroundWork(this.backgroundTasks) ? this.backgroundLatestRunId : '');
      await client.stopBackgroundWork(environmentKey, thread.id, runId, detail.backgroundStopWatches,
        () => sameView() && this.canStopBackgroundWork() && hasOriginalTasks());
      if (this.backgroundStopRequests.get(scope) !== request) return;
      if (sameView() && !hasOriginalTasks()) {
        this.finishBackgroundStop(scope, request);
      } else {
        // Host acceptance precedes shell removal. Android allows another attempt after ten seconds.
        request.timer = setTimeout(() => this.finishBackgroundStop(scope, request), 10000);
      }
    } catch (error) {
      this.finishBackgroundStop(scope, request);
      if (sameView() && hasOriginalTasks() && !this.handleExpiredAccount(error as Error)) {
        this.getUIContext().getPromptAction().showToast({
          message: errorMessage(error as Error, '无法停止后台工作。'),
        });
      }
    }
  }

  private threadAgentRows(): ThreadAgentSheetRow[] {
    return (this.threadDetail?.subagents?.subagents ?? []).map((agent: NativeThreadSubagent): ThreadAgentSheetRow => {
      const seconds = agent.startedAt ? Math.max(0, Math.floor(
        ((agent.completedAt ? Date.parse(agent.completedAt) : Date.now()) - Date.parse(agent.startedAt)) / 1000)) : 0;
      const prompt = agent.prompt.trim();
      return {
        id: agent.id,
        title: agent.title?.trim() || (prompt.length > 80 ? prompt.slice(0, 77) + '…' : prompt) || '子代理',
        status: agent.status,
        description: agent.progress?.trim() || agent.result?.trim() || prompt,
        elapsedText: seconds > 59 ? Math.floor(seconds / 60) + '分 ' + seconds % 60 + '秒' :
          seconds > 0 ? seconds + '秒' : undefined,
        metadata: agent.remoteChild?.label ?? agent.executedModel ?? agent.model ?? undefined,
        canOpen: !!agent.childThreadId || agent.remoteChild !== undefined,
        canStop: false,
      };
    });
  }

  private async openThreadAgent(agentId: string): Promise<void> {
    const client = this.client;
    const parent = this.selected;
    const environment = client?.currentEnvironment();
    const agent = this.threadDetail?.subagents?.subagents.find((row: NativeThreadSubagent) => row.id === agentId);
    if (!client || !parent || !environment || !agent || !this.showThreadAgents ||
      this.openingThreadAgent || this.sending || this.threadActionBusy || this.pairing) return;
    const title = this.threadAgentRows().find((row: ThreadAgentSheetRow) => row.id === agentId)?.title ?? '';
    if (!agent.childThreadId) {
      const remote = agent.remoteChild;
      if (remote && remote.environmentId !== environment.environmentId) {
        this.pendingLinkedThreadTarget = {
          environmentId: remote.environmentId, threadId: remote.threadId, label: remote.label,
          title: remote.title ?? title, sourceEnvironmentId: environment.environmentId, sourceLabel: environment.label,
        };
        this.showThreadAgents = false;
      }
      return;
    }
    if (agent.childThreadId === parent.id) return;
    const generation = this.threadViewGeneration;
    this.openingThreadAgent = agentId;
    this.threadAgentsError = '';
    try {
      const thread = this.allThreads.find((row: NativeThread) =>
        row.id === agent.childThreadId && row.environmentKey === environment.key) ??
        await client.readThreadLinkTarget(agent.childThreadId);
      if (this.threadViewGeneration === generation && this.showThreadAgents && this.openingThreadAgent === agentId &&
        client.currentEnvironment()?.key === environment.key) {
        this.openRelatedThread(parent, thread);
      }
    } catch (error) {
      if (this.threadViewGeneration === generation && this.openingThreadAgent === agentId) {
        this.threadAgentsError = errorMessage(error as Error, '无法打开此子代理会话。');
      }
    } finally {
      if (this.openingThreadAgent === agentId) this.openingThreadAgent = '';
    }
  }

  private onThreadAgentsDisappear(): void {
    const target = this.pendingLinkedThreadTarget;
    this.closeThreadAgents();
    if (this.selected && target) {
      this.linkedThreadTarget = target;
      this.watchLinkedThreadView();
    }
  }

  private watchLinkedThreadView(): void {
    const client = this.client;
    const target = this.linkedThreadTarget;
    if (!client || !target) return;
    this.stopLinkedThreadView();
    const generation = this.linkedThreadGeneration;
    this.linkedThreadLoading = true;
    this.linkedThreadError = '';
    const fail = (error: Error): void => {
      if (generation !== this.linkedThreadGeneration) return;
      this.linkedThreadLoading = false;
      this.linkedThreadError = errorMessage(error, '无法读取关联会话。');
      this.linkedThreadWorking = false;
      if (error instanceof LinkedThreadUnavailableError && error.accessLost) {
        this.linkedThreadTitle = target.title;
        this.clearLinkedThreadTranscript();
      }
    };
    try {
      this.linkedThreadUnsubscribe = client.watchLinkedThread(target.sourceEnvironmentId, target.environmentId,
        target.threadId, (messages: NativeMessage[], detail: NativeThreadDetail, historyCursor?: string) => {
          if (generation !== this.linkedThreadGeneration) return;
          if (this.linkedThreadSnapshotCursor !== historyCursor) {
            this.linkedThreadSnapshotCursor = historyCursor;
            this.linkedThreadHistoryCursor = historyCursor;
            this.linkedThreadOlderMessages = [];
            this.linkedThreadOlderWork.clear();
            this.linkedThreadHistoryError = '';
          }
          this.linkedThreadLoading = false;
          this.linkedThreadRecentMessages = messages;
          this.linkedThreadRecentWork = detail.work;
          this.updateLinkedThreadTranscript();
          this.linkedThreadWorking = detail.runBusy;
          this.linkedThreadTitle = detail.title || target.title;
        }, fail);
    } catch (error) {
      fail(error as Error);
    }
  }

  private async connectToLinkedThread(): Promise<void> {
    const target = this.linkedThreadTarget;
    const client = this.client;
    if (!target || !client || this.pairing || this.linkedThreadConnecting) return;
    if (this.environments.some((entry: EnvironmentSummary) =>
      entry.environmentId === target.environmentId && entry.enabled)) {
      await this.openDirectLinkedThread(target);
      return;
    }
    this.linkedThreadConnecting = true;
    this.pairing = true;
    this.linkedThreadConnectionError = '';
    let paired = false;
    try {
      const result = await client.pairLinkedThreadEnvironment(target.sourceEnvironmentId, target.environmentId,
        target.threadId, () => this.linkedThreadTarget === target);
      if (this.linkedThreadTarget !== target) return;
      if (result.status === 'paired') paired = true;
      else if (result.status === 'manual') {
        this.linkedPairingReturnFullscreen = this.linkedThreadFullscreen;
        this.linkedPairingAddress = result.address;
        this.linkedPairingLink = '';
        this.linkedPairingManual = true;
        this.linkedThreadFullscreen = true;
        this.stopLinkedThreadView();
      } else {
        this.linkedThreadConnectionError = '此设备无法访问 ' + target.label + '，请检查网络后重试。';
      }
    } catch (error) {
      if (this.linkedThreadTarget === target) {
        this.linkedThreadConnectionError = errorMessage(error as Error, '无法连接关联环境。');
      }
    } finally {
      this.linkedThreadConnecting = false;
      this.pairing = false;
    }
    if (paired && this.linkedThreadTarget === target) await this.openDirectLinkedThread(target);
  }

  private backFromLinkedPairing(): void {
    this.linkedPairingManual = false;
    this.linkedPairingAddress = '';
    this.linkedPairingLink = '';
    this.linkedThreadConnectionError = '';
    this.linkedThreadFullscreen = this.linkedPairingReturnFullscreen;
    this.watchLinkedThreadView();
  }

  private async pairLinkedThreadManually(address: string, code: string): Promise<void> {
    const target = this.linkedThreadTarget;
    const client = this.client;
    if (!target || !client || !this.linkedPairingManual || this.scanning || this.pairing) return;
    this.linkedThreadConnecting = true;
    this.pairing = true;
    this.linkedThreadConnectionError = '';
    let paired = false;
    try {
      if (address.trim() || code.trim()) await client.pairAddress(address, code, target.environmentId);
      else await client.pair(this.linkedPairingLink.trim(), target.environmentId);
      paired = true;
    } catch (error) {
      if (this.linkedThreadTarget === target) {
        this.linkedThreadConnectionError = errorMessage(error as Error, '无法配对关联环境。');
      }
    } finally {
      this.linkedThreadConnecting = false;
      this.pairing = false;
    }
    if (paired && this.linkedThreadTarget === target) await this.openDirectLinkedThread(target);
  }

  private async openDirectLinkedThread(target: LinkedThreadTarget): Promise<void> {
    const source = this.selected;
    if (!source) return;
    const sourceIndex = this.messageCount > 0 && !this.messageScroller.isAtEnd() ? this.firstVisibleThreadIndex : -1;
    const sourceMessageId = sourceIndex < 0 ? undefined :
      this.messages.getData(Math.max(0, sourceIndex - this.threadHistoryHeaderSize()))?.message?.id;
    const uri = `t3code://threads/${encodeURIComponent(target.environmentId)}/${encodeURIComponent(target.threadId)}`;
    this.linkedThreadConnecting = true;
    try {
      await this.openLinkedThread(target.environmentId, target.threadId, uri);
      if (this.selected?.id === target.threadId && this.client?.currentEnvironment()?.environmentId === target.environmentId) {
        this.linkedDirectReturn = {
          sourceEnvironmentId: target.sourceEnvironmentId, sourceThreadId: source.id, sourceMessageId, sourceIndex,
          environmentId: target.environmentId, threadId: target.threadId,
        };
      }
    } finally {
      this.linkedThreadConnecting = false;
    }
  }

  private async returnToLinkedSource(parent: LinkedDirectReturn): Promise<void> {
    const uri = `t3code://threads/${encodeURIComponent(parent.sourceEnvironmentId)}/${encodeURIComponent(parent.sourceThreadId)}`;
    await this.openLinkedThread(parent.sourceEnvironmentId, parent.sourceThreadId, uri, parent.sourceMessageId);
    if (this.selected?.id === parent.sourceThreadId &&
      this.client?.currentEnvironment()?.environmentId === parent.sourceEnvironmentId) {
      this.linkedDirectReturn = undefined;
      this.resumeThreadIndex = parent.sourceIndex;
    }
  }

  private updateLinkedThreadTranscript(): void {
    this.linkedThreadMessages = mergeMessages(this.linkedThreadOlderMessages, this.linkedThreadRecentMessages);
    const work = new Map(this.linkedThreadOlderWork);
    for (const item of this.linkedThreadRecentWork) work.set(item.id, item);
    this.linkedThreadWork = Array.from(work.values());
  }

  private async loadEarlierLinkedThread(): Promise<void> {
    const target = this.linkedThreadTarget;
    const client = this.client;
    const cursor = this.linkedThreadHistoryCursor;
    if (!target || !client || !cursor || this.linkedThreadHistoryLoading || this.linkedThreadError) return;
    const generation = this.linkedThreadGeneration;
    this.linkedThreadHistoryLoading = true;
    this.linkedThreadHistoryError = '';
    try {
      const earlier = await client.readLinkedThreadHistory(target.sourceEnvironmentId, target.environmentId,
        target.threadId, cursor);
      if (this.linkedThreadGeneration !== generation || this.linkedThreadHistoryCursor !== cursor) return;
      this.linkedThreadOlderMessages = mergeMessages(earlier.messages, this.linkedThreadOlderMessages);
      for (const item of readHistoricalThreadWork(earlier.visibleTurnItems)) this.linkedThreadOlderWork.set(item.id, item);
      this.linkedThreadHistoryCursor = earlier.nextCursor;
      this.updateLinkedThreadTranscript();
    } catch (_) {
      if (this.linkedThreadGeneration === generation && this.linkedThreadHistoryCursor === cursor) {
        this.linkedThreadHistoryError = '无法读取较早的内容，请重试。';
      }
    } finally {
      if (this.linkedThreadGeneration === generation) this.linkedThreadHistoryLoading = false;
    }
  }

  private async readLinkedThreadOutput(item: NativeThreadWork): Promise<string> {
    const target = this.linkedThreadTarget;
    const client = this.client;
    const generation = this.linkedThreadGeneration;
    if (!target || !client || this.linkedThreadError || !this.linkedThreadWork.some((row: NativeThreadWork) =>
      row.id === item.id && row.threadId === item.threadId && row.wantsOutput)) {
      throw new Error('关联会话已更换或不可读。');
    }
    const output = await client.readLinkedThreadWork(target.sourceEnvironmentId, target.environmentId,
      item.threadId, item.id);
    if (this.linkedThreadGeneration !== generation || this.linkedThreadError) {
      throw new Error('关联会话已更换或不可读。');
    }
    return output;
  }

  private stopLinkedThreadView(): void {
    this.linkedThreadGeneration++;
    this.linkedThreadUnsubscribe?.();
    this.linkedThreadUnsubscribe = undefined;
    this.linkedThreadHistoryLoading = false;
  }

  private clearLinkedThreadTranscript(): void {
    this.linkedThreadHistoryCursor = undefined;
    this.linkedThreadSnapshotCursor = undefined;
    this.linkedThreadHistoryError = '';
    this.linkedThreadRecentMessages = [];
    this.linkedThreadOlderMessages = [];
    this.linkedThreadRecentWork = [];
    this.linkedThreadOlderWork.clear();
    this.linkedThreadMessages = [];
    this.linkedThreadWork = [];
  }

  private closeLinkedThreadView(): void {
    this.stopLinkedThreadView();
    this.linkedThreadTarget = undefined;
    this.linkedThreadFullscreen = false;
    this.linkedThreadLoading = false;
    this.linkedThreadError = '';
    this.linkedThreadTitle = '';
    this.clearLinkedThreadTranscript();
    this.linkedThreadWorking = false;
    this.linkedThreadConnectionError = '';
    this.linkedPairingManual = false;
    this.linkedPairingAddress = '';
    this.linkedPairingLink = '';
  }

  private updateSideChats(): void {
    const parent = this.selected;
    if (!parent) {
      this.sideChats = [];
      return;
    }
    this.sideChats = this.allThreads.filter((thread: NativeThread) => thread.environmentKey === this.environmentKey &&
      thread.id !== parent.id && thread.lineage?.sideChat === true && thread.lineage.parentThreadId === parent.id && !thread.deletedAt)
      .map((thread: NativeThread): ThreadSideChatItem => {
        const kind = thread.pendingRuntimeRequest?.kind;
        const item: ThreadSideChatItem = { threadId: thread.id, title: thread.title };
        if (kind && kind !== 'auth_refresh') item.needs = kind === 'user_input' ? 'input' : 'approval';
        return item;
      });
  }

  private openSideChat(threadId: string): void {
    const parent = this.selected;
    if (!parent || parent.id === threadId || this.sending || this.threadActionBusy || this.pairing) return;
    const thread = this.allThreads.find((row: NativeThread) => row.environmentKey === this.environmentKey &&
      row.id === threadId && row.lineage?.sideChat === true && row.lineage.parentThreadId === parent.id && !row.deletedAt);
    if (!thread) return;
    this.openRelatedThread(parent, thread);
  }

  private openRelatedThread(parent: NativeThread, thread: NativeThread): void {
    const index = this.messageCount > 0 && !this.messageScroller.isAtEnd() ? this.firstVisibleThreadIndex : -1;
    const messageId = index < 0 ? undefined :
      this.messages.getData(Math.max(0, index - this.threadHistoryHeaderSize()))?.message?.id;
    this.threadReturnPoints.set(JSON.stringify([this.environmentKey, thread.id]), { thread: parent, index, messageId });
    this.openThread(thread);
  }

  private closeThreadGit(): void {
    this.closeThreadReview();
    this.threadGitRequest++;
    this.showThreadGit = false;
    this.threadGitPane = 'status';
    this.threadGitLoading = false;
    this.threadGitMutation = false;
    this.threadGitError = '';
    this.threadGitStatus = undefined;
  }

  private async loadThreadReview(cwd: string): Promise<NativeThreadReview> {
    if (!this.client || !cwd || !this.showThreadReview || this.threadReviewCheckpoint ||
      cwd !== this.threadFilesCwd() || !this.threadCanReadFiles) {
      throw new Error('此连接缺少读取工作区改动的权限。');
    }
    return this.client.readThreadReview(cwd);
  }

  private async loadThreadReviewFile(cwd: string, file: NativeThreadReviewFile,
    baseRef: string | null): Promise<NativeThreadReviewPatch> {
    if (!this.client || !cwd || !this.showThreadReview || this.threadReviewCheckpoint ||
      cwd !== this.threadFilesCwd() || !this.threadCanReadFiles) {
      throw new Error('此连接缺少读取文件改动的权限。');
    }
    return this.client.readThreadReviewFile(cwd, file, baseRef);
  }

  private async listThreadGitRefs(query: string, cursor: number | null): Promise<NativeThreadGitRefs> {
    const client = this.client;
    const cwd = this.threadFilesCwd();
    if (!client || !cwd || !this.showThreadGit) throw new Error('当前工作区已更换。');
    const result = await client.listThreadGitRefs(cwd, query, cursor);
    if (cwd !== this.threadFilesCwd() || !this.showThreadGit) throw new Error('当前工作区已更换。');
    return result;
  }

  private async changeThreadGitBranch(refName: string, create: boolean): Promise<void> {
    const client = this.client;
    const thread = this.selected;
    const cwd = this.threadFilesCwd();
    if (!client || !thread || !cwd || !this.showThreadGit || this.threadGitMutation ||
      !this.threadCanWriteGit || this.threadAccess !== 'allowed' || this.watchError) {
      throw new Error('当前无法更改分支，请检查连接和权限。');
    }
    const generation = this.threadViewGeneration;
    this.threadGitMutation = true;
    try {
      await client.changeThreadGitBranch(cwd, thread.id, this.threadWorktree() || null, refName, create);
    } finally {
      if (generation === this.threadViewGeneration) {
        this.threadGitMutation = false;
        await this.loadThreadGit();
      }
    }
  }

  private async commitThreadGit(message: string, filePaths?: string[]): Promise<NativeThreadGitCommitResult> {
    const client = this.client;
    const thread = this.selected;
    const cwd = this.threadFilesCwd();
    if (!client || !thread || !cwd || !this.showThreadGit || this.threadGitMutation ||
      !this.threadCanWriteGit || this.watchError) {
      throw new Error('当前无法提交代码，请检查连接和权限。');
    }
    const generation = this.threadViewGeneration;
    this.threadGitMutation = true;
    try {
      return await client.commitThreadGit(cwd, message, filePaths, thread.id, thread.projectId);
    } finally {
      if (generation === this.threadViewGeneration) {
        this.threadGitMutation = false;
        await this.loadThreadGit();
      }
    }
  }

  private async pullThreadGit(): Promise<NativeThreadGitPullResult> {
    const client = this.client;
    const cwd = this.threadFilesCwd();
    const refName = this.threadGitStatus?.refName;
    if (!client || !cwd || !refName || !this.showThreadGit || this.threadGitMutation ||
      !this.threadCanWriteGit || this.watchError || !canPullThreadGit(this.threadGitStatus)) {
      throw new Error('当前分支无法拉取，请刷新 Git 状态。');
    }
    const generation = this.threadViewGeneration;
    this.threadGitMutation = true;
    try {
      return await client.pullThreadGit(cwd, refName);
    } finally {
      if (generation === this.threadViewGeneration) {
        this.threadGitMutation = false;
        await this.loadThreadGit();
      }
      this.showIncomingPairing();
    }
  }

  private async pushThreadGit(refName: string, confirmedDefault: boolean): Promise<NativeThreadGitPushResult> {
    const client = this.client;
    const thread = this.selected;
    const cwd = this.threadFilesCwd();
    if (!client || !thread || !cwd || !this.showThreadGit || this.threadGitMutation ||
      !this.threadCanWriteGit || this.watchError || this.threadGitStatus?.refName !== refName ||
      !canPushThreadGit(this.threadGitStatus)) {
      throw new Error('当前分支无法推送，请刷新 Git 状态。');
    }
    const generation = this.threadViewGeneration;
    this.threadGitMutation = true;
    try {
      return await client.pushThreadGit(cwd, refName, confirmedDefault, thread.id, thread.projectId);
    } finally {
      if (generation === this.threadViewGeneration) {
        this.threadGitMutation = false;
        await this.loadThreadGit();
      }
      this.showIncomingPairing();
    }
  }

  private async loadThreadGit(): Promise<void> {
    const cwd = this.threadFilesCwd();
    const client = this.client;
    if (!cwd || !client || !this.showThreadGit) return;
    const request = ++this.threadGitRequest;
    this.threadGitLoading = true;
    this.threadGitError = '';
    try {
      const status = await client.threadGitStatus(cwd, false);
      if (request === this.threadGitRequest) this.threadGitStatus = status;
    } catch (error) {
      if (request === this.threadGitRequest && !this.handleExpiredAccount(error as Error)) {
        this.threadGitError = errorMessage(error as Error, '无法读取 Git 状态');
      }
    } finally {
      if (request === this.threadGitRequest) this.threadGitLoading = false;
    }
  }

  private closeThreadFiles(): void {
    this.filesGeneration++;
    this.showThreadFiles = false;
    this.filesDirectory = '';
    this.filesEntries = [];
    this.filesPreview = undefined;
    this.filesBusy = false;
    this.filesTruncated = false;
    this.filesError = '';
    this.filesSearchOpen = false;
    this.fileTarget = '';
  }

  private backFromThreadFiles(): void {
    if (this.fileTarget) {
      this.filesGeneration++;
      this.fileTarget = '';
      this.filesPreview = undefined;
      this.filesError = '';
      this.filesBusy = false;
    } else if (this.filesSearchOpen) {
      this.filesSearchOpen = false;
    } else if (this.filesDirectory) {
      void this.loadThreadDirectory(this.filesDirectory.slice(0, Math.max(0, this.filesDirectory.lastIndexOf('/'))));
    } else {
      this.closeThreadFiles();
    }
  }

  private async searchThreadFiles(query: string): Promise<NativeThreadFileDirectory> {
    const client = this.client;
    const cwd = this.threadFilesCwd();
    if (!client || !cwd || !this.threadCanReadFiles || !this.showThreadFiles) {
      throw new Error('当前工作区的文件不可访问。');
    }
    return client.searchThreadFiles(cwd, query);
  }

  private async loadThreadDirectory(path: string): Promise<void> {
    const client = this.client;
    const cwd = this.threadFilesCwd();
    if (!client || !cwd || !this.threadCanReadFiles || !this.showThreadFiles) return;
    const generation = ++this.filesGeneration;
    if (path !== this.filesDirectory) this.filesEntries = [];
    this.filesDirectory = path;
    this.filesPreview = undefined;
    this.fileTarget = '';
    this.filesBusy = true;
    this.filesError = '';
    this.filesTruncated = false;
    try {
      const result = await client.listThreadFiles(cwd, path);
      if (this.filesGeneration !== generation) return;
      this.filesEntries = result.entries;
      this.filesTruncated = result.truncated;
    } catch (error) {
      if (this.filesGeneration === generation) this.filesError = errorMessage(error as Error, '无法读取文件目录');
    } finally {
      if (this.filesGeneration === generation) this.filesBusy = false;
    }
  }

  private async previewThreadFile(path: string): Promise<void> {
    const client = this.client;
    const cwd = this.threadFilesCwd();
    if (!client || !cwd || !this.threadCanReadFiles || !this.showThreadFiles) return;
    const generation = ++this.filesGeneration;
    this.fileTarget = path;
    this.filesBusy = true;
    this.filesError = '';
    try {
      const result = await client.readThreadFile(cwd, path);
      if (this.filesGeneration === generation) this.filesPreview = result;
    } catch (error) {
      if (this.filesGeneration === generation) this.filesError = errorMessage(error as Error, '无法读取文件内容');
    } finally {
      if (this.filesGeneration === generation) this.filesBusy = false;
    }
  }

  private openFileEntry(entry: NativeThreadFileEntry): void {
    if (entry.kind === 'directory') void this.loadThreadDirectory(entry.path);
    else void this.previewThreadFile(entry.path);
  }

  private composerAction(): string {
    const detail = this.threadDetail;
    if (detail?.userInput) return detail.userInput.stopRunId ? 'stop' : 'send';
    if (detail?.approval?.supportsFeedback && this.draft.trim()) return 'send';
    if (this.draft.trim() || this.draftAttachments.length > 0 || this.draftQuotes.length > 0 ||
      this.draftTerminalContexts.length > 0) {
      return detail?.runBusy === true || (detail?.queuedCount ?? 0) > 0 ? 'queue' : 'send';
    }
    if (detail?.activeRunId) return 'stop';
    if (detail?.queueHeld && !detail.runBusy) return 'resume';
    return 'send';
  }

  private async runThreadAction(requestId?: string, decision?: string): Promise<void> {
    const client = this.client;
    const thread = this.selected;
    const detail = this.threadDetail;
    if (!client || !thread || !detail || this.threadAccess !== 'allowed' || this.threadActionBusy ||
      this.sending || this.loadingMessages || this.watchError) return;
    const action = this.composerAction();
    const approval = detail.approval;
    let feedback: string | undefined;
    if (decision === undefined && (action === 'send' || action === 'queue')) {
      if (detail.userInput) return;
      if (approval?.supportsFeedback) {
        if (this.draftAttachments.length > 0 || this.draftQuotes.length > 0 || this.draftTerminalContexts.length > 0) {
          this.sendError = '审批反馈只能发送文字，请先移除附件和引用。';
          return;
        }
        if (!this.draft.trim() || this.draft.length > MAX_MESSAGE_CHARS) {
          this.sendError = '请输入有效的审批反馈。';
          return;
        }
        feedback = this.draft;
      } else {
        await this.send(action === 'queue');
        return;
      }
    }
    if (decision !== undefined && (!approval?.canRespond || approval.id !== requestId ||
      !approval.options.some((option) => option.decision === decision))) return;
    const generation = this.threadViewGeneration;
    this.threadActionBusy = true;
    this.sendError = '';
    try {
      if (feedback !== undefined && approval) {
        await client.respondThreadApproval(thread.id, approval.id, 'decline', feedback);
        if (this.threadViewGeneration === generation && this.draft === feedback) this.changeDraft('');
      } else if (decision !== undefined && approval) await client.respondThreadApproval(thread.id, approval.id, decision);
      else if (action === 'stop') await client.interruptThread(thread.id, detail.userInput?.stopRunId || detail.activeRunId);
      else if (action === 'resume') await client.resumeThreadQueue(thread.id);
    } catch (error) {
      if (this.threadViewGeneration === generation) this.sendError = errorMessage(error as Error, '操作失败');
    } finally {
      if (this.threadViewGeneration === generation) this.threadActionBusy = false;
      this.showIncomingPairing();
    }
  }

  private async answerThreadQuestion(requestId: string, answers?: NativeThreadUserInputAnswers): Promise<void> {
    const client = this.client;
    const thread = this.selected;
    const question = this.threadDetail?.userInput;
    if (!client || !thread || !question || question.id !== requestId || this.threadAccess !== 'allowed' ||
      this.threadActionBusy || this.sending || this.loadingMessages || this.watchError ||
      (answers ? !question.canRespond : !question.dismissible)) return;
    const generation = this.threadViewGeneration;
    this.threadActionBusy = true;
    this.sendError = '';
    try {
      await client.respondThreadQuestion(thread.id, requestId, answers);
    } catch (error) {
      if (generation === this.threadViewGeneration) this.sendError = errorMessage(error as Error, '无法处理提问');
    } finally {
      if (generation === this.threadViewGeneration) this.threadActionBusy = false;
      this.showIncomingPairing();
    }
  }

  private approvalOptions(): ThreadDetailApprovalOption[] {
    const approval = this.threadDetail?.approval;
    return approval?.options.map((option): ThreadDetailApprovalOption => ({
      requestId: approval.id,
      decision: option.decision,
      label: option.label,
    })) ?? [];
  }

  private async changeQueuedRun(action: 'send' | 'edit' | 'remove', runId: string,
    text: string = ''): Promise<boolean> {
    const client = this.client;
    const thread = this.selected;
    const detail = this.threadDetail;
    if (!client || !thread || !detail || this.threadAccess !== 'allowed' || this.pairing || this.threadActionBusy ||
      this.sending || this.loadingMessages || this.watchError) return false;
    const row = detail.queuedMessages.find((message) => message.runId === runId);
    if (!row || (action === 'send' && !row.canSendNow) ||
      (action === 'edit' && (!row.canEdit || detail.queueEditBlocked))) return false;
    const generation = this.threadViewGeneration;
    this.threadActionBusy = true;
    this.sendError = '';
    try {
      if (action === 'send') await client.startQueuedRun(thread.id, runId, row.targetRunId);
      else if (action === 'edit') await client.editQueuedRun(thread.id, runId, text);
      else await client.removeQueuedRun(thread.id, runId);
      return this.threadViewGeneration === generation;
    } catch (error) {
      if (this.threadViewGeneration === generation) this.sendError = errorMessage(error as Error, '队列操作失败');
      return false;
    } finally {
      if (this.threadViewGeneration === generation) this.threadActionBusy = false;
      this.showIncomingPairing();
    }
  }

  @Builder
  private ThreadModelSheet() {
    ThreadModelPicker({
      language: this.uiLanguage(),
      providers: this.threadModelProviders,
      selection: this.displayedThreadModel(),
      currentProviderInstanceId: this.threadDetail?.modelSelection?.instanceId ?? '',
      loading: this.threadModelLoading,
      applying: this.threadModelApplying,
      error: this.threadModelError,
      showRuntime: this.showThreadRuntime,
      runtimeMode: this.threadRuntimeDraft ?? this.threadDetail?.runtimeMode,
      maxRuntimeMode: this.threadRuntimeCeiling,
      parameters: threadModelOptionDescriptors(this.threadModelFromCatalog(this.displayedThreadModel()),
        this.displayedThreadModel(), this.threadModelPendingPrompt ?? this.draft),
      parameterId: this.threadModelParameterId,
      pendingModel: this.threadModelPending !== undefined,
      modelCatalog: this.threadModelCatalog,
      canWriteCatalog: this.threadModelCatalogCanWrite,
      canSwitchProvider: this.threadDetail?.canSwitchProvider === true,
      onChoose: (selection: ThreadLaunchSelection) => this.previewThreadModel(selection),
      onSaveModel: () => this.savePendingThreadModel(),
      onOpenParameter: (id: string) => { this.threadModelParameterId = id; },
      onBackParameter: () => { this.threadModelParameterId = ''; },
      onChangeParameter: (id: string, value: string | boolean) => this.updateThreadModelParameter(id, value),
      onChangeCatalog: (provider: string, model: string, kind: ModelCatalogPreferenceKind, enabled: boolean) => {
        void this.changeThreadModelCatalog(provider, model, kind, enabled);
      },
      onOpenRuntime: () => { this.showThreadRuntime = true; },
      onBackRuntime: () => { this.showThreadRuntime = false; },
      onChooseRuntime: (mode: ThreadLaunchRuntimeMode) => this.selectThreadRuntime(mode),
      onRetry: () => { void this.loadThreadModels(); },
      onClose: () => this.closeThreadModel(),
    })
  }

  @Builder
  private CitationSheet() {
    ThreadCitationSheet({
      citation: this.citationPreview,
      onClose: () => { this.citationPreview = undefined; },
      onJump: (citation: NativeThreadCitation) => this.jumpToCitation(citation),
    })
  }

  @Builder
  private LinkedThreadContent(fullscreen: boolean) {
    LinkedThreadView({
      title: this.linkedThreadTitle || this.linkedThreadTarget?.title || '',
      label: this.linkedThreadTarget?.label ?? '',
      via: this.linkedThreadTarget?.sourceLabel ?? '',
      loading: this.linkedThreadLoading,
      error: this.linkedThreadError,
      hasHistory: this.linkedThreadHistoryCursor !== undefined && !this.linkedThreadError,
      historyLoading: this.linkedThreadHistoryLoading,
      historyError: this.linkedThreadHistoryError,
      working: this.linkedThreadWorking,
      connecting: this.linkedThreadConnecting,
      connectionError: this.linkedThreadConnectionError,
      messages: this.linkedThreadMessages,
      work: this.linkedThreadWork,
      onClose: () => { this.onBackPress(); },
      onMaximize: fullscreen ? undefined : () => { this.linkedThreadFullscreen = true; },
      onRetry: () => this.watchLinkedThreadView(),
      onConnect: () => { void this.connectToLinkedThread(); },
      onLoadEarlier: () => { void this.loadEarlierLinkedThread(); },
      onReadOutput: (item: NativeThreadWork) => this.readLinkedThreadOutput(item),
    })
  }

  @Builder
  private LinkedPairingContent() {
    Column() {
      Row({ space: 10 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_left')).fontSize(20).fontColor([$r('sys.color.icon_primary')])
        }.id('linked-pairing-back').width(44).height(44).backgroundColor(Color.Transparent)
          .accessibilityText('返回关联会话').onClick(() => { this.onBackPress(); })
        Text(this.linkedThreadTarget?.label ?? '连接关联环境')
          .fontSize(20).fontWeight(FontWeight.Medium).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      }.width('100%').height(56).padding({ left: 4, right: 18 })
      AddEnvironmentView({
        initialAddress: this.linkedPairingAddress,
        link: this.linkedPairingLink,
        pairing: this.linkedThreadConnecting,
        scanning: this.scanning,
        error: this.linkedThreadConnectionError,
        onLink: (value: string) => { this.linkedPairingLink = value; },
        onScan: () => { void this.scanPairingCode(true); },
        onSubmit: (address: string, code: string) => { void this.pairLinkedThreadManually(address, code); },
      })
    }.width('100%').height('100%').backgroundColor($r('sys.color.background_primary'))
  }

  @Builder
  private ThreadAgentsContent() {
    ThreadAgentsSheet({
      rows: this.threadAgentRows(),
      loading: this.loadingMessages,
      error: this.threadAgentsError,
      openingId: this.openingThreadAgent,
      onClose: () => this.closeThreadAgents(),
      onOpen: (id: string) => { void this.openThreadAgent(id); },
    })
  }

  @Builder
  private BackgroundWorkContent() {
    ThreadBackgroundWorkSheet({
      tasks: this.backgroundTasks,
      loading: this.backgroundWorkWaiting,
      error: this.backgroundWorkError,
      openingThreadId: this.backgroundChildOpening,
      onClose: () => this.closeBackgroundWork(),
      onOpenThread: (threadId: string) => { void this.openBackgroundChild(threadId); },
      onRetry: () => this.watchBackgroundTasks(),
    })
  }

  @Builder
  private GroupedThreadWork(entry: FeedEntry) {
    Column({ space: 2 }) {
      ThreadWorkGroupToggle({
        rowId: entry.id,
        summary: this.copy('已运行 ' + (entry.workGroup?.length ?? 0) + ' 条命令',
          'Ran ' + (entry.workGroup?.length ?? 0) + ' commands'),
        expanded: this.expandedMessages.includes(entry.id),
        hasFailure: entry.workGroup?.some((work: NativeThreadWork) => work.status === 'failed') ?? false,
        dark: this.darkAppearance,
        language: this.uiLanguage(),
        onToggle: () => this.toggleMessage(entry.id),
      })
      if (this.expandedMessages.includes(entry.id)) {
        ForEach(entry.workGroup ?? [], (work: NativeThreadWork) => {
          ThreadWorkRow({
            rowId: work.id,
            title: work.title,
            detail: this.workOutput.get('work:' + work.id) ?? work.detail,
            loading: this.loadingWork.includes('work:' + work.id),
            expandable: work.wantsOutput,
            status: work.status,
            expanded: this.expandedMessages.includes('work:' + work.id),
            grouped: true,
            dark: this.darkAppearance,
            language: this.uiLanguage(),
            onToggle: () => { void this.toggleWorkRow('work:' + work.id, work); },
          })
        }, (work: NativeThreadWork) => work.id)
      }
    }.width('100%')
  }

  @Builder
  private Conversation() {
    ThreadDetailHeader({
      title: this.threadDetail?.title || this.selected?.title || '',
      subtitle: this.threadDetail?.approval ? this.copy('等待审批', 'Awaiting approval') :
        this.threadDetail?.runBusy ? this.copy('运行中', 'Running') : this.threadSubtitle(),
      branchLabel: this.threadGitStatus?.refName ?? '',
      language: this.uiLanguage(),
      dark: this.darkAppearance,
      canOpenFiles: this.threadCanReadFiles && !!this.threadFilesCwd(),
      canOpenGit: !!this.threadDetail && !this.watchError && !!this.threadFilesCwd(),
      canOpenTerminal: !!this.selected?.workspaceRoot && (this.threadCanReadTerminal || this.threadCanOperateTerminal),
      onOpenFiles: () => this.openThreadFiles(),
      onOpenGit: () => this.openThreadGit(),
      onOpenReview: this.threadCanReadFiles ? () => this.openThreadReview() : undefined,
      onOpenTerminal: () => { void this.openThreadTerminal(); },
      onBack: () => { this.onBackPress(); },
    })
    Column() {
      this.ConversationBody()
    }
    .width('100%').layoutWeight(1)
    .backgroundColor(workspaceSurfaceColor(this.darkAppearance))
    .borderRadius({ topLeft: 28, topRight: 28 }).clip(true)
  }

  @Builder
  private ConversationBody() {
    if (this.watchError) {
      Row({ space: 8 }) {
        if (this.threadReconnecting) {
          LoadingProgress().width(18).height(18)
        }
        Text(this.threadReconnecting ? this.copy('正在重新连接会话…', 'Reconnecting to chat…') : this.watchError)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .layoutWeight(1)
        Button(this.copy('重试', 'Retry'))
          .controlSize(ControlSize.SMALL)
          .onClick(() => this.watchThread())
      }
      .width('100%')
      .padding(14)
    }
    if (this.messageCount > 0 || this.historyCursor !== undefined || this.showBackgroundWorkStatus()) {
      List({
        space: 8,
        scroller: this.messageScroller,
        initialIndex: this.resumeThreadIndex < 0 ? this.lastThreadFeedIndex() :
          Math.min(this.resumeThreadIndex, this.lastThreadFeedIndex()),
      }) {
        if (this.historyCursor !== undefined) {
          ListItem() {
            Column({ space: 6 }) {
              if (this.historyError) {
                Text(this.historyError).fontSize(14).textAlign(TextAlign.Center)
              }
              if (this.historyBusy) {
                LoadingProgress().width(20).height(20)
              }
              Button(this.historyBusy ? this.copy('正在加载…', 'Loading…') : this.historyError ?
                this.copy('重试', 'Retry') : this.copy('加载更早的活动', 'Load earlier activity'))
                .id('thread-load-history')
                .height(44)
                .enabled(!this.historyBusy)
                .onClick(() => { void this.loadOlderThreadHistory(); })
            }.width('100%').padding(8)
          }
        }
        LazyForEach(this.messages, (entry: FeedEntry) => {
          ListItem() {
            if (entry.workGroup) {
              this.GroupedThreadWork(entry)
            } else {
              CurrentFeedRow({
                entry,
                language: this.uiLanguage(),
                dark: this.darkAppearance,
                isLastAssistant: entry.id === this.lastAssistantFeedId,
                expanded: this.expandedMessages.includes(entry.id),
                expandedCodes: this.expandedCodeBlocks.get(entry.id) ?? [],
                workOutput: this.workOutput.get(entry.id),
                loadingWork: this.loadingWork.includes(entry.id),
                quoteEnabled: this.threadAccess === 'allowed' && !this.watchError && !this.sending &&
                  entry.message?.threadId === this.selected?.id,
                citationEnabled: entry.message?.threadId === this.selected?.id,
                checkpointEnabled: !this.watchError && !this.loadingMessages,
                forkEnabled: this.canForkReply() && !this.replyForkBusyMessage,
                forkBusy: this.replyForkBusyMessage !== '' && this.replyForkBusyMessage === entry.message?.id,
                onQuote: (messageId: string, selector: ThreadCitationSelector) => this.addThreadQuote(messageId, selector),
                onOpenCitation: (citation: NativeThreadCitation) => this.openCitation(citation),
                onOpenAttachment: (message: NativeMessage, attachment: NativeThreadAttachment) =>
                  this.openThreadAttachment(message, attachment),
                onOpenCheckpoint: (checkpoint: NativeThreadCheckpointSummary) => this.openThreadCheckpoint(checkpoint),
                onFork: (source: NativeThreadForkSource, messageId: string) => { void this.forkReply(source, messageId); },
                onToggle: () => { void this.toggleFeedEntry(entry); },
                onToggleCode: (blockIndex: number) => this.toggleCodeBlock(entry.id, blockIndex),
              })
            }
          }
        }, (entry: FeedEntry) => entry.id)
        if (this.showBackgroundWorkStatus()) {
          ListItem() {
            ThreadBackgroundWorkStatus({
              tasks: this.backgroundTasks,
              canStop: this.canStopBackgroundWork(),
              stopping: this.backgroundStopping,
              onOpen: () => this.openBackgroundWork(),
              onStop: () => { void this.stopBackgroundWork(); },
            })
          }
        }
      }
      .stackFromEnd(true)
      .maintainVisibleContentPosition(true)
      .onScrollIndex((first: number) => { this.firstVisibleThreadIndex = first; })
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })
    } else {
      this.Status(this.loadingMessages ? this.copy('正在加载消息…', 'Loading messages…') : this.watchError ?
        this.copy('消息暂时不可用', 'Messages are unavailable') : this.copy('尚无对话', 'No messages yet'),
        this.loadingMessages)
    }
    if (this.threadDetail?.approval) {
      Column() {
        ThreadDetailApproval({
          language: this.uiLanguage(),
          prompt: this.threadDetail.approval.prompt,
          reason: this.threadDetail.approval.reason,
          options: this.approvalOptions(),
          supportsFeedback: this.threadDetail.approval.supportsFeedback && this.threadAccess === 'allowed' &&
            !this.watchError && !this.threadDetail.userInput,
          busy: this.threadActionBusy || this.sending || this.threadAccess !== 'allowed' ||
            !this.threadDetail.approval.canRespond || !!this.watchError,
          onDecision: (requestId: string, decision: string) => { void this.runThreadAction(requestId, decision); },
        })
      }.width('100%').padding({ left: 12, right: 12 })
    }
    if (this.threadAccess === 'read-only' || this.threadAccess === 'failed') {
      Row({ space: 8 }) {
        Text(this.threadAccess === 'read-only' ? this.copy('此环境连接只能读取会话', 'This connection is read-only') :
          this.copy('无法确认环境操作权限', 'Could not confirm environment permissions'))
          .fontSize(13).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
        if (this.threadAccess === 'failed') {
          Button(this.copy('重试', 'Retry')).controlSize(ControlSize.SMALL).onClick(() => this.watchThread())
        }
      }.width('100%').padding({ left: 16, right: 16 })
    }
    if (this.sideChats.length > 0) {
      ThreadSideChatsRow({ chats: this.sideChats, onOpen: (threadId: string) => this.openSideChat(threadId) })
    }
    if (this.threadDetail?.subagents?.showPill) {
      Row() {
        Button({ type: ButtonType.Capsule }) {
          Row({ space: 6 }) {
            if ((this.threadDetail?.subagents?.liveCount ?? 0) > 0) {
              Circle().width(7).height(7).fill($r('sys.color.font_emphasize'))
            }
            Text(this.copy('子代理', 'Subagents') + ' ' + this.threadDetail?.subagents?.subagents.length)
              .fontSize(13).fontColor($r('sys.color.font_primary'))
          }
        }
        .id('thread-agents-open')
        .height(34)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .onClick(() => {
          this.getUIContext().getFocusController().clearFocus();
          this.showThreadAgents = true;
        })
      }.width('100%').justifyContent(FlexAlign.End).padding({ right: 16, bottom: 6 })
    }
    ThreadDetailComposer({
      draft: this.draft,
      language: this.uiLanguage(),
      dark: this.darkAppearance,
      readOnly: this.threadAccess !== 'allowed' || !!this.watchError,
      placeholder: this.threadDetail?.approval?.supportsFeedback && this.threadAccess === 'allowed' ?
        this.copy('输入审批反馈', 'Enter approval feedback') : this.copy('问点什么', 'Ask anything'),
      error: this.sendError,
      sending: this.sending,
      canSend: (!!this.draft.trim() || this.draftAttachments.length > 0 || this.draftQuotes.length > 0 ||
        this.draftTerminalContexts.length > 0) && !this.pickingAttachments && !this.loadingMessages &&
        !this.watchError && this.threadAccess === 'allowed',
      action: this.threadAccess === 'allowed' && !this.watchError ? this.composerAction() : 'send',
      actionBusy: this.threadActionBusy,
      modelLabel: this.threadModelDraft?.model ?? this.threadDetail?.modelLabel ?? '',
      canPickModel: this.canPickThreadComposerModel(),
      suggestionScope: this.threadComposerScope() ? JSON.stringify([this.threadComposerScope(),
        this.displayedThreadModel()?.instanceId]) : '',
      canAttach: this.threadAccess === 'allowed' && !this.watchError,
      pickingFiles: this.pickingAttachments,
      attachments: this.draftAttachments,
      contextRecords: referencedComposerCommandContext(this.draft,
        this.commandContextDrafts.get(this.environmentKey)?.get(this.selected?.id ?? '') ?? []),
      quotes: this.draftQuotes.map((quote: DraftThreadQuote) => quote.text)
        .concat(this.draftTerminalContexts.map((record: ThreadTerminalContextRecord) => record.label)),
      queuedCount: this.threadDetail?.queuedCount ?? 0,
      queuedMessages: this.threadDetail?.queuedMessages ?? [],
      queueContext: this.threadViewGeneration,
      queueHeld: this.threadDetail?.queueHeld ?? false,
      queueEditBlocked: this.threadDetail?.queueEditBlocked ?? false,
      queueCanWrite: this.threadAccess === 'allowed' && !this.loadingMessages && !this.watchError,
      queueBusy: this.threadActionBusy || this.sending || this.pairing,
      userInput: this.threadDetail?.userInput,
      userInputCanWrite: this.threadAccess === 'allowed' && !this.loadingMessages && !this.watchError,
      userInputBusy: this.threadActionBusy || this.sending || this.pairing,
      onUserInputSubmit: (requestId: string, answers: NativeThreadUserInputAnswers) => {
        void this.answerThreadQuestion(requestId, answers);
      },
      onUserInputDismiss: (requestId: string) => { void this.answerThreadQuestion(requestId); },
      onUserInputStop: (requestId: string) => {
        const question = this.threadDetail?.userInput;
        if (question?.id === requestId && question.stopRunId) void this.runThreadAction();
      },
      onQueueSend: (runId: string) => { void this.changeQueuedRun('send', runId); },
      onQueueEdit: (runId: string, text: string) => this.changeQueuedRun('edit', runId, text),
      onQueueRemove: (runId: string) => { void this.changeQueuedRun('remove', runId); },
      onDraft: (value: string) => this.changeDraft(value),
      onReadSuggestions: (trigger: ComposerCommandTrigger): Promise<ThreadComposerSuggestion[]> => {
        const scope = this.threadComposerScope();
        if (!scope) return Promise.resolve([]);
        return this.readComposerSuggestions(scope, this.displayedThreadModel()?.instanceId ?? '', trigger,
          this.canPickThreadComposerModel(), !!this.selected?.latestRunCompletedAt && !this.threadDetail?.runBusy);
      },
      onSuggestionContext: (record: ComposerCommandContextRecord) => this.addCommandContext(record),
      onOpenContextThread: (environmentId: string, threadId: string) => {
        const uri = `t3code://threads/${encodeURIComponent(environmentId)}/${encodeURIComponent(threadId)}`;
        if (!this.pairing && !this.sending && !this.threadActionBusy) void this.openLinkedThread(environmentId, threadId, uri);
      },
      onPickModel: () => { void this.loadThreadModels(); },
      onPickAttachment: (photos: boolean) => { void this.pickThreadAttachments(photos); },
      onRemoveAttachment: (uri: string) => this.setDraftAttachments(this.draftAttachments.filter((item) => item.uri !== uri)),
      onRemoveQuote: (index: number) => {
        if (index < this.draftQuotes.length) {
          this.setDraftQuotes(this.draftQuotes.filter((item, current) => current !== index));
        } else {
          this.setDraftTerminalContexts(this.draftTerminalContexts.filter(
            (item, current) => current !== index - this.draftQuotes.length));
        }
      },
      onAction: () => { void this.runThreadAction(); },
    })
  }

  @Builder
  private ProjectOrLaunch() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.showProjects) {
        ProjectManagementView({
          environmentKey: this.environmentKey,
          environmentLabel: this.client?.currentEnvironment()?.label ?? '',
          backRequest: this.projectBackRequest,
          addedProjectId: this.projectManagementAddedId,
          onBack: () => {
            this.showProjects = false;
            this.projectManagementAddedId = '';
          },
          onAddProject: () => this.openProjectWizard('projects'),
          onLoad: () => this.loadProjects(),
          onChange: (change: ProjectManagementChange) => this.changeProject(change),
          onChanged: () => { void this.refreshThreads(true); },
        })
          .width('100%').height('100%')
          .visibility(this.projectWizardOrigin ? Visibility.None : Visibility.Visible)
      } else {
        ThreadLaunchView({
          language: this.uiLanguage(),
          dark: this.darkAppearance,
          options: this.threadLaunchOptions,
          loading: this.loadingThreadLaunch,
          launching: this.creatingThread,
          error: this.threadLaunchError,
          attachments: this.threadLaunchAttachments,
          pickingAttachments: this.pickingLaunchAttachments,
          canWriteGit: this.threadLaunchCanWriteGit,
          canOpenScratch: this.threadLaunchCanOpenScratch,
          canReadFiles: this.threadLaunchCanReadFiles,
          environments: this.visibleEnvironmentRows(),
          activeEnvironmentKey: this.environmentKey,
          backRequest: this.threadLaunchBackRequest,
          addedProjectId: this.threadLaunchAddedProjectId,
          onBack: () => this.closeThreadLaunch(),
          onAddProject: () => this.openProjectWizard('launch'),
          onRetry: () => { void this.loadThreadLaunch(); },
          onPickAttachment: (photos: boolean) => { void this.pickLaunchAttachments(photos); },
          onRemoveAttachment: (uri: string) => {
            this.threadLaunchAttachments = this.threadLaunchAttachments.filter((attachment) => attachment.uri !== uri);
          },
          onRecallModelOptions: (selection: ThreadLaunchSelection) => this.modelOptionMemory.get(this.modelMemoryKey(selection)),
          onRememberModelOptions: (selection: ThreadLaunchSelection) => {
            this.modelOptionMemory.set(this.modelMemoryKey(selection), selection.options ?? []);
          },
          onLoadRefs: (cwd: string, query: string, cursor: number | null, kind: ThreadGitRefKind, refresh: boolean) =>
            this.loadLaunchRefs(cwd, query, cursor, kind, refresh),
          onSwitchRef: (cwd: string, refName: string) => this.switchLaunchRef(cwd, refName),
          onOpenScratch: (root: string) => this.openLaunchScratch(root),
          onLoadWorkspaceProviders: (projectId: string, cwd: string) => this.loadLaunchWorkspaceProviders(projectId, cwd),
          onListFiles: async (cwd: string, path: string) => this.launchFileClient(cwd).listThreadFiles(cwd, path),
          onReadFile: async (cwd: string, path: string) => this.launchFileClient(cwd).readThreadFile(cwd, path),
          onSearchFiles: async (cwd: string, query: string) => this.launchFileClient(cwd).searchThreadFiles(cwd, query),
          onReadSuggestions: (scope: NativeComposerScope, provider: string, trigger: ComposerCommandTrigger) =>
            this.showThreadLaunch && this.threadListCanWrite && scope.environmentKey === this.threadLaunchEnvironmentKey ?
              this.readComposerSuggestions(scope, provider, trigger, !!provider, false) : Promise.resolve([]),
          onLaunch: (project: ThreadLaunchProject, model: ThreadLaunchSelection, text: string,
            mode: ThreadLaunchRuntimeMode, workspace: ThreadLaunchWorkspaceStrategy, records: ComposerCommandContextRecord[]) => {
            void this.launchThread(project, model, text, mode, workspace, records);
          },
        })
          .width('100%').height('100%')
          .visibility(this.projectWizardOrigin ? Visibility.None : Visibility.Visible)
      }
      if (this.projectWizardOrigin) {
        ProjectAddWizard({
          language: this.uiLanguage(),
          dark: this.darkAppearance,
          environmentLabel: this.client?.currentEnvironment()?.label ?? '',
          canAddFolder: this.connected,
          busy: this.projectMutationBusy,
          error: this.projectWizardError,
          backRequest: this.projectWizardBackRequest,
          onBack: () => this.closeProjectWizard(),
          onAddFolder: (path: string) => { void this.addProjectWizardFolder(path); },
          onBrowseFolders: (path: string) => this.browseProjectWizardFolders(path),
        }).width('100%').height('100%')
      }
    }.width('100%').layoutWeight(1)
  }

  build() {
    Column() {
      if (this.restoring || (!this.selected && !this.isWorkspaceRoot() && !this.showAccount &&
        (!this.environmentDetails || this.addingEnvironment) &&
        !this.showApprovals && !this.approvalEnvironmentId && !this.showThreadLaunch &&
        !this.showArchivedThreads && !this.threadListActionTarget && !this.showProjects)) {
        this.Header()
      }
      if (!this.selected && !this.isWorkspaceRoot()) {
        Divider()
      }
      if (this.restoring) {
        this.Status(this.copy('正在恢复连接…', 'Restoring connection…'), true)
      } else if (this.openingThreadLink) {
        this.Status(this.copy('正在打开会话…', 'Opening chat…'), true)
      } else if (this.threadListActionTarget) {
        ThreadListActions({
          thread: this.threadListActionTarget,
          language: this.uiLanguage(),
          startWithSnooze: this.threadListStartWithSnooze,
          canOperate: this.threadListCanWrite,
          busy: this.threadListActionBusy,
          error: this.threadListActionError,
          onAction: (action: ThreadLifecycleAction, value?: string) => { void this.updateThreadLifecycle(action, value); },
          onClose: () => { this.onBackPress(); },
        })
      } else if (this.showProjects || this.showThreadLaunch) {
        this.ProjectOrLaunch()
      } else if (this.approvalEnvironmentId) {
        DeviceApprovalPendingView({
          environmentId: this.approvalEnvironmentId,
          environmentLabel: this.approvalEnvironmentLabel,
          verificationCode: this.approvalCode,
          error: this.approvalPendingError,
          busy: this.pairing,
          onRetry: () => { void this.useRelayEnvironment(this.approvalEnvironmentId); },
          onCancel: () => this.clearPendingApproval(),
        })
      } else if (this.showApprovals) {
        DeviceApprovalView({
          environmentId: this.client?.currentEnvironment()?.environmentId ?? '',
          environmentLabel: this.client?.currentEnvironment()?.label ?? '',
          requests: this.approvals,
          busy: this.approvalsBusy,
          error: this.approvalError,
          notice: this.approvalNotice,
          onRefresh: () => { void this.loadApprovals(); },
          onApprove: (id: string) => { void this.answerApproval(id, true); },
          onDeny: (id: string) => { void this.answerApproval(id, false); },
          onBack: () => { this.onBackPress(); },
        })
      } else if (this.showConnectOnboarding) {
        this.ConnectOnboarding()
      } else if (this.showAccount) {
        AccountView({
          configured: this.accountConfigured,
          identity: this.accountIdentity,
          working: this.accountBusy,
          awaitingBrowser: this.accountPending,
          error: this.accountError,
          emailStep: this.emailStep,
          emailWorking: this.emailInFlight,
          relayConfigured: this.relayConfigured,
          connectProfileOpen: this.accountConnectProfileOpen,
          registeredServers: this.relayRows,
          registeredServersLoading: this.relayLoading,
          registeredServersLoaded: this.relayHasListed,
          registeredServersError: this.relayError,
          deregisteringEnvironmentId: this.deregisteringEnvironmentId,
          deregisterError: this.deregisterError,
          onRefreshServers: () => { void this.loadRelayEnvironments(); },
          onOpenConnectProfile: () => {
            this.accountConnectProfileOpen = true;
            void this.loadRelayEnvironments();
          },
          onDeregisterServer: (environment: RelayEnvironment) => { void this.deregisterRelayEnvironment(environment); },
          onSaveProfileName: (identity: AccountIdentity, update: AccountNameUpdate) => this.updateAccountName(identity, update),
          onListSessions: (identity: AccountIdentity) => this.listAccountSessions(identity),
          onRevokeSession: (identity: AccountIdentity, sessionId: string) => this.revokeAccountSession(identity, sessionId),
          onEmail: (action: AccountEmailAction) => { void this.continueWithEmail(action); },
          onStart: (mode: AccountMode) => { void this.startAccount(mode); },
          onCancel: () => this.cancelAccount(),
          onSignOut: () => { void this.signOut(); },
          onRetry: () => { void this.restoreAccount(); },
          onBack: () => { this.onBackPress(); },
        })
      } else if (this.selected && this.showThreadTerminal) {
        ThreadTerminal({
          threadTitle: this.threadDetail?.title || this.selected.title,
          cwd: this.terminalCwd,
          terminalId: this.terminalId,
          sessions: this.terminalSessions,
          status: this.terminalStatus,
          cols: this.terminalCols,
          rows: this.terminalRows,
          output: this.terminalOutput,
          loading: this.terminalLoading,
          error: this.terminalError,
          readOnly: !this.threadCanOperateTerminal,
          canAttachOutput: this.threadCanReadTerminal || this.threadCanOperateTerminal,
          onAttachOutput: (selection: ThreadTerminalAttachment) => this.attachThreadTerminalOutput(selection),
          onBack: () => this.leaveThreadTerminal(),
          onRetry: () => this.retryThreadTerminal(),
          onNewSession: () => this.attachThreadTerminal(createThreadTerminalId()),
          onSelectSession: (terminalId: string) => this.attachThreadTerminal(terminalId),
          onCloseSession: () => { void this.closeThreadTerminal(); },
          onClear: () => { void this.clearThreadTerminal(); },
          onInput: (data: string, reply: boolean) => { void this.writeThreadTerminal(data, reply); },
          onResize: (cols: number, rows: number) => this.resizeThreadTerminal(cols, rows),
        })
      } else if (this.selected && this.showThreadReview && (this.threadReviewCheckpoint || this.threadCanReadFiles)) {
        Stack({ alignContent: Alignment.TopStart }) {
          ThreadReview({
            cwd: this.threadFilesCwd(),
            contextKey: JSON.stringify([this.environmentKey, this.selected.id, this.threadFilesCwd(), this.threadReviewCheckpoint?.id]),
            historical: this.threadReviewCheckpoint !== undefined,
            onBack: () => this.closeThreadReview(),
            onLoadCheckpoint: this.threadReviewCheckpoint ? () => this.loadThreadCheckpoint() : undefined,
            onLoad: () => this.loadThreadReview(this.threadFilesCwd()),
            onLoadFile: (file: NativeThreadReviewFile, baseRef: string | null) =>
              this.loadThreadReviewFile(this.threadFilesCwd(), file, baseRef),
            onCommentFile: this.threadComposerScope() ?
              (target: NativeThreadFileReviewCommentTarget) => this.openThreadReviewComment(target) : undefined,
          }).visibility(this.threadReviewCommentTarget ? Visibility.Hidden : Visibility.Visible)
          if (this.threadReviewCommentTarget) {
            ThreadReviewCommentEditor({
              filePath: this.threadReviewCommentTarget.filePath,
              sourceTitle: this.threadReviewCommentTarget.sectionTitle ?? '',
              selectionLabel: this.threadReviewCommentTarget.selection?.rangeLabel ?? '',
              selectionRows: this.threadReviewCommentTarget.selection?.rows ?? [],
              diff: this.threadReviewCommentTarget.selection?.diff ?? this.threadReviewCommentTarget.diff ?? '',
              comment: this.threadReviewComment,
              error: this.threadReviewCommentError,
              onChange: (comment: string) => {
                this.threadReviewComment = comment;
                this.threadReviewCommentError = '';
              },
              onCancel: () => this.closeThreadReviewComment(),
              onAdd: (comment: string) => this.addThreadReviewComment(comment),
            })
          }
        }.width('100%').height('100%')
      } else if (this.selected && this.showThreadGit) {
        ThreadGitStatus({
          pane: $threadGitPane,
          cwd: this.threadFilesCwd(),
          canWrite: this.threadCanWriteGit && !this.watchError,
          canChangeBranch: this.threadCanWriteGit && this.threadAccess === 'allowed' && !this.watchError,
          status: this.threadGitStatus,
          loading: this.threadGitLoading,
          error: this.threadGitError,
          onBack: () => this.closeThreadGit(),
          onRefresh: () => { void this.loadThreadGit(); },
          onListRefs: (query: string, cursor: number | null) => this.listThreadGitRefs(query, cursor),
          onChangeBranch: (refName: string, create: boolean) => this.changeThreadGitBranch(refName, create),
          onCommit: (message: string, paths?: string[]) => this.commitThreadGit(message, paths),
          onPull: () => this.pullThreadGit(),
          onPush: (refName: string, confirmedDefault: boolean) => this.pushThreadGit(refName, confirmedDefault),
          onReview: this.threadCanReadFiles ? () => { this.showThreadReview = true; } : undefined,
        })
      } else if (this.selected && this.showThreadFiles) {
        ThreadDetailFiles({
          projectTitle: this.selected.projectTitle ?? '',
          directory: this.filesDirectory,
          entries: this.filesEntries,
          preview: this.filesPreview,
          fileTarget: this.fileTarget,
          loading: this.filesBusy,
          error: this.filesError,
          truncated: this.filesTruncated,
          searchOpen: this.filesSearchOpen,
          searchContext: JSON.stringify([this.environmentKey, this.threadFilesCwd()]),
          onSearchOpenChange: (open: boolean) => { this.filesSearchOpen = open; },
          onSearch: (query: string) => this.searchThreadFiles(query),
          onBack: () => this.backFromThreadFiles(),
          onRefresh: () => {
            if (this.fileTarget) void this.previewThreadFile(this.fileTarget);
            else void this.loadThreadDirectory(this.filesDirectory);
          },
          onOpen: (entry: NativeThreadFileEntry) => this.openFileEntry(entry),
        })
      } else if (this.selected) {
        Stack({ alignContent: Alignment.TopStart }) {
          Column() { this.Conversation() }
            .width('100%').height('100%')
            .visibility(this.previewAttachment || this.linkedThreadFullscreen ? Visibility.Hidden : Visibility.Visible)
            .bindSheet(this.citationPreview !== undefined, this.CitationSheet(), {
              height: SheetSize.MEDIUM,
              detents: [SheetSize.MEDIUM, SheetSize.LARGE],
              showClose: false,
              onDisappear: () => { this.citationPreview = undefined; },
            })
          Row() {}.width(0).height(0)
            .bindSheet(this.showThreadAgents, this.ThreadAgentsContent(), {
              height: SheetSize.MEDIUM,
              detents: [SheetSize.MEDIUM, SheetSize.LARGE],
              showClose: false,
              onDisappear: () => this.onThreadAgentsDisappear(),
            })
          Row() {}.width(0).height(0)
            .bindSheet(this.showBackgroundWork, this.BackgroundWorkContent(), {
              height: '50%',
              detents: ['50%', '90%'],
              showClose: false,
              onDisappear: () => this.closeBackgroundWork(),
            })
          Row() {}.width(0).height(0)
            .bindSheet(this.linkedThreadTarget !== undefined && !this.linkedThreadFullscreen,
              this.LinkedThreadContent(false), {
                height: SheetSize.LARGE,
                detents: [SheetSize.MEDIUM, SheetSize.LARGE],
                showClose: false,
                onDisappear: () => { if (!this.linkedThreadFullscreen) this.closeLinkedThreadView(); },
              })
          if (this.linkedThreadFullscreen && this.linkedThreadTarget) {
            if (this.linkedPairingManual) this.LinkedPairingContent()
            else this.LinkedThreadContent(true)
          }
          if (this.previewAttachment) {
            ThreadAttachmentPreview({
              name: this.previewAttachment.name,
              mimeType: this.previewAttachment.mimeType,
              sizeBytes: this.previewAttachment.sizeBytes,
              kind: threadAttachmentPreviewKind(this.previewAttachment),
              pdf: isPdfThreadAttachment(this.previewAttachment),
              video: isVideoThreadAttachment(this.previewAttachment),
              uri: this.previewContent?.uri ?? '',
              text: this.previewContent?.text,
              truncated: this.previewContent?.truncated ?? false,
              loading: this.previewAttachmentLoading,
              actionBusy: this.previewActionBusy,
              error: this.previewAttachmentError,
              onBack: () => this.closeAttachmentPreview(),
              onRetry: () => this.retryAttachmentPreview(),
              onPrevious: this.adjacentPreviewAttachment(-1) ? () => this.stepAttachmentPreview(-1) : undefined,
              onNext: this.adjacentPreviewAttachment(1) ? () => this.stepAttachmentPreview(1) : undefined,
              onOpen: this.previewAttachment.sizeBytes <= MAX_ATTACHMENT_ACTION_BYTES ?
                () => { void this.runAttachmentAction('open'); } : undefined,
              onShare: this.previewAttachment.sizeBytes <= MAX_ATTACHMENT_ACTION_BYTES && this.attachmentActions.canShare() ?
                () => { void this.runAttachmentAction('share'); } : undefined,
              onSave: this.previewAttachment.sizeBytes <= MAX_ATTACHMENT_ACTION_BYTES &&
                this.attachmentActions.canSaveImage(this.previewAttachment.mimeType) ?
                () => { void this.runAttachmentAction('save'); } : undefined,
            })
          }
        }.width('100%').height('100%')
      } else if (this.showArchivedThreads) {
        this.ArchivedThreads()
      } else if (this.showPairing) {
        if (this.addingEnvironment) {
          AddEnvironmentView({
            link: this.pairLink,
            pairing: this.pairing,
            scanning: this.scanning,
            error: this.pairError,
            onLink: (value: string) => { this.pairLink = value; },
            onScan: () => { void this.scanPairingCode(); },
            onSubmit: (address: string, code: string) => { void this.pair(address, code); },
          })
        } else if (this.environmentDetails && this.showEnvironmentRoutes) {
          EnvironmentRoutesView({
            label: this.environmentDetails.label,
            routes: this.environmentRouteRows(),
            activeKey: this.environmentKey,
            busy: this.pairing,
            error: this.pairError,
            notice: this.environmentRouteNotice,
            onBack: () => { this.onBackPress(); },
            onAddRoute: () => {
              this.pairLink = '';
              this.pairError = '';
              this.addingEnvironment = true;
            },
            onMoveRoute: (key: string, delta: number) => { void this.changeEnvironmentRoute(key, delta); },
            onRemoveRoute: (key: string) => { void this.changeEnvironmentRoute(key); },
            onUseRoute: (key: string) => { void this.manageEnvironment(key, false, true, false); },
          })
        } else if (this.environmentDetails) {
          EnvironmentDetails({
            label: this.environmentDetails.label,
            origin: this.environmentDetails.origin,
            managed: this.environmentDetails.managed,
            connectionEnabled: this.environmentDetails.enabled,
            active: this.environmentKey === this.environmentDetails.key,
            busy: this.pairing,
            error: this.pairError,
            notice: this.environmentRouteNotice,
            canRemove: this.environmentRouteRows().length === 1,
            linkedEnvironments: this.linkedEnvironmentHealth,
            linkedLoading: this.linkedEnvironmentLoading,
            linkedError: this.linkedEnvironmentError,
            linkedNotice: this.linkedEnvironmentNotice,
            linkedCanManage: this.linkedEnvironmentCanManage,
            linkedCandidates: this.linkedEnvironmentCandidates(),
            maintenanceSnapshot: this.maintenanceSnapshot,
            maintenanceLoading: this.maintenanceLoading,
            maintenanceBusy: this.maintenanceBusy,
            maintenanceError: this.maintenanceError,
            maintenanceNotice: this.maintenanceNotice,
            maintenanceRelease: this.maintenanceRelease,
            onCheckRelease: () => { void this.runEnvironmentMaintenance('check'); },
            onRefreshProviders: () => { void this.runEnvironmentMaintenance('refresh'); },
            onUpdateProvider: (provider: EnvironmentMaintenanceProvider) => {
              void this.runEnvironmentMaintenance('update', provider);
            },
            onLink: (candidate: LinkedEnvironmentCandidate, access: NativePeerLinkAccess) => {
              void this.changeLinkedEnvironment(candidate.key, access);
            },
            onUnlink: (link: NativeLinkedEnvironment) => { void this.changeLinkedEnvironment(link.environmentId); },
            onSave: (label: string, address: string) => { void this.updateEnvironmentDetails(label, address); },
            onChangeEnabled: (enabled: boolean) => { void this.updateEnvironmentDetails('', undefined, enabled); },
            onReconnect: () => {
              const route = this.environmentRouteRows().find((entry) => entry.enabled);
              if (route) void this.manageEnvironment(route.key, false, true);
            },
            onManageRoutes: () => {
              this.pairError = '';
              this.showEnvironmentRoutes = true;
            },
            onRemove: () => {
              if (this.environmentDetails) void this.manageEnvironment(this.environmentDetails.key, true);
            },
            onBack: () => this.backFromEnvironmentDetails(),
          })
        } else {
          this.Environments()
        }
      } else {
        this.Workspace()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isWorkspaceRoot() || this.selected
      ? workspaceHeaderColor(this.darkAppearance) : $r('sys.color.comp_background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet(this.showThreadModel, this.ThreadModelSheet(), {
      height: SheetSize.LARGE,
      showClose: false,
      onDisappear: () => {
        if (this.showThreadModel) this.closeThreadModel();
      },
    })
  }
}
