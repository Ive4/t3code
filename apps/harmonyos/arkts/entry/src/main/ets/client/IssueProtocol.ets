import { REQUEST_ID } from './T3Protocol';

export type NativeIssueStateFilter = 'all' | 'open' | 'closed';
export type NativeIssueInvolvement = 'all' | 'assigned' | 'authored' | 'mentioned';
export type NativeIssueSort = 'updated' | 'created';
export type NativeIssueEditor = 'edit' | 'labels' | 'assignees';
export type NativeIssueFacet = 'labels' | 'assignee';

export interface NativeIssueAssigneeFilter {
  login: string;
  name: string | null;
}

export interface NativeIssueFilters {
  state: NativeIssueStateFilter;
  query?: string;
  involvement?: NativeIssueInvolvement;
  sort?: NativeIssueSort;
  labels?: string[];
  assignee?: string;
}

export interface NativeIssueScope {
  projectId: string;
  tracker: string;
  host?: string;
  scope: string;
}

export interface NativeIssueRef extends NativeIssueScope {
  key: string;
}

export interface NativeIssueState {
  category: 'open' | 'closed';
  name: string;
}

export interface NativeIssueActor {
  login: string;
  name: string | null;
  avatarUrl: string | null;
}

export interface NativeIssueLabel {
  name: string;
  color: string | null;
}

export interface NativeIssueLabelCandidate extends NativeIssueLabel {
  description: string | null;
}

export interface NativeIssueAssigneeCandidate extends NativeIssueActor {
  id: string;
}

export interface NativeIssueCandidates {
  labels: NativeIssueLabelCandidate[];
  assignees: NativeIssueAssigneeCandidate[];
  truncated: boolean;
}

export interface NativeIssueEntry extends NativeIssueRef {
  host: string;
  projectTitle: string;
  displayKey: string;
  title: string;
  url: string;
  author: NativeIssueActor | null;
  state: NativeIssueState;
  createdAt: string;
  updatedAt: string;
  closedAt: string | null;
  labels: NativeIssueLabel[];
  assignees: NativeIssueActor[];
  commentCount: number;
}

interface NativeIssueCapabilities {
  create: boolean;
  edit: boolean;
  comment: boolean;
  labels: boolean;
  assignees: boolean;
  reactions: boolean;
  templates: boolean;
  linkedPullRequests: boolean;
  events: boolean;
  search: boolean;
}

interface NativeIssueViewerPermissions {
  setState: boolean;
  comment: boolean;
  edit: boolean;
  labels: boolean;
  assignees: boolean;
}

export interface NativeIssueTracker {
  tracker: string;
  host: string;
  projectCount: number;
  capabilities: NativeIssueCapabilities | null;
  configured: boolean;
  detail: string | null;
}

export interface NativeIssueError {
  projectId: string;
  projectTitle: string;
  message: string;
}

export interface NativeIssuePage {
  entries: NativeIssueEntry[];
  trackers: NativeIssueTracker[];
  errors: NativeIssueError[];
  nextCursors: Record<string, string>;
  viewers?: Record<string, string>;
  scopes?: NativeIssueScope[];
  unavailable?: boolean;
}

export interface NativeIssueComment {
  id: string;
  author: NativeIssueActor | null;
  body: string;
  createdAt: string;
  url: string | null;
}

export interface NativeIssueEvent {
  id: string;
  kind: string;
  actor: NativeIssueActor | null;
  createdAt: string;
  detail: string | null;
}

export interface NativeIssueLinkedPullRequest {
  repository: string;
  number: number;
  title: string;
  url: string;
  state: 'open' | 'closed' | 'merged';
  isDraft: boolean;
  closesIssue: boolean;
}

export interface NativeIssueDetail extends NativeIssueEntry {
  writable: boolean;
  capabilities: NativeIssueCapabilities;
  viewerPermissions: NativeIssueViewerPermissions;
  states: NativeIssueState[];
  viewer: string | null;
  body: string;
  comments: NativeIssueComment[];
  commentsCursor: string | null;
  events: NativeIssueEvent[];
  linkedPullRequests: NativeIssueLinkedPullRequest[];
}

