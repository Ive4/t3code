import { REQUEST_ID } from './T3Protocol';
import { readGitDiffFiles } from './ThreadReviewProtocol';
import type { NativeThreadReviewFile } from './ThreadReviewProtocol';

type CheckpointStatus = 'ready' | 'missing' | 'error' | 'stale';
const TRUNCATED_MARKER = '\n\n[truncated]';

export interface NativeThreadCheckpointFile {
  path: string;
  kind: string;
  additions: number;
  deletions: number;
}

export interface NativeThreadCheckpointTotals {
  count: number;
  additions: number;
  deletions: number;
}

export interface NativeThreadCheckpointRepository {
  name: string;
  repositoryPath: string;
  files: NativeThreadCheckpointFile[];
  totals: NativeThreadCheckpointTotals;
  baselineMissing: boolean;
}

export interface NativeThreadCheckpointSummary {
  id: string;
  threadId: string;
  runId: string;
  ordinal: number;
  status: CheckpointStatus;
  assistantMessageId: string | null;
  completedAt: string;
  files: NativeThreadCheckpointFile[];
  repositories: NativeThreadCheckpointRepository[];
  totals: NativeThreadCheckpointTotals;
}

export interface NativeThreadCheckpointDiffGroup {
  key: string;
  name?: string;
  repositoryPath: string | null;
  relativePath: string;
  files: NativeThreadReviewFile[];
  totalFiles: number;
  incomplete: boolean;
}

interface ThreadCheckpointDiffRange {
  threadId: string;
  fromTurnCount: number;
  toTurnCount: number;
}

export interface NativeThreadCheckpointDiff extends ThreadCheckpointDiffRange {
  groups: NativeThreadCheckpointDiffGroup[];
}

interface ThreadCheckpointDiffInput extends ThreadCheckpointDiffRange {
  ignoreWhitespace: boolean;
}

interface ThreadCheckpointDiffRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: ThreadCheckpointDiffInput;
  headers: string[][];
}

interface RepositoryDiffWire {
  name: string;
  repositoryPath: string;
  relativePath: string;
  diff: string;
}

interface CheckpointDiffWire extends ThreadCheckpointDiffRange {
  diff: string;
  repositories?: RepositoryDiffWire[];
}

interface CheckpointScopeWire {
  id: string;
  threadId: string;
  cwd: string;
  label?: string;
  repositoryPath?: string;
}

interface CheckpointWire {
  id: string;
  threadId: string;
  scopeId: string;
  runId: string | null;
  appRunOrdinal: number | null;
  ordinalWithinScope: number;
  status: CheckpointStatus;
  files: NativeThreadCheckpointFile[];
  filesTotal?: NativeThreadCheckpointTotals;
  capturedAt: string;
}

interface CheckpointAssistantWire {
  id: string;
  threadId: string;
  runId?: string | null;
  role: string;
  createdAt: string;
}

interface CheckpointSnapshotWire {
  checkpointScopes?: CheckpointScopeWire[];
  checkpoints?: CheckpointWire[];
  messages?: CheckpointAssistantWire[];
}

function validIdentifier(value: string | null | undefined): boolean {
  return typeof value === 'string' && value.trim() === value && value.length > 0 && !/[\u0000-\u001f\u007f]/.test(value);
}

function validCount(value: number): boolean {
  return Number.isSafeInteger(value) && value >= 0;
}

export function threadCheckpointDiffRequest(threadId: string, ordinal: number): ThreadCheckpointDiffRequest {
  if (!validIdentifier(threadId) || !validCount(ordinal) || ordinal === 0) throw new Error('当前轮次的检查点无效。');
  const payload: ThreadCheckpointDiffInput = {
    threadId, fromTurnCount: Math.max(0, ordinal - 1), toTurnCount: ordinal, ignoreWhitespace: false,
  };
  return { _tag: 'Request', id: REQUEST_ID, tag: 'orchestration.getTurnDiff', payload, headers: [] };
}

function diffGroup(diff: string, repository?: RepositoryDiffWire): NativeThreadCheckpointDiffGroup {
  const incomplete = diff.endsWith(TRUNCATED_MARKER);
  const files = Array.from(readGitDiffFiles(diff, incomplete).values());
  return {
    key: repository ? 'repo:' + repository.repositoryPath : '.',
    name: repository?.name,
    repositoryPath: repository?.repositoryPath ?? null,
    relativePath: repository?.relativePath ?? '',
    files, totalFiles: files.length, incomplete,
  };
}

