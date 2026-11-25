import { REQUEST_ID } from './T3Protocol';
import { readGitDiffFile } from './ThreadReviewProtocol';
import type { NativePullRequestReviewVerdict } from './PullRequestReviewDraft';
import type { NativePullRequestCompletionSupport, NativePullRequestReferenceSigil } from './PullRequestReferenceProtocol';

export type NativePullRequestState = 'open' | 'merged' | 'closed';
export type NativePullRequestInvolvement = 'all' | 'reviewing' | 'authored';
export type NativePullRequestSort = 'updated' | 'created' | 'oldest';
export type NativePullRequestDraftFilter = 'only' | 'hide';
export type NativePullRequestReviewDecision = 'approved' | 'changes-requested' | 'review-required';
export type NativePullRequestReviewFilter = NativePullRequestReviewDecision | 'none';
export type NativePullRequestChecksFilter = 'passing' | 'failing';
export type NativePullRequestChecksState = NativePullRequestChecksFilter | 'pending';

export interface NativePullRequestFilters {
  draft?: NativePullRequestDraftFilter;
  review?: NativePullRequestReviewFilter;
  checks?: NativePullRequestChecksFilter;
  author?: string;
  labels?: string[][];
  excludedLabels?: string[];
}

export interface NativePullRequestListControls {
  state: NativePullRequestState | 'all';
  involvement: NativePullRequestInvolvement;
  sort?: NativePullRequestSort;
  filters?: NativePullRequestFilters;
  projectId?: string;
}

export interface NativePullRequestQuery extends NativePullRequestListControls {
  query?: string;
  limit?: number;
  cursors?: Record<string, string>;
}

export interface NativePullRequestViewScope extends NativePullRequestListControls {
  query: string;
}

export interface NativePullRequestSavedView extends NativePullRequestViewScope {
  id: string;
  name: string;
}

export interface NativePullRequestPreferences extends NativePullRequestListControls {
  key: string;
  views: NativePullRequestSavedView[];
}

export interface NativePullRequestRef {
  projectId: string;
  host: string;
  repository: string;
  number: number;
}

export interface NativePullRequestRow extends NativePullRequestRef {
  projectTitle: string;
  title: string;
  url: string;
  state: NativePullRequestState;
  isDraft: boolean;
  headBranch: string;
  baseBranch: string;
  updatedAt: string;
  createdAt?: string;
  reviewDecision?: NativePullRequestReviewDecision;
  checksState?: NativePullRequestChecksState;
  author: string;
  authorLogin?: string;
  viewerLogin?: string;
  labels: string[];
}

export interface NativePullRequestPage {
  rows: NativePullRequestRow[];
  messages: string[];
  nextCursors: Record<string, string>;
  truncated: boolean;
}

export interface NativePullRequestDetail extends NativePullRequestRow {
  body: string;
  changedFiles: number | null;
  reviewers: string[];
  diffAvailable: boolean;
  headSha: string;
  actions: NativePullRequestActions;
  completion: NativePullRequestCompletionSupport;
}

interface PullRequestCommentIdentity {
  authorLogin: string;
  kind: string;
  canEdit?: boolean;
}

export interface NativePullRequestActions {
  viewerLogin: string;
  editChangeRequest: boolean;
  editComments: boolean;
  comment: boolean;
  inlineComment: boolean;
  verdicts: NativePullRequestReviewVerdict[];
  requiresChangeSummary: boolean;
  editLabels: boolean;
  requestReviewers: boolean;
  listReviewers: boolean;
  searchReviewers: boolean;
}

export interface NativePullRequestComment extends PullRequestCommentIdentity {
  key: string;
  author: string;
  body: string;
  createdAt: string;
  location: string;
}

export interface NativePullRequestDiffLine {
  side: 'LEFT' | 'RIGHT';
  line: number;
  code: string;
}

export interface NativePullRequestDiscussion {
  comments: NativePullRequestComment[];
  truncated: boolean;
}

export interface NativePullRequestFile {
  path: string;
  previousPath: string | null;
  additions: number | null;
  deletions: number | null;
  patch: string;
  withheld: boolean;
}

export interface NativePullRequestFileGroup {
  directory: string;
  files: NativePullRequestFile[];
}

