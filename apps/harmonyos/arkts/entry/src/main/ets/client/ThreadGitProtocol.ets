import { REQUEST_ID } from './T3Protocol';

export interface NativeThreadGitFile {
  path: string;
  insertions: number;
  deletions: number;
}

export interface NativeThreadGitStatus {
  isRepo: boolean;
  refName: string | null;
  hasPrimaryRemote: boolean;
  isDefaultRef: boolean;
  hasUpstream: boolean;
  aheadCount: number;
  behindCount: number;
  hasWorkingTreeChanges: boolean;
  files: NativeThreadGitFile[];
  insertions: number;
  deletions: number;
}

export interface NativeThreadGitRef {
  name: string;
  current: boolean;
  isDefault: boolean;
  worktreePath: string | null;
  isRemote?: boolean;
  remoteName?: string;
  upstreamRef?: string;
}

export type ThreadGitRefKind = 'all' | 'local';

export interface NativeThreadGitRefs {
  refs: NativeThreadGitRef[];
  isRepo: boolean;
  isAtRepositoryRoot?: boolean;
  nextCursor: number | null;
  totalCount: number;
}

export interface NativeThreadGitCommitResult {
  status: 'created' | 'skipped_no_changes';
  commitSha?: string;
  subject?: string;
}

export interface NativeThreadGitPullResult {
  status: 'pulled' | 'skipped_up_to_date';
  refName: string;
  upstreamRef: string | null;
}

export interface NativeThreadGitPushResult {
  status: 'pushed' | 'skipped_up_to_date';
  branch?: string;
  upstreamBranch?: string;
  setUpstream?: boolean;
}

interface GitDirectoryInput {
  cwd: string;
}

interface GitStatusInput {
  cwd: string;
  localOnly?: boolean;
}

interface GitRequest<T> {
  _tag: string;
  id: string;
  tag: string;
  payload: T;
  headers: string[][];
}

interface GitRefsInput {
  cwd: string;
  refKind: string;
  limit: number;
  query?: string;
  cursor?: number;
  refresh?: boolean;
}

interface GitRefInput {
  cwd: string;
  refName: string;
  switchRef?: boolean;
}

interface GitBranchMetadataInput {
  type: string;
  commandId: string;
  threadId: string;
  branch: string | null;
  expectedWorktreePath: string | null;
}

interface GitStackedActionInput {
  cwd: string;
  actionId: string;
  action: string;
  threadId?: string;
  projectId?: string;
}

interface GitCommitInput extends GitStackedActionInput {
  commitMessage: string;
  filePaths?: string[];
}

interface GitWorkingTree {
  files: NativeThreadGitFile[];
  insertions: number;
  deletions: number;
}

interface GitStatusResponse {
  isRepo: boolean;
  refName: string | null;
  hasPrimaryRemote: boolean;
  isDefaultRef: boolean;
  hasUpstream: boolean;
  aheadCount: number;
  behindCount: number;
  hasWorkingTreeChanges: boolean;
  workingTree: GitWorkingTree;
}

interface GitRefResponse {
  refName: string | null;
}

interface GitActionResponse {
  action: string;
  commit?: NativeThreadGitCommitResult;
  push?: NativeThreadGitPushResult;
}

interface GitActionProgress {
  actionId: string;
  cwd: string;
  action: string;
  kind: string;
  message?: string;
  result?: GitActionResponse;
}

function validGitText(value: string | undefined): boolean {
  return typeof value === 'string' && value.length > 0 && value.trim() === value && !value.includes('\u0000');
}

function requireGitDirectory(cwd: string): void {
  if (!validGitText(cwd)) throw new Error('会话工作目录无效。');
}

function gitRequest<T>(tag: string, payload: T): GitRequest<T> {
  return { _tag: 'Request', id: REQUEST_ID, tag, payload, headers: [] };
}

