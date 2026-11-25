import { scopedRef } from './PullRequestProtocol';
import type { NativePullRequestRef } from './PullRequestProtocol';
import { REQUEST_ID } from './T3Protocol';

export interface NativePullRequestGuideTarget {
  path: string;
  side?: 'old' | 'new';
  start?: number;
  end?: number;
}

export interface NativePullRequestGuideAttention {
  kind: 'tradeoff' | 'contract' | 'product' | 'risk' | 'accessibility';
  note: string;
}

export interface NativePullRequestGuideExcerpt extends NativePullRequestGuideTarget {
  side: 'old' | 'new';
  start: number;
  end: number;
  caption: string;
}

export interface NativePullRequestGuideFile extends NativePullRequestGuideTarget {
  note?: string;
}

export interface NativePullRequestGuideNote {
  path: string;
  line: number;
  title: string;
  body: string;
}

export interface NativePullRequestGuideStop {
  title: string;
  summary: string;
  attention: NativePullRequestGuideAttention | null;
  excerpts: NativePullRequestGuideExcerpt[];
  files: NativePullRequestGuideFile[];
  notes: NativePullRequestGuideNote[];
  questions: string[];
}

export interface NativePullRequestGuide {
  headSha: string;
  generatedAt: string;
  stops: NativePullRequestGuideStop[];
}

export interface NativePullRequestGuideRun {
  _tag: 'Running' | 'Failed';
  headSha: string;
  detail?: string;
}

export interface NativePullRequestGuideResult {
  guide: NativePullRequestGuide | null;
  run: NativePullRequestGuideRun | null;
  currentHeadSha: string | null;
}

interface PullRequestGuideRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: NativePullRequestRef;
  headers: string[][];
}

interface PullRequestGuideSettings {
  reviewGuidesEnabled?: boolean;
}

interface PullRequestGuideConfig {
  settings?: PullRequestGuideSettings;
}

interface GuideDiffRow {
  code: string;
  oldLine: number;
  newLine: number;
  hunk: number;
}

export function pullRequestGuideRequest(ref: NativePullRequestRef): PullRequestGuideRequest {
  return { _tag: 'Request', id: REQUEST_ID, tag: 'pullRequests.reviewGuide', payload: scopedRef(ref), headers: [] };
}

export function generatePullRequestGuideRequest(ref: NativePullRequestRef): PullRequestGuideRequest {
  return { _tag: 'Request', id: REQUEST_ID, tag: 'pullRequests.generateReviewGuide',
    payload: scopedRef(ref), headers: [] };
}

export function pullRequestGuidesEnabled(config?: Object): boolean {
  const value = config as PullRequestGuideConfig | undefined;
  return value?.settings?.reviewGuidesEnabled === true;
}

function validText(value: string): boolean {
  return typeof value === 'string' && !!value.trim();
}

function validPath(path: string): boolean {
  return validText(path) && !/^[a-z]:|^[\\]|^[a-z][a-z\d+.-]*:\/\//i.test(path) &&
    !/[\0\r\n]/.test(path) && path.split(/[\\/]/).every((part: string) => !!part && part !== '.' && part !== '..');
}

function validLine(line: number): boolean {
  return Number.isSafeInteger(line) && line > 0;
}

function validStop(stop: NativePullRequestGuideStop): boolean {
  if (!stop || !validText(stop.title) || typeof stop.summary !== 'string' || !Array.isArray(stop.excerpts) ||
    !Array.isArray(stop.files) || !Array.isArray(stop.notes) || !Array.isArray(stop.questions)) return false;
  const attention = stop.attention;
  return (attention === null || (!!attention && validText(attention.note) &&
    ['tradeoff', 'contract', 'product', 'risk', 'accessibility'].includes(attention.kind))) &&
    stop.excerpts.every((excerpt: NativePullRequestGuideExcerpt) => !!excerpt && validPath(excerpt.path) &&
      (excerpt.side === 'old' || excerpt.side === 'new') && validLine(excerpt.start) && validLine(excerpt.end) &&
      excerpt.end >= excerpt.start && typeof excerpt.caption === 'string') &&
    stop.files.every((file: NativePullRequestGuideFile) => !!file && validPath(file.path) &&
      (file.note === undefined || typeof file.note === 'string')) &&
    stop.notes.every((note: NativePullRequestGuideNote) => !!note && validPath(note.path) && validLine(note.line) &&
      validText(note.title) && typeof note.body === 'string') &&
    stop.questions.every(validText);
}

