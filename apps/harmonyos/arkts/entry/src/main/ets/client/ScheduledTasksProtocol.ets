import { validProviderInstanceId } from './T3Protocol';
import type { ThreadLaunchRuntimeMode, ThreadLaunchSelection, ThreadLaunchWorkspaceStrategy } from './ThreadLaunchProtocol';

export type NativeScheduledTaskRunStatus = 'never' | 'running' | 'succeeded' | 'failed';
export type NativeScheduledTaskThreadMode = 'new_thread' | 'continue' | 'fresh_session';
export type NativeScheduledTaskInteractionMode = 'default' | 'plan';

export interface NativeScheduledTaskIntervalSchedule {
  type: 'interval';
  everyMs: number;
}

export interface NativeScheduledTaskFixedTimeSchedule {
  type: 'fixed_time';
  timeOfDay: string;
  weekdays?: number[];
}

export interface NativeScheduledTaskOnceSchedule {
  type: 'once';
  runAt: string;
}

export interface NativeScheduledTaskWebhookSchedule {
  type: 'webhook';
  signature?: Object | null;
  maxDeliveryAgeMinutes?: number | null;
  dedupe?: Object;
  filters?: Object[];
}

export type NativeScheduledTaskSchedule =
  | NativeScheduledTaskIntervalSchedule
  | NativeScheduledTaskFixedTimeSchedule
  | NativeScheduledTaskOnceSchedule
  | NativeScheduledTaskWebhookSchedule;

export interface NativeScheduledTask {
  id: string;
  title: string;
  prompt: string;
  cronExpression?: string;
  enabled: boolean;
  schedule: NativeScheduledTaskSchedule;
  projectId: string;
  threadId: string | null;
  threadMode?: NativeScheduledTaskThreadMode;
  workspaceStrategy: ThreadLaunchWorkspaceStrategy;
  modelSelection: ThreadLaunchSelection;
  runtimeMode: ThreadLaunchRuntimeMode;
  interactionMode: NativeScheduledTaskInteractionMode;
  createdAt?: string;
  updatedAt?: string;
  nextRunAt: string | null;
  lastRunAt: string | null;
  lastRunStatus: NativeScheduledTaskRunStatus;
  lastRunError: string | null;
  runCount: number;
  blockedByPolicy?: string;
}

export interface ScheduledTaskUpsertDraft {
  id?: string;
  requireExisting?: boolean;
  commandId?: string;
  title: string;
  prompt: string;
  enabled: boolean;
  schedule: NativeScheduledTaskSchedule;
  projectId: string;
  threadId?: string | null;
  unbindThread?: boolean;
  threadMode?: NativeScheduledTaskThreadMode;
  workspaceStrategy?: ThreadLaunchWorkspaceStrategy;
  modelSelection: ThreadLaunchSelection;
  runtimeMode?: ThreadLaunchRuntimeMode;
  interactionMode?: NativeScheduledTaskInteractionMode;
}

export interface ScheduledTaskUpsertPayload {
  id?: string;
  requireExisting?: boolean;
  commandId?: string;
  title: string;
  prompt: string;
  enabled: boolean;
  schedule: NativeScheduledTaskSchedule;
  projectId: string;
  threadId?: string | null;
  unbindThread?: boolean;
  threadMode?: NativeScheduledTaskThreadMode;
  workspaceStrategy: ThreadLaunchWorkspaceStrategy;
  modelSelection: ThreadLaunchSelection;
  runtimeMode: ThreadLaunchRuntimeMode;
  interactionMode: NativeScheduledTaskInteractionMode;
  creationSource?: string;
}

export interface ScheduledTaskIdPayload {
  id: string;
}

export interface ScheduledTaskSetEnabledPayload {
  id: string;
  enabled: boolean;
}

export interface ScheduledTaskUpsertRequest {
  method: string;
  params: ScheduledTaskUpsertPayload;
}

export interface ScheduledTaskSetEnabledRequest {
  method: string;
  params: ScheduledTaskSetEnabledPayload;
}

export interface ScheduledTaskIdRequest {
  method: string;
  params: ScheduledTaskIdPayload;
}

interface ScheduledTaskScheduleWire {
  type?: string;
  everyMs?: number;
  timeOfDay?: string;
  weekdays?: number[];
  runAt?: string;
  signature?: Object | null;
  maxDeliveryAgeMinutes?: number | null;
  dedupe?: Object;
  filters?: Object[];
}

interface ScheduledTaskModelSelectionWire {
  instanceId?: string;
  provider?: string;
  model?: string;
  options?: Object;
}

interface ScheduledTaskWorkspaceStrategyWire {
  type?: string;
  branch?: string;
  worktreePath?: string;
  baseRef?: string;
  startFromOrigin?: boolean;
}