export interface NativePullRequestDiff {
  files: NativePullRequestFile[];
  truncated: boolean;
  nextCursor?: string;
  withheldFilesReadable?: boolean;
}

interface NativePullRequestListRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: NativePullRequestQuery;
  headers: string[][];
}

interface NativePullRequestRefRequest<Input> {
  _tag: string;
  id: string;
  tag: string;
  payload: Input;
  headers: string[][];
}

interface NativePullRequestDetailInput extends NativePullRequestRef {
  allowStale?: boolean;
}

interface NativePullRequestDiffInput extends NativePullRequestRef {
  cursor?: string;
  path?: string;
}

interface PullRequestActor {
  login: string;
  name: string | null;
}

interface PullRequestLabel {
  name: string;
}

interface PullRequestEntry {
  projectId: string;
  host?: string;
  repository: string;
  number: number;
  projectTitle: string;
  title: string;
  url: string;
  state: NativePullRequestState;
  isDraft: boolean;
  headBranch: string;
  baseBranch: string;
  updatedAt: string;
  createdAt?: string;
  reviewDecision?: NativePullRequestReviewDecision;
  checksState?: NativePullRequestChecksState;
  author: PullRequestActor | null;
  labels: PullRequestLabel[];
}

interface PullRequestProvider {
  host: string;
  configured: boolean;
  detail: string | null;
}

interface PullRequestListError {
  projectTitle: string;
  message: string;
}

interface PullRequestListResult {
  entries: PullRequestEntry[];
  providers: PullRequestProvider[];
  errors: PullRequestListError[];
  truncated: boolean;
  nextCursors: Record<string, string>;
  viewers?: Record<string, string>;
}

interface PullRequestCapabilities {
  diff: boolean;
  comment?: boolean;
  edit?: PullRequestEditCapabilities;
  review?: PullRequestReviewCapabilities;
  labels?: boolean;
  reviewers?: PullRequestReviewerCapabilities;
  mentions?: boolean;
  referenceSigils?: NativePullRequestReferenceSigil[];
}

interface PullRequestEditCapabilities {
  changeRequest?: boolean;
  comment?: boolean;
}

interface PullRequestReviewCapabilities {
  inlineComment?: boolean;
  verdicts?: string[];
}

interface PullRequestReviewerCapabilities {
  request?: boolean;
  listCandidates?: boolean;
  searchCandidates?: boolean;
}

interface PullRequestViewerPermissions {
  comment?: boolean;
  actions?: string[];
  verdicts?: string[];
  editChangeRequest?: boolean;
  labels?: boolean;
  requestReviewers?: boolean;
}

interface PullRequestDetailResult extends PullRequestEntry {
  body: string;
  changedFiles: number | null;
  reviewers: PullRequestActor[];
  capabilities?: PullRequestCapabilities;
  viewer?: string | null;
  viewerPermissions?: PullRequestViewerPermissions;
  headSha?: string;
  provider?: string;
}

interface PullRequestComment {
  id: string;
  author: PullRequestActor | null;
  body: string;
  createdAt: string;
  kind?: string;
  canEdit?: boolean;
}

interface PullRequestThread {
  id: string;
  path: string | null;
  line: number | null;
  comments: PullRequestComment[];
}

interface PullRequestActivityResult {
  comments: PullRequestComment[];
  commentsTruncated: boolean;
  reviewThreads: PullRequestThread[];
  reviewThreadsTruncated?: boolean;
  overviewThreads?: PullRequestThread[];
}

interface PullRequestDiffResult {
  patch: string;
  truncated: boolean;
  nextCursor: string | null;
  omittedFileStats?: PullRequestOmittedFileStat[];
  withheldFilesReadable?: boolean;
}

interface PullRequestOmittedFileStat {
  path: string;
  additions: number;
  deletions: number;
}

const PAGE_SIZE = 30;
const MAX_LIST_LIMIT = 500;
const SAVED_VIEW_NAME_LIMIT = 80;

function isListState(value: string): boolean {
  return value === 'open' || value === 'closed' || value === 'merged' || value === 'all';
}

function isInvolvement(value: string): boolean {
  return value === 'all' || value === 'reviewing' || value === 'authored';
}

