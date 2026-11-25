import type { NativePullRequestRef } from './PullRequestProtocol';
import { REQUEST_ID } from './T3Protocol';

export type NativePullRequestReferenceSigil = '#' | '!';
export type NativePullRequestCompletionKind = 'mention' | 'reference';
type CompletionState = 'open' | 'closed' | 'merged';

export interface NativePullRequestCompletionSupport {
  mentions: boolean;
  referenceSigils: NativePullRequestReferenceSigil[];
}

interface CompletionSearch {
  kind: NativePullRequestCompletionKind;
  sigil: '@' | NativePullRequestReferenceSigil;
  query: string;
}

export interface NativePullRequestComposerTrigger extends CompletionSearch {
  rangeStart: number;
  rangeEnd: number;
}

export interface NativePullRequestCompletionInsertion {
  text: string;
  cursor: number;
}

interface CompletionAuthor {
  login: string;
  name: string | null;
}

interface CompletionReference {
  reference: string;
  number: number;
  title: string;
  state: CompletionState;
}

export interface NativePullRequestCompletionOptions {
  authors: CompletionAuthor[];
  references: CompletionReference[];
}

interface CompletionOptionsWire {
  authors: CompletionAuthor[];
  references?: CompletionReference[];
}

export interface NativePullRequestCompletion {
  token: string;
  title: string;
  subtitle: string;
  state?: CompletionState;
}

interface CompletionOptionsInput {
  kind: 'authors' | 'references';
  projectId: string;
  query?: string;
  sigil?: NativePullRequestReferenceSigil;
}

interface CompletionOptionsRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: CompletionOptionsInput;
  headers: string[][];
}

const TOKEN = /^(?:@([\p{L}\p{N}_][\p{L}\p{M}\p{N}_.-]*)?|([#!])([\p{L}\p{N}_-]*))$/u;
const COMPLETION_LIMIT = 6;

export function detectPullRequestComposerTrigger(text: string, cursor: number,
  support?: NativePullRequestCompletionSupport): NativePullRequestComposerTrigger | undefined {
  const end = Math.max(0, Math.min(text.length, cursor));
  if (end < text.length && !/\s/.test(text[end])) return undefined;
  let start = end;
  while (start > 0 && !/\s/.test(text[start - 1])) start--;
  const match = TOKEN.exec(text.slice(start, end));
  if (!match) return undefined;
  const sigil = match[2];
  if (sigil === '#' || sigil === '!') {
    if (!support?.referenceSigils.includes(sigil)) return undefined;
    return { kind: 'reference', sigil, query: match[3] ?? '', rangeStart: start, rangeEnd: end };
  }
  if (support?.mentions !== true) return undefined;
  return { kind: 'mention', sigil: '@', query: match[1] ?? '', rangeStart: start, rangeEnd: end };
}

export function insertPullRequestCompletion(text: string, trigger: NativePullRequestComposerTrigger,
  token: string): NativePullRequestCompletionInsertion {
  const suffix = text.slice(trigger.rangeEnd);
  const space = /^[ \t]/.test(suffix) ? '' : ' ';
  return { text: text.slice(0, trigger.rangeStart) + token + space + suffix,
    cursor: trigger.rangeStart + token.length + 1 };
}

export function pullRequestCompletionOptionsRequest(ref: NativePullRequestRef, trigger: CompletionSearch):
  CompletionOptionsRequest {
  const projectId = ref.projectId;
  if (!projectId.trim()) throw new Error('引用联想缺少当前项目。');
  const payload: CompletionOptionsInput = { kind: trigger.sigil === '@' ? 'authors' : 'references', projectId };
  if (trigger.sigil !== '@') payload.sigil = trigger.sigil;
  const query = trigger.query.slice(0, 100).trim();
  if (query) payload.query = query;
  return { _tag: 'Request', id: REQUEST_ID, tag: 'pullRequests.filterOptions', payload, headers: [] };
}

export function readPullRequestCompletionOptions(value: Object | undefined): NativePullRequestCompletionOptions {
  const wire = value as CompletionOptionsWire | undefined;
  if (!wire || !Array.isArray(wire.authors) ||
    (wire.references !== undefined && !Array.isArray(wire.references))) {
    throw new Error('环境返回的引用候选无效。');
  }
  const authors = wire.authors.filter((author: CompletionAuthor) =>
    typeof author?.login === 'string' && /^\S+$/.test(author.login) &&
    (author.name === null || typeof author.name === 'string'));
  const references = (wire.references ?? []).filter((item: CompletionReference) =>
    typeof item?.reference === 'string' && /^\S+$/.test(item.reference) &&
    Number.isSafeInteger(item.number) && item.number > 0 && typeof item.title === 'string' &&
    (item.state === 'open' || item.state === 'closed' || item.state === 'merged'));
  return { authors, references };
}

export function pullRequestCompletions(trigger: CompletionSearch | undefined,
  options: NativePullRequestCompletionOptions | undefined): NativePullRequestCompletion[] {
  if (!trigger || !options) return [];
  const query = trigger.query.toLowerCase();
  if (trigger.kind === 'mention') {
    return options.authors.filter((author: CompletionAuthor) =>
      author.login.toLowerCase().includes(query) || !!author.name?.toLowerCase().includes(query))
      .slice(0, COMPLETION_LIMIT).map((author: CompletionAuthor): NativePullRequestCompletion => ({
        token: '@' + author.login, title: author.login, subtitle: author.name === author.login ? '' : author.name ?? '',
      }));
  }
  return options.references.filter((item: CompletionReference) =>
    item.reference.startsWith(trigger.sigil) &&
    (String(item.number).startsWith(query) || item.title.toLowerCase().includes(query)))
    .slice(0, COMPLETION_LIMIT).map((item: CompletionReference): NativePullRequestCompletion => ({
      token: item.reference, title: item.reference, subtitle: item.title, state: item.state,
    }));
}
