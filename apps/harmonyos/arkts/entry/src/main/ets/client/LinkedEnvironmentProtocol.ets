import { REQUEST_ID } from './T3Protocol';
import type { RpcExit } from './T3Protocol';

type LinkedEnvironmentStatus = 'reachable' | 'unreachable' | 'expired';

export type NativePeerLinkAccess = 'read-only' | 'approval-required' | 'auto-accept-edits' | 'auto' | 'full-access';

export interface LinkedEnvironmentCandidate {
  key: string;
  environmentId: string;
  label: string;
  origin: string;
}

export interface LinkedEnvironmentBatchResult {
  key: string;
  label: string;
  status: 'pending' | 'linking' | 'linked' | 'failed';
  message?: string;
}

export interface UnlinkEnvironmentResult {
  removed: boolean;
  endedThere?: boolean;
}

export interface NativeLinkedEnvironment {
  environmentId: string;
  label: string;
  status: LinkedEnvironmentStatus;
  expiresAtMs: number;
  lastError: string | null;
}

export interface LinkedEnvironmentHealth {
  kind: LinkedEnvironmentStatus | 'failing';
  detail?: string;
  expiresInDays?: number;
}

interface LinkedEnvironmentCapabilities {
  peerLinks?: boolean;
  peerLinkPairingCodes?: boolean;
}

interface LinkedEnvironmentConfigEnvironment {
  capabilities?: LinkedEnvironmentCapabilities;
}

interface LinkedEnvironmentSettings {
  linkedEnvironmentsEnabled?: boolean;
}

interface LinkedEnvironmentConfig {
  environment?: LinkedEnvironmentConfigEnvironment;
  settings?: LinkedEnvironmentSettings;
}

interface LinkedEnvironmentWire {
  environmentId: string;
  label: string;
  status: LinkedEnvironmentStatus;
  expiresAt: string;
  lastError: string | null;
}

interface LinkedEnvironmentListWire {
  links: LinkedEnvironmentWire[];
}

interface LinkedEnvironmentPairingInput {
  label: string;
  purpose: string;
  access: NativePeerLinkAccess;
}

interface LinkedEnvironmentPairingWire {
  purpose?: string;
  access?: NativePeerLinkAccess;
  credential?: string;
}

interface LinkedEnvironmentsRpcRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: Record<string, string | string[]>;
  headers: string[][];
}

interface LinkedThreadFailureReason {
  _tag: string;
  reason?: string;
}

interface LinkedThreadFailureCause {
  _tag: string;
  error?: LinkedThreadFailureReason;
}

interface LinkedThreadFailureExit extends RpcExit {
  cause?: LinkedThreadFailureCause[];
}

interface LinkedClientPairingWire {
  type: string;
  environmentId: string;
  urls: string[];
  credential?: string;
  expiresAt?: string;
}

export interface LinkedClientPairing {
  urls: string[];
  credential?: string;
}

export class LinkedThreadUnavailableError extends Error {
  readonly accessLost: boolean;

  constructor(message: string, accessLost: boolean) {
    super(message);
    this.accessLost = accessLost;
  }
}

const DAY_MS = 24 * 60 * 60 * 1000;
const EXPIRY_WARNING_DAYS = 5;

export const LINKED_ENVIRONMENT_PAIRING_PATH = '/api/auth/pairing-token';

export function supportsLinkedEnvironments(value?: Object): boolean {
  const config = value as LinkedEnvironmentConfig | undefined;
  return config?.environment?.capabilities?.peerLinks === true && config.settings?.linkedEnvironmentsEnabled === true;
}

export function supportsLinkedEnvironmentPairing(value?: Object): boolean {
  const config = value as LinkedEnvironmentConfig | undefined;
  return config?.environment?.capabilities?.peerLinkPairingCodes === true;
}

export function canMintLinkedEnvironmentPairing(permissions: string[] | undefined, access: NativePeerLinkAccess): boolean {
  return Array.isArray(permissions) && permissions.includes('access:write') &&
    permissions.includes('orchestration:read') &&
    (access === 'read-only' || permissions.includes('orchestration:operate')) &&
    (access !== 'full-access' ||
      (permissions.includes('settings:write') && permissions.includes('source-control:write')));
}

export function linkedEnvironmentPairingBody(access: NativePeerLinkAccess): string {
  const input: LinkedEnvironmentPairingInput = { label: 'T3 Code link', purpose: 'peer-link', access };
  return JSON.stringify(input);
}

export function readLinkedEnvironmentPairingCode(value: Object | undefined, access: NativePeerLinkAccess): string {
  const response = value as LinkedEnvironmentPairingWire | undefined;
  if (response?.purpose !== 'peer-link' || response.access !== access ||
    typeof response.credential !== 'string' || !response.credential.trim()) {
    throw new Error('目标环境未签发所选权限的关联配对码。');
  }
  return response.credential;
}

export function linkedEnvironmentsRequest(): LinkedEnvironmentsRpcRequest {
  const payload: Record<string, string | string[]> = {};
  return { _tag: 'Request', id: REQUEST_ID, tag: 'peerLinks.list', payload, headers: [] };
}

export function linkedThreadRequest(environmentId: string, threadId: string): LinkedEnvironmentsRpcRequest {
  const payload: Record<string, string | string[]> = { 'environmentId': environmentId, 'threadId': threadId };
  return { _tag: 'Request', id: REQUEST_ID, tag: 'peerLinks.subscribeThread', payload, headers: [] };
}

export function linkedThreadHistoryRequest(environmentId: string, threadId: string,
  cursor: string): LinkedEnvironmentsRpcRequest {
  const payload: Record<string, string | string[]> = {
    'environmentId': environmentId, 'threadId': threadId, 'cursor': cursor,
  };
  return { _tag: 'Request', id: REQUEST_ID, tag: 'peerLinks.threadHistoryPage', payload, headers: [] };
}