function isSort(value: NativePullRequestSort | undefined): boolean {
  return value === 'updated' || value === 'created' || value === 'oldest';
}

function isReviewDecision(value: NativePullRequestReviewFilter | undefined): boolean {
  return value === 'approved' || value === 'changes-requested' || value === 'review-required';
}

function trimmedValue(value?: string): string | undefined {
  return typeof value === 'string' ? value.trim() || undefined : undefined;
}

function qualifier(value?: string): string | undefined {
  const text = trimmedValue(value);
  return text && text.length <= 200 ? text : undefined;
}

function qualifierValues(values?: string[]): string[] {
  if (!Array.isArray(values)) return [];
  const result: string[] = [];
  for (const value of values) {
    const text = qualifier(value);
    if (!text) continue;
    result.push(text);
    if (result.length === 10) break;
  }
  return result;
}

function normalizeFilters(filters: NativePullRequestFilters | undefined): NativePullRequestFilters | undefined {
  const result: NativePullRequestFilters = {};
  if (filters?.draft === 'only' || filters?.draft === 'hide') result.draft = filters.draft;
  if (filters && (filters.review === 'none' || isReviewDecision(filters.review))) result.review = filters.review;
  if (filters?.checks === 'passing' || filters?.checks === 'failing') result.checks = filters.checks;
  const author = qualifier(filters?.author);
  if (author) result.author = author;
  const groups = filters?.labels;
  if (groups && Array.isArray(groups)) {
    const labels = groups.map((group: string[]) => qualifierValues(group))
      .filter((group: string[]) => group.length > 0).slice(0, 10);
    if (labels.length) result.labels = labels;
  }
  const excludedLabels = qualifierValues(filters?.excludedLabels);
  if (excludedLabels.length) result.excludedLabels = excludedLabels;
  return Object.keys(result).length > 0 ? result : undefined;
}

function isSavedView(view: NativePullRequestSavedView): boolean {
  return !!view && typeof view.id === 'string' && view.id.length > 0 && typeof view.name === 'string' &&
    view.name.trim().length > 0 && view.name.length <= SAVED_VIEW_NAME_LIMIT && typeof view.query === 'string' &&
    isListState(view.state) && isInvolvement(view.involvement);
}

function normalizeSavedView(view: NativePullRequestSavedView): NativePullRequestSavedView {
  const result: NativePullRequestSavedView = {
    id: view.id, name: view.name, query: view.query, state: view.state, involvement: view.involvement,
  };
  if (isSort(view.sort)) result.sort = view.sort;
  const project = trimmedValue(view.projectId);
  if (project) result.projectId = project;
  const filters = normalizeFilters(view.filters);
  if (filters) result.filters = filters;
  return result;
}

export function pullRequestPreferencesKey(owner: string, environment: string): string {
  return JSON.stringify([owner, environment]);
}

export function readPullRequestPreferences(raw: string, key: string): NativePullRequestPreferences {
  const defaults: NativePullRequestPreferences = { key, state: 'open', involvement: 'all', views: [] };
  if (!raw) return defaults;
  try {
    const saved = JSON.parse(raw) as NativePullRequestPreferences;
    if (saved?.key === key) {
      if (isListState(saved.state)) defaults.state = saved.state;
      if (isInvolvement(saved.involvement)) defaults.involvement = saved.involvement;
      if (isSort(saved.sort)) defaults.sort = saved.sort;
      const project = trimmedValue(saved.projectId);
      if (project) defaults.projectId = project;
      const filters = normalizeFilters(saved.filters);
      if (filters) defaults.filters = filters;
      if (Array.isArray(saved.views)) defaults.views = saved.views.filter(isSavedView).map(normalizeSavedView);
    }
  } catch (_) {}
  return defaults;
}

export function pullRequestViewMatches(view: NativePullRequestViewScope, scope: NativePullRequestViewScope): boolean {
  return view.state === scope.state && view.involvement === scope.involvement &&
    (view.sort ?? 'updated') === (scope.sort ?? 'updated') && view.query.trim() === scope.query.trim() &&
    trimmedValue(view.projectId) === trimmedValue(scope.projectId) && view.filters?.author === scope.filters?.author &&
    view.filters?.draft === scope.filters?.draft && view.filters?.review === scope.filters?.review &&
    view.filters?.checks === scope.filters?.checks &&
    labelGroupsKey(view.filters?.labels) === labelGroupsKey(scope.filters?.labels) &&
    JSON.stringify(view.filters?.excludedLabels?.slice().sort() ?? []) ===
      JSON.stringify(scope.filters?.excludedLabels?.slice().sort() ?? []);
}