export function threadGitStatusRequest(cwd: string, localOnly: boolean = true): GitRequest<GitStatusInput> {
  requireGitDirectory(cwd);
  const payload: GitStatusInput = { cwd };
  if (localOnly) payload.localOnly = true;
  return gitRequest('vcs.refreshStatus', payload);
}

function validLineCount(value: number): boolean {
  return Number.isSafeInteger(value) && value >= 0;
}

function validChangedFile(file: NativeThreadGitFile): boolean {
  return !!file && typeof file.path === 'string' && file.path.length > 0 &&
    validLineCount(file.insertions) && validLineCount(file.deletions);
}

export function readThreadGitStatus(value: Object): NativeThreadGitStatus {
  const status = value as GitStatusResponse;
  const tree = status?.workingTree;
  if (typeof status?.isRepo !== 'boolean' || typeof status.hasWorkingTreeChanges !== 'boolean' ||
    (status.refName !== null && !validGitText(status.refName)) ||
    typeof status.hasPrimaryRemote !== 'boolean' || typeof status.isDefaultRef !== 'boolean' ||
    typeof status.hasUpstream !== 'boolean' || !validLineCount(status.aheadCount) || !validLineCount(status.behindCount) ||
    !tree || !Array.isArray(tree.files) || !tree.files.every(validChangedFile) ||
    !validLineCount(tree.insertions) || !validLineCount(tree.deletions)) {
    throw new Error('环境返回的 Git 状态无效。');
  }
  return {
    isRepo: status.isRepo,
    refName: status.refName,
    hasPrimaryRemote: status.hasPrimaryRemote,
    isDefaultRef: status.isDefaultRef,
    hasUpstream: status.hasUpstream,
    aheadCount: status.aheadCount,
    behindCount: status.behindCount,
    hasWorkingTreeChanges: status.hasWorkingTreeChanges,
    files: tree.files,
    insertions: tree.insertions,
    deletions: tree.deletions,
  };
}

export function canPullThreadGit(status: NativeThreadGitStatus | undefined): boolean {
  return status !== undefined && status.isRepo && status.refName !== null && status.hasUpstream && status.behindCount > 0;
}

export function canPushThreadGit(status: NativeThreadGitStatus | undefined): boolean {
  return status !== undefined && status.isRepo && status.refName !== null && !status.hasWorkingTreeChanges &&
    status.aheadCount > 0 && status.behindCount === 0 && (status.hasUpstream || status.hasPrimaryRemote);
}

export function threadGitPullRequest(cwd: string): GitRequest<GitDirectoryInput> {
  requireGitDirectory(cwd);
  const payload: GitDirectoryInput = { cwd };
  return gitRequest('vcs.pull', payload);
}

export function readThreadGitPullResult(value: Object): NativeThreadGitPullResult {
  const result = value as NativeThreadGitPullResult;
  if ((result?.status !== 'pulled' && result?.status !== 'skipped_up_to_date') || !validGitText(result.refName) ||
    (result.upstreamRef !== null && !validGitText(result.upstreamRef))) throw new Error('环境返回的 Git 拉取结果无效。');
  return result;
}

export function threadGitRefsRequest(cwd: string, query: string, cursor: number | null,
  refKind: ThreadGitRefKind = 'local', refresh: boolean = !query.trim() && cursor === null): GitRequest<GitRefsInput> {
  requireGitDirectory(cwd);
  const term = query.trim();
  if (term.length > 256 || term.includes('\u0000') || (cursor !== null && !validLineCount(cursor))) {
    throw new Error('Git 分支搜索条件无效。');
  }
  const payload: GitRefsInput = { cwd, refKind, limit: 50 };
  if (term) payload.query = term;
  if (cursor !== null) payload.cursor = cursor;
  if (refresh) payload.refresh = true;
  return gitRequest('vcs.listRefs', payload);
}

