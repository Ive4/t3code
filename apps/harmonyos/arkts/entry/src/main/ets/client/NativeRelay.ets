import { http } from '@kit.NetworkKit';
import { ORCHESTRATION_PROTOCOL } from './T3Protocol';
import type { RelayAccessGrant, RelayAvailability, RelayDescriptor, RelayEndpoint, RelayEnvironment } from './RelayProtocol';
import {
  ENVIRONMENT_BOOTSTRAP_TYPE, JWT_TOKEN_TYPE, RELAY_CONNECT_SCOPE, RELAY_STATUS_SCOPES,
  connectDeviceVerificationCode,
  readDpopGrant, readRelayBootstrap, readRelayDescriptor, readRelayEnvironments, readRelayStatus, readRelayTicket,
  readRelayUnlinkResponse, relayAccountId, relaySocketTarget, secureRelayOrigin, tokenExchangeBody,
} from './RelayProtocol';

const TIMEOUT_MS = 15000;
const REFRESH_SKEW_MS = 5000;
const FORM_TYPE = 'application/x-www-form-urlencoded';
const JSON_TYPE = 'application/json';

export interface RelayProofSigner {
  proof: (method: string, target: string, accessToken?: string) => Promise<string>;
  thumbprint: () => Promise<string>;
}

export interface EnvironmentResponseLimits {
  readTimeout: number;
  maxLimit: number;
}

export type EnvironmentRequest = (path: string, method?: string, body?: string,
  limits?: EnvironmentResponseLimits) => Promise<Object>;

export interface RelayConnection {
  environmentId: string;
  label: string;
  origin: string;
  orchestrationProtocolVersion?: number;
  request: EnvironmentRequest;
  socketAddress: (orchestrationProtocol: string) => Promise<string>;
  currentOrigin: () => string;
}

interface TunnelGrant {
  endpoint: RelayEndpoint;
  origin: string;
  descriptor: RelayDescriptor;
  grant: RelayAccessGrant;
}

interface TunnelRequest {
  environmentId: string;
  deviceId?: string;
  readClerkToken: () => Promise<string>;
}

interface TunnelReply {
  payload: Object;
  endpoint: RelayEndpoint;
}

interface RelayConnectBody {
  clientKeyThumbprint: string;
  deviceId?: string;
}

interface RelayErrorResponse {
  _tag?: string;
  code?: string;
  reason?: string;
  traceId?: string;
  dpopFailureReason?: string;
}

interface RelaySessionResponse {
  authenticated?: boolean;
}

function validateEnvironmentId(environmentId: string): void {
  if (!environmentId || environmentId.trim() !== environmentId || environmentId === '.' || environmentId === '..') {
    throw new Error('T3 Connect 环境标识无效。');
  }
}

class RelayAccount {
  readonly id: string;
  readonly tokens: Map<string, RelayAccessGrant> = new Map();
  readonly exchanges: Map<string, Promise<RelayAccessGrant>> = new Map();
  readonly tunnels: Map<string, TunnelGrant> = new Map();
  readonly tunnelExchanges: Map<string, Promise<TunnelGrant>> = new Map();

  constructor(id: string) {
    this.id = id;
  }
}

class RelayHttpError extends Error {
  readonly status: number;
  readonly response?: RelayErrorResponse;

  constructor(status: number, response?: RelayErrorResponse) {
    super(status === 403 && response?._tag === 'EnvironmentScopeRequiredError'
      ? '此连接缺少执行操作所需的环境权限。'
      : status === 401 ? 'T3 Connect 凭据被拒绝。' : `T3 Connect 请求失败（${status}）。`);
    this.status = status;
    this.response = response;
  }
}

class RelayNetworkError extends Error {}

export function isRelayRouteUnavailable(error: Error): boolean {
  return error instanceof RelayNetworkError ||
    (error instanceof RelayHttpError && [502, 503, 504].includes(error.status));
}

class RelayDeviceApprovalError extends Error {
  readonly environmentId: string;
  readonly environmentLabel: string;
  readonly verificationCode: string;
  readonly traceId?: string;