interface IssueListPayload extends NativeIssueFilters {
  limit: number;
  cursors?: Record<string, string>;
  refresh?: boolean;
}

interface IssueRpcRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: Object;
  headers: string[][];
}

interface EnvironmentCapabilities {
  issues?: boolean;
}

interface IssueEnvironment {
  capabilities?: EnvironmentCapabilities;
}

interface IssueServerConfig {
  environment?: IssueEnvironment | null;
}

const ISSUE_TRACKER_KIND = /^[a-z][a-z0-9-]*$/;
export const ISSUE_FILTER_LABEL_LIMIT = 20;

export function supportsIssues(config?: Object): boolean {
  return (config as IssueServerConfig | undefined)?.environment?.capabilities?.issues === true;
}

export function normalizeIssueQuery(query: string): string {
  return query.trim().slice(0, 200).trim();
}

export function normalizeIssueFilterLabels(labels?: string[]): string[] {
  if (!Array.isArray(labels)) return [];
  return Array.from(new Set(labels.filter((label: string) => nonempty(label) && label.length <= 200)))
    .slice(0, ISSUE_FILTER_LABEL_LIMIT);
}

export function issueListRequest(filters: NativeIssueFilters, cursors?: Record<string, string>,
  refresh?: boolean): IssueRpcRequest {
  const payload: IssueListPayload = { state: filters.state, limit: 50 };
  const query = normalizeIssueQuery(filters.query ?? '');
  if (query) payload.query = query;
  if (filters.involvement) payload.involvement = filters.involvement;
  if (filters.sort) payload.sort = filters.sort;
  const labels = normalizeIssueFilterLabels(filters.labels);
  if (labels.length > 0) payload.labels = labels;
  if (filters.assignee && nonempty(filters.assignee) && filters.assignee.length <= 320) {
    payload.assignee = filters.assignee;
  }
  if (cursors && Object.keys(cursors).length > 0) payload.cursors = cursors;
  if (refresh) payload.refresh = true;
  return { _tag: 'Request', id: REQUEST_ID, tag: 'issues.list', payload, headers: [] };
}

export function issueDetailRequest(ref: NativeIssueRef): IssueRpcRequest {
  if (!validScope(ref) || !nonempty(ref.key)) throw new Error('工单地址无效。');
  const payload: NativeIssueRef = {
    projectId: ref.projectId, tracker: ref.tracker, scope: ref.scope, key: ref.key,
  };
  if (ref.host) payload.host = ref.host;
  return { _tag: 'Request', id: REQUEST_ID, tag: 'issues.detail', payload, headers: [] };
}

export function issueCandidatesRequest(scope: NativeIssueScope): IssueRpcRequest {
  if (!validScope(scope)) throw new Error('工单候选范围无效。');
  const payload: NativeIssueScope = { projectId: scope.projectId, tracker: scope.tracker, scope: scope.scope };
  if (scope.host) payload.host = scope.host;
  return { _tag: 'Request', id: REQUEST_ID, tag: 'issues.candidates', payload, headers: [] };
}

export function issueRefKey(ref: NativeIssueRef): string {
  return JSON.stringify([ref.projectId, ref.tracker, ref.host ?? '', ref.scope, ref.key]);
}

export function mergeIssueEntries(previous: NativeIssueEntry[], next: NativeIssueEntry[],
  sort: NativeIssueSort): NativeIssueEntry[] {
  const entries = new Map<string, NativeIssueEntry>();
  previous.forEach((entry) => entries.set(issueRefKey(entry), entry));
  next.forEach((entry) => entries.set(issueRefKey(entry), entry));
  return Array.from(entries.values()).sort((left, right) => {
    const leftTime = sort === 'created' ? left.createdAt : left.updatedAt;
    const rightTime = sort === 'created' ? right.createdAt : right.updatedAt;
    return Date.parse(rightTime) - Date.parse(leftTime);
  });
}

function trackerKey(tracker: string, host: string): string {
  return `${tracker} ${host.toLowerCase()}`;
}

