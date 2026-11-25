import { REQUEST_ID } from './T3Protocol';

export type NativePullRequestFilterMode = 'projects' | 'authors' | 'labels' | 'excluded-labels';

export interface NativePullRequestFilterCandidate {
  key: string;
  title: string;
  color?: string;
}

export interface NativePullRequestFilterCandidatePage {
  candidates: NativePullRequestFilterCandidate[];
  truncated: boolean;
}

interface PullRequestFilterOptionsInput {
  kind: 'authors' | 'labels';
  projectId?: string;
  query?: string;
}

interface PullRequestFilterOptionsRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: PullRequestFilterOptionsInput;
  headers: string[][];
}

interface FilterOptionLabel {
  name: string;
  color: string | null;
}

interface FilterOptionAuthor {
  login: string;
  name: string | null;
}

interface FilterOptionsWire {
  labels: FilterOptionLabel[];
  authors: FilterOptionAuthor[];
  truncated: boolean;
}

export function pullRequestFilterOptionsRequest(mode: NativePullRequestFilterMode, projectId?: string,
  query?: string): PullRequestFilterOptionsRequest {
  if (mode === 'projects') throw new Error('项目选项需从当前环境项目列表读取。');
  const payload: PullRequestFilterOptionsInput = { kind: mode === 'authors' ? 'authors' : 'labels' };
  const project = projectId?.trim();
  if (project) payload.projectId = project;
  const needle = query?.trim().slice(0, 100).trimEnd();
  if (needle) payload.query = needle;
  return { _tag: 'Request', id: REQUEST_ID, tag: 'pullRequests.filterOptions', payload, headers: [] };
}

export function readPullRequestFilterOptions(value: Object | undefined, mode: NativePullRequestFilterMode):
  NativePullRequestFilterCandidatePage {
  const data = value as FilterOptionsWire | undefined;
  if (mode === 'projects' || !data || !Array.isArray(data.labels) || !Array.isArray(data.authors) ||
    typeof data.truncated !== 'boolean') {
    throw new Error('环境返回的拉取请求筛选选项无效。');
  }
  const candidates: NativePullRequestFilterCandidate[] = [];
  if (mode === 'authors') {
    for (const author of data.authors) {
      if (typeof author?.login !== 'string' || !author.login.trim()) continue;
      const title = typeof author.name === 'string' ? author.name.trim() : '';
      candidates.push({ key: author.login, title: title || author.login });
    }
  } else {
    for (const label of data.labels) {
      if (typeof label?.name !== 'string' || !label.name.trim()) continue;
      const candidate: NativePullRequestFilterCandidate = { key: label.name, title: label.name };
      const hex = typeof label.color === 'string' ? label.color.replace(/^#/, '') : '';
      if (/^[\da-f]{6}$/i.test(hex)) candidate.color = '#' + hex;
      candidates.push(candidate);
    }
  }
  return { candidates, truncated: data.truncated };
}