export function readThreadCheckpointDiff(value: Object, expected: ThreadCheckpointDiffRange): NativeThreadCheckpointDiff {
  const result = value as CheckpointDiffWire;
  if (result?.threadId !== expected.threadId || result.fromTurnCount !== expected.fromTurnCount ||
    result.toTurnCount !== expected.toTurnCount || typeof result.diff !== 'string' ||
    (result.repositories !== undefined && !Array.isArray(result.repositories))) {
    throw new Error('环境返回了不匹配的轮次变更。');
  }
  const groups: NativeThreadCheckpointDiffGroup[] = [];
  if (result.diff.trim()) groups.push(diffGroup(result.diff));
  const paths = new Set<string>();
  for (const repository of result.repositories ?? []) {
    if (!repository || !validIdentifier(repository.name) || !validIdentifier(repository.repositoryPath) ||
      typeof repository.relativePath !== 'string' || repository.relativePath.includes('\0') ||
      typeof repository.diff !== 'string' || paths.has(repository.repositoryPath)) {
      throw new Error('环境返回了无效的轮次仓库变更。');
    }
    paths.add(repository.repositoryPath);
    if (repository.diff.trim()) groups.push(diffGroup(repository.diff, repository));
  }
  return { threadId: result.threadId, fromTurnCount: result.fromTurnCount, toTurnCount: result.toTurnCount, groups };
}

function readCheckpointsFileTotals(checkpoint: CheckpointWire): NativeThreadCheckpointTotals {
  const totals = checkpoint.filesTotal;
  if (totals && validCount(totals.count) && validCount(totals.additions) && validCount(totals.deletions) &&
    totals.count >= checkpoint.files.length) return totals;
  let additions = 0;
  let deletions = 0;
  for (const file of checkpoint.files) {
    additions += file.additions;
    deletions += file.deletions;
  }
  return { count: checkpoint.files.length, additions, deletions };
}

function validCheckpointFile(file: NativeThreadCheckpointFile): boolean {
  return !!file && typeof file.path === 'string' && file.path.length > 0 && !file.path.includes('\0') &&
    validIdentifier(file.kind) && validCount(file.additions) && validCount(file.deletions);
}

function validCheckpointStatus(status: CheckpointStatus): boolean {
  return status === 'ready' || status === 'missing' || status === 'error' || status === 'stale';
}

export class ThreadCheckpointProjection {
  private readonly threadId: string;
  private readonly scopes = new Map<string, CheckpointScopeWire>();
  private readonly checkpoints = new Map<string, CheckpointWire>();
  private readonly assistants = new Map<string, CheckpointAssistantWire>();
  private summaries?: NativeThreadCheckpointSummary[] = undefined;

  constructor(threadId: string) {
    this.threadId = threadId;
  }

  reset(value: Object): void {
    const snapshot = value as CheckpointSnapshotWire;
    this.scopes.clear();
    this.checkpoints.clear();
    this.assistants.clear();
    this.summaries = undefined;
    if (Array.isArray(snapshot.checkpointScopes)) {
      for (const scope of snapshot.checkpointScopes) this.updateScope(scope);
    }
    if (Array.isArray(snapshot.checkpoints)) {
      for (const checkpoint of snapshot.checkpoints) this.updateCheckpoint(checkpoint);
    }
    if (Array.isArray(snapshot.messages)) {
      for (const message of snapshot.messages) this.updateAssistant(message);
    }
  }

  updateScope(value: Object): boolean {
    const scope = value as CheckpointScopeWire;
    if (scope?.threadId !== this.threadId || !validIdentifier(scope.id) || !validIdentifier(scope.cwd) ||
      (scope.repositoryPath !== undefined && !validIdentifier(scope.repositoryPath))) return false;
    this.scopes.set(scope.id, scope);
    this.summaries = undefined;
    return true;
  }

