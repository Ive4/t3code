import { REQUEST_ID } from './T3Protocol';

export type ProjectManagementAction = 'rename' | 'pin' | 'unpin' | 'archive' | 'restore' | 'add';

export interface ProjectManagementChange {
  action: ProjectManagementAction;
  projectId?: string;
  value?: string;
}

export interface NativeManagedProject {
  id: string;
  title: string;
  workspaceRoot: string;
  pinned: boolean;
  archived: boolean;
}

export interface ProjectManagementSnapshot {
  projects: NativeManagedProject[];
  canOperate: boolean;
  canOrganize: boolean;
}

export interface NativeProjectFolder {
  name: string;
  fullPath: string;
}

export interface NativeProjectFolderListing {
  parentPath: string;
  entries: NativeProjectFolder[];
}

interface ProjectBrowseInput {
  partialPath: string;
}

interface ProjectBrowseRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: ProjectBrowseInput;
  headers: string[][];
}

interface ProjectWire {
  id: string;
  title: string;
  workspaceRoot: string;
  pinnedAt?: string | null;
  archivedAt?: string | null;
  deletedAt?: string | null;
}

interface ProjectSnapshotWire {
  projects: ProjectWire[];
}

interface ProjectCapabilities {
  projectOrganization?: boolean;
}

interface ProjectPlatform {
  os?: string;
}

interface ProjectEnvironment {
  capabilities?: ProjectCapabilities;
  platform?: ProjectPlatform;
}

interface ProjectServerConfig {
  environment?: ProjectEnvironment;
  scratchWorkspaceRoot?: string;
}

interface ProjectMutation {
  type: string;
  commandId: string;
  projectId: string;
  title?: string;
  workspaceRoot?: string;
  createWorkspaceRootIfMissing?: boolean;
  pinned?: boolean;
  archived?: boolean;
}

interface ProjectManagementRpcRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: ProjectMutation;
  headers: string[][];
}

function nonBlank(value: string | undefined): boolean {
  return typeof value === 'string' && value.trim().length > 0;
}

export function projectBrowseRequest(path: string): ProjectBrowseRequest {
  const partialPath = path.trim();
  if (!partialPath || partialPath.length > 512 || partialPath.includes('\u0000')) {
    throw new Error('请输入有效的主机目录路径。');
  }
  return { _tag: 'Request', id: REQUEST_ID, tag: 'filesystem.browse', payload: { partialPath }, headers: [] };
}

export function readProjectFolderListing(value?: Object): NativeProjectFolderListing {
  const listing = value as NativeProjectFolderListing | undefined;
  if (!listing || !nonBlank(listing.parentPath) || !Array.isArray(listing.entries) ||
    !listing.entries.every((entry) => !!entry && nonBlank(entry.name) && nonBlank(entry.fullPath))) {
    throw new Error('环境未返回有效的目录列表。');
  }
  return listing;
}

function projectRow(row: ProjectWire): NativeManagedProject | undefined {
  if (!row || row.deletedAt != null || !nonBlank(row.id) || !nonBlank(row.title) ||
    !nonBlank(row.workspaceRoot)) return undefined;
  return {
    id: row.id, title: row.title, workspaceRoot: row.workspaceRoot,
    pinned: nonBlank(row.pinnedAt ?? undefined), archived: nonBlank(row.archivedAt ?? undefined),
  };
}

export function readManagedProject(value: Object): NativeManagedProject {
  const project = projectRow(value as ProjectWire);
  if (!project) throw new Error('环境返回的项目无效。');
  return project;
}

function isWindowsPath(path: string): boolean {
  return /^[a-zA-Z]:[/\\]/.test(path) || /^[/\\]{2}[^/\\]+[/\\]+[^/\\]+/.test(path);
}

function pathKey(path: string, windows: boolean): string {
  return windows ? path.replace(/[/\\]+/g, '/').replace(/\/+$/, '').toLowerCase() : path.replace(/\/+$/, '');
}

export function readManagedProjects(value: Object, config?: Object): NativeManagedProject[] {
  const snapshot = value as ProjectSnapshotWire;
  if (!Array.isArray(snapshot?.projects)) throw new Error('环境返回的项目列表无效。');
  const scratch = (config as ProjectServerConfig | undefined)?.scratchWorkspaceRoot;
  const windows = typeof scratch === 'string' && isWindowsPath(scratch);
  const scratchPath = typeof scratch === 'string' ? pathKey(scratch, windows) : undefined;
  const projects: NativeManagedProject[] = [];
  for (const row of snapshot.projects) {
    const project = projectRow(row);
    if (project && pathKey(project.workspaceRoot, windows) !== scratchPath) projects.push(project);
  }
  return projects;
}

export function supportsProjectOrganization(value: Object): boolean {
  return (value as ProjectServerConfig)?.environment?.capabilities?.projectOrganization === true;
}

export function projectsOnShelf(projects: NativeManagedProject[], archived: boolean): NativeManagedProject[] {
  return projects.filter((project: NativeManagedProject) => project.archived === archived)
    .sort((left: NativeManagedProject, right: NativeManagedProject) => Number(right.pinned) - Number(left.pinned));
}

export function availableProjectActions(project: NativeManagedProject, canOperate: boolean,
  canOrganize: boolean): ProjectManagementAction[] {
  if (!canOperate) return [];
  if (!canOrganize) return ['rename'];
  return ['rename', project.pinned ? 'unpin' : 'pin', project.archived ? 'restore' : 'archive'];
}

export function projectManagementRequest(commandId: string, projectId: string,
  change: ProjectManagementChange, config?: Object): ProjectManagementRpcRequest {
  const mutation: ProjectMutation = {
    type: change.action === 'add' ? 'project.create' : 'project.update', commandId, projectId,
  };
  const value = change.value?.trim() ?? '';
  switch (change.action) {
    case 'add': {
      const windows = isWindowsPath(value);
      const os = (config as ProjectServerConfig | undefined)?.environment?.platform?.os;
      const home = value === '~' || /^~[/\\]/.test(value);
      const unix = value.startsWith('/');
      if (value.includes('\u0000') || (!home && !(os === 'windows' ? windows :
        os === 'linux' || os === 'darwin' ? unix : unix || windows))) {
        throw new Error('请输入环境机器上的目录绝对路径，例如 /home/me/project 或 ~/project。');
      }
      const segments = value.split(windows || os === 'windows' ? /[/\\]+/ : /\/+/).filter(Boolean);
      mutation.title = segments[segments.length - 1]?.trim() || value;
      mutation.workspaceRoot = value;
      mutation.createWorkspaceRootIfMissing = false;
      break;
    }
    case 'rename':
      if (!value) throw new Error('项目名称不能为空。');
      mutation.title = value;
      break;
    case 'pin':
    case 'unpin':
      mutation.pinned = change.action === 'pin';
      break;
    case 'archive':
    case 'restore':
      mutation.archived = change.action === 'archive';
      break;
  }
  return { _tag: 'Request', id: REQUEST_ID, tag: 'projects.mutate', payload: mutation, headers: [] };
}
