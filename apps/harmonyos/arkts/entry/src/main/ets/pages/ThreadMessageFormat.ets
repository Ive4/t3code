import { readThreadCitation, threadCitationPreview } from '../client/ThreadCitationProtocol';
import type { NativeThreadCitation } from '../client/ThreadCitationProtocol';
import { parseHistoricalReviewCommentBlocks, readStructuredReviewCommentBlocks } from '../client/ThreadHistoricalReviewCommentProtocol';
import type { NativeHistoricalReviewComment } from '../client/ThreadHistoricalReviewCommentProtocol';
import type { ThreadMessageContext } from '../client/T3Protocol';

export interface ThreadMarkdownSpan {
  kind: 'text' | 'code' | 'strong' | 'emphasis' | 'strong-emphasis' | 'link' | 'citation';
  text: string;
  href?: string;
  citation?: NativeThreadCitation;
}

export interface ThreadMarkdownSection {
  kind: 'paragraph' | 'heading' | 'list' | 'quote';
  index: number;
  level: number;
  marker: string;
  separated: boolean;
  spans: ThreadMarkdownSpan[];
}

export type ThreadMarkdownTableAlignment = 'left' | 'center' | 'right';

export interface ThreadMarkdownTable {
  alignments: ThreadMarkdownTableAlignment[];
  rows: ThreadMarkdownSpan[][][];
}

export interface ThreadMessageBlock {
  kind: 'text' | 'code' | 'review-comment' | 'table';
  text: string;
  language: string;
  index: number;
  prose?: ThreadMarkdownSection[];
  reviewComment?: NativeHistoricalReviewComment;
  table?: ThreadMarkdownTable;
}

interface InlineMatch {
  span: ThreadMarkdownSpan;
  end: number;
}