function labelGroupsKey(groups?: string[][]): string {
  return JSON.stringify(groups?.map((group: string[]) => JSON.stringify(group.slice().sort())).sort() ?? []);
}

export function savePullRequestView(views: NativePullRequestSavedView[], id: string, rawName: string,
  scope: NativePullRequestViewScope): NativePullRequestSavedView[] {
  const name = rawName.trim();
  if (!name) throw new Error('请输入视图名称。');
  if (name.length > SAVED_VIEW_NAME_LIMIT) throw new Error(`视图名称最多 ${SAVED_VIEW_NAME_LIMIT} 个字符。`);
  if (views.some((view: NativePullRequestSavedView) => view.id !== id && view.name.toLowerCase() === name.toLowerCase())) {
    throw new Error('已存在同名视图。');
  }
  const saved: NativePullRequestSavedView = { id, name, state: scope.state, involvement: scope.involvement,
    query: scope.query.trim() };
  if (isSort(scope.sort)) saved.sort = scope.sort;
  const project = trimmedValue(scope.projectId);
  if (project) saved.projectId = project;
  const filters = normalizeFilters(scope.filters);
  if (filters) saved.filters = filters;
  return views.some((view: NativePullRequestSavedView) => view.id === id)
    ? views.map((view: NativePullRequestSavedView) => view.id === id ? saved : view)
    : views.concat(saved);
}

export function pullRequestListRequest(input: NativePullRequestQuery): NativePullRequestListRequest {
  const payload: NativePullRequestQuery = {
    state: input.state,
    involvement: input.involvement,
    limit: input.limit ?? PAGE_SIZE
  };
  const query = input.query?.trim().slice(0, 200);
  if (query) payload.query = query;
  const project = trimmedValue(input.projectId);
  if (project) payload.projectId = project;
  const filters = normalizeFilters(input.filters);
  if (filters) payload.filters = filters;
  if (input.cursors && Object.keys(input.cursors).length > 0) payload.cursors = input.cursors;
  return { _tag: 'Request', id: REQUEST_ID, tag: 'pullRequests.list', payload, headers: [] };
}

export function scopedRef(input: NativePullRequestRef): NativePullRequestRef {
  if (!input.projectId || !input.host || !input.repository || !Number.isSafeInteger(input.number) || input.number < 1) {
    throw new Error('拉取请求缺少有效的项目信息。');
  }
  return { projectId: input.projectId, host: input.host, repository: input.repository, number: input.number };
}

export function pullRequestDetailRequest(ref: NativePullRequestRef, allowStale?: boolean):
  NativePullRequestRefRequest<NativePullRequestDetailInput> {
  const scope = scopedRef(ref);
  const payload: NativePullRequestDetailInput = {
    projectId: scope.projectId, host: scope.host, repository: scope.repository, number: scope.number,
  };
  if (allowStale !== undefined) payload.allowStale = allowStale;
  return { _tag: 'Request', id: REQUEST_ID, tag: 'pullRequests.detail', payload, headers: [] };
}

export function pullRequestActivityRequest(ref: NativePullRequestRef): NativePullRequestRefRequest<NativePullRequestRef> {
  return { _tag: 'Request', id: REQUEST_ID, tag: 'pullRequests.activity', payload: scopedRef(ref), headers: [] };
}

export function pullRequestDiffBody(ref: NativePullRequestRef, cursor?: string, path?: string): string {
  const source = scopedRef(ref);
  if (path !== undefined && (path.trim() !== path || path.includes('\0') ||
    path.split('/').some((part: string) => part === '' || part === '.' || part === '..'))) {
    throw new Error('拉取请求文件路径无效。');
  }
  const input: NativePullRequestDiffInput = {
    projectId: source.projectId, host: source.host, repository: source.repository, number: source.number,
    cursor: path === undefined ? cursor : undefined, path,
  };
  return JSON.stringify(input);
}

