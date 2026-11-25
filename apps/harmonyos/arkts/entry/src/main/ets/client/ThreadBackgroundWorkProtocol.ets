export type NativeThreadBackgroundTaskKind = 'subagent' | 'command' | 'monitor' | 'background_task';

export interface NativeThreadBackgroundTask {
  taskId: string;
  kind: NativeThreadBackgroundTaskKind;
  description?: string;
  parentTaskId?: string;
  awaited?: boolean;
  childThreadId?: string;
}

interface BackgroundTaskWire {
  taskId: string;
  kind: string;
  description?: string;
  parentTaskId?: string;
  awaited?: boolean;
  childThreadId?: string;
}

export interface NativeThreadBackgroundPullRequestWatch {
  host: string;
  repository: string;
  number: number;
}

interface BackgroundPullRequestWire extends NativeThreadBackgroundPullRequestWatch {
  source?: string;
  watch?: Object;
}

interface BackgroundToolInput {
  persistent?: boolean;
}

function validBackgroundText(value?: string): boolean {
  return typeof value === 'string' && value.length > 0 && value.trim() === value && !value.includes('\0');
}

export function readThreadBackgroundTasks(value?: Object[], parentThreadId?: string): NativeThreadBackgroundTask[] {
  if (!Array.isArray(value)) return [];
  const tasks: NativeThreadBackgroundTask[] = [];
  const seen = new Set<string>();
  for (const item of value) {
    const raw = item as BackgroundTaskWire;
    if (!raw || !validBackgroundText(raw.taskId) || typeof raw.kind !== 'string' || seen.has(raw.taskId)) continue;
    const base: NativeThreadBackgroundTask = { taskId: raw.taskId, kind: 'background_task' };
    if (validBackgroundText(raw.description)) base.description = raw.description;
    if (validBackgroundText(raw.parentTaskId)) base.parentTaskId = raw.parentTaskId;
    if (raw.kind === 'subagent' || raw.kind === 'command' || raw.kind === 'monitor' || raw.kind === 'background_task') {
      base.kind = raw.kind;
      if (raw.awaited === true) base.awaited = true;
      if (raw.kind === 'subagent' && validBackgroundText(raw.childThreadId) && raw.childThreadId !== parentThreadId) {
        base.childThreadId = raw.childThreadId;
      }
    }
    seen.add(raw.taskId);
    tasks.push(base);
  }
  return tasks;
}

export function hasNativeThreadBackgroundWork(tasks?: NativeThreadBackgroundTask[]): boolean {
  return tasks?.some((task: NativeThreadBackgroundTask) => !task.taskId.startsWith('pull-request-watch:')) === true;
}

export function readBackgroundPullRequestIdentity(value: Object): NativeThreadBackgroundPullRequestWatch | undefined {
  const link = value as BackgroundPullRequestWire;
  if (!link || !validBackgroundText(link.host) || !validBackgroundText(link.repository) ||
    !Number.isSafeInteger(link.number) || link.number <= 0) return undefined;
  return { host: link.host, repository: link.repository, number: link.number };
}

export function backgroundPullRequestIsWatched(value: Object): boolean {
  const link = value as BackgroundPullRequestWire;
  return link?.source !== 'stack-dismissed' && typeof link?.watch === 'object' &&
    link.watch !== null && !Array.isArray(link.watch);
}

export function isPersistentThreadBackgroundTool(value?: Object): boolean {
  return typeof value === 'object' && value !== null && (value as BackgroundToolInput).persistent === true;
}