export function isMarkdownWebLink(target: string): boolean {
  const authority = /^https?:\/\/([^/?#]+)/i.exec(target)?.[1];
  return !!authority && !/[\s\\<>\u0000-\u001f\u007f]/.test(target) && !/[@%]/.test(authority);
}

function readInlineLink(text: string, index: number): InlineMatch | undefined {
  if (text[index - 1] === '!') return undefined;
  const link = /\[([^\[\]\r\n]+)\]\(([^()<>\s]+)\)|<(https?:\/\/[^<>\s]+)>/iy;
  link.lastIndex = index;
  const match = link.exec(text);
  const href = match?.[2] ?? match?.[3];
  if (!match || !href) return undefined;
  if (match[1] === 'Assistant quote') {
    const citation = readThreadCitation(href);
    if (citation !== undefined) {
      return {
        span: { kind: 'citation', text: '“' + threadCitationPreview(citation) + '”', citation },
        end: link.lastIndex,
      };
    }
  }
  if (match[1] && /^t3-context:\/\/v1\/terminal\/[a-z0-9_-]{1,128}$/i.test(href)) {
    return { span: { kind: 'citation', text: match[1] }, end: link.lastIndex };
  }
  if (!isMarkdownWebLink(href)) return undefined;
  return { span: { kind: 'link', text: match[1] ?? href, href }, end: link.lastIndex };
}

function readDelimitedSpan(text: string, index: number, delimiter: string): InlineMatch | undefined {
  const marker = delimiter[0];
  const openEnd = index + delimiter.length;
  if (marker === '\x60') {
    let closing = text.indexOf(delimiter, openEnd);
    while (closing !== -1) {
      const end = closing + delimiter.length;
      if (text[closing - 1] !== marker && text[end] !== marker) {
        const value = text.slice(openEnd, closing);
        const trimPadding = /^ .+ $/.test(value) && value.trim().length > 0;
        return { span: { kind: 'code', text: trimPadding ? value.slice(1, -1) : value }, end };
      }
      closing = text.indexOf(delimiter, end);
    }
    return undefined;
  }
  if (delimiter.length > 3 || !text[openEnd] || /\s/.test(text[openEnd]) ||
    (marker === '_' && /\w/.test(text[index - 1] ?? ''))) return undefined;

  const closing = text.indexOf(delimiter, openEnd);
  const end = closing + delimiter.length;
  if (closing <= openEnd || text[end] === marker || /[\s\\]/.test(text[closing - 1]) ||
    (marker === '_' && /\w/.test(text[end] ?? ''))) return undefined;
  const span: ThreadMarkdownSpan = {
    kind: delimiter.length === 1 ? 'emphasis' : delimiter.length === 2 ? 'strong' : 'strong-emphasis',
    text: text.slice(openEnd, closing),
  };
  return { span, end };
}

function appendText(spans: ThreadMarkdownSpan[], text: string): void {
  if (!text) return;
  const previous = spans[spans.length - 1];
  if (previous?.kind === 'text') previous.text += text;
  else spans.push({ kind: 'text', text });
}

function markdownSpans(lines: string[]): ThreadMarkdownSpan[] {
  const spans: ThreadMarkdownSpan[] = [];
  const markers = /\\([\\\x60*_\[\]()#+.!<>-])|\x60+|\*+|_+|\[|</g;
  for (let i = 0; i < lines.length; i++) {
    if (i > 0) appendText(spans, '\n');
    const line = lines[i];
    let cursor = 0;
    markers.lastIndex = 0;
    let marker = markers.exec(line);
    while (marker !== null) {
      const match = marker[1] !== undefined ? undefined : marker[0] === '[' || marker[0] === '<'
        ? readInlineLink(line, marker.index) : readDelimitedSpan(line, marker.index, marker[0]);
      if (marker[1] !== undefined || match !== undefined) {
        appendText(spans, line.slice(cursor, marker.index));
        if (match !== undefined) spans.push(match.span);
        else appendText(spans, marker[1]);
        cursor = match?.end ?? markers.lastIndex;
        markers.lastIndex = cursor;
      }
      marker = markers.exec(line);
    }
    appendText(spans, line.slice(cursor));
  }
  return spans;
}

function markdownSections(lines: string[]): ThreadMarkdownSection[] | undefined {
  const sections: ThreadMarkdownSection[] = [];
  let plain: string[] = [];
  let separated = false;
  let formatted = false;
  const flushParagraph = (): void => {
    if (plain.length === 0) return;
    const spans = markdownSpans(plain);
    formatted = formatted || spans.length !== 1 || spans[0].kind !== 'text' || spans[0].text !== plain.join('\n');
    sections.push({ kind: 'paragraph', index: sections.length, level: 0, marker: '', separated, spans });
    plain = [];
    separated = false;
  };

  for (const line of lines) {
    if (!line.trim()) {
      flushParagraph();
      separated = sections.length > 0;
      continue;
    }
    const heading = /^ {0,3}(#{1,6})[ \t]+(\S.*)$/.exec(line);
    const quote = /^ {0,3}>[ \t]?(.*)$/.exec(line);
    const list = /^([ \t]{0,12})([-+*]|\d{1,9}[.)])[ \t]+(\S.*)$/.exec(line);
    if (!heading && !quote && !list) {
      plain.push(line);
      continue;
    }
    flushParagraph();
    formatted = true;
    if (heading) {
      const title = heading[2].replace(/[ \t]+#+[ \t]*$/, '');
      sections.push({
        kind: 'heading', index: sections.length, level: heading[1].length,
        marker: '', separated, spans: markdownSpans([title]),
      });
    } else if (quote) {
      sections.push({
        kind: 'quote', index: sections.length, level: 0,
        marker: '', separated, spans: markdownSpans([quote[1]]),
      });
    } else if (list) {
      sections.push({
        kind: 'list', index: sections.length, level: Math.min(3, Math.floor(list[1].replace(/\t/g, '    ').length / 2)),
        marker: list[2].length === 1 ? '•' : list[2], separated, spans: markdownSpans([list[3]]),
      });
    }
    separated = false;
  }
  flushParagraph();
  return formatted ? sections : undefined;
}

function appendProse(blocks: ThreadMessageBlock[], lines: string[]): void {
  const text = lines.join('\n').replace(/^(?:[ \t]*\n)+|(?:\n[ \t]*)+$/g, '');
  if (!text.trim()) return;
  const block: ThreadMessageBlock = { kind: 'text', text, language: '', index: blocks.length };
  const prose = markdownSections(lines);
  if (prose !== undefined) block.prose = prose;
  blocks.push(block);
}

function splitTableCells(line: string): string[] {
  const source = line.trim();
  if (!source.includes('|')) return [];
  const cells: string[] = [];
  let cell = '';
  let endPipe = false;
  for (let index = 0; index < source.length; index++) {
    const char = source[index];
    endPipe = false;
    if (char === '\\' && source[index + 1] === '|') {
      cell += '|';
      index++;
    } else if (char === '\\' && source[index + 1] === '\\') {
      cell += '\\\\';
      index++;
    } else if (char === '|') {
      endPipe = true;
      if (index > 0) cells.push(cell.trim());
      cell = '';
    } else {
      cell += char;
    }
  }
  if (!endPipe && cells.length === 0 && !source.startsWith('|')) return [];
  if (!endPipe) cells.push(cell.trim());
  return cells;
}

function tableRowAt(lines: string[], index: number): string[] {
  const line = lines[index];
  if (!line || /^(?: {4}|\t| {0,3}(?:#{1,6}[ \t]|>|[-+*][ \t]|\d{1,9}[.)][ \t]))/.test(line)) return [];
  return splitTableCells(line);
}

function appendProseAndTables(blocks: ThreadMessageBlock[], lines: string[]): void {
  let proseStart = 0;
  for (let index = 0; index + 1 < lines.length; index++) {
    if (!lines[index + 1].includes('-')) continue;
    const headers = tableRowAt(lines, index);
    const delimiters = tableRowAt(lines, index + 1);
    if (headers.length === 0 || headers.length !== delimiters.length ||
      !delimiters.every((cell: string): boolean => /^:?-+:?$/.test(cell))) continue;

    appendProse(blocks, lines.slice(proseStart, index));
    const alignments = delimiters.map((cell: string): ThreadMarkdownTableAlignment =>
      cell.endsWith(':') ? (cell.startsWith(':') ? 'center' : 'right') : 'left');
    const rows: ThreadMarkdownSpan[][][] = [headers.map((cell: string) => markdownSpans([cell]))];
    const tableStart = index;
    index += 2;
    for (; index < lines.length; index++) {
      const cells = tableRowAt(lines, index);
      if (cells.length === 0) break;
      rows.push(headers.map((_header: string, column: number) => markdownSpans([cells[column] ?? ''])));
    }
    blocks.push({ kind: 'table', text: lines.slice(tableStart, index).join('\n'), language: '',
      index: blocks.length, table: { rows, alignments } });
    proseStart = index;
    index--;
  }
  appendProse(blocks, lines.slice(proseStart));
}

function appendMarkdownBlocks(blocks: ThreadMessageBlock[], text: string): void {
  let lines: string[] = [];
  let fence = '';
  let language = '';
  for (const line of text.split(/\r?\n/)) {
    const match = /^ {0,3}(\x60{3,}|~{3,})(.*)$/.exec(line);
    const marker = match?.[1] ?? '';
    const info = match?.[2].trim() ?? '';
    if (fence.length > 0) {
      if (marker[0] === fence[0] && marker.length >= fence.length && info.length === 0) {
        blocks.push({ kind: 'code', text: lines.join('\n'), language, index: blocks.length });
        lines = [];
        fence = '';
      } else {
        lines.push(line);
      }
    } else if (marker && (marker[0] === '~' || !info.includes('\x60'))) {
      appendProseAndTables(blocks, lines);
      lines = [];
      fence = marker;
      language = info.split(/\s+/, 1)[0];
    } else {
      lines.push(line);
    }
  }
  if (fence.length > 0) {
    blocks.push({ kind: 'code', text: lines.join('\n'), language, index: blocks.length });
  } else {
    appendProseAndTables(blocks, lines);
  }
}

export function threadMessageBlocks(text: string, includeHistoricalReview: boolean = false,
  context?: ThreadMessageContext): ThreadMessageBlock[] {
  const blocks: ThreadMessageBlock[] = [];
  if (includeHistoricalReview && (context || text.includes('<review_comment'))) {
    for (const segment of parseHistoricalReviewCommentBlocks(text)) {
      if (segment.kind === 'review-comment' && segment.comment) {
        blocks.push({ kind: 'review-comment', text: segment.text, language: '', index: blocks.length,
          reviewComment: segment.comment });
      } else {
        let offset = 0;
        for (const reference of readStructuredReviewCommentBlocks(segment.text, context)) {
          appendMarkdownBlocks(blocks, segment.text.slice(offset, reference.start));
          blocks.push({ kind: 'review-comment', text: reference.text, language: '', index: blocks.length,
            reviewComment: reference.comment });
          offset = reference.end;
        }
        appendMarkdownBlocks(blocks, segment.text.slice(offset));
      }
    }
  } else {
    appendMarkdownBlocks(blocks, text);
  }
  return blocks;
}
