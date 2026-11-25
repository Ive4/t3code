import type { ComposerCommandContextRecord } from './ComposerCommandProtocol';

export const THREAD_REVIEW_COMMENT_MAX_CHARS = 16_000;
const REVIEW_COMMENT_DIFF_MAX_CHARS = 32_000;
const REVIEW_COMMENT_SECTION_ID_MAX_CHARS = 255;
const REVIEW_COMMENT_PATH_MAX_CHARS = 2_048;
const REVIEW_COMMENT_SECTION_TITLE_MAX_CHARS = 2_048;
const REVIEW_COMMENT_LABEL_MAX_CHARS = 200;

type ThreadReviewDiffRowKind = 'add' | 'delete' | 'context' | 'hunk' | 'metadata';

export interface NativeThreadReviewDiffRow {
  kind: ThreadReviewDiffRowKind;
  text: string;
  content: string;
  index: number | null;
  oldNumber: number | null;
  newNumber: number | null;
}

export interface NativeThreadReviewLineSelection {
  startIndex: number;
  endIndex: number;
  rangeLabel: string;
  diff: string;
  rows: NativeThreadReviewDiffRow[];
}

export interface NativeThreadFileReviewCommentTarget {
  filePath: string;
  sectionId?: string;
  sectionTitle?: string;
  diff?: string;
  selection?: NativeThreadReviewLineSelection;
}

export interface NativeThreadFileReviewCommentRecord extends ComposerCommandContextRecord {
  kind: 'review-comment';
  sectionId: string;
  sectionTitle: string;
  filePath: string;
  startIndex: number;
  endIndex: number;
  rangeLabel: string;
  text: string;
  diff: string;
  fenceLanguage: string;
}

function limitReviewText(value: string, maxLength: number): string {
  if (value.length <= maxLength) return value;
  return value.slice(0, maxLength).replace(/[\uD800-\uDBFF]$/, '');
}

export function parseThreadReviewDiffRows(lines: string[]): NativeThreadReviewDiffRow[] {
  let oldLine = 0;
  let newLine = 0;
  let oldRemaining = 0;
  let newRemaining = 0;
  let index = 0;
  return lines.map((text: string): NativeThreadReviewDiffRow => {
    const hunk = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?:\s|$)/.exec(text);
    if (hunk) {
      oldLine = Number(hunk[1]);
      newLine = Number(hunk[3]);
      oldRemaining = Number(hunk[2] ?? '1');
      newRemaining = Number(hunk[4] ?? '1');
      if (!Number.isSafeInteger(oldLine + oldRemaining) || !Number.isSafeInteger(newLine + newRemaining) ||
        (oldLine === 0 && oldRemaining > 0) || (newLine === 0 && newRemaining > 0)) {
        oldRemaining = 0;
        newRemaining = 0;
      }
      return { kind: 'hunk', text, content: text, index: null, oldNumber: null, newNumber: null };
    }
    const marker = text[0];
    const oldNumber = (marker === '-' || marker === ' ') && oldRemaining > 0 ? oldLine : null;
    const newNumber = (marker === '+' || marker === ' ') && newRemaining > 0 ? newLine : null;
    if ((oldNumber === null && newNumber === null) ||
      (marker === ' ' && (oldNumber === null || newNumber === null))) {
      if (!text.startsWith('\\ No newline at end of file')) {
        oldRemaining = 0;
        newRemaining = 0;
      }
      return { kind: 'metadata', text, content: text, index: null, oldNumber: null, newNumber: null };
    }
    if (oldNumber !== null) {
      oldLine++;
      oldRemaining--;
    }
    if (newNumber !== null) {
      newLine++;
      newRemaining--;
    }
    return { kind: marker === '+' ? 'add' : marker === '-' ? 'delete' : 'context',
      text, content: text.slice(1), index: index++, oldNumber, newNumber };
  });
}

