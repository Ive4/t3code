export type NativeThreadSubagentStatus = 'idle' | 'pending' | 'running' | 'waiting' | 'completed' |
  'failed' | 'cancelled' | 'interrupted';

export interface NativeThreadSubagentRun {
  id: string;
  ordinal: number;
  status: string;
  startedAt?: string | null;
}

export interface NativeThreadRemoteSubagent {
  environmentId: string;
  threadId: string;
  label: string;
  title?: string;
  runId?: string;
  stoppedThere?: boolean;
  stopCount?: number;
}

export interface NativeThreadSubagentWorkflowPhase {
  index: number;
  title: string;
}

export interface NativeThreadSubagentWorkflowAgent {
  index: number;
  label: string;
  agentId?: string;
  childThreadId?: string;
  state: 'queued' | 'running' | 'completed' | 'failed';
  phaseIndex?: number;
  phaseTitle?: string;
  model?: string;
  effort?: string;
  speed?: string;
  attempt?: number;
  totalTokens?: number;
  toolCalls?: number;
  durationMs?: number;
  queuedAt?: number;
  startedAt?: number;
  completedAt?: number;
  prompt?: string;
  result?: string;
}

export interface NativeThreadSubagentWorkflow {
  name?: string;
  phases: NativeThreadSubagentWorkflowPhase[];
  agents: NativeThreadSubagentWorkflowAgent[];
  totalTokens?: number;
  toolCalls?: number;
  durationMs?: number;
}

interface NativeSubagentTaskReference {
  driver: string;
  nativeId: string | null;
  strength: 'strong' | 'weak' | 'none';
}

export interface NativeThreadSubagent {
  id: string;
  threadId: string;
  runId: string | null;
  origin: 'provider_native' | 'app_owned';
  driver: string;
  providerInstanceId: string;
  nativeTaskRef: NativeSubagentTaskReference | null;
  childThreadId: string | null;
  remoteChild?: NativeThreadRemoteSubagent;
  prompt: string;
  title: string | null;
  model: string | null;
  executedModel?: string;
  status: NativeThreadSubagentStatus;
  progress?: string;
  workflow?: NativeThreadSubagentWorkflow;
  result: string | null;
  startedAt: string | null;
  completedAt: string | null;
  updatedAt: string;
  promptOmitted?: boolean;
  resultOmitted?: boolean;
}

export interface NativeThreadTurnSubagents {
  runId: string | null;
  turnActive: boolean;
  latestTurn: boolean;
  showPill: boolean;
  subagents: NativeThreadSubagent[];
  liveCount: number;
  settledCount: number;
}

const ACTIVE_RUN_STATUSES = new Set<string>(['preparing', 'starting', 'running', 'waiting']);
const LIVE_AGENT_STATUSES = new Set<string>(['pending', 'running', 'waiting']);
const SETTLED_AGENT_STATUSES = new Set<string>(['completed', 'failed', 'cancelled', 'interrupted']);

function agentIdentifier(value?: string | null): boolean {
  return typeof value === 'string' && value.length > 0 && value.trim() === value && !/[\u0000-\u001f\u007f]/.test(value);
}

export function threadSubagentIsLive(status: NativeThreadSubagentStatus): boolean {
  return LIVE_AGENT_STATUSES.has(status);
}

export class ThreadAgentsProjection {
  private readonly threadId: string;
  private readonly agents = new Map<string, NativeThreadSubagent>();
  private cached: NativeThreadTurnSubagents | undefined = undefined;
  private dirty: boolean = true;

  constructor(threadId: string) {
    this.threadId = threadId;
  }

  reset(items?: Object[]): void {
    this.agents.clear();
    this.invalidate();
    if (Array.isArray(items)) {
      for (const value of items) this.update(value);
    }
  }

  invalidate(): void {
    this.dirty = true;
  }

