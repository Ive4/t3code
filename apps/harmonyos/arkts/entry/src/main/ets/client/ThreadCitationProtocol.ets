const CITATION_PREFIX = 't3-citation://v1/';
const CITATION_CONTEXT_LENGTH = 32;
const CITATION_MAX_TEXT_LENGTH = 8000;
const CITATION_MAX_ID_LENGTH = 4096;
const CITATION_PREVIEW_LENGTH = 64;
const CITATION_MAX_HREF_LENGTH = 9 * (2 * CITATION_MAX_TEXT_LENGTH +
  3 * CITATION_MAX_ID_LENGTH + 2 * CITATION_CONTEXT_LENGTH) + 1000;

export interface ThreadCitationSelector {
  text: string;
  start: number;
  end: number;
  prefix: string;
  suffix: string;
}

export interface NativeThreadCitation extends ThreadCitationSelector {
  version: 1;
  environmentId: string;
  threadId: string;
  messageId: string;
  comment?: string;
}

export function canLocatePlainThreadCitation(text: string): boolean {
  if (!text.trim() || /[\x60\\*_~<>&\[\]$|]/.test(text)) return false;
  return !text.split('\n').some((line: string) =>
    /^\s|\s$|^[#=-]|^\+[ \t]|^\d{1,9}[.)](?:[ \t]|$)/.test(line));
}

function normalizedWhitespace(text: string): string {
  return text.replace(/\s+/g, ' ');
}

function splitsSurrogatePair(text: string, offset: number): boolean {
  const before = text.charCodeAt(offset - 1);
  const after = text.charCodeAt(offset);
  return before >= 0xd800 && before <= 0xdbff && after >= 0xdc00 && after <= 0xdfff;
}

function uniqueContext(source: string, selector: ThreadCitationSelector): boolean {
  const text = normalizedWhitespace(selector.text);
  let match = source.indexOf(text);
  while (match !== -1) {
    if (match !== selector.start &&
      source.slice(Math.max(0, match - selector.prefix.length), match) === selector.prefix &&
      source.slice(match + text.length, match + text.length + selector.suffix.length) === selector.suffix) {
      return false;
    }
    match = source.indexOf(text, match + 1);
  }
  return true;
}

export function createThreadCitationSelector(source: string, rawStart?: number,
  rawEnd?: number): ThreadCitationSelector | undefined {
  if (rawStart === undefined || rawEnd === undefined || !Number.isSafeInteger(rawStart) ||
    !Number.isSafeInteger(rawEnd) || rawStart < 0 || rawEnd <= rawStart || rawEnd > source.length ||
    rawEnd - rawStart > CITATION_MAX_TEXT_LENGTH ||
    splitsSurrogatePair(source, rawStart) || splitsSurrogatePair(source, rawEnd)) return undefined;

  const text = source.slice(rawStart, rawEnd);
  if (!text.trim()) return undefined;
  const normalized = normalizedWhitespace(source);
  let start = normalizedWhitespace(source.slice(0, rawStart)).length;
  if (rawStart > 0 && /\s/.test(source[rawStart - 1]) && /\s/.test(source[rawStart])) start -= 1;
  const end = normalizedWhitespace(source.slice(0, rawEnd)).length;
  let prefixStart = Math.max(0, start - CITATION_CONTEXT_LENGTH);
  let suffixEnd = Math.min(normalized.length, end + CITATION_CONTEXT_LENGTH);
  if (splitsSurrogatePair(normalized, prefixStart)) prefixStart += 1;
  if (splitsSurrogatePair(normalized, suffixEnd)) suffixEnd -= 1;
  const selector: ThreadCitationSelector = {
    text, start, end, prefix: normalized.slice(prefixStart, start), suffix: normalized.slice(end, suffixEnd),
  };
  return uniqueContext(normalized, selector) ? selector : undefined;
}

function validId(value: string): boolean {
  return value.length <= CITATION_MAX_ID_LENGTH && value.length > 0 && value.trim() === value;
}

function validSelector(selector: ThreadCitationSelector): boolean {
  return selector.text.trim().length > 0 && selector.text.length <= CITATION_MAX_TEXT_LENGTH &&
    selector.prefix.length <= CITATION_CONTEXT_LENGTH && selector.suffix.length <= CITATION_CONTEXT_LENGTH &&
    Number.isSafeInteger(selector.start) && selector.start >= 0 && Number.isSafeInteger(selector.end) &&
    selector.end - selector.start === normalizedWhitespace(selector.text).length;
}

function encodePathPart(value: string): string {
  return encodeURIComponent(value).replace(/[!'()*]/g,
    (part: string): string => '%' + part.charCodeAt(0).toString(16).toUpperCase());
}

function encodeQueryPart(value: string): string {
  return encodeURIComponent(value).replace(/[!'()~]/g,
    (part: string): string => '%' + part.charCodeAt(0).toString(16).toUpperCase()).replace(/%20/g, '+');
}

export function serializeThreadCitation(environmentId: string, threadId: string, messageId: string,
  selector: ThreadCitationSelector): string | undefined {
  const ids = [environmentId, threadId, messageId];
  if (!ids.every(validId) || !validSelector(selector)) return undefined;
  try {
    const path = ids.map(encodePathPart).join('/');
    const query = 'text=' + encodeQueryPart(selector.text) + '&start=' + selector.start + '&end=' + selector.end +
      '&prefix=' + encodeQueryPart(selector.prefix) + '&suffix=' + encodeQueryPart(selector.suffix);
    return '[Assistant quote](' + CITATION_PREFIX + path + '?' + query + ')';
  } catch (_) {
    return undefined;
  }
}

export function readThreadCitation(href: string): NativeThreadCitation | undefined {
  if (!href.startsWith(CITATION_PREFIX) || href.length > CITATION_MAX_HREF_LENGTH || href.includes('#')) return undefined;
  const at = href.indexOf('?');
  if (at < 0) return undefined;
  try {
    const ids = href.slice(CITATION_PREFIX.length, at).split('/').map((part: string) => decodeURIComponent(part));
    if (ids.length !== 3 || !ids.every(validId)) return undefined;
    const values = new Map<string, string>();
    for (const field of href.slice(at + 1).split('&')) {
      const equals = field.indexOf('=');
      if (equals < 0) return undefined;
      const name = field.slice(0, equals);
      if (values.has(name)) return undefined;
      values.set(name, decodeURIComponent(field.slice(equals + 1).replace(/\+/g, ' ')));
    }
    const comment = values.get('comment');
    const text = values.get('text');
    const start = values.get('start');
    const end = values.get('end');
    const prefix = values.get('prefix');
    const suffix = values.get('suffix');
    if (values.size !== (comment === undefined ? 5 : 6) || text === undefined ||
      start === undefined || end === undefined || prefix === undefined || suffix === undefined ||
      !/^\d{1,16}$/.test(start) || !/^\d{1,16}$/.test(end) ||
      (comment !== undefined && comment.length > CITATION_MAX_TEXT_LENGTH)) return undefined;

    const from = Number(start);
    const to = Number(end);
    if (!Number.isSafeInteger(from) || !Number.isSafeInteger(to) || to <= from ||
      !text.trim() || text.length > CITATION_MAX_TEXT_LENGTH ||
      prefix.length > CITATION_CONTEXT_LENGTH || suffix.length > CITATION_CONTEXT_LENGTH) return undefined;

    const citation: NativeThreadCitation = {
      version: 1, environmentId: ids[0], threadId: ids[1], messageId: ids[2],
      text, start: from, end: to, prefix, suffix,
    };
    if (comment !== undefined) citation.comment = comment;
    return citation;
  } catch (_) {
    return undefined;
  }
}

export function threadCitationPreview(citation: NativeThreadCitation): string {
  const preview = normalizedWhitespace(citation.comment?.trim() || citation.text).trim();
  if (preview.length <= CITATION_PREVIEW_LENGTH) return preview;
  const length = splitsSurrogatePair(preview, CITATION_PREVIEW_LENGTH)
    ? CITATION_PREVIEW_LENGTH - 1 : CITATION_PREVIEW_LENGTH;
  return preview.slice(0, length) + '…';
}

export function readThreadCitationPreview(href: string): string | undefined {
  const citation = readThreadCitation(href);
  return citation === undefined ? undefined : threadCitationPreview(citation);
}
