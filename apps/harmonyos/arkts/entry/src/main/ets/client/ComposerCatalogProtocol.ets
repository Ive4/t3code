import { REQUEST_ID, validProviderInstanceId } from './T3Protocol';
import type { NativeThread } from './T3Protocol';
import type { NativePullRequestRow } from './PullRequestProtocol';

export interface NativeComposerScope {
  environmentKey: string;
  projectId?: string;
  cwd?: string;
  threadId?: string;
}

interface ComposerCommandInput {
  hint: string;
}

export interface NativeComposerProviderCommand {
  name: string;
  description?: string;
  input?: ComposerCommandInput;
}

export interface NativeComposerProviderSkill {
  name: string;
  path: string;
  displayName?: string;
  shortDescription?: string;
  description?: string;
  userInvocationOnly?: boolean;
}

export interface NativeComposerProviderCatalog {
  instanceId: string;
  driver: string;
  pending: boolean;
  slashCommands: NativeComposerProviderCommand[];
  skills: NativeComposerProviderSkill[];
}

interface ComposerProviderSkillWire extends NativeComposerProviderSkill {
  enabled: boolean;
  userInvocable?: boolean;
}

interface ComposerProviderWorkspaceWire {
  cwd: string;
  slashCommands?: NativeComposerProviderCommand[];
  slashCommandsPending?: boolean;
  skills?: ComposerProviderSkillWire[];
}

interface ComposerProviderWire extends ComposerProviderWorkspaceWire {
  instanceId: string;
  driver: string;
  installed: boolean;
  workspaceSnapshots?: ComposerProviderWorkspaceWire[];
}

interface ComposerProvidersWire {
  providers: ComposerProviderWire[];
}

interface ComposerProviderCatalogInput {
  instanceId: string;
  cwd: string;
  workspaceSnapshotsOnDemand: boolean;
  providerCatalogsOnDemand: boolean;
}

interface ComposerPathSearchInput {
  cwd: string;
  query: string;
  limit: number;
}

interface ComposerCatalogRequest<T> {
  _tag: string;
  id: string;
  tag: string;
  payload: T;
  headers: string[][];
}

export interface NativeComposerRepository {
  projectId: string;
  host: string;
  repository: string;
}

interface ComposerRepositoryIdentity {
  canonicalKey: string;
  displayName?: string;
}

interface ComposerProjectWire {
  id: string;
  deletedAt?: string | null;
  repositoryIdentity?: ComposerRepositoryIdentity | null;
}

interface ComposerProjectsWire {
  projects: ComposerProjectWire[];
}

function nonBlank(value: string | undefined): boolean {
  return typeof value === 'string' && value.trim().length > 0 && !value.includes('\0');
}

function requireCwd(cwd: string): string {
  if (!nonBlank(cwd) || cwd !== cwd.trim()) throw new Error('当前会话没有可用的工作区。');
  return cwd;
}