export function issueCandidateScopes(page: NativeIssuePage, facet: NativeIssueFacet): NativeIssueScope[] {
  const trackers = new Set<string>();
  page.trackers.forEach((tracker) => {
    if (tracker.configured && (facet === 'labels' ? tracker.capabilities?.labels : tracker.capabilities?.assignees) === true) {
      trackers.add(trackerKey(tracker.tracker, tracker.host));
    }
  });
  const scopes: NativeIssueScope[] = [];
  const seen = new Set<string>();
  for (const entry of page.scopes ?? page.entries) {
    if (!entry.host || !trackers.has(trackerKey(entry.tracker, entry.host))) continue;
    const key = JSON.stringify([page.scopes === undefined ? '' : entry.projectId, entry.tracker,
      entry.host.toLowerCase(), entry.scope]);
    if (seen.has(key)) continue;
    seen.add(key);
    scopes.push({ projectId: entry.projectId, tracker: entry.tracker, host: entry.host, scope: entry.scope });
  }
  return scopes;
}

export function issueSearchEntries(page: NativeIssuePage, query: string): NativeIssueEntry[] {
  const needle = normalizeIssueQuery(query).toLowerCase();
  if (!needle) return page.entries;
  const trackerSearch = new Set<string>();
  page.trackers.forEach((tracker) => {
    if (tracker.capabilities?.search === true) trackerSearch.add(trackerKey(tracker.tracker, tracker.host));
  });
  return page.entries.filter((entry) => trackerSearch.has(trackerKey(entry.tracker, entry.host)) ||
    entry.title.toLowerCase().includes(needle) || entry.displayKey.toLowerCase().includes(needle));
}

export function issueListEmptyMessage(page: NativeIssuePage, query: string): string {
  if (page.entries.length > 0 || Object.keys(page.nextCursors).length > 0) return '';
  if (page.unavailable) return '当前环境版本未启用工单。';
  if (page.scopes?.length === 0 || page.trackers.length === 0) return '当前环境没有工单来源。';
  if (!page.trackers.some((tracker) => tracker.configured)) return '请先配置工单跟踪器。';
  return normalizeIssueQuery(query) ? '没有相关搜索结果。' : '没有符合当前筛选条件的工单。';
}

function nonempty(value: string): boolean {
  return typeof value === 'string' && value.length > 0 && value.trim() === value;
}

function validDate(value: string): boolean {
  return typeof value === 'string' && Number.isFinite(Date.parse(value));
}

function validTracker(value: string): boolean {
  return typeof value === 'string' && value.length <= 64 && ISSUE_TRACKER_KIND.test(value);
}

function validScope(scope: NativeIssueScope): boolean {
  return !!scope && nonempty(scope.projectId) && validTracker(scope.tracker) && nonempty(scope.scope) &&
    (scope.host === undefined || nonempty(scope.host));
}

function validActor(actor: NativeIssueActor | null): boolean {
  return actor === null || (!!actor && nonempty(actor.login) &&
    (actor.name === null || typeof actor.name === 'string') &&
    (actor.avatarUrl === null || typeof actor.avatarUrl === 'string'));
}

function validState(state: NativeIssueState): boolean {
  return !!state && (state.category === 'open' || state.category === 'closed') && nonempty(state.name);
}

function validEntry(entry: NativeIssueEntry): boolean {
  return validScope(entry) && nonempty(entry.host) && nonempty(entry.key) && nonempty(entry.title) &&
    nonempty(entry.projectTitle) && nonempty(entry.displayKey) && nonempty(entry.url) &&
    validActor(entry.author) && validState(entry.state) && validDate(entry.createdAt) &&
    validDate(entry.updatedAt) && (entry.closedAt === null || validDate(entry.closedAt)) &&
    Number.isInteger(entry.commentCount) && entry.commentCount >= 0 &&
    Array.isArray(entry.assignees) && entry.assignees.every((actor: NativeIssueActor) => !!actor && validActor(actor)) &&
    Array.isArray(entry.labels) && entry.labels.every((label: NativeIssueLabel) => !!label && nonempty(label.name) &&
      (label.color === null || typeof label.color === 'string'));
}

function validStringRecord(value?: Record<string, string>, maxLength: number = Infinity): boolean {
  return !!value && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).every((key: string) => nonempty(key) && nonempty(value[key]) && value[key].length <= maxLength);
}

