import { REQUEST_ID } from './T3Protocol';

export interface NativeThreadFileEntry {
  path: string;
  name: string;
  kind: string;
}

export interface NativeThreadFileDirectory {
  entries: NativeThreadFileEntry[];
  truncated: boolean;
}

export interface NativeThreadFile {
  relativePath: string;
  contents: string;
  truncated: boolean;
}

interface ThreadFilesPayload {
  cwd: string;
  directoryPath?: string;
  relativePath?: string;
  query?: string;
  limit?: number;
}

interface ThreadFilesRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: ThreadFilesPayload;
  headers: string[][];
}

interface DirectoryEntryRecord {
  path: string;
  kind: string;
}

interface DirectoryRecord {
  entries: DirectoryEntryRecord[];
  truncated: boolean;
}

interface FileRecord {
  relativePath: string;
  contents: string;
  byteLength: number;
  truncated: boolean;
  exists?: boolean;
}

function isWorkspaceRelativePath(path: string): boolean {
  return !/^[a-zA-Z]:|^[\\]|^~[\\/]/.test(path) && !path.includes('\0') &&
    path.split('/').every((segment: string): boolean => segment.length > 0) &&
    !path.split(/[\\/]/).some((segment: string): boolean => segment === '.' || segment === '..');
}

function validateDirectory(path: string): void {
  if (path !== '' && (path !== path.trim() || !isWorkspaceRelativePath(path))) {
    throw new Error('目录必须位于当前工作区内。');
  }
}

function filesRequest(tag: string, payload: ThreadFilesPayload): ThreadFilesRequest {
  payload.cwd = payload.cwd.trim();
  if (!payload.cwd || payload.cwd.includes('\0')) throw new Error('当前任务没有可用的工作区。');
  return { _tag: 'Request', id: REQUEST_ID, tag, payload, headers: [] };
}

export function listThreadFilesRequest(cwd: string, path: string): ThreadFilesRequest {
  validateDirectory(path);
  return filesRequest('projects.listEntries', { cwd, directoryPath: path });
}

export function searchThreadFilesRequest(cwd: string, query: string): ThreadFilesRequest {
  const search = query.trim().slice(0, 256).trimEnd();
  if (!search) throw new Error('请输入要搜索的文件或目录。');
  return filesRequest('projects.searchEntries', { cwd, query: search, limit: 200 });
}

export function readThreadFileRequest(cwd: string, path: string): ThreadFilesRequest {
  if (!isWorkspaceRelativePath(path) || path.length > 512) {
    throw new Error('文件路径无效或超出当前工作区。');
  }
  return filesRequest('projects.readFile', { cwd, relativePath: path });
}

export function readThreadFileDirectory(value: Object, directory: string): NativeThreadFileDirectory {
  validateDirectory(directory);
  return readThreadFileEntries(value, directory);
}

export function readThreadFileSearch(value: Object): NativeThreadFileDirectory {
  return readThreadFileEntries(value);
}

function readThreadFileEntries(value: Object, directory?: string): NativeThreadFileDirectory {
  const result = value as DirectoryRecord;
  if (!result || !Array.isArray(result.entries) || typeof result.truncated !== 'boolean') {
    throw new Error('环境返回的文件列表无效。');
  }
  const entries: NativeThreadFileEntry[] = [];
  const paths = new Set<string>();
  for (const entry of result.entries) {
    if (!entry || typeof entry.path !== 'string' || !isWorkspaceRelativePath(entry.path) ||
      (entry.kind !== 'file' && entry.kind !== 'directory') || paths.has(entry.path)) {
      throw new Error('环境返回的文件条目无效。');
    }
    const separator = entry.path.lastIndexOf('/');
    if (directory !== undefined && entry.path.slice(0, Math.max(0, separator)) !== directory) {
      throw new Error('环境返回的目录条目与当前目录不符。');
    }
    paths.add(entry.path);
    entries.push({ path: entry.path, name: entry.path.slice(separator + 1), kind: entry.kind });
  }
  return { entries, truncated: result.truncated };
}

export function readThreadFile(value: Object, requestedPath: string): NativeThreadFile {
  const result = value as FileRecord;
  if (!isWorkspaceRelativePath(requestedPath) || !result || result.relativePath !== requestedPath ||
    typeof result.contents !== 'string' || typeof result.truncated !== 'boolean' ||
    !Number.isInteger(result.byteLength) || result.byteLength < 0 ||
    (result.exists !== undefined && result.exists !== true)) {
    throw new Error('环境返回的文件内容无效。');
  }
  return { relativePath: result.relativePath, contents: result.contents, truncated: result.truncated };
}
