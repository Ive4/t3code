import { REQUEST_ID, validProviderInstanceId } from './T3Protocol';
import type { ThreadMessageContext } from './T3Protocol';
import type { UploadedThreadAttachment } from './ThreadAttachmentProtocol';
import type { NativeThreadGitRef, NativeThreadGitRefs, ThreadGitRefKind } from './ThreadGitProtocol';
import { readThreadModelCapabilities, readThreadModelSelection } from './ThreadModelOptionProtocol';
import type { ThreadModelCapabilities, ThreadModelOptionSelection } from './ThreadModelOptionProtocol';
import { readModelCatalogPreferences } from './ModelCatalogPreferences';
import type { NativeModelCatalogPreferences } from './ModelCatalogPreferences';

export type ThreadLaunchRuntimeMode = 'approval-required' | 'auto-accept-edits' | 'auto' | 'full-access';
const RUNTIME_MODES: ThreadLaunchRuntimeMode[] = ['approval-required', 'auto-accept-edits', 'auto', 'full-access'];

export interface ThreadLaunchSelection {
  instanceId: string;
  model: string;
  options?: ThreadModelOptionSelection[];
}

export interface ThreadLaunchProject {
  id: string;
  title: string;
  workspaceRoot: string;
  defaultModelSelection?: ThreadLaunchSelection;
  startFromOrigin?: boolean;
}

export interface ThreadLaunchModel {
  slug: string;
  name: string;
  isDefault?: boolean;
  isCustom?: boolean;
  supportedRuntimeModes?: ThreadLaunchRuntimeMode[];
  capabilities?: ThreadModelCapabilities;
}

export interface ThreadLaunchProvider {
  instanceId: string;
  displayName: string;
  models: ThreadLaunchModel[];
  projectIds: string[];
}

export interface ThreadModelSettings {
  providers: ThreadLaunchProvider[];
  maxRuntimeMode?: ThreadLaunchRuntimeMode;
  modelCatalog?: NativeModelCatalogPreferences;
}

export interface ThreadRuntimeModeChoice {
  mode: ThreadLaunchRuntimeMode;
  allowed: boolean;
}

export interface ThreadLaunchOptions {
  projects: ThreadLaunchProject[];
  providers: ThreadLaunchProvider[];
  defaultRuntimeMode: ThreadLaunchRuntimeMode;
  maxRuntimeMode?: ThreadLaunchRuntimeMode;
  scratchWorkspaceRoot?: string;
  modelCatalog?: NativeModelCatalogPreferences;
}

export interface ThreadLaunchScratch {
  project: ThreadLaunchProject;
  providers: ThreadLaunchProvider[];
}

interface LaunchSelectionWire {
  instanceId?: string;
  provider?: string;
  model: string;
  options?: Object;
}

interface ProjectShell {
  id: string;
  title: string;
  workspaceRoot: string;
  pinnedAt?: string | null;
  archivedAt?: string | null;
  defaultModelSelection?: LaunchSelectionWire | null;
}

interface ProjectShellSnapshot {
  projects: ProjectShell[];
}

interface ProviderAuth {
  status: string;
}

interface ProviderWorkspaceModels {
  cwd: string;
  models?: ThreadLaunchModel[];
}

interface ThreadLaunchProviderSnapshot {
  instanceId: string;
  driver: string;
  displayName?: string;
  enabled: boolean;
  installed: boolean;
  status: string;
  availability?: string;
  auth: ProviderAuth;
  supportedRuntimeModes?: ThreadLaunchRuntimeMode[];
  models: ThreadLaunchModel[];
  workspaceSnapshots?: ProviderWorkspaceModels[];
}

interface ProviderEnabledOverride {
  enabled?: boolean;
}

interface ProjectSettingsOverride {
  providerInstances?: Record<string, ProviderEnabledOverride>;
  newWorktreesStartFromOrigin?: boolean;
}

interface LaunchServerSettings {
  defaultRuntimeMode?: ThreadLaunchRuntimeMode;
  newWorktreesStartFromOrigin?: boolean;
  projectSettingsOverrides?: Record<string, ProjectSettingsOverride>;
}

interface LaunchProviderLimits {
  allowedDrivers?: string[];
}

interface LaunchManagedLimits {
  providers?: LaunchProviderLimits;
  maxRuntimeMode?: ThreadLaunchRuntimeMode;
}

interface LaunchManagedPolicy {
  limits?: LaunchManagedLimits;
}

interface LaunchServerConfig {
  providers: ThreadLaunchProviderSnapshot[];
  scratchWorkspaceRoot?: string;
  settings?: LaunchServerSettings;
  managedPolicy?: LaunchManagedPolicy;
}