export function readIssuePage(value?: Object): NativeIssuePage {
  const page = value as NativeIssuePage | undefined;
  if (!page || !Array.isArray(page.entries) || !page.entries.every(validEntry) ||
    !Array.isArray(page.trackers) || !page.trackers.every((tracker: NativeIssueTracker) => !!tracker &&
      validTracker(tracker.tracker) && nonempty(tracker.host) && Number.isInteger(tracker.projectCount) &&
      tracker.projectCount > 0 && typeof tracker.configured === 'boolean' &&
      (tracker.detail === null || nonempty(tracker.detail))) ||
    !Array.isArray(page.errors) || !page.errors.every((error: NativeIssueError) => !!error &&
      nonempty(error.projectId) && nonempty(error.projectTitle) && nonempty(error.message)) ||
    !validStringRecord(page.nextCursors, 4096) || !validStringRecord(page.viewers) ||
    (page.scopes !== undefined && (!Array.isArray(page.scopes) || !page.scopes.every(validScope)))) {
    throw new Error('环境返回的工单列表无效。');
  }
  return page;
}

export function readIssueDetail(value: Object | undefined, ref: NativeIssueRef): NativeIssueDetail {
  const detail = value as NativeIssueDetail | undefined;
  if (!detail || !validEntry(detail) || detail.projectId !== ref.projectId || detail.tracker !== ref.tracker ||
    detail.scope !== ref.scope || detail.key !== ref.key || (ref.host !== undefined && detail.host !== ref.host) ||
    typeof detail.writable !== 'boolean' || !detail.capabilities || !detail.viewerPermissions ||
    typeof detail.body !== 'string' || !Array.isArray(detail.states) || !detail.states.every(validState) ||
    !Array.isArray(detail.comments) || !detail.comments.every((comment: NativeIssueComment) => !!comment &&
      nonempty(comment.id) && validActor(comment.author) && typeof comment.body === 'string' &&
      validDate(comment.createdAt)) ||
    (detail.commentsCursor !== null && !nonempty(detail.commentsCursor)) ||
    !Array.isArray(detail.events) || !detail.events.every((event: NativeIssueEvent) => !!event &&
      nonempty(event.id) && nonempty(event.kind) && validActor(event.actor) && validDate(event.createdAt) &&
      (event.detail === null || nonempty(event.detail))) ||
    !Array.isArray(detail.linkedPullRequests) ||
    !detail.linkedPullRequests.every((pullRequest: NativeIssueLinkedPullRequest) => !!pullRequest &&
      nonempty(pullRequest.repository) && Number.isInteger(pullRequest.number) && pullRequest.number > 0 &&
      nonempty(pullRequest.title) && (pullRequest.state === 'open' || pullRequest.state === 'closed' ||
        pullRequest.state === 'merged'))) {
    throw new Error('环境返回的工单详情无效。');
  }
  return detail;
}

export function readIssueCandidates(value?: Object): NativeIssueCandidates {
  const candidates = value as NativeIssueCandidates | undefined;
  if (!candidates || typeof candidates.truncated !== 'boolean' || !Array.isArray(candidates.labels) ||
    !candidates.labels.every((label: NativeIssueLabelCandidate) => !!label && nonempty(label.name) &&
      (label.color === null || typeof label.color === 'string') &&
      (label.description === null || typeof label.description === 'string')) ||
    !Array.isArray(candidates.assignees) ||
    !candidates.assignees.every((actor: NativeIssueAssigneeCandidate) => !!actor && nonempty(actor.id) && validActor(actor))) {
    throw new Error('环境返回的工单候选无效。');
  }
  return candidates;
}

export function issueCanShowEditor(detail: NativeIssueDetail, sourceCanWrite: boolean,
  action: NativeIssueEditor): boolean {
  if (!sourceCanWrite || !detail.writable) return false;
  switch (action) {
    case 'edit':
      return detail.capabilities.edit === true && detail.viewerPermissions.edit === true;
    case 'labels':
      return detail.capabilities.labels === true && detail.viewerPermissions.labels === true;
    case 'assignees':
      return detail.capabilities.assignees === true && detail.viewerPermissions.assignees === true;
  }
}