export function readPullRequestGuide(value: Object | undefined): NativePullRequestGuideResult {
  const result = value as NativePullRequestGuideResult | undefined;
  if (!result || (result.currentHeadSha !== null && !validText(result.currentHeadSha))) {
    throw new Error('环境返回的拉取请求审查导览无效。');
  }
  const guide = result.guide;
  const run = result.run;
  if ((guide !== null && (!guide || !validText(guide.headSha) || !validText(guide.generatedAt) ||
    !Number.isFinite(Date.parse(guide.generatedAt)) || !Array.isArray(guide.stops) || !guide.stops.every(validStop))) ||
    (run !== null && (!run || !validText(run.headSha) ||
      (run._tag !== 'Running' && (run._tag !== 'Failed' || !validText(run.detail ?? '')))))) {
    throw new Error('环境返回的拉取请求审查导览无效。');
  }
  return result;
}

export function pullRequestGuideIsStale(result?: NativePullRequestGuideResult | null): boolean {
  return !!result?.guide && !!result.currentHeadSha && result.guide.headSha !== result.currentHeadSha;
}

function diffRows(patch: string): GuideDiffRow[] {
  const rows: GuideDiffRow[] = [];
  let hunk = 0;
  let oldLine = 0;
  let newLine = 0;
  let remainingOld = 0;
  let remainingNew = 0;
  for (const code of patch.split('\n')) {
    const range = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/.exec(code);
    if (range) {
      hunk++;
      oldLine = Number(range[1]);
      newLine = Number(range[3]);
      remainingOld = Number(range[2] ?? '1');
      remainingNew = Number(range[4] ?? '1');
      if (!Number.isSafeInteger(oldLine + remainingOld) || !Number.isSafeInteger(newLine + remainingNew)) {
        remainingOld = 0;
        remainingNew = 0;
      }
    } else if (code.startsWith('@@') || code.startsWith('diff --git ')) {
      remainingOld = 0;
      remainingNew = 0;
    } else if (code.startsWith('-') && remainingOld > 0 && oldLine > 0) {
      rows.push({ code, oldLine: oldLine++, newLine: 0, hunk });
      remainingOld--;
    } else if (code.startsWith('+') && remainingNew > 0 && newLine > 0) {
      rows.push({ code, oldLine: 0, newLine: newLine++, hunk });
      remainingNew--;
    } else if (code.startsWith(' ') && remainingOld > 0 && remainingNew > 0 && oldLine > 0 && newLine > 0) {
      rows.push({ code, oldLine: oldLine++, newLine: newLine++, hunk });
      remainingOld--;
      remainingNew--;
    }
  }
  return rows;
}

export function pullRequestGuideExcerpt(patch: string, target: NativePullRequestGuideTarget): string {
  const start = target.start ?? 0;
  const end = target.end ?? start;
  if (!validPath(target.path) || !validLine(start) || !validLine(end) || end < start ||
    (target.side !== 'old' && target.side !== 'new')) return '';
  const rows = diffRows(patch);
  let first = -1;
  let last = -1;
  for (let index = 0; index < rows.length; index++) {
    const row = rows[index];
    const line = target.side === 'old' ? row.oldLine : row.newLine;
    if (line >= start && line <= end) {
      if (first === -1) first = index;
      last = index;
    }
  }
  if (first === -1) return '';
  // Keep the paired change within its hunk, as the Android excerpt does.
  if (target.side === 'new' && rows[first].code.startsWith('+')) {
    while (first > 0 && rows[first - 1].hunk === rows[first].hunk && rows[first - 1].code.startsWith('-')) first--;
  } else if (target.side === 'old' && rows[last].code.startsWith('-')) {
    while (last + 1 < rows.length && rows[last + 1].hunk === rows[last].hunk && rows[last + 1].code.startsWith('+')) last++;
  }
  return rows.slice(first, last + 1).map((row: GuideDiffRow) => row.code).join('\n');
}