function validGitRef(ref: NativeThreadGitRef, refKind: ThreadGitRefKind): boolean {
  return !!ref && validGitText(ref.name) && typeof ref.current === 'boolean' &&
    typeof ref.isDefault === 'boolean' && (ref.isRemote === undefined ||
      (typeof ref.isRemote === 'boolean' && (refKind === 'all' || !ref.isRemote))) &&
    (ref.remoteName === undefined || validGitText(ref.remoteName)) &&
    (ref.upstreamRef === undefined || validGitText(ref.upstreamRef)) &&
    (ref.worktreePath === null || validGitText(ref.worktreePath));
}

export function readThreadGitRefs(value: Object, refKind: ThreadGitRefKind = 'local'): NativeThreadGitRefs {
  const result = value as NativeThreadGitRefs;
  if (typeof result?.isRepo !== 'boolean' || !Array.isArray(result.refs) ||
    !result.refs.every((ref: NativeThreadGitRef) => validGitRef(ref, refKind)) || !validLineCount(result.totalCount) ||
    (result.isAtRepositoryRoot !== undefined && typeof result.isAtRepositoryRoot !== 'boolean') ||
    (result.nextCursor !== null && (!validLineCount(result.nextCursor) || result.nextCursor === 0))) {
    throw new Error('环境返回的 Git 分支列表无效。');
  }
  const refs: NativeThreadGitRefs = {
    refs: result.refs, isRepo: result.isRepo, nextCursor: result.nextCursor, totalCount: result.totalCount,
  };
  if (result.isAtRepositoryRoot !== undefined) refs.isAtRepositoryRoot = result.isAtRepositoryRoot;
  return refs;
}

export function threadGitRefOccupied(ref: NativeThreadGitRef, cwd: string): boolean {
  return !ref.current && ref.worktreePath !== null && ref.worktreePath !== cwd;
}

