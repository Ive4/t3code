import { REQUEST_ID } from './T3Protocol';

export interface NativeThreadReviewPatch {
  lines: string[];
  truncated: boolean;
}

type ReviewChangeType = 'change' | 'rename-pure' | 'rename-changed' | 'new' | 'deleted';

export interface NativeThreadReviewFile {
  path: string;
  previousPath: string | null;
  changeType?: ReviewChangeType;
  additions: number;
  deletions: number;
  patch?: NativeThreadReviewPatch;
}

export interface NativeThreadReview {
  baseRef: string | null;
  files: NativeThreadReviewFile[];
  totalFiles: number;
  incomplete: boolean;
}

interface ReviewFileSelector {
  path: string;
  previousPath: string | null;
  changeType?: ReviewChangeType;
  sourceKind: string;
}

interface ReviewInput {
  cwd: string;
  sourceKind?: string;
  baseRef?: string;
  file?: ReviewFileSelector;
}

interface ReviewRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: ReviewInput;
  headers: string[][];
}

interface ReviewSource {
  kind: string;
  baseRef: string | null;
  diff: string;
  truncated: boolean;
  patchesDeferred?: boolean;
  files?: NativeThreadReviewFile[];
}

interface ReviewResponse {
  cwd: string;
  generatedAt: string;
  sources: ReviewSource[];
  incomplete?: boolean;
}

const FILE_LIMIT = 100;
const PATCH_LINE_LIMIT = 300;
const LINE_LENGTH_LIMIT = 480;
const OUTPUT_TRUNCATED_MARKER = '\n\n[truncated]';

function validReviewText(value: string): boolean {
  return typeof value === 'string' && value.length > 0 && value.trim() === value && !value.includes('\0');
}

function validPath(path: string): boolean {
  return typeof path === 'string' && !path.includes('\0') &&
    path.split('/').every((part: string) => part !== '' && part !== '.' && part !== '..');
}

function validChangeType(value: ReviewChangeType | undefined): boolean {
  return value === undefined || value === 'change' || value === 'rename-pure' ||
    value === 'rename-changed' || value === 'new' || value === 'deleted';
}

export function threadReviewRequest(cwd: string, file?: NativeThreadReviewFile,
  baseRef?: string | null): ReviewRequest {
  if (!validReviewText(cwd)) throw new Error('当前任务没有可用的工作区。');
  const payload: ReviewInput = { cwd };
  if (file === undefined) {
    payload.sourceKind = 'working-tree';
  } else {
    if (!validPath(file.path) || (file.previousPath !== null && !validPath(file.previousPath)) ||
      !validChangeType(file.changeType)) throw new Error('当前变更文件的路径无效。');
    payload.file = { path: file.path, previousPath: file.previousPath, sourceKind: 'working-tree' };
    if (file.changeType !== undefined) payload.file.changeType = file.changeType;
    if (baseRef !== undefined && baseRef !== null) {
      if (!validReviewText(baseRef)) throw new Error('当前变更的基准引用无效。');
      payload.baseRef = baseRef;
    }
  }
  return { _tag: 'Request', id: REQUEST_ID, tag: 'review.getDiffPreview', payload, headers: [] };
}

function readReviewResponse(value: Object, cwd: string): ReviewResponse {
  const response = value as ReviewResponse;
  if (response?.cwd !== cwd || typeof response?.generatedAt !== 'string' || !Array.isArray(response.sources) ||
    (response.incomplete !== undefined && typeof response.incomplete !== 'boolean')) {
    throw new Error('环境返回的未提交变更无效。');
  }
  return response;
}

function readWorkingTree(sources: ReviewSource[]): ReviewSource | undefined {
  const matches = sources.filter((source: ReviewSource) => source?.kind === 'working-tree');
  if (matches.length === 0) return undefined;
  const source = matches[0];
  if (matches.length !== 1 || (source.baseRef !== null && !validReviewText(source.baseRef)) ||
    typeof source.diff !== 'string' || typeof source.truncated !== 'boolean' ||
    (source.patchesDeferred !== undefined && typeof source.patchesDeferred !== 'boolean') ||
    (source.files !== undefined && !Array.isArray(source.files))) {
    throw new Error('环境返回的未提交变更无效。');
  }
  return source;
}

function readFileStats(files: NativeThreadReviewFile[]): NativeThreadReviewFile[] {
  const paths = new Set<string>();
  return files.map((file: NativeThreadReviewFile): NativeThreadReviewFile => {
    if (!file || !validPath(file.path) || paths.has(file.path) ||
      (file.previousPath !== null && !validPath(file.previousPath)) || !validChangeType(file.changeType) ||
      !Number.isSafeInteger(file.additions) || file.additions < 0 ||
      !Number.isSafeInteger(file.deletions) || file.deletions < 0) {
      throw new Error('环境返回的变更文件统计无效。');
    }
    paths.add(file.path);
    return {
      path: file.path,
      previousPath: file.previousPath,
      changeType: file.changeType,
      additions: file.additions,
      deletions: file.deletions,
    };
  });
}

function gitEscape(token: string): string {
  switch (token) {
    case '%': return '%25';
    case '\\a': return '%07';
    case '\\b': return '%08';
    case '\\t': return '%09';
    case '\\n': return '%0a';
    case '\\v': return '%0b';
    case '\\f': return '%0c';
    case '\\r': return '%0d';
    case '\\"': return '%22';
    case '\\\\': return '%5c';
    default: return '%' + parseInt(token.slice(1), 8).toString(16).padStart(2, '0');
  }
}

