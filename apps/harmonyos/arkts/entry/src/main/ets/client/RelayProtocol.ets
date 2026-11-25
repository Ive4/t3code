import { url, util } from '@kit.ArkTS';

export const RELAY_CONNECT_SCOPE = 'environment:connect';
export const RELAY_STATUS_SCOPES = 'environment:status environment:connect';
export const ACCESS_TOKEN_TYPE = 'urn:ietf:params:oauth:token-type:access_token';
export const JWT_TOKEN_TYPE = 'urn:ietf:params:oauth:token-type:jwt';
export const ENVIRONMENT_BOOTSTRAP_TYPE = 'urn:t3:params:oauth:token-type:environment-bootstrap';

const BASE64URL_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
const PAIRING_CODE_ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

type RelayStatus = 'online' | 'offline';
export type RelayAvailability = 'checking' | RelayStatus | 'error';

export interface RelayEndpoint {
  httpBaseUrl: string;
  wsBaseUrl: string;
  providerKind: 'manual' | 'cloudflare_tunnel' | 't3_relay';
}

export interface RelayEnvironment {
  environmentId: string;
  label: string;
  endpoint: RelayEndpoint;
  linkedAt: string;
  availability: RelayAvailability;
}

export interface RelayDescriptor {
  environmentId: string;
  label: string;
  orchestrationProtocolVersion?: number;
}

export interface RelayBootstrap {
  environmentId: string;
  endpoint: RelayEndpoint;
  credential: string;
  expiresAt: string;
}

export interface RelayAccessGrant {
  token: string;
  expiresAt: number;
}

export interface DeviceApprovalRequest {
  pairingLinkId: string;
  verificationCode: string;
  deviceLabel: string;
  createdAt: string;
}

export type DeviceApprovalOutcome = 'done' | 'gone';

interface ApprovalDevice {
  label?: string;
  browser?: string;
  os?: string;
}

interface PairingLink {
  id: string;
  createdAt: string;
  connectDeviceRequest?: ConnectDeviceRequest;
}

interface ConnectDeviceRequest {
  verificationCode: string;
  client?: ApprovalDevice;
}

interface AccessSnapshotPayload {
  pairingLinks: PairingLink[];
}

interface AccessSnapshotEvent {
  version: number;
  type: string;
  revision: number;
  payload: AccessSnapshotPayload;
}

interface DeviceApprovalResponse {
  approved?: boolean;
  revoked?: boolean;
}

interface RelayAccessResponse {
  access_token: string;
  expires_in: number;
  issued_token_type: string;
  token_type: string;
  scope: string;
}

interface RelayListResponse {
  environments: RelayEnvironment[];
}

interface RelayUnlinkResponse {
  ok: boolean;
}

interface RelayStatusResponse {
  environmentId: string;
  endpoint: RelayEndpoint;
  status: 'online' | 'offline';
  checkedAt: string;
  descriptor?: RelayDescriptor;
}

interface RelayTicketResponse {
  ticket: string;
  expiresAt: string;
}

interface RelayAccountClaims {
  sub?: string;
}

function validText(value: string | undefined): boolean {
  return typeof value === 'string' && value.length > 0 && value.trim() === value;
}

function validCredential(value: string): boolean {
  return typeof value === 'string' && /^[\x21-\x7e]+$/.test(value);
}

// Match connectDeviceVerificationCode in the environment auth contract.
export function connectDeviceVerificationCode(proofKeyThumbprint: string): string {
  let code = '';
  for (const character of proofKeyThumbprint.slice(0, 8)) {
    const value = Math.max(0, BASE64URL_ALPHABET.indexOf(character));
    code += PAIRING_CODE_ALPHABET.charAt(value % PAIRING_CODE_ALPHABET.length);
  }
  return code.slice(0, 4) + '-' + code.slice(4);
}

export function normalizeDeviceVerificationCode(code: string): string {
  return code.toUpperCase().replace(/[^0-9A-Z]/g, '');
}

function describeApprovalDevice(device?: ApprovalDevice): string {
  if (device?.label && validText(device.label)) return device.label;
  if (device?.browser && validText(device.browser)) {
    return device.os && validText(device.os) ? device.browser + ' · ' + device.os : device.browser;
  }
  return device?.os && validText(device.os) ? device.os : '新设备';
}