function authorLabel(actor: PullRequestActor | null): string {
  return actor?.name || actor?.login || '';
}

function readEntry(entry: PullRequestEntry, host: string, viewer?: string): NativePullRequestRow {
  if (!entry.projectId || !host || !entry.repository || !Number.isSafeInteger(entry.number) || entry.number < 1 ||
    typeof entry.title !== 'string' || typeof entry.projectTitle !== 'string' || typeof entry.updatedAt !== 'string' ||
    (entry.state !== 'open' && entry.state !== 'closed' && entry.state !== 'merged')) {
    throw new Error('拉取请求列表返回了无效记录。');
  }
  return {
    projectId: entry.projectId, projectTitle: entry.projectTitle, host, repository: entry.repository,
    number: entry.number, title: entry.title, url: entry.url, state: entry.state, isDraft: entry.isDraft === true,
    headBranch: entry.headBranch, baseBranch: entry.baseBranch, updatedAt: entry.updatedAt,
    createdAt: typeof entry.createdAt === 'string' ? entry.createdAt : undefined,
    reviewDecision: isReviewDecision(entry.reviewDecision) ? entry.reviewDecision : undefined,
    checksState: entry.checksState === 'passing' || entry.checksState === 'failing' || entry.checksState === 'pending'
      ? entry.checksState : undefined,
    author: authorLabel(entry.author), authorLogin: trimmedValue(entry.author?.login), viewerLogin: trimmedValue(viewer),
    labels: (entry.labels ?? []).map((label: PullRequestLabel) => label.name)
  };
}

export function pullRequestRowKey(row: NativePullRequestRef): string {
  return JSON.stringify([row.projectId, row.host, row.repository, row.number]);
}

function pullRequestSortTime(row: NativePullRequestRow, sort: NativePullRequestSort): number {
  if (sort === 'created' && row.createdAt) {
    const created = Date.parse(row.createdAt);
    if (Number.isFinite(created)) return created;
  }
  return Date.parse(row.updatedAt) || 0;
}

export function sortPullRequestRows(rows: NativePullRequestRow[], sort: NativePullRequestSort): NativePullRequestRow[] {
  const direction = sort === 'oldest' ? 1 : -1;
  return rows.slice().sort((left: NativePullRequestRow, right: NativePullRequestRow) =>
    direction * (pullRequestSortTime(left, sort) - pullRequestSortTime(right, sort)));
}

export function mergePullRequestRows(existing: NativePullRequestRow[], next: NativePullRequestRow[]): NativePullRequestRow[] {
  const rows = new Map<string, NativePullRequestRow>();
  existing.concat(next).forEach((row: NativePullRequestRow) => {
    const key = pullRequestRowKey(row);
    const previous = rows.get(key);
    if (!previous || Date.parse(previous.updatedAt) <= Date.parse(row.updatedAt)) rows.set(key, row);
  });
  return Array.from(rows.values()).sort((left: NativePullRequestRow, right: NativePullRequestRow) =>
    Date.parse(right.updatedAt) - Date.parse(left.updatedAt));
}

export function filterPullRequestRows(rows: NativePullRequestRow[], filters?: NativePullRequestFilters,
  projectId?: string): NativePullRequestRow[] {
  const author = filters?.author?.trim().toLowerCase();
  const useViewer = !!author && /^@?me$/.test(author);
  const included = filters?.labels?.map((group: string[]) => group.map((label: string) => label.toLowerCase())) ?? [];
  const excluded = filters?.excludedLabels?.map((label: string) => label.toLowerCase()) ?? [];
  if (!projectId && !author && !included.length && !excluded.length &&
    !filters?.draft && !filters?.review && !filters?.checks) return rows;
  return rows.filter((row: NativePullRequestRow) => {
    if (projectId && row.projectId !== projectId) return false;
    if ((filters?.draft === 'only' && !row.isDraft) || (filters?.draft === 'hide' && row.isDraft)) return false;
    if (filters?.review && row.reviewDecision && filters.review !== row.reviewDecision) return false;
    if (filters?.checks && row.checksState && filters.checks !== row.checksState) return false;
    const login = useViewer ? (row.viewerLogin?.toLowerCase() ?? author) : author;
    if (login && row.authorLogin?.toLowerCase() !== login) return false;
    if (!included.length && !excluded.length) return true;
    const labels = new Set<string>(row.labels.map((label: string) => label.toLowerCase()));
    return included.every((group: string[]) => group.some((label: string) => labels.has(label))) &&
      !excluded.some((label: string) => labels.has(label));
  });
}