interface ScheduledTaskWire {
  id?: string;
  title?: string;
  prompt?: string;
  cronExpression?: string;
  enabled?: boolean;
  schedule?: ScheduledTaskScheduleWire;
  projectId?: string;
  threadId?: string | null;
  threadMode?: string;
  workspaceStrategy?: ScheduledTaskWorkspaceStrategyWire;
  modelSelection?: ScheduledTaskModelSelectionWire;
  runtimeMode?: string;
  interactionMode?: string;
  createdAt?: string;
  updatedAt?: string;
  nextRunAt?: string | null;
  lastRunAt?: string | null;
  lastRunStatus?: string;
  lastRunError?: string | null;
  runCount?: number;
  blockedByPolicy?: string;
}

interface ScheduledTaskListWire {
  tasks?: ScheduledTaskWire[];
}

function nonBlank(value: string | null | undefined): boolean {
  return typeof value === 'string' && value.trim().length > 0;
}

function requireNonBlank(value: string | undefined, message: string): string {
  if (!nonBlank(value)) {
    throw new Error(message);
  }
  return value!.trim();
}

function readRunStatus(value: string | undefined): NativeScheduledTaskRunStatus {
  if (value === 'never' || value === 'running' || value === 'succeeded' || value === 'failed') {
    return value;
  }
  return 'never';
}

function readThreadMode(value: string | undefined): NativeScheduledTaskThreadMode | undefined {
  if (value === 'new_thread' || value === 'continue' || value === 'fresh_session') {
    return value;
  }
  return undefined;
}

function readRuntimeMode(value: string | undefined): ThreadLaunchRuntimeMode {
  if (value === 'approval-required' || value === 'auto-accept-edits' ||
    value === 'auto' || value === 'full-access') {
    return value;
  }
  return 'approval-required';
}

function readInteractionMode(value: string | undefined): NativeScheduledTaskInteractionMode {
  return value === 'plan' ? 'plan' : 'default';
}

function readSchedule(wire: ScheduledTaskScheduleWire | undefined): NativeScheduledTaskSchedule | undefined {
  if (!wire || typeof wire !== 'object') return undefined;
  if (wire.type === 'interval' && typeof wire.everyMs === 'number' && wire.everyMs > 0) {
    return { type: 'interval', everyMs: wire.everyMs };
  }
  if (wire.type === 'fixed_time' && nonBlank(wire.timeOfDay)) {
    const schedule: NativeScheduledTaskFixedTimeSchedule = {
      type: 'fixed_time',
      timeOfDay: wire.timeOfDay!.trim(),
    };
    if (Array.isArray(wire.weekdays)) {
      schedule.weekdays = wire.weekdays.filter((day: number) =>
        typeof day === 'number' && Number.isInteger(day) && day >= 0 && day <= 6);
    }
    return schedule;
  }
  if (wire.type === 'once' && nonBlank(wire.runAt)) {
    return { type: 'once', runAt: wire.runAt!.trim() };
  }
  if (wire.type === 'webhook') {
    const schedule: NativeScheduledTaskWebhookSchedule = { type: 'webhook' };
    if (wire.signature !== undefined) schedule.signature = wire.signature;
    if (wire.maxDeliveryAgeMinutes !== undefined) schedule.maxDeliveryAgeMinutes = wire.maxDeliveryAgeMinutes;
    if (wire.dedupe !== undefined) schedule.dedupe = wire.dedupe;
    if (Array.isArray(wire.filters)) schedule.filters = wire.filters;
    return schedule;
  }
  return undefined;
}

function readWorkspaceStrategy(wire: ScheduledTaskWorkspaceStrategyWire | undefined): ThreadLaunchWorkspaceStrategy {
  if (wire?.type === 'existing_worktree' && nonBlank(wire.worktreePath) && nonBlank(wire.branch)) {
    return {
      type: 'existing_worktree',
      worktreePath: wire.worktreePath!.trim(),
      branch: wire.branch!.trim(),
    };
  }
  if (wire?.type === 'worktree' && nonBlank(wire.baseRef)) {
    return wire.startFromOrigin === true
      ? { type: 'worktree', baseRef: wire.baseRef!.trim(), startFromOrigin: true }
      : { type: 'worktree', baseRef: wire.baseRef!.trim() };
  }
  if (nonBlank(wire?.branch)) {
    return { type: 'root', branch: wire!.branch!.trim() };
  }
  return { type: 'root' };
}

function readModelSelection(wire: ScheduledTaskModelSelectionWire | undefined): ThreadLaunchSelection | undefined {
  if (!wire || typeof wire !== 'object' || !nonBlank(wire.model)) return undefined;
  const instanceId = nonBlank(wire.instanceId) ? wire.instanceId!.trim() :
    nonBlank(wire.provider) ? wire.provider!.trim() : '';
  if (!validProviderInstanceId(instanceId)) return undefined;
  return {
    instanceId,
    model: wire.model!.trim(),
  };
}