function readGitPath(value: string, prefix: string): string {
  let path = value.endsWith('\t') ? value.slice(0, -1) : value;
  if (path.startsWith('"')) {
    if (!path.endsWith('"')) return '';
    try {
      path = decodeURIComponent(path.slice(1, -1).replace(/%|\\(?:[0-3][0-7]{2}|.)/g, gitEscape));
    } catch (_) {
      return '';
    }
  }
  if (!path.startsWith(prefix)) return '';
  const relative = path.slice(prefix.length);
  return validPath(relative) ? relative : '';
}

export function readGitDiffFile(section: string, truncated: boolean): NativeThreadReviewFile | undefined {
  const rows = section.split('\n');
  if (rows[rows.length - 1] === '') rows.pop();
  const header = rows[0];
  if (!header) return undefined;
  // A non-rename header repeats the path with equally long a/ and b/ prefixes.
  const middle = Math.floor(header.length / 2);
  const left = readGitPath(header.slice(0, middle), 'a/');
  let path = header[middle] === ' ' && left === readGitPath(header.slice(middle + 1), 'b/') ? left : '';
  let oldPath = '';
  let changeType: ReviewChangeType = 'change';
  let additions = 0;
  let deletions = 0;
  let inHunk = false;
  const patch: NativeThreadReviewPatch = { lines: [], truncated };
  for (let index = 1; index < rows.length; index += 1) {
    const line = rows[index];
    if (line.startsWith('@@ ')) inHunk = true;
    if (inHunk) {
      if (line.startsWith('+')) additions += 1;
      if (line.startsWith('-')) deletions += 1;
    } else if (line.startsWith('+++ b/') || line.startsWith('+++ "b/')) {
      path = readGitPath(line.slice(4), 'b/') || path;
    } else if (line.startsWith('--- a/') || line.startsWith('--- "a/')) {
      oldPath = readGitPath(line.slice(4), 'a/');
    } else if (line.startsWith('rename to ')) {
      path = readGitPath(line.slice(10), '') || path;
      changeType = 'rename-pure';
    } else if (line.startsWith('rename from ')) {
      oldPath = readGitPath(line.slice(12), '');
    } else if (line.startsWith('new file mode ')) {
      changeType = 'new';
    } else if (line.startsWith('deleted file mode ')) {
      changeType = 'deleted';
    }
    if (inHunk || line.startsWith('Binary files ') || line.startsWith('GIT binary patch') ||
      line.startsWith('similarity index ') || line.startsWith('old mode ') || line.startsWith('new mode ')) {
      if (patch.lines.length === PATCH_LINE_LIMIT) {
        patch.truncated = true;
      } else if (line.length > LINE_LENGTH_LIMIT) {
        patch.lines.push(line.slice(0, LINE_LENGTH_LIMIT - 1) + '…');
        patch.truncated = true;
      } else {
        patch.lines.push(line);
      }
    }
  }
  const previousPath = oldPath && path && oldPath !== path ? oldPath : null;
  if (changeType === 'rename-pure' && (additions > 0 || deletions > 0)) changeType = 'rename-changed';
  path = path || oldPath;
  return path ? { path, previousPath, changeType, additions, deletions, patch } : undefined;
}

export function readGitDiffFiles(patch: string, truncated: boolean): Map<string, NativeThreadReviewFile> {
  const files = new Map<string, NativeThreadReviewFile>();
  const diff = truncated && patch.endsWith(OUTPUT_TRUNCATED_MARKER) ?
    patch.slice(0, -OUTPUT_TRUNCATED_MARKER.length) : patch;
  const sections = diff.split(/^diff --git /m);
  for (let index = 1; index < sections.length; index += 1) {
    const file = readGitDiffFile(sections[index], truncated && index === sections.length - 1);
    if (file !== undefined) files.set(file.path, file);
  }
  return files;
}

export function readThreadReview(value: Object, cwd: string): NativeThreadReview {
  const response = readReviewResponse(value, cwd);
  const source = readWorkingTree(response.sources);
  if (source === undefined) {
    return { baseRef: null, files: [], totalFiles: 0, incomplete: response.incomplete === true };
  }
  const stats = source.files === undefined ? undefined : readFileStats(source.files);
  let files: NativeThreadReviewFile[] = [];
  if (stats === undefined) {
    files = Array.from(readGitDiffFiles(source.diff, source.truncated).values());
  } else {
    files = stats;
    if (!source.truncated && !source.patchesDeferred) {
      const patches = readGitDiffFiles(source.diff, source.truncated);
      for (const file of files) file.patch = patches.get(file.path)?.patch;
    }
  }
  return {
    baseRef: source.baseRef,
    files: files.slice(0, FILE_LIMIT),
    totalFiles: files.length,
    incomplete: response.incomplete === true || (source.truncated && stats === undefined),
  };
}

export function readThreadReviewPatch(value: Object, cwd: string,
  file: NativeThreadReviewFile): NativeThreadReviewPatch {
  const source = readWorkingTree(readReviewResponse(value, cwd).sources);
  const patch = source === undefined ? undefined :
    readGitDiffFiles(source.diff, source.truncated).get(file.path)?.patch;
  if (patch !== undefined) return patch;
  if (source?.truncated && source.files?.some((stat: NativeThreadReviewFile) => stat?.path === file.path)) {
    return { lines: [], truncated: true };
  }
  throw new Error('无法读取此文件的差异，请刷新变更列表。');
}