export function readPullRequestPage(value: Object): NativePullRequestPage {
  const result = value as PullRequestListResult;
  if (!result || !Array.isArray(result.entries) || !Array.isArray(result.errors) || !Array.isArray(result.providers)) {
    throw new Error('拉取请求列表响应格式无效。');
  }
  const messages = result.errors.map((item: PullRequestListError) => `${item.projectTitle}：${item.message}`);
  result.providers.forEach((provider: PullRequestProvider) => {
    if (!provider.configured && provider.detail) messages.push(`${provider.host}：${provider.detail}`);
  });
  return {
    rows: mergePullRequestRows([], result.entries.map((entry: PullRequestEntry) => {
      const host = entry.host ?? '';
      return readEntry(entry, host, result.viewers?.[host]);
    })),
    messages, truncated: result.truncated === true, nextCursors: result.nextCursors ?? {}
  };
}

export function nextPullRequestQuery(input: NativePullRequestQuery, page: NativePullRequestPage): NativePullRequestQuery | undefined {
  const cursorKeys = Object.keys(page.nextCursors);
  const hasCursors = cursorKeys.length > 0;
  if (input.cursors && cursorKeys.length === Object.keys(input.cursors).length &&
    cursorKeys.every((key: string) => page.nextCursors[key] === input.cursors?.[key])) return undefined;
  const limit = input.limit ?? PAGE_SIZE;
  if (!hasCursors && (!page.truncated || limit >= MAX_LIST_LIMIT)) return undefined;
  const next: NativePullRequestQuery = {
    state: input.state, involvement: input.involvement,
    limit: hasCursors ? PAGE_SIZE : Math.min(limit + PAGE_SIZE, MAX_LIST_LIMIT)
  };
  if (input.query) next.query = input.query;
  const project = trimmedValue(input.projectId);
  if (project) next.projectId = project;
  if (input.sort) next.sort = input.sort;
  const filters = normalizeFilters(input.filters);
  if (filters) next.filters = filters;
  if (hasCursors) next.cursors = page.nextCursors;
  return next;
}

export function readPullRequestDetail(value: Object, ref: NativePullRequestRef): NativePullRequestDetail {
  const result = value as PullRequestDetailResult;
  if (!result || result.projectId !== ref.projectId || result.repository !== ref.repository || result.number !== ref.number ||
    (result.host !== undefined && result.host !== ref.host)) {
    throw new Error('拉取请求详情与请求的项目不匹配。');
  }
  if (typeof result.body !== 'string') throw new Error('拉取请求详情响应格式无效。');
  const row = readEntry(result, ref.host, result.viewer ?? undefined);
  const referenceSigils: NativePullRequestReferenceSigil[] = [];
  const sigils = result.capabilities?.referenceSigils;
  if (sigils && Array.isArray(sigils)) {
    for (const sigil of sigils) {
      if (sigil === '#' || sigil === '!') referenceSigils.push(sigil);
    }
  }
  return {
    projectId: row.projectId, projectTitle: row.projectTitle, host: row.host, repository: row.repository,
    number: row.number, title: row.title, url: row.url, state: row.state, isDraft: row.isDraft,
    headBranch: row.headBranch, baseBranch: row.baseBranch, updatedAt: row.updatedAt, author: row.author, labels: row.labels,
    createdAt: row.createdAt, authorLogin: row.authorLogin, viewerLogin: row.viewerLogin,
    reviewDecision: row.reviewDecision, checksState: row.checksState,
    body: result.body, changedFiles: result.changedFiles ?? null,
    reviewers: (result.reviewers ?? []).map(authorLabel), diffAvailable: result.capabilities?.diff !== false,
    headSha: typeof result.headSha === 'string' ? result.headSha : '', actions: readPullRequestActions(result),
    completion: { mentions: result.capabilities?.mentions === true, referenceSigils },
  };
}