export function readScheduledTasksSnapshot(payload?: Object | null): NativeScheduledTask[] {
  const wire = payload as ScheduledTaskListWire | null | undefined;
  if (!wire || typeof wire !== 'object' || !Array.isArray(wire.tasks)) {
    return [];
  }
  const tasks: NativeScheduledTask[] = [];
  for (const item of wire.tasks) {
    if (!item || typeof item !== 'object') continue;
    if (!nonBlank(item.id) || !nonBlank(item.title) || !nonBlank(item.prompt) || !nonBlank(item.projectId)) {
      continue;
    }
    const schedule = readSchedule(item.schedule);
    const modelSelection = readModelSelection(item.modelSelection);
    if (!schedule || !modelSelection) continue;
    const task: NativeScheduledTask = {
      id: item.id!.trim(),
      title: item.title!.trim(),
      prompt: item.prompt!.trim(),
      enabled: item.enabled === true,
      schedule,
      projectId: item.projectId!.trim(),
      threadId: nonBlank(item.threadId) ? item.threadId!.trim() : null,
      workspaceStrategy: readWorkspaceStrategy(item.workspaceStrategy),
      modelSelection,
      runtimeMode: readRuntimeMode(item.runtimeMode),
      interactionMode: readInteractionMode(item.interactionMode),
      nextRunAt: nonBlank(item.nextRunAt) ? item.nextRunAt!.trim() : null,
      lastRunAt: nonBlank(item.lastRunAt) ? item.lastRunAt!.trim() : null,
      lastRunStatus: readRunStatus(item.lastRunStatus),
      lastRunError: typeof item.lastRunError === 'string' ? item.lastRunError : null,
      runCount: typeof item.runCount === 'number' && item.runCount >= 0 ? item.runCount : 0,
    };
    if (nonBlank(item.cronExpression)) task.cronExpression = item.cronExpression!.trim();
    const threadMode = readThreadMode(item.threadMode);
    if (threadMode) task.threadMode = threadMode;
    if (nonBlank(item.createdAt)) task.createdAt = item.createdAt!.trim();
    if (nonBlank(item.updatedAt)) task.updatedAt = item.updatedAt!.trim();
    if (nonBlank(item.blockedByPolicy)) task.blockedByPolicy = item.blockedByPolicy!.trim();
    tasks.push(task);
  }
  return tasks;
}

export function buildScheduledTaskUpsertRequest(draft: ScheduledTaskUpsertDraft): ScheduledTaskUpsertRequest {
  const title = requireNonBlank(draft?.title, '请输入定时任务名称。');
  const prompt = requireNonBlank(draft?.prompt, '请输入定时任务提示词。');
  const projectId = requireNonBlank(draft?.projectId, '请选择所属项目。');
  if (!draft?.schedule || typeof draft.schedule !== 'object') {
    throw new Error('请配置定时任务计划。');
  }
  if (!draft.modelSelection || !validProviderInstanceId(draft.modelSelection.instanceId) ||
    !nonBlank(draft.modelSelection.model)) {
    throw new Error('请选择可用的模型。');
  }
  const payload: ScheduledTaskUpsertPayload = {
    title,
    prompt,
    enabled: draft.enabled === true,
    schedule: draft.schedule,
    projectId,
    workspaceStrategy: draft.workspaceStrategy ?? { type: 'root' },
    modelSelection: {
      instanceId: draft.modelSelection.instanceId.trim(),
      model: draft.modelSelection.model.trim(),
    },
    runtimeMode: draft.runtimeMode ?? 'approval-required',
    interactionMode: draft.interactionMode ?? 'default',
    creationSource: 'mobile',
  };
  if (nonBlank(draft.id)) payload.id = draft.id!.trim();
  if (draft.requireExisting !== undefined) payload.requireExisting = draft.requireExisting;
  if (nonBlank(draft.commandId)) payload.commandId = draft.commandId!.trim();
  if (draft.threadId !== undefined) {
    payload.threadId = nonBlank(draft.threadId) ? draft.threadId!.trim() : null;
  }
  if (draft.unbindThread !== undefined) payload.unbindThread = draft.unbindThread;
  if (draft.threadMode !== undefined) payload.threadMode = draft.threadMode;
  return {
    method: 'scheduledTasks.upsert',
    params: payload,
  };
}

export function buildScheduledTaskSetEnabledRequest(
  taskId: string,
  enabled: boolean,
): ScheduledTaskSetEnabledRequest {
  const id = requireNonBlank(taskId, '缺少定时任务标识。');
  return {
    method: 'scheduledTasks.setEnabled',
    params: { id, enabled: enabled === true },
  };
}

export function buildScheduledTaskDeleteRequest(taskId: string): ScheduledTaskIdRequest {
  const id = requireNonBlank(taskId, '缺少定时任务标识。');
  return {
    method: 'scheduledTasks.delete',
    params: { id },
  };
}

export function buildScheduledTaskRunNowRequest(taskId: string): ScheduledTaskIdRequest {
  const id = requireNonBlank(taskId, '缺少定时任务标识。');
  return {
    method: 'scheduledTasks.runNow',
    params: { id },
  };
}