  constructor(message: string, descriptor: RelayDescriptor, thumbprint: string, traceId?: string) {
    super(message);
    this.environmentId = descriptor.environmentId;
    this.environmentLabel = descriptor.label;
    this.verificationCode = connectDeviceVerificationCode(thumbprint);
    this.traceId = traceId;
  }
}

export class RelayApprovalPendingError extends RelayDeviceApprovalError {
  constructor(descriptor: RelayDescriptor, thumbprint: string, traceId?: string) {
    super('此设备正在等待批准。请在 T3 环境中批准后重试。', descriptor, thumbprint, traceId);
  }
}

export class RelayApprovalUnavailableError extends RelayDeviceApprovalError {
  constructor(descriptor: RelayDescriptor, thumbprint: string, traceId?: string) {
    super('设备连接请求已被拒绝或已失效。请在环境中确认后重试。', descriptor, thumbprint, traceId);
  }
}

export class NativeRelay {
  private readonly origin: string;
  private readonly signer: RelayProofSigner;
  private account?: RelayAccount;
  private listGeneration: number = 0;

  constructor(relayUrl: string, signer: RelayProofSigner) {
    this.origin = secureRelayOrigin(relayUrl);
    this.signer = signer;
  }

  clear(): void {
    this.account?.tokens.clear();
    this.account?.exchanges.clear();
    this.account?.tunnels.clear();
    this.account?.tunnelExchanges.clear();
    this.account = undefined;
  }

  private useAccount(clerkToken: string): RelayAccount {
    const id = relayAccountId(clerkToken);
    if (this.account?.id === id) return this.account;
    this.clear();
    const account = new RelayAccount(id);
    this.account = account;
    return account;
  }

  private assertAccount(account: RelayAccount): void {
    if (this.account !== account) throw new Error('T3 账号已更换，请重试。');
  }

  private async requestJson(account: RelayAccount, target: string, method: string,
    headers: Record<string, string>, body?: string, limits?: EnvironmentResponseLimits): Promise<Object> {
    this.assertAccount(account);
    const request = http.createHttp();
    try {
      let response: http.HttpResponse;
      try {
        const options: http.HttpRequestOptions = {
          method: method as http.RequestMethod,
          header: headers,
          extraData: body,
          expectDataType: http.HttpDataType.STRING,
          usingCache: false,
          maxRedirects: 0,
          remoteValidation: 'system',
          connectTimeout: TIMEOUT_MS,
          readTimeout: limits?.readTimeout ?? TIMEOUT_MS,
        };
        if (limits) options.maxLimit = limits.maxLimit;
        response = await request.request(target, options);
      } catch (error) {
        this.assertAccount(account);
        throw new RelayNetworkError('无法访问 T3 Connect。请检查网络后重试。');
      }
      this.assertAccount(account);
      const status = response.responseCode;
      if (status >= 300 && status < 400) throw new RelayHttpError(status);
      let payload: Object | undefined;
      if (typeof response.result === 'string') {
        try {
          payload = JSON.parse(response.result) as Object;
        } catch (error) {
          payload = undefined;
        }
      }
      if (status < 200 || status >= 300) throw new RelayHttpError(status, payload as RelayErrorResponse);
      if (!payload || typeof payload !== 'object') throw new Error('T3 Connect 返回的数据无效。');
      return payload;
    } finally {
      request.destroy();
    }
  }

  private async exchangeRelayToken(account: RelayAccount, clerkToken: string, scope: string): Promise<RelayAccessGrant> {
    const target = this.origin + '/v1/client/dpop-token';
    const proof = await this.signer.proof('POST', target);
    const body = tokenExchangeBody(clerkToken, JWT_TOKEN_TYPE) + '&resource=' + encodeURIComponent(this.origin) +
      '&scope=' + encodeURIComponent(scope) + '&client_id=t3-mobile';
    const issuedAt = Date.now();
    const headers: Record<string, string> = { 'dpop': proof, 'content-type': FORM_TYPE };
    return readDpopGrant(await this.requestJson(account, target, 'POST', headers, body), issuedAt, scope);
  }

