import { parseThreadLink } from './ThreadLinkProtocol';

export type PushRegistrationStatus =
  | 'disabled'
  | 'registering'
  | 'registered'
  | 'permission-denied'
  | 'account-required'
  | 'error';

export type AgentNotificationKind =
  | 'turn-complete'
  | 'approval-required'
  | 'error'
  | 'ongoing';

export interface HarmonyPushDeviceRegistration {
  pushToken: string;
  huaweiAccountOpenId?: string;
  deviceName: string;
  environmentIds: string[];
  liveActivityEnabled: boolean;
}

export interface AgentNotificationPayload {
  title: string;
  text: string;
  environmentId: string;
  threadId: string;
  kind: AgentNotificationKind;
}

export interface NotificationLaunchLink {
  environmentId: string;
  threadId: string;
}

interface NormalizedPushRegistrationBody {
  pushToken: string;
  huaweiAccountOpenId?: string;
  deviceName: string;
  environmentIds: string[];
  liveActivityEnabled: boolean;
}

const CONTROL_CHARACTER = /[\u0000-\u001f\u007f]/;

function readCleanIdentifier(value: Object | undefined): string | null {
  if (typeof value !== 'string' || CONTROL_CHARACTER.test(value)) {
    return null;
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return null;
  }
  return trimmed;
}

function readLinkFromUriParam(value: Object | undefined): NotificationLaunchLink | null {
  if (typeof value !== 'string') {
    return null;
  }
  const parsed = parseThreadLink(value.trim());
  if (!parsed) {
    return null;
  }
  return {
    environmentId: parsed.environmentId,
    threadId: parsed.threadId,
  };
}

export function parseNotificationLaunchLink(
  wantParams: Record<string, Object | undefined>,
): NotificationLaunchLink | null {
  if (!wantParams || typeof wantParams !== 'object' || Array.isArray(wantParams)) {
    return null;
  }

  const environmentId = readCleanIdentifier(wantParams['environmentId']);
  const threadId = readCleanIdentifier(wantParams['threadId']);
  if (environmentId !== null && threadId !== null) {
    return { environmentId, threadId };
  }

  const uriKeys = ['threadLink', 'uri', 'link', 'url'];
  for (const key of uriKeys) {
    const parsed = readLinkFromUriParam(wantParams[key]);
    if (parsed !== null) {
      return parsed;
    }
  }

  return null;
}

function requireNonEmptyText(value: Object | undefined, fieldName: string): string {
  if (typeof value !== 'string' || CONTROL_CHARACTER.test(value)) {
    throw new Error(`${fieldName} must be a non-empty string.`);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    throw new Error(`${fieldName} must be a non-empty string.`);
  }
  return trimmed;
}

function normalizeEnvironmentIds(environmentIds: Object | undefined): string[] {
  if (!Array.isArray(environmentIds)) {
    throw new Error('environmentIds must be an array.');
  }
  const seen = new Set<string>();
  const normalized: string[] = [];
  for (let i = 0; i < environmentIds.length; i += 1) {
    const entry = environmentIds[i] as Object | undefined;
    const id = requireNonEmptyText(entry, `environmentIds[${i}]`);
    if (!seen.has(id)) {
      seen.add(id);
      normalized.push(id);
    }
  }
  return normalized;
}

export function buildPushRegistrationBody(input: HarmonyPushDeviceRegistration): string {
  if (!input || typeof input !== 'object') {
    throw new Error('Push registration input is required.');
  }
  const pushToken = requireNonEmptyText(input.pushToken, 'pushToken');
  const deviceName = requireNonEmptyText(input.deviceName, 'deviceName');
  const environmentIds = normalizeEnvironmentIds(input.environmentIds);
  if (typeof input.liveActivityEnabled !== 'boolean') {
    throw new Error('liveActivityEnabled must be a boolean.');
  }

  const body: NormalizedPushRegistrationBody = {
    pushToken,
    deviceName,
    environmentIds,
    liveActivityEnabled: input.liveActivityEnabled,
  };

  if (input.huaweiAccountOpenId !== undefined) {
    if (typeof input.huaweiAccountOpenId !== 'string') {
      throw new Error('huaweiAccountOpenId must be a string.');
    }
    if (CONTROL_CHARACTER.test(input.huaweiAccountOpenId)) {
      throw new Error('huaweiAccountOpenId contains invalid control characters.');
    }
    const trimmedOpenId = input.huaweiAccountOpenId.trim();
    if (trimmedOpenId.length > 0) {
      body.huaweiAccountOpenId = trimmedOpenId;
    }
  }

  return JSON.stringify(body);
}

export function formatOngoingAgentSummary(
  activeCount: number,
  title: string,
  statusText: string,
): string {
  const normalizedCount =
    typeof activeCount === 'number' && Number.isFinite(activeCount) && activeCount > 0
      ? Math.floor(activeCount)
      : 0;
  const cleanTitle = typeof title === 'string' && title.trim().length > 0 ? title.trim() : 'Agent';
  const cleanStatus = typeof statusText === 'string' ? statusText.trim() : '';

  const prefix = normalizedCount > 1 ? `${normalizedCount} active · ${cleanTitle}` : cleanTitle;
  return cleanStatus.length > 0 ? `${prefix} · ${cleanStatus}` : prefix;
}
