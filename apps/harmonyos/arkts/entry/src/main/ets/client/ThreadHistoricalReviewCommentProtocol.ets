import type { ThreadMessageContext } from './T3Protocol';

export interface NativeHistoricalReviewComment {
  id: string;
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

export interface NativeHistoricalReviewCommentBlock {
  kind: 'text' | 'review-comment';
  start: number;
  end: number;
  text: string;
  comment?: NativeHistoricalReviewComment;
}

interface ReviewFence {
  language: string;
  length: number;
  start: number;
  contentsStart: number;
}

interface ReviewBody {
  closeStart: number;
  proseEnd: number;
  contentsStart: number;
  contentsEnd: number;
  language: string;
}

interface StoredReviewComment extends NativeHistoricalReviewComment {
  kind: string;
  version: number;
  contextId: string;
}

const REVIEW_OPEN_TAG = '<review_comment';
const REVIEW_CLOSE_TAG = '</review_comment>';
const CONTEXT_REFERENCE = /!?\[[^[\]\n]{0,512}\]\(t3-context:\/\/v1\/[a-z][a-z0-9-]{0,39}\/[a-zA-Z0-9_-]{1,128}\)/g;

export function readReviewCommentContextRecord(value: Object): NativeHistoricalReviewComment | undefined {
  const record = value as StoredReviewComment;
  if (record?.version !== 1 || record.kind !== 'review-comment' || typeof record.contextId !== 'string' ||
    typeof record.sectionId !== 'string' || record.sectionId.startsWith('pull-request:') ||
    typeof record.sectionTitle !== 'string' || typeof record.filePath !== 'string' || !record.filePath.trim() ||
    typeof record.rangeLabel !== 'string' || typeof record.text !== 'string' || typeof record.diff !== 'string' ||
    !Number.isSafeInteger(record.startIndex) || !Number.isSafeInteger(record.endIndex) ||
    record.startIndex < 0 || record.endIndex < record.startIndex) return undefined;
  return { id: record.contextId, sectionId: record.sectionId, sectionTitle: record.sectionTitle, filePath: record.filePath,
    startIndex: record.startIndex, endIndex: record.endIndex, rangeLabel: record.rangeLabel, text: record.text,
    diff: record.diff, fenceLanguage: typeof record.fenceLanguage === 'string' ? record.fenceLanguage : 'diff' };
}

export function readStructuredReviewCommentBlocks(text: string, context?: ThreadMessageContext): NativeHistoricalReviewCommentBlock[] {
  if (context?.version !== 1 || !text.includes('t3-context://v1/review-comment/')) return [];
  const records = new Map<string, NativeHistoricalReviewComment>();
  for (const value of context.records) {
    const record = readReviewCommentContextRecord(value);
    if (record) records.set(record.id, record);
  }
  const blocks: NativeHistoricalReviewCommentBlock[] = [];
  const reference = /\[[^[\]\n]{0,512}\]\(t3-context:\/\/v1\/review-comment\/([a-zA-Z0-9_-]{1,128})\)/g;
  for (let match = reference.exec(text); match; match = reference.exec(text)) {
    const comment = records.get(match[1]);
    if (!comment) continue;
    blocks.push({ kind: 'review-comment', start: match.index, end: match.index + match[0].length, text: match[0], comment });
  }
  return blocks;
}

function reviewAttributes(source: string): Map<string, string> {
  const attributes = new Map<string, string>();
  const attribute = /([a-zA-Z][a-zA-Z0-9_-]*)="([^"]*)"/g;
  for (let match = attribute.exec(source); match; match = attribute.exec(source)) {
    attributes.set(match[1], match[2].replace(/&lt;/g, '<').replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"').replace(/&amp;/g, '&'));
  }
  return attributes;
}

function readLineIndex(value: string): number {
  if (!/^\d+$/.test(value)) return -1;
  const index = Number(value);
  return Number.isSafeInteger(index) ? index : -1;
}