  private async relayToken(account: RelayAccount, clerkToken: string, scope: string): Promise<RelayAccessGrant> {
    this.assertAccount(account);
    const cached = account.tokens.get(scope);
    if (cached && cached.expiresAt > Date.now() + REFRESH_SKEW_MS) return cached;
    const pending = account.exchanges.get(scope);
    if (pending) return pending;
    const exchange = this.exchangeRelayToken(account, clerkToken, scope);
    account.exchanges.set(scope, exchange);
    try {
      const issued = await exchange;
      this.assertAccount(account);
      account.tokens.set(scope, issued);
      return issued;
    } finally {
      account.exchanges.delete(scope);
    }
  }

  private async postRelay(account: RelayAccount, clerkToken: string, scope: string, path: string,
    body?: string, retry: boolean = true): Promise<Object> {
    const authorization = await this.relayToken(account, clerkToken, scope);
    const target = this.origin + path;
    const proof = await this.signer.proof('POST', target, authorization.token);
    const headers: Record<string, string> = { 'authorization': 'DPoP ' + authorization.token, 'dpop': proof };
    if (body !== undefined) headers['content-type'] = JSON_TYPE;
    try {
      return await this.requestJson(account, target, 'POST', headers, body);
    } catch (error) {
      if (error instanceof RelayHttpError && error.status === 401 &&
        error.response?._tag === 'RelayAuthInvalidError' && error.response?.reason === 'invalid_bearer') {
        if (account.tokens.get(scope)?.token === authorization.token) account.tokens.delete(scope);
        if (retry) return this.postRelay(account, clerkToken, scope, path, body, false);
      }
      throw error as Error;
    }
  }

  async listEnvironments(clerkToken: string, onRows?: (rows: RelayEnvironment[]) => void): Promise<RelayEnvironment[]> {
    const account = this.useAccount(clerkToken);
    const generation = ++this.listGeneration;
    const assertCurrent = (): void => {
      this.assertAccount(account);
      if (this.listGeneration !== generation) throw new Error('T3 Connect 环境列表已刷新。');
    };
    const headers: Record<string, string> = { 'authorization': 'Bearer ' + clerkToken };
    const listed = await this.requestJson(account, this.origin + '/v1/environments', 'GET', headers);
    assertCurrent();
    const rows = readRelayEnvironments(listed);
    onRows?.(rows.slice());
    assertCurrent();
    await Promise.all(rows.map(async (row: RelayEnvironment, index: number) => {
      let availability: RelayAvailability;
      try {
        const path = '/v1/environments/' + encodeURIComponent(row.environmentId) + '/status';
        availability = readRelayStatus(await this.postRelay(account, clerkToken, RELAY_STATUS_SCOPES, path), row);
      } catch (error) {
        availability = 'error';
      }
      assertCurrent();
      rows[index] = { environmentId: row.environmentId, label: row.label, endpoint: row.endpoint,
        linkedAt: row.linkedAt, availability };
      onRows?.(rows.slice());
    }));
    assertCurrent();
    return rows;
  }

  async deregisterEnvironment(clerkToken: string, environmentId: string): Promise<void> {
    validateEnvironmentId(environmentId);
    const account = this.useAccount(clerkToken);
    const path = '/v1/client/environment-links/' + encodeURIComponent(environmentId);
    const headers: Record<string, string> = { 'authorization': 'Bearer ' + clerkToken };
    readRelayUnlinkResponse(await this.requestJson(account, this.origin + path, 'DELETE', headers));
    this.assertAccount(account);
    this.listGeneration++;
    account.tunnels.delete(environmentId);
    account.tunnelExchanges.delete(environmentId);
  }