export function normalizeThreadGitNewRef(name: string): string {
  const fragment = name.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').trim().toLowerCase()
    .replace(/['"`]/g, '')
    .replace(/[^a-z0-9/_-]+/g, '-')
    .replace(/\/+/g, '/')
    .replace(/-+/g, '-')
    .replace(/^[./_-]+|[./_-]+$/g, '')
    .slice(0, 64)
    .replace(/[./_-]+$/g, '') || 'update';
  return fragment.includes('/') ? fragment : `feature/${fragment}`;
}

export function threadGitCreateRefRequest(cwd: string, refName: string): GitRequest<GitRefInput> {
  requireGitDirectory(cwd);
  if (!validGitText(refName)) throw new Error('新分支名无效。');
  const payload: GitRefInput = { cwd, refName, switchRef: true };
  return gitRequest('vcs.createRef', payload);
}

export function threadGitSwitchRefRequest(cwd: string, refName: string): GitRequest<GitRefInput> {
  requireGitDirectory(cwd);
  if (!validGitText(refName)) throw new Error('Git 分支名无效。');
  const payload: GitRefInput = { cwd, refName };
  return gitRequest('vcs.switchRef', payload);
}

export function readThreadGitRefName(value: Object): string | null {
  const result = value as GitRefResponse;
  if (result?.refName !== null && !validGitText(result?.refName)) throw new Error('环境返回的 Git 分支无效。');
  return result.refName;
}

export function threadGitBranchMetadataRequest(commandId: string, threadId: string, refName: string | null,
  expectedWorktreePath: string | null): GitRequest<GitBranchMetadataInput> {
  if (!validGitText(commandId) || !validGitText(threadId) || (refName !== null && !validGitText(refName)) ||
    (expectedWorktreePath !== null && !validGitText(expectedWorktreePath))) {
    throw new Error('会话的 Git 分支信息无效。');
  }
  const payload: GitBranchMetadataInput = {
    type: 'thread.metadata.update', commandId, threadId, branch: refName, expectedWorktreePath,
  };
  return gitRequest('orchestration.dispatchCommand', payload);
}

export function threadGitCommitFilePaths(files: NativeThreadGitFile[], excluded: Set<string>): string[] | undefined {
  const paths = files.filter((file: NativeThreadGitFile) => !excluded.has(file.path))
    .map((file: NativeThreadGitFile) => file.path);
  if (paths.length === 0) throw new Error('请选择要提交的文件。');
  // Git needs the all-files form to complete a merge, cherry-pick, or revert.
  return paths.length === files.length ? undefined : paths;
}

export function threadGitCommitRequest(cwd: string, actionId: string, message: string, filePaths?: string[],
  threadId?: string, projectId?: string): GitRequest<GitCommitInput> {
  requireGitDirectory(cwd);
  const commitMessage = message.trim();
  if (!validGitText(commitMessage) || commitMessage.length > 10_000) throw new Error('请输入有效的 Git 提交说明。');
  if (!validGitText(actionId) || (threadId !== undefined && !validGitText(threadId)) ||
    (projectId !== undefined && !validGitText(projectId))) throw new Error('Git 提交标识无效。');
  if (filePaths && (filePaths.length === 0 || filePaths.some((path: string) => !path || path.includes('\u0000')))) {
    throw new Error('请选择要提交的有效文件。');
  }
  const payload: GitCommitInput = { cwd, actionId, action: 'commit', commitMessage };
  if (filePaths !== undefined) payload.filePaths = filePaths;
  if (threadId !== undefined) payload.threadId = threadId;
  if (projectId !== undefined) payload.projectId = projectId;
  return gitRequest('git.runStackedAction', payload);
}

export function threadGitPushRequest(cwd: string, actionId: string, threadId?: string,
  projectId?: string): GitRequest<GitStackedActionInput> {
  requireGitDirectory(cwd);
  if (!validGitText(actionId) || (threadId !== undefined && !validGitText(threadId)) ||
    (projectId !== undefined && !validGitText(projectId))) throw new Error('Git 推送标识无效。');
  const payload: GitStackedActionInput = { cwd, actionId, action: 'push' };
  if (threadId !== undefined) payload.threadId = threadId;
  if (projectId !== undefined) payload.projectId = projectId;
  return gitRequest('git.runStackedAction', payload);
}

function readThreadGitActionResult(value: Object, cwd: string, actionId: string, action: string,
  label: string): GitActionResponse | undefined {
  const progress = value as GitActionProgress;
  if (progress?.actionId !== actionId || progress.cwd !== cwd || progress.action !== action ||
    typeof progress.kind !== 'string') throw new Error(`环境返回的 Git ${label}进度无效。`);
  if (progress.kind === 'action_failed') throw new Error(progress.message || `Git ${label}失败。`);
  if (progress.kind !== 'action_finished') return undefined;
  if (progress.result?.action !== action) throw new Error(`环境返回的 Git ${label}结果无效。`);
  return progress.result;
}

export function readThreadGitCommitProgress(value: Object, cwd: string,
  actionId: string): NativeThreadGitCommitResult | undefined {
  const result = readThreadGitActionResult(value, cwd, actionId, 'commit', '提交');
  if (result === undefined) return undefined;
  const commit = result.commit;
  if (!commit || (commit.status !== 'created' && commit.status !== 'skipped_no_changes') ||
    (commit.status === 'created' && !validGitText(commit.commitSha)) ||
    (commit.subject !== undefined && !validGitText(commit.subject))) {
    throw new Error('环境返回的 Git 提交结果无效。');
  }
  return commit;
}

export function readThreadGitPushProgress(value: Object, cwd: string,
  actionId: string): NativeThreadGitPushResult | undefined {
  const result = readThreadGitActionResult(value, cwd, actionId, 'push', '推送');
  if (result === undefined) return undefined;
  const push = result.push;
  if (!push || (push.status !== 'pushed' && push.status !== 'skipped_up_to_date') ||
    (push.branch !== undefined && !validGitText(push.branch)) ||
    (push.upstreamBranch !== undefined && !validGitText(push.upstreamBranch)) ||
    (push.setUpstream !== undefined && typeof push.setUpstream !== 'boolean')) {
    throw new Error('环境返回的 Git 推送结果无效。');
  }
  return push;
}