export function readDeviceApprovalRequest(value: Object): DeviceApprovalRequest | undefined {
  const link = value as PairingLink;
  const device = link?.connectDeviceRequest;
  if (device === undefined) return undefined;
  if (!device || !validText(link.id) || !validText(device.verificationCode) ||
    !validText(link.createdAt) || !Number.isFinite(Date.parse(link.createdAt))) {
    throw new Error('环境返回的设备申请无效。');
  }
  return { pairingLinkId: link.id, verificationCode: device.verificationCode,
    deviceLabel: describeApprovalDevice(device.client), createdAt: link.createdAt };
}

export function readDeviceApprovalSnapshot(value: Object): DeviceApprovalRequest[] {
  const event = value as AccessSnapshotEvent;
  if (event?.version !== 1 || event.type !== 'snapshot' || !Number.isSafeInteger(event.revision) ||
    !Array.isArray(event.payload?.pairingLinks)) {
    throw new Error('环境返回的设备申请列表无效。');
  }
  const seen = new Set<string>();
  const requests: DeviceApprovalRequest[] = [];
  for (const link of event.payload.pairingLinks) {
    const request = readDeviceApprovalRequest(link);
    if (!request) continue;
    if (seen.has(request.pairingLinkId)) throw new Error('环境返回的设备申请无效。');
    seen.add(request.pairingLinkId);
    requests.push(request);
  }
  return requests.sort((left: DeviceApprovalRequest, right: DeviceApprovalRequest) =>
    Date.parse(left.createdAt) - Date.parse(right.createdAt));
}

export function readDeviceApprovalOutcome(value: Object, approve: boolean): DeviceApprovalOutcome {
  const response = value as DeviceApprovalResponse;
  const result = approve ? response?.approved : response?.revoked;
  if (typeof result !== 'boolean') throw new Error('环境返回的设备审批结果无效。');
  return result ? 'done' : 'gone';
}

