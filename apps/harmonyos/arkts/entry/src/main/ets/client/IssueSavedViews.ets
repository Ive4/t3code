import { normalizeIssueFilterLabels, normalizeIssueQuery } from './IssueProtocol';
import type {
  NativeIssueAssigneeFilter, NativeIssueInvolvement, NativeIssueSort, NativeIssueStateFilter,
} from './IssueProtocol';

export const ISSUE_VIEW_NAME_LIMIT = 80;

export interface NativeIssueViewScope {
  query: string;
  state: NativeIssueStateFilter;
  involvement: NativeIssueInvolvement;
  sort: NativeIssueSort;
  labels?: string[];
  assignee?: NativeIssueAssigneeFilter | null;
}

export interface NativeIssueSavedView extends NativeIssueViewScope {
  id: string;
  name: string;
}

function validIssueView(view: NativeIssueSavedView): boolean {
  return !!view && typeof view.id === 'string' && view.id.trim().length > 0 &&
    typeof view.name === 'string' && typeof view.query === 'string' &&
    (view.state === 'open' || view.state === 'closed' || view.state === 'all') &&
    (view.involvement === 'all' || view.involvement === 'assigned' || view.involvement === 'authored' ||
      view.involvement === 'mentioned') && (view.sort === 'updated' || view.sort === 'created');
}

function normalizedView(view: NativeIssueSavedView, name: string): NativeIssueSavedView {
  const assignee = view.assignee;
  return {
    id: view.id, name, query: normalizeIssueQuery(view.query),
    state: view.state, involvement: view.involvement, sort: view.sort,
    labels: normalizeIssueFilterLabels(view.labels),
    assignee: assignee && typeof assignee.login === 'string' && assignee.login.length > 0 &&
      assignee.login.trim() === assignee.login && assignee.login.length <= 320 &&
      (assignee.name === null || typeof assignee.name === 'string')
      ? { login: assignee.login, name: assignee.name } : null,
  };
}

export function issueSavedViewMatches(view: NativeIssueViewScope, scope: NativeIssueViewScope): boolean {
  return view.state === scope.state && view.involvement === scope.involvement && view.sort === scope.sort &&
    view.assignee?.login === scope.assignee?.login &&
    JSON.stringify(normalizeIssueFilterLabels(view.labels).sort()) ===
      JSON.stringify(normalizeIssueFilterLabels(scope.labels).sort()) &&
    normalizeIssueQuery(view.query) === normalizeIssueQuery(scope.query);
}

export function readIssueSavedViews(raw: string): NativeIssueSavedView[] {
  let parsed: NativeIssueSavedView[];
  try {
    parsed = JSON.parse(raw) as NativeIssueSavedView[];
  } catch (_) {
    return [];
  }
  if (!Array.isArray(parsed)) return [];
  const views: NativeIssueSavedView[] = [];
  const ids = new Set<string>();
  const names = new Set<string>();
  for (const view of parsed) {
    if (!validIssueView(view)) continue;
    const name = view.name.trim();
    const key = name.toLowerCase();
    if (!name || name.length > ISSUE_VIEW_NAME_LIMIT || names.has(key) || ids.has(view.id)) continue;
    views.push(normalizedView(view, name));
    ids.add(view.id);
    names.add(key);
  }
  return views;
}

export function writeIssueSavedView(current: NativeIssueSavedView[], view: NativeIssueSavedView): NativeIssueSavedView[] {
  if (!validIssueView(view)) throw new Error('工单视图筛选条件无效。');
  const name = view.name.trim();
  if (!name) throw new Error('请输入视图名称。');
  if (name.length > ISSUE_VIEW_NAME_LIMIT) throw new Error(`视图名称最多 ${ISSUE_VIEW_NAME_LIMIT} 个字符。`);
  if (current.some((item) => item.id !== view.id && item.name.toLowerCase() === name.toLowerCase())) {
    throw new Error('已经存在同名工单视图。');
  }
  const next = normalizedView(view, name);
  if (!current.some((item) => item.id === view.id)) return [...current, next];
  return current.map((item) => item.id === view.id ? next : item);
}
