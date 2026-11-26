import { validProviderInstanceId } from './T3Protocol';

export type NativeProviderAuthStatus = 'authenticated' | 'unauthenticated' | 'unknown';
export type NativeProviderAvailability = 'available' | 'unavailable';

export interface NativeProviderSummary {
  instanceId: string;
  driver: string;
  displayName: string;
  installed: boolean;
  enabled: boolean;
  authStatus: NativeProviderAuthStatus;
  availability: NativeProviderAvailability;
  status?: string;
  version?: string | null;
  message?: string;
}

export interface ProviderInstanceEnabledPatchEntry {
  driver: string;
  enabled: boolean;
}

export interface ProviderEnabledPatch {
  providerInstances: Record<string, ProviderInstanceEnabledPatchEntry>;
}

export interface ProviderEnabledPatchParams {
  patch: ProviderEnabledPatch;
}

export interface ProviderEnabledPatchRequest {
  method: string;
  params: ProviderEnabledPatchParams;
}

interface ProviderAuthWire {
  status?: string;
}

interface ProviderWire {
  instanceId?: string;
  driver?: string;
  displayName?: string;
  installed?: boolean;
  enabled?: boolean;
  status?: string;
  availability?: string;
  version?: string | null;
  message?: string;
  auth?: ProviderAuthWire;
}

interface ServerConfigWire {
  providers?: ProviderWire[];
}

function nonBlank(value: string | null | undefined): boolean {
  return typeof value === 'string' && value.trim().length > 0;
}

function readAuthStatus(auth: ProviderAuthWire | undefined): NativeProviderAuthStatus {
  const status = auth?.status;
  if (status === 'authenticated' || status === 'unauthenticated' || status === 'unknown') {
    return status;
  }
  return 'unknown';
}

function readAvailability(availability: string | undefined): NativeProviderAvailability {
  return availability === 'unavailable' ? 'unavailable' : 'available';
}

export function readProvidersSummary(config?: Object | null): NativeProviderSummary[] {
  const wire = config as ServerConfigWire | null | undefined;
  if (!wire || typeof wire !== 'object' || !Array.isArray(wire.providers)) {
    return [];
  }
  const result: NativeProviderSummary[] = [];
  for (const item of wire.providers) {
    if (!item || typeof item !== 'object' || !validProviderInstanceId(item.instanceId)) {
      continue;
    }
    const instanceId = item.instanceId!.trim();
    const driver = nonBlank(item.driver) ? item.driver!.trim() : instanceId;
    const displayName = nonBlank(item.displayName) ? item.displayName!.trim() : instanceId;
    const installed = item.installed === true;
    const enabled = item.enabled === true && item.status !== 'disabled';
    const summary: NativeProviderSummary = {
      instanceId,
      driver,
      displayName,
      installed,
      enabled,
      authStatus: readAuthStatus(item.auth),
      availability: readAvailability(item.availability),
    };
    if (nonBlank(item.status)) {
      summary.status = item.status!.trim();
    }
    if (item.version === null || nonBlank(item.version)) {
      summary.version = item.version === null ? null : item.version!.trim();
    }
    if (nonBlank(item.message)) {
      summary.message = item.message!.trim();
    }
    result.push(summary);
  }
  return result;
}

export function buildProviderEnabledPatchRequest(
  instanceId: string,
  enabled: boolean,
  driver?: string,
): ProviderEnabledPatchRequest {
  const trimmedId = typeof instanceId === 'string' ? instanceId.trim() : '';
  if (!validProviderInstanceId(trimmedId)) {
    throw new Error('无效的 Provider 实例标识。');
  }
  const resolvedDriver = nonBlank(driver) ? driver!.trim() : trimmedId;
  if (!validProviderInstanceId(resolvedDriver)) {
    throw new Error('无效的 Provider 驱动标识。');
  }
  const providerInstances: Record<string, ProviderInstanceEnabledPatchEntry> = {};
  providerInstances[trimmedId] = {
    driver: resolvedDriver,
    enabled: enabled === true,
  };
  return {
    method: 'server.updateSettings',
    params: {
      patch: {
        providerInstances,
      },
    },
  };
}