interface ThreadLaunchRpcRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: Object;
  headers: string[][];
}

interface InitialMessage {
  messageId: string;
  text: string;
  attachments: UploadedThreadAttachment[];
  context?: ThreadMessageContext;
}

interface RootWorkspace {
  type: 'root';
  branch?: string;
}

interface ExistingWorktreeWorkspace {
  type: 'existing_worktree';
  worktreePath: string;
  branch: string;
}

interface NewWorktreeWorkspace {
  type: 'worktree';
  baseRef: string;
  startFromOrigin?: boolean;
}

export type ThreadLaunchLocalWorkspace = RootWorkspace | ExistingWorktreeWorkspace;
export type ThreadLaunchWorkspaceStrategy = ThreadLaunchLocalWorkspace | NewWorktreeWorkspace;
export type ThreadLaunchReadRefs = (cwd: string, query: string, cursor: number | null,
  refKind: ThreadGitRefKind, refresh: boolean) => Promise<NativeThreadGitRefs>;
export type ThreadLaunchSwitchRef = (cwd: string, refName: string) => Promise<string | null>;

interface ThreadLaunchPayload {
  commandId: string;
  creationSource: string;
  threadId: string;
  projectId: string;
  title: string;
  generateTitle: boolean;
  modelSelection: ThreadLaunchSelection;
  runtimeMode: ThreadLaunchRuntimeMode;
  interactionMode: string;
  workspaceStrategy: ThreadLaunchWorkspaceStrategy;
  initialMessage: InitialMessage;
}

interface ThreadLaunchResult {
  threadId: string;
}

interface ScratchProjectResult {
  projectId: string;
}

function nonBlank(value: string | null | undefined): boolean {
  return typeof value === 'string' && value.trim().length > 0;
}

function normalizeWorkspaceRoot(value: string): string {
  const trimmed = value.trim();
  if (/^[a-zA-Z]:([/\\]|$)/.test(trimmed) || trimmed.startsWith('\\\\')) {
    return trimmed.replace(/[/\\]/g, '\\').replace(/\\+$/, '').toLowerCase();
  }
  return trimmed.replace(/\/+$/, '');
}

function readProjects(shell: Object, config: LaunchServerConfig): ThreadLaunchProject[] {
  const snapshot = shell as ProjectShellSnapshot;
  if (!snapshot || !Array.isArray(snapshot.projects)) throw new Error('环境返回的项目列表无效。');
  const scratch = typeof config.scratchWorkspaceRoot === 'string'
    ? normalizeWorkspaceRoot(config.scratchWorkspaceRoot)
    : undefined;
  const pinned: ThreadLaunchProject[] = [];
  const projects: ThreadLaunchProject[] = [];
  for (const project of snapshot.projects) {
    if (!project || project.archivedAt != null || !nonBlank(project.id) ||
      !nonBlank(project.title) || !nonBlank(project.workspaceRoot) ||
      normalizeWorkspaceRoot(project.workspaceRoot) === scratch) continue;

    const selection = readThreadModelSelection(project.defaultModelSelection ?? undefined);
    const option: ThreadLaunchProject = { id: project.id, title: project.title, workspaceRoot: project.workspaceRoot };
    option.startFromOrigin = config.settings?.projectSettingsOverrides?.[project.id]?.newWorktreesStartFromOrigin ??
      config.settings?.newWorktreesStartFromOrigin ?? true;
    if (selection) option.defaultModelSelection = selection;
    if (project.pinnedAt != null) pinned.push(option);
    else projects.push(option);
  }
  return pinned.concat(projects);
}