  update(value: Object): boolean {
    const agent = value as NativeThreadSubagent;
    if (!agent || agent.threadId !== this.threadId || !agentIdentifier(agent.id) ||
      (agent.runId !== null && !agentIdentifier(agent.runId)) || !Number.isFinite(Date.parse(agent.updatedAt)) ||
      (agent.origin !== 'provider_native' && agent.origin !== 'app_owned') ||
      (agent.status !== 'idle' && !threadSubagentIsLive(agent.status) && !SETTLED_AGENT_STATUSES.has(agent.status)) ||
      typeof agent.prompt !== 'string' || (agent.result !== null && typeof agent.result !== 'string')) return false;
    const previous = this.agents.get(agent.id);
    if (previous && Date.parse(agent.updatedAt) < Date.parse(previous.updatedAt)) return false;
    const next: NativeThreadSubagent = {
      id: agent.id, threadId: agent.threadId, runId: agent.runId, origin: agent.origin, driver: agent.driver,
      providerInstanceId: agent.providerInstanceId, nativeTaskRef: agent.nativeTaskRef,
      childThreadId: agent.childThreadId, remoteChild: agent.remoteChild, prompt: agent.prompt, title: agent.title,
      model: agent.model, executedModel: agent.executedModel, status: agent.status, progress: agent.progress,
      workflow: agent.workflow, result: agent.result, startedAt: agent.startedAt, completedAt: agent.completedAt,
      updatedAt: agent.updatedAt, promptOmitted: agent.promptOmitted, resultOmitted: agent.resultOmitted,
    };
    if (typeof next.startedAt !== 'string' || !Number.isFinite(Date.parse(next.startedAt))) next.startedAt = null;
    if (typeof next.completedAt !== 'string' || !Number.isFinite(Date.parse(next.completedAt))) next.completedAt = null;
    if (!agentIdentifier(next.childThreadId) || next.childThreadId === this.threadId) next.childThreadId = null;
    const remote = next.remoteChild;
    if (remote && (!agentIdentifier(remote.environmentId) || !agentIdentifier(remote.threadId) ||
      typeof remote.label !== 'string')) next.remoteChild = undefined;
    if (next.workflow && (!Array.isArray(next.workflow.phases) || !Array.isArray(next.workflow.agents))) {
      next.workflow = undefined;
    }
    if (agent.promptOmitted === true) {
      next.prompt = previous?.prompt ?? '';
      next.promptOmitted = previous && previous.promptOmitted !== true ? undefined : true;
    }
    if (agent.resultOmitted === true) {
      next.result = previous?.result ?? null;
      next.resultOmitted = previous && previous.resultOmitted !== true ? undefined : true;
    }
    this.agents.set(agent.id, next);
    this.invalidate();
    return true;
  }

  view(runs: Iterable<NativeThreadSubagentRun>): NativeThreadTurnSubagents | undefined {
    if (!this.dirty) return this.cached;
    this.dirty = false;
    this.cached = undefined;
    if (this.agents.size === 0) return undefined;

    const rolledBack = new Set<string>();
    let latestStarted: NativeThreadSubagentRun | undefined;
    let activeRunId: string | undefined;
    for (const run of runs) {
      if (run.status === 'rolled_back') {
        rolledBack.add(run.id);
        continue;
      }
      if (ACTIVE_RUN_STATUSES.has(run.status)) activeRunId = run.id;
      if (run.startedAt && (latestStarted === undefined || run.ordinal > latestStarted.ordinal)) latestStarted = run;
    }
    const eligible = Array.from(this.agents.values()).filter((agent: NativeThreadSubagent) =>
      agent.runId === null || !rolledBack.has(agent.runId));
    if (!eligible.length) return undefined;
    let latestUpdated = eligible[0];
    for (const agent of eligible) {
      if (Date.parse(agent.updatedAt) > Date.parse(latestUpdated.updatedAt)) latestUpdated = agent;
    }
    const latestStartedId = latestStarted?.id;
    const latestAgentRunId = latestStartedId !== undefined &&
      eligible.some((agent: NativeThreadSubagent) => agent.runId === latestStartedId) ? latestStartedId : undefined;
    const runId = activeRunId ?? latestAgentRunId ?? latestUpdated.runId;
    const subagents = eligible.filter((agent: NativeThreadSubagent) =>
      agent.runId === runId || threadSubagentIsLive(agent.status) || agent.workflow !== undefined);
    if (!subagents.length) return undefined;
    subagents.sort((left: NativeThreadSubagent, right: NativeThreadSubagent) =>
      Date.parse(left.startedAt ?? left.updatedAt) - Date.parse(right.startedAt ?? right.updatedAt) || left.id.localeCompare(right.id));
    let liveCount = 0;
    let settledCount = 0;
    for (const agent of subagents) {
      if (threadSubagentIsLive(agent.status)) liveCount++;
      else if (SETTLED_AGENT_STATUSES.has(agent.status)) settledCount++;
    }
    const turnActive = activeRunId !== undefined;
    const latestTurn = runId === null || latestStartedId === undefined || runId === latestStartedId;
    const showPill = turnActive || latestTurn || liveCount > 0 ||
      subagents.some((agent: NativeThreadSubagent) => agent.workflow !== undefined);
    this.cached = { runId, turnActive, latestTurn, showPill, subagents, liveCount, settledCount };
    return this.cached;
  }
}
