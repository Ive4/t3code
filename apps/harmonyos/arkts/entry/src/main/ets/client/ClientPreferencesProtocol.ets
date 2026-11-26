export type ProjectGroupingMode = 'repository' | 'repository-path' | 'separate';

export type RunningAgentBehavior = 'queue' | 'steer';

export type ComposerReturnBehavior = 'send' | 'newline';

export interface ClientPreferencesSnapshot {
  projectGrouping: ProjectGroupingMode;
  sidebarChatsFirst: boolean;
  useLastProject: boolean;
  runningAgentBehavior: RunningAgentBehavior;
  composerReturnBehavior: ComposerReturnBehavior;
}

export type ClientPreferenceKey =
  | 'projectGrouping'
  | 'sidebarChatsFirst'
  | 'useLastProject'
  | 'runningAgentBehavior'
  | 'composerReturnBehavior';

export type ClientPreferenceValue =
  | ProjectGroupingMode
  | RunningAgentBehavior
  | ComposerReturnBehavior
  | boolean;

export interface ClientStorageSummary {
  cacheBytes: number;
  environmentCount: number;
  clearable: boolean;
}

interface RawClientPreferences {
  projectGrouping?: Object | null;
  sidebarChatsFirst?: Object | null;
  useLastProject?: Object | null;
  runningAgentBehavior?: Object | null;
  composerReturnBehavior?: Object | null;
}

export function defaultClientPreferences(): ClientPreferencesSnapshot {
  return {
    projectGrouping: 'repository',
    sidebarChatsFirst: false,
    useLastProject: true,
    runningAgentBehavior: 'queue',
    composerReturnBehavior: 'send',
  };
}

function parseProjectGrouping(value?: Object | null): ProjectGroupingMode {
  if (value === 'repository') return 'repository';
  if (value === 'repository-path') return 'repository-path';
  if (value === 'separate') return 'separate';
  return 'repository';
}

function parseRunningAgentBehavior(value?: Object | null): RunningAgentBehavior {
  if (value === 'queue') return 'queue';
  if (value === 'steer') return 'steer';
  return 'queue';
}

function parseComposerReturnBehavior(value?: Object | null): ComposerReturnBehavior {
  if (value === 'send') return 'send';
  if (value === 'newline') return 'newline';
  return 'send';
}

function parseBoolean(value: Object | null | undefined, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

export function parseClientPreferences(raw: string): ClientPreferencesSnapshot {
  const defaults = defaultClientPreferences();
  if (typeof raw !== 'string' || !raw.trim()) {
    return defaults;
  }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(raw) as Object | null;
  } catch (_) {
    return defaults;
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return defaults;
  }
  const record = parsed as RawClientPreferences;
  return {
    projectGrouping: parseProjectGrouping(record.projectGrouping),
    sidebarChatsFirst: parseBoolean(record.sidebarChatsFirst, defaults.sidebarChatsFirst),
    useLastProject: parseBoolean(record.useLastProject, defaults.useLastProject),
    runningAgentBehavior: parseRunningAgentBehavior(record.runningAgentBehavior),
    composerReturnBehavior: parseComposerReturnBehavior(record.composerReturnBehavior),
  };
}

export function serializeClientPreferences(prefs: ClientPreferencesSnapshot): string {
  const normalized: ClientPreferencesSnapshot = {
    projectGrouping: parseProjectGrouping(prefs.projectGrouping),
    sidebarChatsFirst: parseBoolean(prefs.sidebarChatsFirst, false),
    useLastProject: parseBoolean(prefs.useLastProject, true),
    runningAgentBehavior: parseRunningAgentBehavior(prefs.runningAgentBehavior),
    composerReturnBehavior: parseComposerReturnBehavior(prefs.composerReturnBehavior),
  };
  return JSON.stringify(normalized);
}

export function updateClientPreference(
  prefs: ClientPreferencesSnapshot,
  key: ClientPreferenceKey,
  value: ClientPreferenceValue,
): ClientPreferencesSnapshot {
  const next: ClientPreferencesSnapshot = {
    projectGrouping: prefs.projectGrouping,
    sidebarChatsFirst: prefs.sidebarChatsFirst,
    useLastProject: prefs.useLastProject,
    runningAgentBehavior: prefs.runningAgentBehavior,
    composerReturnBehavior: prefs.composerReturnBehavior,
  };
  if (key === 'projectGrouping') {
    next.projectGrouping = parseProjectGrouping(value as Object);
  } else if (key === 'sidebarChatsFirst') {
    next.sidebarChatsFirst = parseBoolean(value as Object, prefs.sidebarChatsFirst);
  } else if (key === 'useLastProject') {
    next.useLastProject = parseBoolean(value as Object, prefs.useLastProject);
  } else if (key === 'runningAgentBehavior') {
    next.runningAgentBehavior = parseRunningAgentBehavior(value as Object);
  } else if (key === 'composerReturnBehavior') {
    next.composerReturnBehavior = parseComposerReturnBehavior(value as Object);
  }
  return next;
}

export function formatStorageBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return '0 B';
  }
  if (bytes < 1024) {
    return `${Math.round(bytes)} B`;
  }
  const units = ['KB', 'MB', 'GB', 'TB'];
  let value = bytes / 1024;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  const formatted = value >= 10 ? value.toFixed(0) : value.toFixed(1).replace(/\.0$/, '');
  return `${formatted} ${units[unitIndex]}`;
}
