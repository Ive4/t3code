import { scopedRef } from './PullRequestProtocol';
import type { NativePullRequestRef } from './PullRequestProtocol';
import { REQUEST_ID } from './T3Protocol';

export type NativePullRequestMetadataKind = 'labels' | 'reviewers';

type ReviewerKind = 'user' | 'team';

export interface NativePullRequestMetadataCandidate {
  key: string;
  title: string;
  subtitle: string;
  selected: boolean;
  color?: string;
  kind?: ReviewerKind;
}

export interface NativePullRequestMetadataPage {
  candidates: NativePullRequestMetadataCandidate[];
  truncated: boolean;
}

interface PullRequestMetadataInput extends NativePullRequestRef {
  query?: string;
}

interface PullRequestMetadataRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: PullRequestMetadataInput;
  headers: string[][];
}

interface PullRequestCandidateList {
  candidates: Object[];
  truncated: boolean;
}

interface PullRequestLabelCandidate {
  name: string;
  color: string | null;
  description: string | null;
  isApplied: boolean;
}

interface PullRequestReviewerCandidate {
  id: string;
  login: string;
  name: string | null;
  kind: ReviewerKind;
  isRequested: boolean;
}

export function pullRequestMetadataRequest(ref: NativePullRequestRef, kind: NativePullRequestMetadataKind,
  query?: string): PullRequestMetadataRequest {
  const scope = scopedRef(ref);
  const payload: PullRequestMetadataInput = {
    projectId: scope.projectId, host: scope.host, repository: scope.repository, number: scope.number,
  };
  const search = kind === 'reviewers' ? query?.trim().slice(0, 100).trimEnd() : undefined;
  if (search) payload.query = search;
  return {
    _tag: 'Request', id: REQUEST_ID,
    tag: kind === 'labels' ? 'pullRequests.labelCandidates' : 'pullRequests.reviewerCandidates',
    payload, headers: [],
  };
}

function malformedCandidates(): Error {
  return new Error('环境返回的拉取请求候选无效。');
}

function readLabel(value: Object): NativePullRequestMetadataCandidate {
  const label = value as PullRequestLabelCandidate;
  if (!label || typeof label.name !== 'string' || !label.name.trim() || typeof label.isApplied !== 'boolean' ||
    (label.color !== null && typeof label.color !== 'string') ||
    (label.description !== null && typeof label.description !== 'string')) {
    throw malformedCandidates();
  }
  const candidate: NativePullRequestMetadataCandidate = {
    key: label.name, title: label.name, subtitle: label.description ?? '', selected: label.isApplied,
  };
  const hex = label.color?.replace(/^#/, '');
  if (hex && /^[\da-f]{6}$/i.test(hex)) candidate.color = '#' + hex;
  return candidate;
}

function readReviewer(value: Object): NativePullRequestMetadataCandidate {
  const reviewer = value as PullRequestReviewerCandidate;
  if (!reviewer || typeof reviewer.id !== 'string' || !reviewer.id.trim() ||
    typeof reviewer.login !== 'string' || !reviewer.login.trim() || typeof reviewer.isRequested !== 'boolean' ||
    (reviewer.name !== null && typeof reviewer.name !== 'string') ||
    (reviewer.kind !== 'user' && reviewer.kind !== 'team')) {
    throw malformedCandidates();
  }
  return {
    key: reviewer.kind + ':' + reviewer.id, title: reviewer.name || reviewer.login, subtitle: reviewer.login,
    selected: reviewer.isRequested, kind: reviewer.kind,
  };
}

export function readPullRequestMetadata(value: Object | undefined,
  kind: NativePullRequestMetadataKind): NativePullRequestMetadataPage {
  const page = value as PullRequestCandidateList | undefined;
  if (!page || !Array.isArray(page.candidates) || typeof page.truncated !== 'boolean') throw malformedCandidates();
  return {
    candidates: page.candidates.map(kind === 'labels' ? readLabel : readReviewer),
    truncated: page.truncated,
  };
}