  private async exchangeTunnelToken(account: RelayAccount, input: TunnelRequest,
    clerkToken: string): Promise<TunnelGrant> {
    this.assertAccount(account);
    if (relayAccountId(clerkToken) !== account.id) throw new Error('T3 账号已更换，请重试。');
    const path = '/v1/environments/' + encodeURIComponent(input.environmentId) + '/connect';
    const payload: RelayConnectBody = { clientKeyThumbprint: await this.signer.thumbprint(), deviceId: input.deviceId };
    const bootstrap = readRelayBootstrap(await this.postRelay(account, clerkToken, RELAY_CONNECT_SCOPE, path,
      JSON.stringify(payload)), input.environmentId);
    const origin = secureRelayOrigin(bootstrap.endpoint.httpBaseUrl);
    const descriptor = readRelayDescriptor(await this.requestJson(account, origin + '/.well-known/t3/environment',
      'GET', {}), input.environmentId);
    const target = origin + '/oauth/token';
    const proof = await this.signer.proof('POST', target);
    const body = tokenExchangeBody(bootstrap.credential, ENVIRONMENT_BOOTSTRAP_TYPE) +
      '&client_label=HarmonyOS&client_device_type=mobile&client_os=HarmonyOS';
    const issuedAt = Date.now();
    try {
      const headers: Record<string, string> = { 'dpop': proof, 'content-type': FORM_TYPE };
      const response = await this.requestJson(account, target, 'POST', headers, body);
      return { origin, endpoint: bootstrap.endpoint, descriptor, grant: readDpopGrant(response, issuedAt) };
    } catch (error) {
      if (error instanceof RelayHttpError && error.status === 403 &&
        error.response?._tag === 'EnvironmentConnectApprovalPendingError') {
        throw new RelayApprovalPendingError(descriptor, payload.clientKeyThumbprint, error.response.traceId);
      }
      if (error instanceof RelayHttpError && error.status === 401 &&
        error.response?._tag === 'EnvironmentAuthInvalidError' && error.response.reason === 'invalid_credential' &&
        error.response.dpopFailureReason === undefined) {
        throw new RelayApprovalUnavailableError(descriptor, payload.clientKeyThumbprint, error.response.traceId);
      }
      throw error as Error;
    }
  }

  private async tunnelToken(account: RelayAccount, input: TunnelRequest, clerkToken?: string): Promise<TunnelGrant> {
    this.assertAccount(account);
    const cached = account.tunnels.get(input.environmentId);
    if (cached && cached.grant.expiresAt > Date.now() + REFRESH_SKEW_MS) return cached;
    const pending = account.tunnelExchanges.get(input.environmentId);
    if (pending) return pending;
    const token = clerkToken === undefined ? input.readClerkToken() : Promise.resolve(clerkToken);
    const exchange: Promise<TunnelGrant> = token
      .then((value: string) => this.exchangeTunnelToken(account, input, value))
      .then((issued: TunnelGrant) => {
        this.assertAccount(account);
        if (account.tunnelExchanges.get(input.environmentId) !== exchange) {
          throw new Error('此服务器的 T3 Connect 登记已注销。');
        }
        account.tunnels.set(input.environmentId, issued);
        return issued;
      });
    account.tunnelExchanges.set(input.environmentId, exchange);
    try {
      return await exchange;
    } finally {
      if (account.tunnelExchanges.get(input.environmentId) === exchange) {
        account.tunnelExchanges.delete(input.environmentId);
      }
    }
  }

  private async authorizedTunnelRequest(account: RelayAccount, tunnel: TunnelGrant, path: string, method: string,
    body: string | undefined, limits: EnvironmentResponseLimits | undefined): Promise<Object> {
    const target = tunnel.origin + path;
    const proof = await this.signer.proof(method, target, tunnel.grant.token);
    const headers: Record<string, string> = { 'authorization': 'DPoP ' + tunnel.grant.token, 'dpop': proof,
      'x-t3-orchestration-protocol': ORCHESTRATION_PROTOCOL };
    if (body !== undefined) headers['content-type'] = JSON_TYPE;
    return this.requestJson(account, target, method, headers, body, limits);
  }

  private discardTunnel(account: RelayAccount, environmentId: string, tunnel: TunnelGrant): void {
    if (account.tunnels.get(environmentId) === tunnel) account.tunnels.delete(environmentId);
  }

