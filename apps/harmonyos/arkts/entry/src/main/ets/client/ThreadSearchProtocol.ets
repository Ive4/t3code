import { REQUEST_ID } from './T3Protocol';

const MAX_QUERY_LENGTH = 200;
const MAX_MATCHES = 50;
const MAX_SNIPPET_LENGTH = 240;
const WRAPPING_QUOTES = /^\s*["'`“”‘’]+|["'`“”‘’]+\s*$/g;
const CJK = /[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uac00-\ud7af]/;

interface ThreadSearchPayload {
  query: string;
  limit: number;
}

interface ThreadSearchRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: ThreadSearchPayload;
  headers: string[][];
}

interface ThreadSearchRecord {
  threadId: string;
  projectId: string;
  source: 'user' | 'assistant';
  snippet: string;
  messageCreatedAt: string | null;
  messageId?: string;
  quality?: number;
  hits?: number;
}

interface ThreadSearchResult {
  matches: ThreadSearchRecord[];
}

export interface NativeThreadSearchMatch extends ThreadSearchRecord {
  environmentId: string;
}

export function normalizeThreadSearchQuery(query: string): string {
  return query.trim().slice(0, MAX_QUERY_LENGTH).trim();
}

export function canSearchThreadMessages(query: string): boolean {
  const tokens = normalizeThreadSearchQuery(query).replace(WRAPPING_QUOTES, '')
    .replace(/[\u2018\u2019]/g, "'").normalize('NFC').toLowerCase().split(/\s+/);
  return tokens.some((token: string) => {
    const length = Array.from(token).length;
    return length >= 3 || (length === 2 && CJK.test(token));
  });
}

export function searchThreadsRequest(query: string): ThreadSearchRequest {
  const normalized = normalizeThreadSearchQuery(query);
  if (!canSearchThreadMessages(normalized)) throw new Error('请输入更完整的消息搜索词。');
  return {
    _tag: 'Request', id: REQUEST_ID, tag: 'orchestration.searchThreads',
    payload: { query: normalized, limit: MAX_MATCHES }, headers: [],
  };
}

function validIdentifier(value: string): boolean {
  return typeof value === 'string' && value.length > 0 && value.trim() === value;
}

export function readThreadSearchMatches(value: Object, environmentId: string): NativeThreadSearchMatch[] {
  const result = value as ThreadSearchResult;
  if (!validIdentifier(environmentId) || !result || !Array.isArray(result.matches) || result.matches.length > MAX_MATCHES) {
    throw new Error('环境返回的消息搜索结果无效。');
  }
  const matches: NativeThreadSearchMatch[] = [];
  const threadIds = new Set<string>();
  for (const match of result.matches) {
    if (!match || !validIdentifier(match.threadId) || !validIdentifier(match.projectId) || threadIds.has(match.threadId) ||
      (match.source !== 'user' && match.source !== 'assistant') ||
      typeof match.snippet !== 'string' || match.snippet.length > MAX_SNIPPET_LENGTH ||
      (match.messageCreatedAt !== null && typeof match.messageCreatedAt !== 'string') ||
      (match.messageId !== undefined && !validIdentifier(match.messageId)) ||
      (match.quality !== undefined && !Number.isFinite(match.quality)) ||
      (match.hits !== undefined && !Number.isInteger(match.hits))) {
      throw new Error('环境返回了无效的消息匹配项。');
    }
    threadIds.add(match.threadId);
    const scoped: NativeThreadSearchMatch = {
      environmentId, threadId: match.threadId, projectId: match.projectId, source: match.source,
      snippet: match.snippet, messageCreatedAt: match.messageCreatedAt,
    };
    if (match.messageId !== undefined) scoped.messageId = match.messageId;
    if (match.quality !== undefined) scoped.quality = match.quality;
    if (match.hits !== undefined) scoped.hits = match.hits;
    matches.push(scoped);
  }
  return matches;
}