  updateCheckpoint(value: Object): boolean {
    const checkpoint = value as CheckpointWire;
    if (checkpoint?.threadId !== this.threadId || !validIdentifier(checkpoint.id) ||
      !validIdentifier(checkpoint.scopeId) || (checkpoint.runId !== null && !validIdentifier(checkpoint.runId)) ||
      !validCount(checkpoint.ordinalWithinScope) ||
      (checkpoint.appRunOrdinal !== null && (!validCount(checkpoint.appRunOrdinal) || checkpoint.appRunOrdinal === 0)) ||
      !validCheckpointStatus(checkpoint.status) || !Number.isFinite(Date.parse(checkpoint.capturedAt)) ||
      !Array.isArray(checkpoint.files) || !checkpoint.files.every(validCheckpointFile)) return false;
    this.checkpoints.set(checkpoint.id, checkpoint);
    this.summaries = undefined;
    return true;
  }

  updateAssistant(value: Object): boolean {
    const message = value as CheckpointAssistantWire;
    if (message?.threadId !== this.threadId || message.role !== 'assistant' || !message.runId ||
      !validIdentifier(message.runId) || !validIdentifier(message.id) ||
      !Number.isFinite(Date.parse(message.createdAt))) return false;
    const previous = this.assistants.get(message.runId);
    if (previous?.id === message.id ||
      (previous && Date.parse(previous.createdAt) > Date.parse(message.createdAt))) return false;
    this.assistants.set(message.runId, message);
    this.summaries = undefined;
    return true;
  }

  private repositoryChanges(): Map<string, NativeThreadCheckpointRepository[]> {
    const missingBaselines = new Set<string>();
    for (const checkpoint of this.checkpoints.values()) {
      if (checkpoint.status === 'missing') missingBaselines.add(
        checkpoint.scopeId + '\0' + (checkpoint.ordinalWithinScope + 1));
    }
    const grouped = new Map<string, NativeThreadCheckpointRepository[]>();
    for (const checkpoint of this.checkpoints.values()) {
      const scope = this.scopes.get(checkpoint.scopeId);
      const repositoryPath = scope?.repositoryPath;
      const runId = checkpoint.runId;
      if (!scope || !repositoryPath || !runId || checkpoint.status !== 'ready') continue;
      const totals = readCheckpointsFileTotals(checkpoint);
      const baselineMissing = totals.count === 0 &&
        missingBaselines.has(checkpoint.scopeId + '\0' + checkpoint.ordinalWithinScope);
      if (!baselineMissing && totals.count === 0) continue;
      const folders = scope.cwd.replace(/\\/g, '/').split('/').filter((folder: string) => folder.length > 0);
      const name = scope.label ?? folders[folders.length - 1] ?? scope.cwd;
      const repositories = grouped.get(runId) ?? [];
      repositories.push({ name, repositoryPath, files: checkpoint.files, totals, baselineMissing });
      grouped.set(runId, repositories);
    }
    for (const repositories of grouped.values()) {
      repositories.sort((left: NativeThreadCheckpointRepository, right: NativeThreadCheckpointRepository) =>
        left.name.localeCompare(right.name) || left.repositoryPath.localeCompare(right.repositoryPath));
    }
    return grouped;
  }

  view(): NativeThreadCheckpointSummary[] {
    if (this.summaries !== undefined) return this.summaries;
    const grouped = this.repositoryChanges();
    const summaries: NativeThreadCheckpointSummary[] = [];
    for (const checkpoint of this.checkpoints.values()) {
      const ordinal = checkpoint.appRunOrdinal;
      const runId = checkpoint.runId;
      if (ordinal === null || runId === null || this.scopes.get(checkpoint.scopeId)?.repositoryPath !== undefined) continue;
      const totals = readCheckpointsFileTotals(checkpoint);
      const combined: NativeThreadCheckpointTotals = {
        count: totals.count, additions: totals.additions, deletions: totals.deletions,
      };
      const repositories = grouped.get(runId) ?? [];
      for (const repository of repositories) {
        combined.count += repository.totals.count;
        combined.additions += repository.totals.additions;
        combined.deletions += repository.totals.deletions;
      }
      summaries.push({
        id: checkpoint.id, threadId: this.threadId, runId, ordinal, status: checkpoint.status, files: checkpoint.files,
        repositories, totals: combined, assistantMessageId: this.assistants.get(runId)?.id ?? null,
        completedAt: checkpoint.capturedAt,
      });
    }
    this.summaries = summaries.sort((left: NativeThreadCheckpointSummary, right: NativeThreadCheckpointSummary) =>
      left.ordinal - right.ordinal);
    return this.summaries;
  }
}
