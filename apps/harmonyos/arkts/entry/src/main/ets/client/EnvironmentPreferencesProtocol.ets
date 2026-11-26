export type DefaultThreadEnvMode = 'local' | 'worktree';
export type DefaultRuntimeMode = 'approval-required' | 'auto-accept-edits' | 'auto' | 'full-access';
export type ResponseStreamingMode = 'turn' | 'paragraph';
export type WorktreeSubmodulesMode = 'recursive' | 'top-level' | 'none';

export interface ThreadPreferencesSnapshot {
  defaultThreadEnvMode: DefaultThreadEnvMode | null;
  defaultRuntimeMode: DefaultRuntimeMode;
  responseStreamingMode: ResponseStreamingMode;
  enableAgentBrowserAccess: boolean;
  autoResumeLimitedThreads: boolean;
  snoozeLimitedThreads: boolean;
  sidebarAutoSettleOnMerge: boolean;
  sidebarAutoSettleAfterDays: number | null;
}

export interface SourceControlPreferencesSnapshot {
  removeAgentCreditsOnMerge: boolean;
  defaultAutoPull: boolean;
  ghqCloneLayout: boolean;
}

export interface WorktreesPreferencesSnapshot {
  newWorktreesStartFromOrigin: boolean;
  worktreeSubmodules: WorktreeSubmodulesMode | null;
}

export interface MaintenancePreferencesSnapshot {
  enableProviderUpdateChecks: boolean;
  continueThreadsAfterServerUpdate: boolean;
  keepAwakeWhileAgentsWork: boolean;
}

export interface LabsPreferencesSnapshot {
  fastWorktreeCheckout: boolean;
  guestSharingEnabled: boolean;
  linkedEnvironmentsEnabled: boolean;
  workflowsEnabled: boolean;
  promptSuggestionsEnabled: boolean;
  simlockDeviceHostsEnabled: boolean;
}

export interface EnvironmentPreferencesSnapshot {
  threadPreferences: ThreadPreferencesSnapshot;
  sourceControl: SourceControlPreferencesSnapshot;
  worktrees: WorktreesPreferencesSnapshot;
  maintenance: MaintenancePreferencesSnapshot;
  labs: LabsPreferencesSnapshot;
}

export interface EnvironmentSettingsPatchParams {
  patch: Record<string, Object | null>;
}

export interface EnvironmentSettingsPatchRequest {
  method: string;
  params: EnvironmentSettingsPatchParams;
}

const SERVER_UPDATE_SETTINGS_METHOD = 'server.updateSettings';
const DEFAULT_SIDEBAR_AUTO_SETTLE_AFTER_DAYS = 7;
const MIN_SIDEBAR_AUTO_SETTLE_AFTER_DAYS = 1;
const MAX_SIDEBAR_AUTO_SETTLE_AFTER_DAYS = 90;

const THREAD_ENV_MODES: readonly DefaultThreadEnvMode[] = ['local', 'worktree'];
const RUNTIME_MODES: readonly DefaultRuntimeMode[] = [
  'approval-required',
  'auto-accept-edits',
  'auto',
  'full-access',
];
const RESPONSE_STREAMING_MODES: readonly ResponseStreamingMode[] = ['turn', 'paragraph'];
const WORKTREE_SUBMODULES_MODES: readonly WorktreeSubmodulesMode[] = [
  'recursive',
  'top-level',
  'none',
];

const BOOLEAN_SETTING_KEYS: readonly string[] = [
  'enableAgentBrowserAccess',
  'autoResumeLimitedThreads',
  'snoozeLimitedThreads',
  'sidebarAutoSettleOnMerge',
  'removeAgentCreditsOnMerge',
  'defaultAutoPull',
  'ghqCloneLayout',
  'newWorktreesStartFromOrigin',
  'enableProviderUpdateChecks',
  'continueThreadsAfterServerUpdate',
  'keepAwakeWhileAgentsWork',
  'fastWorktreeCheckout',
  'guestSharingEnabled',
  'linkedEnvironmentsEnabled',
  'workflowsEnabled',
  'promptSuggestionsEnabled',
  'simlockDeviceHostsEnabled',
];

function asRecord(value?: Object | null): Record<string, Object | null | undefined> | undefined {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return undefined;
  }
  return value as Record<string, Object | null | undefined>;
}

function readBoolean(
  settings: Record<string, Object | null | undefined> | undefined,
  key: string,
  fallback: boolean,
): boolean {
  const value = settings ? settings[key] : undefined;
  return typeof value === 'boolean' ? value : fallback;
}

function readLiteral<T extends string>(
  settings: Record<string, Object | null | undefined> | undefined,
  key: string,
  allowed: readonly T[],
  fallback: T,
): T {
  const value = settings ? settings[key] : undefined;
  if (typeof value === 'string' && allowed.includes(value as T)) {
    return value as T;
  }
  return fallback;
}

function readNullableLiteral<T extends string>(
  settings: Record<string, Object | null | undefined> | undefined,
  key: string,
  allowed: readonly T[],
): T | null {
  const value = settings ? settings[key] : undefined;
  if (typeof value === 'string' && allowed.includes(value as T)) {
    return value as T;
  }
  return null;
}

function isValidSidebarAutoSettleDays(value: Object | null | undefined): boolean {
  return (
    typeof value === 'number' &&
    Number.isFinite(value) &&
    value >= MIN_SIDEBAR_AUTO_SETTLE_AFTER_DAYS &&
    value <= MAX_SIDEBAR_AUTO_SETTLE_AFTER_DAYS
  );
}