function sameLogin(viewer: string, author: string): boolean {
  const login = viewer.trim().toLowerCase();
  return login.length > 0 && login === author.trim().toLowerCase();
}

function readPullRequestActions(result: PullRequestDetailResult): NativePullRequestActions {
  const permissions = result.viewerPermissions;
  const capabilities = result.capabilities;
  const viewerLogin = typeof result.viewer === 'string' ? result.viewer : '';
  const verdicts: NativePullRequestReviewVerdict[] = [];
  if (result.state === 'open') {
    const known: NativePullRequestReviewVerdict[] = ['comment', 'approve', 'request-changes'];
    for (const verdict of known) {
      if (capabilities?.review?.verdicts?.includes(verdict) && permissions?.verdicts?.includes(verdict)) {
        verdicts.push(verdict);
      }
    }
  }
  return {
    viewerLogin,
    editChangeRequest: capabilities?.edit?.changeRequest === true && (permissions?.editChangeRequest ??
      (sameLogin(viewerLogin, result.author?.login ?? '') || permissions?.actions?.includes('merge') === true)),
    editComments: capabilities?.edit?.comment === true,
    comment: capabilities?.comment === true && permissions?.comment === true,
    inlineComment: verdicts.length > 0 && capabilities?.review?.inlineComment === true && permissions?.comment === true,
    verdicts,
    requiresChangeSummary: result.provider === 'forgejo',
    editLabels: capabilities?.labels === true && !!permissions && permissions.labels !== false,
    requestReviewers: result.state === 'open' && capabilities?.reviewers?.request === true &&
      permissions?.requestReviewers === true,
    listReviewers: capabilities?.reviewers?.listCandidates === true,
    searchReviewers: capabilities?.reviewers?.listCandidates === true &&
      capabilities?.reviewers?.searchCandidates === true,
  };
}

export function canEditPullRequestComment(detail: NativePullRequestDetail, comment: PullRequestCommentIdentity): boolean {
  return detail.actions.editComments && (comment.kind === 'issue-comment' || comment.kind === 'review-comment') &&
    (comment.canEdit ?? sameLogin(detail.actions.viewerLogin, comment.authorLogin));
}

function addComments(output: NativePullRequestComment[], items: PullRequestComment[], key: string, location: string,
  threadComment: boolean = false): void {
  items.forEach((item: PullRequestComment) => {
    if (!item.id || typeof item.body !== 'string') return;
    output.push({ key: JSON.stringify([key, item.id]), author: authorLabel(item.author), body: item.body,
      createdAt: item.createdAt, location, authorLogin: item.author?.login ?? '',
      kind: threadComment ? 'review-comment' : item.kind ?? '', canEdit: item.canEdit });
  });
}

export function readPullRequestDiscussion(value: Object): NativePullRequestDiscussion {
  const result = value as PullRequestActivityResult;
  if (!result || !Array.isArray(result.comments) || !Array.isArray(result.reviewThreads)) {
    throw new Error('拉取请求讨论响应格式无效。');
  }
  const comments: NativePullRequestComment[] = [];
  addComments(comments, result.comments, 'conversation', '');
  (result.overviewThreads ?? []).forEach((thread: PullRequestThread) => {
    addComments(comments, thread.comments, `overview-${thread.id}`, '', true);
  });
  result.reviewThreads.forEach((thread: PullRequestThread) => {
    const location = thread.path && thread.line !== null && thread.line !== undefined ?
      `${thread.path}:${thread.line}` : thread.path ?? '';
    addComments(comments, thread.comments, `review-${thread.id}`, location, true);
  });
  return { comments: comments.sort((a: NativePullRequestComment, b: NativePullRequestComment) =>
    Date.parse(a.createdAt) - Date.parse(b.createdAt)),
    truncated: result.commentsTruncated === true || result.reviewThreadsTruncated === true };
}