function secureAddress(value: string, protocol: 'https:' | 'wss:'): url.URL {
  if (!validText(value) || /[\\#?\s]/.test(value) || !value.toLowerCase().startsWith(protocol + '//')) {
    throw new Error('T3 Connect 地址无效。');
  }
  let address: url.URL;
  try {
    address = url.URL.parseURL(value);
  } catch (error) {
    throw new Error('T3 Connect 地址无效。');
  }
  if (address.protocol !== protocol || !address.hostname || address.username || address.password) {
    throw new Error('T3 Connect 地址无效。');
  }
  return address;
}

export function secureRelayOrigin(value: string): string {
  const trimmed = value.trim();
  if (!/^https:\/\/[^/@]+\/*$/i.test(trimmed)) throw new Error('T3 Connect 中继地址必须是 HTTPS 源地址。');
  return 'https://' + secureAddress(trimmed, 'https:').host;
}

export function relayAccountId(token: string): string {
  if (validCredential(token)) {
    const parts = token.split('.');
    if (parts.length === 3 && parts[0] && /^[A-Za-z0-9_-]+$/.test(parts[1]) && parts[1].length % 4 !== 1 && parts[2]) {
      try {
        const payload = parts[1].padEnd(Math.ceil(parts[1].length / 4) * 4, '=');
        const bytes = new util.Base64Helper().decodeSync(payload, util.Type.BASIC_URL_SAFE);
        const claims = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(bytes)) as RelayAccountClaims;
        if (claims?.sub && validText(claims.sub)) return claims.sub;
      } catch (error) {
        throw new Error('T3 账号凭据无效。');
      }
    }
  }
  throw new Error('T3 账号凭据无效。');
}

function validateEndpoint(endpoint: RelayEndpoint): void {
  if (!endpoint || (endpoint.providerKind !== 'manual' && endpoint.providerKind !== 'cloudflare_tunnel' &&
    endpoint.providerKind !== 't3_relay')) {
    throw new Error('T3 Connect 返回的环境线路无效。');
  }
  secureRelayOrigin(endpoint.httpBaseUrl);
  secureAddress(endpoint.wsBaseUrl, 'wss:');
}

export function readRelayEnvironments(value: Object): RelayEnvironment[] {
  const response = value as RelayListResponse;
  if (!response || !Array.isArray(response.environments)) throw new Error('T3 Connect 返回的环境列表无效。');
  const seen = new Set<string>();
  return response.environments.map((environment: RelayEnvironment): RelayEnvironment => {
    if (!environment || !validText(environment.environmentId) || !validText(environment.label) ||
      !validText(environment.linkedAt) || seen.has(environment.environmentId)) {
      throw new Error('T3 Connect 返回的环境记录无效。');
    }
    validateEndpoint(environment.endpoint);
    seen.add(environment.environmentId);
    const row: RelayEnvironment = { environmentId: environment.environmentId, label: environment.label, endpoint: environment.endpoint,
      linkedAt: environment.linkedAt, availability: 'checking' };
    return row;
  });
}

export function readRelayUnlinkResponse(value: Object): void {
  const response = value as RelayUnlinkResponse;
  if (typeof response?.ok !== 'boolean') throw new Error('T3 Connect 返回的注销结果无效。');
}

export function readRelayStatus(value: Object, environment: RelayEnvironment): RelayStatus {
  const response = value as RelayStatusResponse;
  if (!response || response.environmentId !== environment.environmentId ||
    (response.status !== 'online' && response.status !== 'offline') || !validText(response.checkedAt) ||
    (response.descriptor !== undefined && response.descriptor?.environmentId !== environment.environmentId)) {
    throw new Error('T3 Connect 返回的环境状态无效。');
  }
  validateEndpoint(response.endpoint);
  if (response.endpoint.httpBaseUrl !== environment.endpoint.httpBaseUrl ||
    response.endpoint.wsBaseUrl !== environment.endpoint.wsBaseUrl ||
    response.endpoint.providerKind !== environment.endpoint.providerKind) {
    throw new Error('T3 Connect 返回的环境线路不匹配。');
  }
  return response.status;
}

export function readRelayBootstrap(value: Object, environmentId: string): RelayBootstrap {
  const response = value as RelayBootstrap;
  if (!response || response.environmentId !== environmentId || !validCredential(response.credential) ||
    !validText(response.expiresAt)) {
    throw new Error('T3 Connect 返回的连接凭据无效。');
  }
  validateEndpoint(response.endpoint);
  return response;
}

export function readRelayDescriptor(value: Object, environmentId: string): RelayDescriptor {
  const descriptor = value as RelayDescriptor;
  if (!descriptor || descriptor.environmentId !== environmentId || !validText(descriptor.label) ||
    (descriptor.orchestrationProtocolVersion !== undefined &&
      !Number.isInteger(descriptor.orchestrationProtocolVersion))) {
    throw new Error('隧道返回的环境与中继记录不匹配。');
  }
  return descriptor;
}

export function readDpopGrant(value: Object, issuedAt: number, expectedScope?: string): RelayAccessGrant {
  const response = value as RelayAccessResponse;
  const expiresAt = issuedAt + response?.expires_in * 1000;
  if (!response || !validCredential(response.access_token) || response.token_type !== 'DPoP' ||
    response.issued_token_type !== ACCESS_TOKEN_TYPE || !Number.isSafeInteger(response.expires_in) ||
    response.expires_in <= 0 || !Number.isSafeInteger(expiresAt) || !validText(response.scope)) {
    throw new Error('T3 Connect 返回的 DPoP 凭据无效。');
  }
  if (expectedScope !== undefined) {
    const expected = expectedScope.split(' ');
    const granted = new Set<string>(response.scope.split(' '));
    if (expected.length !== granted.size || expected.some((scope: string) => !granted.has(scope))) {
      throw new Error('T3 Connect 返回的权限范围不匹配。');
    }
  }
  return { token: response.access_token, expiresAt };
}

export function readRelayTicket(value: Object): string {
  const response = value as RelayTicketResponse;
  if (!response || !validCredential(response.ticket) || !validText(response.expiresAt)) {
    throw new Error('环境未返回有效的会话连接凭据。');
  }
  return response.ticket;
}

export function tokenExchangeBody(subject: string, subjectType: string): string {
  return 'grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Atoken-exchange&subject_token=' +
    encodeURIComponent(subject) + '&subject_token_type=' + encodeURIComponent(subjectType) +
    '&requested_token_type=' + encodeURIComponent(ACCESS_TOKEN_TYPE);
}

export function relaySocketTarget(endpoint: RelayEndpoint): string {
  const socket = secureAddress(endpoint.wsBaseUrl, 'wss:');
  const path = socket.pathname === '' || socket.pathname === '/' ? '/ws' : socket.pathname;
  return 'wss://' + socket.host + path;
}