function readReviewBody(masked: string, start: number): ReviewBody | undefined {
  // A snippet can contain the closing review tag as source text.
  const boundaries = /^[ \t]{0,3}(`{3,})([^\r\n]*)\r?$|<\/review_comment>/gm;
  boundaries.lastIndex = start;
  let openFence: ReviewFence | undefined;
  let proseEnd = -1;
  let contentsStart = 0;
  let contentsEnd = 0;
  let language = 'diff';
  for (let boundary = boundaries.exec(masked); boundary; boundary = boundaries.exec(masked)) {
    if (boundary[1] !== undefined) {
      if (openFence === undefined) {
        openFence = {
          language: /^[^\s`]+/.exec(boundary[2])?.[0] ?? 'diff',
          length: boundary[1].length,
          start: boundary.index,
          contentsStart: boundaries.lastIndex + 1,
        };
      } else if (boundary[1].length >= openFence.length && !boundary[2].trim()) {
        proseEnd = openFence.start;
        contentsStart = openFence.contentsStart;
        const newlineLength = masked[boundary.index - 2] === '\r' ? 2 : 1;
        contentsEnd = Math.max(contentsStart, boundary.index - newlineLength);
        language = openFence.language;
        openFence = undefined;
      }
    } else if (openFence === undefined) {
      return { closeStart: boundary.index, proseEnd: proseEnd < 0 ? boundary.index : proseEnd,
        contentsStart, contentsEnd, language };
    }
  }
  return undefined;
}

function readReviewComment(value: string, rawAttributes: string, bodyStart: number, body: ReviewBody,
  index: number): NativeHistoricalReviewComment | undefined {
  const attributes = reviewAttributes(rawAttributes);
  const sectionId = attributes.get('sectionId')?.trim() ?? '';
  const filePath = attributes.get('filePath')?.trim() ?? '';
  const startIndex = readLineIndex(attributes.get('startIndex') ?? '');
  const endIndex = readLineIndex(attributes.get('endIndex') ?? '');
  if (!sectionId || !filePath || startIndex < 0 || endIndex < 0) return undefined;
  return {
    id: `review-comment:${index}:${sectionId}:${filePath}:${startIndex}:${endIndex}`,
    sectionId, filePath, sectionTitle: attributes.get('sectionTitle')?.trim() || '审查',
    startIndex: Math.min(startIndex, endIndex), endIndex: Math.max(startIndex, endIndex),
    rangeLabel: attributes.get('rangeLabel')?.trim() || '行',
    text: value.slice(bodyStart, body.proseEnd).trim(),
    diff: value.slice(body.contentsStart, body.contentsEnd),
    fenceLanguage: body.language,
  };
}

export function parseHistoricalReviewCommentBlocks(value: string): NativeHistoricalReviewCommentBlock[] {
  if (value.length === 0) return [];
  if (!value.includes(REVIEW_OPEN_TAG) || !value.includes(REVIEW_CLOSE_TAG)) {
    return [{ kind: 'text', start: 0, end: value.length, text: value }];
  }
  const masked = value.includes('](t3-context:') ?
    value.replace(CONTEXT_REFERENCE, (reference: string): string => ' '.repeat(reference.length)) : value;
  const openings = /<review_comment\b([^>]*)>/g;
  const blocks: NativeHistoricalReviewCommentBlock[] = [];
  let cursor = 0;
  let commentIndex = 0;
  for (let opening = openings.exec(masked); opening; opening = openings.exec(masked)) {
    const start = opening.index;
    const bodyStart = openings.lastIndex;
    const body = readReviewBody(masked, bodyStart);
    if (body === undefined) break;
    if (start > cursor) blocks.push({ kind: 'text', start: cursor, end: start, text: value.slice(cursor, start) });
    const end = body.closeStart + REVIEW_CLOSE_TAG.length;
    const rawAttributes = value.slice(start + REVIEW_OPEN_TAG.length, bodyStart - 1);
    const comment = readReviewComment(value, rawAttributes, bodyStart, body, commentIndex);
    const text = value.slice(start, end);
    if (comment === undefined) {
      blocks.push({ kind: 'text', start, end, text });
    } else {
      blocks.push({ kind: 'review-comment', start, end, text, comment });
      commentIndex++;
    }
    cursor = end;
    openings.lastIndex = end;
  }
  if (cursor < value.length) blocks.push({ kind: 'text', start: cursor, end: value.length, text: value.slice(cursor) });
  return blocks;
}