function readProviders(config: LaunchServerConfig, projects: string[], cwd?: string): ThreadLaunchProvider[] {
  const allowedDrivers = config.managedPolicy?.limits?.providers?.allowedDrivers;
  const overrides = config.settings?.projectSettingsOverrides;
  const providers: ThreadLaunchProvider[] = [];
  for (const provider of config.providers) {
    if (!provider || !validProviderInstanceId(provider.instanceId) || provider.installed !== true ||
      provider.auth?.status === 'unauthenticated' || provider.availability === 'unavailable' ||
      (Array.isArray(allowedDrivers) && !allowedDrivers.includes(provider.driver)) ||
      !Array.isArray(provider.models)) continue;

    const projectIds = projects.filter((projectId: string) => {
      const enabled = overrides?.[projectId]?.providerInstances?.[provider.instanceId]?.enabled;
      return (enabled ?? (provider.enabled === true && provider.status !== 'disabled')) === true;
    });
    if (projectIds.length === 0) continue;

    const workspace = cwd && Array.isArray(provider.workspaceSnapshots)
      ? provider.workspaceSnapshots.find((item: ProviderWorkspaceModels) => item.cwd === cwd)
      : undefined;
    const workspaceModels = workspace?.models;
    const catalog = Array.isArray(workspaceModels) ? workspaceModels : provider.models;
    const supportedModes = provider.supportedRuntimeModes;
    const models = catalog.filter((model: ThreadLaunchModel) =>
      model && nonBlank(model.slug) && nonBlank(model.name))
      .map((model: ThreadLaunchModel): ThreadLaunchModel => {
        const entry: ThreadLaunchModel = { slug: model.slug, name: model.name };
        if (model.isDefault !== undefined) entry.isDefault = model.isDefault;
        if (model.isCustom !== undefined) entry.isCustom = model.isCustom;
        const runtimeModes = Array.isArray(supportedModes) && supportedModes.length > 0
          ? supportedModes : model.supportedRuntimeModes;
        if (runtimeModes) entry.supportedRuntimeModes = runtimeModes;
        const capabilities = readThreadModelCapabilities(model.capabilities);
        if (capabilities) entry.capabilities = capabilities;
        return entry;
      });
    if (models.length > 0) {
      const displayName = provider.displayName?.trim() || provider.instanceId;
      providers.push({ instanceId: provider.instanceId, displayName, models, projectIds });
    }
  }
  return providers;
}

export function readThreadLaunchOptions(shell: Object, value: Object): ThreadLaunchOptions {
  const config = value as LaunchServerConfig;
  if (!config || !Array.isArray(config.providers)) throw new Error('环境返回的模型配置无效。');
  const projects = readProjects(shell, config);
  return {
    projects, providers: readProviders(config, projects.map((project: ThreadLaunchProject) => project.id)),
    defaultRuntimeMode: config.settings?.defaultRuntimeMode ?? 'approval-required',
    maxRuntimeMode: config.managedPolicy?.limits?.maxRuntimeMode,
    scratchWorkspaceRoot: nonBlank(config.scratchWorkspaceRoot) ? config.scratchWorkspaceRoot : undefined,
    modelCatalog: config.settings ? readModelCatalogPreferences(config.settings) : undefined,
  };
}

export function threadLaunchWorktree(refs: NativeThreadGitRef[], selected: string | undefined,
  startFromOrigin: boolean): NewWorktreeWorkspace | undefined {
  const baseRef = selected ?? refs.find((ref: NativeThreadGitRef) => ref.isDefault)?.name ??
    refs.find((ref: NativeThreadGitRef) => ref.current && !ref.isRemote)?.name;
  if (!baseRef) return undefined;
  return startFromOrigin
    ? { type: 'worktree', baseRef, startFromOrigin: true }
    : { type: 'worktree', baseRef };
}

export async function resolveThreadLaunchLocalWorkspace(cwd: string, selected: NativeThreadGitRef,
  listRefs: ThreadLaunchReadRefs, switchRef: ThreadLaunchSwitchRef): Promise<ThreadLaunchLocalWorkspace> {
  const remotePrefix = selected.remoteName ? `${selected.remoteName}/` : '';
  const separator = selected.name.indexOf('/');
  const localName = !selected.isRemote ? selected.name
    : remotePrefix && selected.name.startsWith(remotePrefix) ? selected.name.slice(remotePrefix.length)
    : separator > 0 ? selected.name.slice(separator + 1) : selected.name;
  let cursor: number | null = null;
  do {
    const page: NativeThreadGitRefs = await listRefs(cwd, localName.slice(0, 256), cursor, 'local', cursor === null);
    const local: NativeThreadGitRef | undefined = page.refs.find((ref: NativeThreadGitRef) => ref.name === localName);
    if (local && (!selected.isRemote || local.upstreamRef === `refs/remotes/${selected.name}`)) {
      if (local.current) return { type: 'root', branch: local.name };
      if (local.worktreePath) {
        if (page.isAtRepositoryRoot !== true) {
          throw new Error('复用工作树需要确认项目位于仓库根目录，请选择其他分支。');
        }
        return { type: 'existing_worktree', branch: local.name, worktreePath: local.worktreePath };
      }
    }
    if (local) break;
    if (page.nextCursor !== null && cursor !== null && page.nextCursor <= cursor) {
      throw new Error('环境未返回下一页 Git 分支。');
    }
    cursor = page.nextCursor;
  } while (cursor !== null);
  const branch = await switchRef(cwd, selected.name);
  return { type: 'root', branch: branch ?? selected.name };
}