export function linkedThreadItemRequest(environmentId: string, threadId: string,
  itemId: string): LinkedEnvironmentsRpcRequest {
  const payload: Record<string, string | string[]> = {
    'environmentId': environmentId, 'threadId': threadId, 'itemId': itemId,
  };
  return { _tag: 'Request', id: REQUEST_ID, tag: 'peerLinks.threadItem', payload, headers: [] };
}

export function linkedClientPairingRequest(environmentId: string): LinkedEnvironmentsRpcRequest {
  const payload: Record<string, string | string[]> = { 'environmentId': environmentId };
  return { _tag: 'Request', id: REQUEST_ID, tag: 'peerLinks.pairClient', payload, headers: [] };
}

export function readLinkedClientPairing(value: Object | undefined, expectedEnvironmentId: string,
  now: number): LinkedClientPairing {
  const wire = value as LinkedClientPairingWire | undefined;
  if (wire?.environmentId !== expectedEnvironmentId || !Array.isArray(wire.urls) ||
    (wire.type !== 'credential' && wire.type !== 'unsupported')) {
    throw new Error('来源环境未返回所选关联环境的连接信息。');
  }
  const urls = wire.urls.filter((value: string) => typeof value === 'string' && !!value.trim());
  const expiresAt = wire.expiresAt ? Date.parse(wire.expiresAt) : 0;
  const credential = wire.type === 'credential' && typeof wire.credential === 'string' &&
    wire.credential.trim() && expiresAt > now ? wire.credential : undefined;
  return { urls, credential };
}

export function linkedThreadReadError(exit?: RpcExit): LinkedThreadUnavailableError {
  const failure = exit as LinkedThreadFailureExit | undefined;
  const causes = failure?.cause;
  const reason = Array.isArray(causes) ? causes.find((cause) => cause?._tag === 'Fail')?.error : undefined;
  if (reason?._tag === 'EnvironmentAuthorizationError') {
    return new LinkedThreadUnavailableError('当前连接缺少读取关联会话的权限。', true);
  }
  switch (reason?.reason) {
    case 'disabled':
      return new LinkedThreadUnavailableError('来源环境尚未启用关联环境。', true);
    case 'unknown_link':
    case 'expired':
    case 'rejected':
      return new LinkedThreadUnavailableError('此环境的关联已失效，请重新关联后再试。', true);
    case 'thread_not_found':
      return new LinkedThreadUnavailableError('关联环境找不到此会话。', true);
    case 'incompatible':
      return new LinkedThreadUnavailableError('请更新关联环境后重试。', false);
    default:
      return new LinkedThreadUnavailableError('无法从关联环境读取会话。', false);
  }
}

export function linkEnvironmentRequest(target: LinkedEnvironmentCandidate, pairingCode: string,
  access: NativePeerLinkAccess, alternateUrls: string[] = []): LinkedEnvironmentsRpcRequest {
  const payload: Record<string, string | string[]> = {
    'url': target.origin, 'expectedEnvironmentId': target.environmentId, 'expectedLabel': target.label,
    'pairingCode': pairingCode, 'access': access,
  };
  if (alternateUrls.length > 0) payload['alternateUrls'] = alternateUrls;
  return { _tag: 'Request', id: REQUEST_ID, tag: 'peerLinks.link', payload, headers: [] };
}

export function unlinkEnvironmentRequest(environmentId: string): LinkedEnvironmentsRpcRequest {
  const payload: Record<string, string | string[]> = { 'environmentId': environmentId };
  return { _tag: 'Request', id: REQUEST_ID, tag: 'peerLinks.unlink', payload, headers: [] };
}

export function readUnlinkEnvironmentResult(value?: Object): UnlinkEnvironmentResult {
  const response = value as UnlinkEnvironmentResult | undefined;
  if (typeof response?.removed !== 'boolean' ||
    (response.endedThere !== undefined && typeof response.endedThere !== 'boolean')) {
    throw new Error('环境未返回有效的解除关联结果。');
  }
  return response;
}

export function readLinkedEnvironments(value?: Object): NativeLinkedEnvironment[] {
  const wire = value as LinkedEnvironmentListWire | undefined;
  if (!wire || !Array.isArray(wire.links)) throw new Error('环境返回的关联环境列表无效。');
  const links: NativeLinkedEnvironment[] = [];
  for (const row of wire.links) {
    if (!row || typeof row.environmentId !== 'string' || !row.environmentId.trim() ||
      typeof row.label !== 'string' || typeof row.expiresAt !== 'string' ||
      (row.status !== 'reachable' && row.status !== 'unreachable' && row.status !== 'expired') ||
      (row.lastError !== null && typeof row.lastError !== 'string')) continue;
    const expiresAtMs = Date.parse(row.expiresAt);
    if (!Number.isFinite(expiresAtMs)) continue;
    links.push({ environmentId: row.environmentId, label: row.label, status: row.status,
      expiresAtMs, lastError: row.lastError });
  }
  return links;
}

export function linkedEnvironmentHealth(link: NativeLinkedEnvironment, nowMs: number): LinkedEnvironmentHealth {
  if (link.status === 'expired' || link.expiresAtMs <= nowMs) return { kind: 'expired' };
  if (link.status === 'unreachable') {
    return link.lastError === null ? { kind: 'unreachable' } : { kind: 'unreachable', detail: link.lastError };
  }
  if (link.lastError !== null) return { kind: 'failing', detail: link.lastError };
  const days = Math.ceil((link.expiresAtMs - nowMs) / DAY_MS);
  return days <= EXPIRY_WARNING_DAYS ? { kind: 'reachable', expiresInDays: days } : { kind: 'reachable' };
}