function readSidebarAutoSettleAfterDays(
  settings: Record<string, Object | null | undefined> | undefined,
): number | null {
  if (!settings || !Object.keys(settings).includes('sidebarAutoSettleAfterDays')) {
    return DEFAULT_SIDEBAR_AUTO_SETTLE_AFTER_DAYS;
  }
  const value = settings.sidebarAutoSettleAfterDays;
  if (value === null) {
    return null;
  }
  if (isValidSidebarAutoSettleDays(value)) {
    return value as number;
  }
  return DEFAULT_SIDEBAR_AUTO_SETTLE_AFTER_DAYS;
}

export function readEnvironmentPreferences(config?: Object | null): EnvironmentPreferencesSnapshot {
  const root = asRecord(config);
  const settings = root && asRecord(root.settings) ? asRecord(root.settings) : root;

  return {
    threadPreferences: {
      defaultThreadEnvMode: readNullableLiteral(settings, 'defaultThreadEnvMode', THREAD_ENV_MODES),
      defaultRuntimeMode: readLiteral(settings, 'defaultRuntimeMode', RUNTIME_MODES, 'full-access'),
      responseStreamingMode: readLiteral(
        settings,
        'responseStreamingMode',
        RESPONSE_STREAMING_MODES,
        'paragraph',
      ),
      enableAgentBrowserAccess: readBoolean(settings, 'enableAgentBrowserAccess', true),
      autoResumeLimitedThreads: readBoolean(settings, 'autoResumeLimitedThreads', false),
      snoozeLimitedThreads: readBoolean(settings, 'snoozeLimitedThreads', false),
      sidebarAutoSettleOnMerge: readBoolean(settings, 'sidebarAutoSettleOnMerge', true),
      sidebarAutoSettleAfterDays: readSidebarAutoSettleAfterDays(settings),
    },
    sourceControl: {
      removeAgentCreditsOnMerge: readBoolean(settings, 'removeAgentCreditsOnMerge', false),
      defaultAutoPull: readBoolean(settings, 'defaultAutoPull', false),
      ghqCloneLayout: readBoolean(settings, 'ghqCloneLayout', false),
    },
    worktrees: {
      newWorktreesStartFromOrigin: readBoolean(settings, 'newWorktreesStartFromOrigin', true),
      worktreeSubmodules: readNullableLiteral(
        settings,
        'worktreeSubmodules',
        WORKTREE_SUBMODULES_MODES,
      ),
    },
    maintenance: {
      enableProviderUpdateChecks: readBoolean(settings, 'enableProviderUpdateChecks', true),
      continueThreadsAfterServerUpdate: readBoolean(
        settings,
        'continueThreadsAfterServerUpdate',
        true,
      ),
      keepAwakeWhileAgentsWork: readBoolean(settings, 'keepAwakeWhileAgentsWork', true),
    },
    labs: {
      fastWorktreeCheckout: readBoolean(settings, 'fastWorktreeCheckout', false),
      guestSharingEnabled: readBoolean(settings, 'guestSharingEnabled', false),
      linkedEnvironmentsEnabled: readBoolean(settings, 'linkedEnvironmentsEnabled', false),
      workflowsEnabled: readBoolean(settings, 'workflowsEnabled', false),
      promptSuggestionsEnabled: readBoolean(settings, 'promptSuggestionsEnabled', false),
      simlockDeviceHostsEnabled: readBoolean(settings, 'simlockDeviceHostsEnabled', false),
    },
  };
}

export function buildEnvironmentSettingsPatchRequest(
  rawPatch: Record<string, Object | null | undefined>,
): EnvironmentSettingsPatchRequest {
  const input = asRecord(rawPatch);
  if (!input) {
    throw new Error('环境设置补丁必须为对象。');
  }

  const patch: Record<string, Object | null> = {};
  const keys = Object.keys(input);
  for (const key of keys) {
    const value = input[key];
    if (value === undefined) {
      continue;
    }

    if (BOOLEAN_SETTING_KEYS.includes(key)) {
      if (typeof value !== 'boolean') {
        throw new Error(`设置项 ${key} 需要布尔值。`);
      }
      patch[key] = value;
      continue;
    }

    switch (key) {
      case 'defaultThreadEnvMode':
        if (value !== null && (typeof value !== 'string' || !THREAD_ENV_MODES.includes(value as DefaultThreadEnvMode))) {
          throw new Error('无效的默认工作区模式。');
        }
        patch[key] = value;
        break;
      case 'defaultRuntimeMode':
        if (typeof value !== 'string' || !RUNTIME_MODES.includes(value as DefaultRuntimeMode)) {
          throw new Error('无效的默认权限模式。');
        }
        patch[key] = value;
        break;
      case 'responseStreamingMode':
        if (
          typeof value !== 'string' ||
          !RESPONSE_STREAMING_MODES.includes(value as ResponseStreamingMode)
        ) {
          throw new Error('无效的回复流式显示模式。');
        }
        patch[key] = value;
        break;
      case 'sidebarAutoSettleAfterDays':
        if (value !== null && !isValidSidebarAutoSettleDays(value)) {
          throw new Error('无效的自动收尾天数。');
        }
        patch[key] = value;
        break;
      case 'worktreeSubmodules':
        if (
          value !== null &&
          (typeof value !== 'string' || !WORKTREE_SUBMODULES_MODES.includes(value as WorktreeSubmodulesMode))
        ) {
          throw new Error('无效的工作树子模块模式。');
        }
        patch[key] = value;
        break;
      default:
        throw new Error(`不支持的环境设置项: ${key}`);
    }
  }

  if (Object.keys(patch).length === 0) {
    throw new Error('环境设置补丁不能为空。');
  }

  return {
    method: SERVER_UPDATE_SETTINGS_METHOD,
    params: { patch },
  };
}