  private async requestTunnel(account: RelayAccount, input: TunnelRequest, path: string, method: string,
    body?: string, limits?: EnvironmentResponseLimits, fallbackPath?: string, retry: boolean = true): Promise<TunnelReply> {
    if (!/^\/(?!\/)/.test(path) || /[\\#\s]/.test(path)) throw new Error('环境请求路径无效。');
    const sessionProbe = method === 'GET' && path === '/api/auth/session';
    const workspaceRead = method === 'GET' && path === '/api/orchestration/shell';
    const cached = account.tunnels.get(input.environmentId);
    const tunnel = await this.tunnelToken(account, input);
    try {
      let payload: Object;
      try {
        payload = await this.authorizedTunnelRequest(account, tunnel, path, method, body, limits);
      } catch (error) {
        if (!(error instanceof RelayHttpError) || error.status !== 404 || fallbackPath === undefined) {
          throw error as Error;
        }
        payload = await this.authorizedTunnelRequest(account, tunnel, fallbackPath, method, body, limits);
      }
      if (sessionProbe && (payload as RelaySessionResponse).authenticated === false) {
        this.discardTunnel(account, input.environmentId, tunnel);
        if (retry) return this.requestTunnel(account, input, path, method, body, limits, fallbackPath, false);
      }
      return { payload, endpoint: tunnel.endpoint };
    } catch (error) {
      const rejected = error instanceof RelayHttpError && error.status === 401 &&
        error.response?._tag === 'EnvironmentAuthInvalidError';
      const staleEndpoint = (fallbackPath !== undefined || sessionProbe || workspaceRead) && (error instanceof RelayNetworkError ||
        (error instanceof RelayHttpError && (error.status === 404 || error.status === 410 || error.status >= 500)));
      if (rejected || staleEndpoint) {
        this.discardTunnel(account, input.environmentId, tunnel);
        if (retry && (rejected || tunnel === cached)) {
          return this.requestTunnel(account, input, path, method, body, limits, fallbackPath, false);
        }
      }
      throw error as Error;
    }
  }

  async connectEnvironment(clerkToken: string, environmentId: string, deviceId?: string,
    renewClerkToken?: () => Promise<string>): Promise<RelayConnection> {
    validateEnvironmentId(environmentId);
    const account = this.useAccount(clerkToken);
    const input: TunnelRequest = { environmentId, deviceId, readClerkToken: renewClerkToken ?? (() =>
      Promise.resolve(clerkToken)) };
    const tunnel = await this.tunnelToken(account, input, clerkToken);
    this.assertAccount(account);
    const connection: RelayConnection = {
      environmentId,
      label: tunnel.descriptor.label,
      origin: tunnel.origin,
      orchestrationProtocolVersion: tunnel.descriptor.orchestrationProtocolVersion,
      currentOrigin: (): string => {
        this.assertAccount(account);
        return account.tunnels.get(environmentId)?.origin ?? tunnel.origin;
      },
      request: async (path: string, method: string = 'GET', body?: string,
        limits?: EnvironmentResponseLimits): Promise<Object> => {
        const result = await this.requestTunnel(account, input, path, method, body, limits);
        this.assertAccount(account);
        return result.payload;
      },
      socketAddress: async (orchestrationProtocol: string): Promise<string> => {
        const issued = await this.requestTunnel(account, input, '/api/auth/websocket-ticket/rpc', 'POST', undefined, undefined,
          '/api/auth/websocket-ticket');
        this.assertAccount(account);
        const ticket = readRelayTicket(issued.payload);
        const socket = relaySocketTarget(issued.endpoint);
        const proof = await this.signer.proof('GET', 'https:' + socket.slice(4), ticket);
        this.assertAccount(account);
        return socket + '?orchestrationProtocol=' + encodeURIComponent(orchestrationProtocol) +
          '&wsTicket=' + encodeURIComponent(ticket) + '&dpop=' + encodeURIComponent(proof) +
          '&connectionMethod=relay&clientSurface=mobile&clientDeviceType=phone&clientOs=HarmonyOS';
      },
    };
    return connection;
  }
}