export function pullRequestDiffLines(patch: string): NativePullRequestDiffLine[] {
  const lines: NativePullRequestDiffLine[] = [];
  let left = 0;
  let right = 0;
  let leftRemaining = 0;
  let rightRemaining = 0;
  for (const code of patch.split('\n')) {
    const hunk = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/.exec(code);
    if (hunk) {
      left = Number(hunk[1]);
      leftRemaining = Number(hunk[2] ?? '1');
      right = Number(hunk[3]);
      rightRemaining = Number(hunk[4] ?? '1');
    } else if (code.startsWith('+') && rightRemaining > 0 && right > 0) {
      lines.push({ side: 'RIGHT', line: right++, code });
      rightRemaining--;
    } else if (code.startsWith('-') && leftRemaining > 0 && left > 0) {
      lines.push({ side: 'LEFT', line: left++, code });
      leftRemaining--;
    } else if (code.startsWith(' ') && leftRemaining > 0 && rightRemaining > 0 && left > 0 && right > 0) {
      lines.push({ side: 'RIGHT', line: right++, code });
      rightRemaining--;
      left++;
      leftRemaining--;
    }
  }
  return lines;
}

export function groupPullRequestFiles(files: NativePullRequestFile[]): NativePullRequestFileGroup[] {
  const groups: NativePullRequestFileGroup[] = [];
  for (const file of files) {
    const slash = file.path.lastIndexOf('/');
    const directory = slash < 0 ? '' : file.path.slice(0, slash);
    const group = groups[groups.length - 1];
    if (group?.directory === directory) group.files.push(file);
    else groups.push({ directory, files: [file] });
  }
  return groups;
}

export function readPullRequestDiff(value: Object): NativePullRequestDiff {
  const result = value as PullRequestDiffResult;
  if (!result || typeof result.patch !== 'string') throw new Error('拉取请求变更响应格式无效。');
  const prefix = 'diff --git ';
  const stats = new Map<string, PullRequestOmittedFileStat>();
  for (const omitted of result.omittedFileStats ?? []) {
    if (omitted?.path && Number.isSafeInteger(omitted.additions) && Number.isSafeInteger(omitted.deletions) &&
      omitted.additions >= 0 && omitted.deletions >= 0) {
      stats.set(omitted.path, omitted);
    }
  }
  const files = result.patch.split(/\n(?=diff --git )/).filter((patch: string) => patch.trim().length > 0)
    .map((patch: string): NativePullRequestFile => {
      const file = patch.startsWith(prefix) ? readGitDiffFile(patch.slice(prefix.length), false) : undefined;
      if (!file) return { path: '补丁', previousPath: null, additions: null, deletions: null, patch, withheld: false };
      const omitted = stats.get(file.path);
      if (omitted) stats.delete(file.path);
      return { path: file.path, previousPath: file.previousPath, additions: omitted?.additions ?? file.additions,
        deletions: omitted?.deletions ?? file.deletions, patch, withheld: false };
    });
  stats.forEach((omitted: PullRequestOmittedFileStat) => {
    files.push({ path: omitted.path, previousPath: null, additions: omitted.additions, deletions: omitted.deletions,
      patch: '', withheld: true });
  });
  return { files, truncated: result.truncated === true, nextCursor: result.nextCursor ?? undefined,
    withheldFilesReadable: typeof result.withheldFilesReadable === 'boolean' ? result.withheldFilesReadable : undefined };
}

export function readPullRequestFileDiff(value: Object, path: string): NativePullRequestFile | undefined {
  const result = value as PullRequestDiffResult;
  if (!result || typeof result.patch !== 'string') throw new Error('文件补丁响应格式无效。');
  if (result.truncated !== false || (result.nextCursor !== null && result.nextCursor !== undefined)) {
    throw new Error('环境返回的单文件补丁不完整。');
  }
  const patch = result.patch;
  if (!patch.trim()) return undefined;
  const prefix = 'diff --git ';
  if (!patch.startsWith(prefix) || patch.includes(`\n${prefix}`)) {
    throw new Error('返回的补丁与所选文件不匹配。');
  }
  const file = readGitDiffFile(patch.slice(prefix.length), false);
  if (!file || file.path !== path) throw new Error('返回的补丁与所选文件不匹配。');
  if (file.additions === 0 && file.deletions === 0) return undefined;
  return { path, previousPath: file.previousPath, additions: file.additions, deletions: file.deletions,
    patch, withheld: false };
}