export function threadLaunchRuntimeModes(model: ThreadLaunchModel | undefined,
  ceiling?: ThreadLaunchRuntimeMode): ThreadLaunchRuntimeMode[] {
  const index = ceiling ? RUNTIME_MODES.indexOf(ceiling) : -1;
  const supported = model?.supportedRuntimeModes;
  return RUNTIME_MODES.filter((mode: ThreadLaunchRuntimeMode, position: number) =>
    (index < 0 || position <= index) && (!supported?.length || supported.includes(mode)));
}

export function readThreadRuntimeMode(value: string | undefined): ThreadLaunchRuntimeMode | undefined {
  return RUNTIME_MODES.find((mode: ThreadLaunchRuntimeMode) => mode === value);
}

export function threadRuntimeModeChoices(model: ThreadLaunchModel | undefined,
  ceiling?: ThreadLaunchRuntimeMode): ThreadRuntimeModeChoice[] {
  const allowed = threadLaunchRuntimeModes(model, ceiling);
  return threadLaunchRuntimeModes(model).map((mode: ThreadLaunchRuntimeMode): ThreadRuntimeModeChoice =>
    ({ mode, allowed: allowed.includes(mode) }));
}

export function readThreadModelProviders(value: Object, projectId: string, cwd?: string): ThreadLaunchProvider[] {
  return readThreadModelSettings(value, projectId, cwd).providers;
}

export function readThreadModelSettings(value: Object, projectId: string, cwd?: string): ThreadModelSettings {
  const config = value as LaunchServerConfig;
  if (!config || !Array.isArray(config.providers)) throw new Error('环境返回的模型配置无效。');
  return { providers: readProviders(config, [projectId], cwd),
    maxRuntimeMode: readThreadRuntimeMode(config.managedPolicy?.limits?.maxRuntimeMode),
    modelCatalog: config.settings ? readModelCatalogPreferences(config.settings) : undefined };
}

export function threadLaunchConfigRequest(): ThreadLaunchRpcRequest {
  const payload: Record<string, string> = {};
  return { _tag: 'Request', id: REQUEST_ID, tag: 'server.getConfig', payload, headers: [] };
}

export function threadLaunchScratchRequest(): ThreadLaunchRpcRequest {
  const payload: Record<string, string> = {};
  return { _tag: 'Request', id: REQUEST_ID, tag: 'projects.ensureScratch', payload, headers: [] };
}

export function readThreadLaunchScratchProject(value: Object, workspaceRoot: string): ThreadLaunchProject {
  const result = value as ScratchProjectResult;
  if (!nonBlank(result?.projectId) || !nonBlank(workspaceRoot)) throw new Error('环境未确认无项目会话的目录。');
  return { id: result.projectId, title: '无项目', workspaceRoot };
}

export function launchThreadRequest(commandId: string, threadId: string, messageId: string, projectId: string,
  modelSelection: ThreadLaunchSelection, text: string, title?: string,
  runtimeMode: ThreadLaunchRuntimeMode = 'approval-required',
  attachments: UploadedThreadAttachment[] = [], workspaceStrategy: ThreadLaunchWorkspaceStrategy = { type: 'root' },
  context?: ThreadMessageContext):
  ThreadLaunchRpcRequest {
  const message = text.trim();
  if (!message && attachments.length === 0) throw new Error('请输入第一条消息或添加附件。');
  if (!nonBlank(commandId) || !nonBlank(threadId) || !nonBlank(messageId) || !nonBlank(projectId)) {
    throw new Error('新会话请求缺少项目或操作标识。');
  }
  if (!modelSelection || !validProviderInstanceId(modelSelection.instanceId) || !nonBlank(modelSelection.model)) {
    throw new Error('请选择可用的模型。');
  }
  const userTitle = title?.trim();
  const titleCharacters = Array.from((message || attachments[0]?.name || '新会话').replace(/\s+/g, ' ').normalize('NFC'));
  const titleSeed = titleCharacters.length <= 50 ? titleCharacters.join('') :
    titleCharacters.slice(0, 50).join('') + '...';
  const payload: ThreadLaunchPayload = {
    commandId,
    threadId,
    creationSource: 'mobile',
    projectId,
    modelSelection,
    title: userTitle || titleSeed,
    generateTitle: !userTitle,
    runtimeMode,
    interactionMode: 'default',
    workspaceStrategy,
    initialMessage: { messageId, text: message, attachments },
  };
  if (context?.records.length) payload.initialMessage.context = context;
  return { _tag: 'Request', id: REQUEST_ID, tag: 'orchestration.launchThread', payload, headers: [] };
}

export function readLaunchedThreadId(value: Object): string {
  const result = value as ThreadLaunchResult;
  if (!result || !nonBlank(result.threadId)) throw new Error('环境确认新会话时未返回会话标识。');
  return result.threadId;
}