export function buildThreadReviewLineSelection(rows: NativeThreadReviewDiffRow[], anchorIndex: number,
  endIndex: number = anchorIndex): NativeThreadReviewLineSelection | undefined {
  const start = Math.min(anchorIndex, endIndex);
  const end = Math.max(anchorIndex, endIndex);
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0) return undefined;
  const selected = rows.filter((row: NativeThreadReviewDiffRow) => row.index !== null && row.index >= start && row.index <= end);
  if (selected.length !== end - start + 1) return undefined;
  const first = selected[0];
  const last = selected[selected.length - 1];
  const firstNumber = first.newNumber ?? first.oldNumber;
  const lastNumber = last.newNumber ?? last.oldNumber;
  if (firstNumber === null || lastNumber === null) return undefined;
  const sameKind = selected.every((row: NativeThreadReviewDiffRow) => row.kind === first.kind);
  const marker = sameKind && first.kind === 'add' ? '+' : sameKind && first.kind === 'delete' ? '-' : '';
  const rangeLabel = firstNumber === lastNumber ? `${marker}${firstNumber}` : `${marker}${firstNumber} to ${marker}${lastNumber}`;
  const oldRows = selected.filter((row: NativeThreadReviewDiffRow) => row.oldNumber !== null);
  const newRows = selected.filter((row: NativeThreadReviewDiffRow) => row.newNumber !== null);
  const diff = [`@@ -${oldRows[0]?.oldNumber ?? 0},${oldRows.length} +${newRows[0]?.newNumber ?? 0},${newRows.length} @@`,
    ...selected.map((row: NativeThreadReviewDiffRow) => row.text)].join('\n');
  return { startIndex: start, endIndex: end, rangeLabel, diff, rows: selected };
}

export function createThreadFileReviewCommentRecord(contextId: string, target: NativeThreadFileReviewCommentTarget,
  comment: string): NativeThreadFileReviewCommentRecord | undefined {
  const path = target.filePath;
  const text = comment.trim();
  if (!/^[a-z0-9_-]{1,128}$/i.test(contextId) || !text || text.length > THREAD_REVIEW_COMMENT_MAX_CHARS ||
    !path || path !== path.trim() || path.length > REVIEW_COMMENT_PATH_MAX_CHARS || path.includes('\0')) return undefined;

  const sectionId = target.sectionId?.trim() || `file:${path}`;
  const sectionTitle = target.sectionTitle?.trim() || 'File comment';
  const basename = path.slice(Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\')) + 1);
  const selection = target.selection;
  if (selection && (!Number.isSafeInteger(selection.startIndex) || !Number.isSafeInteger(selection.endIndex) ||
    selection.startIndex < 0 || selection.endIndex < selection.startIndex || !selection.rangeLabel.trim())) return undefined;
  const rangeLabel = selection?.rangeLabel ?? 'file';
  const label = `${basename} ${rangeLabel}`.replace(/[[\]\\\r\n]/g, ' ').replace(/\s+/g, ' ').trim();
  return {
    version: 1,
    kind: 'review-comment',
    contextId,
    label: limitReviewText(label, REVIEW_COMMENT_LABEL_MAX_CHARS),
    sectionId: limitReviewText(sectionId, REVIEW_COMMENT_SECTION_ID_MAX_CHARS).trimEnd(),
    sectionTitle: limitReviewText(sectionTitle, REVIEW_COMMENT_SECTION_TITLE_MAX_CHARS),
    filePath: path,
    startIndex: selection?.startIndex ?? 0,
    endIndex: selection?.endIndex ?? 0,
    rangeLabel: limitReviewText(rangeLabel, REVIEW_COMMENT_SECTION_TITLE_MAX_CHARS),
    text,
    diff: limitReviewText(selection?.diff ?? target.diff ?? '', REVIEW_COMMENT_DIFF_MAX_CHARS),
    fenceLanguage: 'diff',
  };
}
