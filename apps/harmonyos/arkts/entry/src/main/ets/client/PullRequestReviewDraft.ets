export type NativePullRequestReviewVerdict = 'comment' | 'approve' | 'request-changes';
export type NativePullRequestReviewMode = 'review' | 'comment' | 'inline';
export type NativePullRequestDiffSide = 'LEFT' | 'RIGHT';

export interface NativePullRequestInlineTarget {
  path: string;
  side: NativePullRequestDiffSide;
  line: number;
  headSha: string;
  oldPath?: string;
  code?: string;
  draftId?: string;
}

export interface NativePullRequestLineDraft extends NativePullRequestInlineTarget {
  id: string;
  body: string;
}

export interface NativePullRequestReviewDraft {
  summary: string;
  comment: string;
  comments: NativePullRequestLineDraft[];
}

export interface NativePullRequestReviewDraftDocument {
  version: number;
  drafts: Record<string, NativePullRequestReviewDraft>;
}

interface ReviewDraftRef {
  projectId: string;
  host: string;
  repository: string;
  number: number;
}

type ReviewDraftProblem = '' | 'unavailable' | 'stale' | 'inline-unavailable' | 'summary-required' | 'empty';

export function pullRequestReviewDraftKey(owner: string, environmentId: string, ref: ReviewDraftRef): string {
  return JSON.stringify([owner, environmentId, ref.projectId, ref.host, ref.repository, ref.number]);
}

export function emptyPullRequestReviewDraft(): NativePullRequestReviewDraft {
  return { summary: '', comment: '', comments: [] };
}

function isLineDraft(draft: NativePullRequestLineDraft): boolean {
  return !!draft && typeof draft.id === 'string' && draft.id.length > 0 &&
    typeof draft.body === 'string' && typeof draft.path === 'string' && draft.path.length > 0 &&
    Number.isSafeInteger(draft.line) && draft.line > 0 && typeof draft.headSha === 'string' &&
    draft.headSha.length > 0 && (draft.side === 'LEFT' || draft.side === 'RIGHT') &&
    (draft.code === undefined || typeof draft.code === 'string') &&
    (draft.oldPath === undefined || typeof draft.oldPath === 'string');
}

export function readPullRequestReviewDrafts(raw: string): Record<string, NativePullRequestReviewDraft> {
  if (!raw) return {};
  const document = JSON.parse(raw) as NativePullRequestReviewDraftDocument;
  if (!document || document.version !== 1 || !document.drafts ||
    typeof document.drafts !== 'object' || Array.isArray(document.drafts)) {
    throw new Error('拉取请求草稿格式无效。');
  }
  const drafts = document.drafts;
  for (const key of Object.keys(drafts)) {
    const draft = drafts[key];
    if (!draft || typeof draft.summary !== 'string' || typeof draft.comment !== 'string' ||
      !Array.isArray(draft.comments) || !draft.comments.every(isLineDraft)) {
      throw new Error('拉取请求草稿格式无效。');
    }
  }
  return drafts;
}

export function withPullRequestLineDraft(draft: NativePullRequestReviewDraft, target: NativePullRequestInlineTarget,
  body: string, id: string): NativePullRequestReviewDraft {
  const comment: NativePullRequestLineDraft = {
    id, path: target.path, side: target.side, line: target.line, headSha: target.headSha,
    oldPath: target.oldPath, code: target.code, body,
  };
  return { summary: draft.summary, comment: draft.comment,
    comments: draft.comments.filter((entry: NativePullRequestLineDraft) => entry.id !== id).concat(comment) };
}

export function pullRequestReviewDraftProblem(draft: NativePullRequestReviewDraft, headSha: string,
  verdict: NativePullRequestReviewVerdict | undefined, canInlineComment: boolean,
  requiresChangeSummary: boolean): ReviewDraftProblem {
  if (draft.comments.some((comment: NativePullRequestLineDraft) => comment.headSha !== headSha)) return 'stale';
  if (draft.comments.length > 0 && !canInlineComment) return 'inline-unavailable';
  if (!verdict) return 'unavailable';
  if (draft.summary.trim()) return '';
  if (verdict === 'request-changes' && requiresChangeSummary) return 'summary-required';
  return verdict === 'approve' || draft.comments.length > 0 ? '' : 'empty';
}