function validName(name: string): boolean {
  return nonBlank(name) && !/[\s\u0000-\u001f\u007f]/.test(name) && !/^[/@$#]/.test(name);
}

export function composerProviderCatalogRequest(instanceId: string, cwd: string):
  ComposerCatalogRequest<ComposerProviderCatalogInput> {
  if (!validProviderInstanceId(instanceId)) throw new Error('当前提供商无效。');
  const payload: ComposerProviderCatalogInput = {
    instanceId, cwd: requireCwd(cwd), workspaceSnapshotsOnDemand: true, providerCatalogsOnDemand: true,
  };
  return { _tag: 'Request', id: REQUEST_ID, tag: 'server.refreshProviders', payload, headers: [] };
}

export function composerPathSearchRequest(cwd: string, query: string): ComposerCatalogRequest<ComposerPathSearchInput> {
  const payload: ComposerPathSearchInput = {
    cwd: requireCwd(cwd), query: query.trim().slice(0, 256).replace(/[\uD800-\uDBFF]$/, '').trimEnd(), limit: 20,
  };
  return { _tag: 'Request', id: REQUEST_ID, tag: 'projects.searchEntries', payload, headers: [] };
}

export function readComposerProviderCatalog(value: Object, instanceId: string, cwd: string): NativeComposerProviderCatalog {
  const response = value as ComposerProvidersWire;
  const provider = Array.isArray(response?.providers) ? response.providers.find((item: ComposerProviderWire) =>
    item?.instanceId === instanceId) : undefined;
  if (!provider || provider.installed !== true || !nonBlank(provider.driver)) throw new Error('当前提供商不可用。');
  const workspace = Array.isArray(provider.workspaceSnapshots) ?
    provider.workspaceSnapshots.find((entry: ComposerProviderWorkspaceWire) => entry?.cwd === cwd) : undefined;
  const rawSkills = workspace?.skills ?? provider.skills;
  const rawCommands = workspace?.slashCommands ?? provider.slashCommands;
  const skills: NativeComposerProviderSkill[] = [];
  const slashCommands: NativeComposerProviderCommand[] = [];
  const names = new Set<string>();
  if (Array.isArray(rawSkills)) {
    for (const item of rawSkills) {
      if (!item || item.enabled !== true || item.userInvocable === false || !validName(item.name) ||
        !nonBlank(item.path) || names.has(item.name.toLowerCase())) continue;
      names.add(item.name.toLowerCase());
      const skill: NativeComposerProviderSkill = { name: item.name, path: item.path };
      if (nonBlank(item.displayName)) skill.displayName = item.displayName;
      if (nonBlank(item.shortDescription)) skill.shortDescription = item.shortDescription;
      if (nonBlank(item.description)) skill.description = item.description;
      if (item.userInvocationOnly === true) skill.userInvocationOnly = true;
      skills.push(skill);
    }
  }
  if (Array.isArray(rawCommands)) {
    for (const item of rawCommands) {
      if (!item || !validName(item.name) || names.has(item.name.toLowerCase())) continue;
      names.add(item.name.toLowerCase());
      const command: NativeComposerProviderCommand = { name: item.name };
      if (nonBlank(item.description)) command.description = item.description;
      const hint = item.input?.hint ?? '';
      if (nonBlank(hint)) command.input = { hint };
      slashCommands.push(command);
    }
  }
  return { instanceId, driver: provider.driver, pending: workspace?.slashCommandsPending === true, slashCommands, skills };
}

export function matchComposerThreadTitles(threads: NativeThread[], query: string, environmentKey: string,
  threadId?: string, linkedEnvironmentKeys: string[] = []): NativeThread[] {
  const normalized = query.trim().normalize('NFC').toLowerCase();
  if (!normalized) return [];
  const words = normalized.split(/\s+/);
  return threads.filter((thread: NativeThread) => {
    const key = thread.environmentKey;
    if (!key || (key !== environmentKey && !linkedEnvironmentKeys.includes(key)) ||
      (key === environmentKey && thread.id === threadId) || thread.archivedAt || thread.deletedAt) return false;
    const lineage = thread.lineage;
    if (lineage?.relationshipToParent === 'subagent' || lineage?.workflowStep === true) return false;
    if (lineage?.sideChat === true &&
      (key !== environmentKey || lineage.parentThreadId !== threadId || !thread.latestUserMessageAt)) return false;
    const searchable = `${thread.title} ${thread.projectTitle ?? ''} ${thread.environmentLabel ?? ''}`
      .normalize('NFC').toLowerCase();
    return words.every((word: string) => searchable.includes(word));
  }).sort((left: NativeThread, right: NativeThread) => {
    const a = left.title.normalize('NFC').toLowerCase();
    const b = right.title.normalize('NFC').toLowerCase();
    return Number(b === normalized) - Number(a === normalized) ||
      Number(b.startsWith(normalized)) - Number(a.startsWith(normalized)) ||
      (Date.parse(right.updatedAt ?? right.createdAt ?? '') || 0) -
      (Date.parse(left.updatedAt ?? left.createdAt ?? '') || 0) || left.title.localeCompare(right.title);
  }).slice(0, 5);
}

export function readComposerProjectRepository(value: Object, projectId: string): NativeComposerRepository | undefined {
  const snapshot = value as ComposerProjectsWire;
  if (!Array.isArray(snapshot?.projects)) throw new Error('环境返回的项目无效。');
  const project = snapshot.projects.find((entry: ComposerProjectWire) => entry?.id === projectId && !entry.deletedAt);
  const repository = project?.repositoryIdentity?.displayName ?? '';
  const key = project?.repositoryIdentity?.canonicalKey ?? '';
  if (!nonBlank(repository) || !nonBlank(key)) return undefined;
  const slash = key.indexOf('/');
  if (slash <= 0 || slash === key.length - 1) return undefined;
  return { projectId, host: key.slice(0, slash).toLowerCase(), repository };
}

export function matchComposerPullRequests(rows: NativePullRequestRow[], scope: NativeComposerRepository,
  query: string): NativePullRequestRow[] {
  const target = query.trim().toLowerCase();
  const numeric = /^\d*$/.test(target);
  const words = target.split(/\s+/).filter((word: string) => word.length > 0);
  const numbers = new Set<number>();
  const matches = rows.filter((row: NativePullRequestRow) => {
    if (row.projectId !== scope.projectId || row.host.toLowerCase() !== scope.host ||
      row.repository.toLowerCase() !== scope.repository.toLowerCase() || numbers.has(row.number)) return false;
    const searchable = `${row.title} ${row.headBranch} ${row.baseBranch}`.toLowerCase();
    if (numeric ? !String(row.number).startsWith(target) :
      !words.every((word: string) => searchable.includes(word))) return false;
    numbers.add(row.number);
    return true;
  });
  if (numeric && target) matches.sort((left: NativePullRequestRow, right: NativePullRequestRow) =>
    Number(right.number === Number(target)) - Number(left.number === Number(target)));
  return matches.slice(0, 20);
}
