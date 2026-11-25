export const ACCOUNT_REDIRECT_URL = 'clerk://com.t3tools.t3code.dev.hosted-callback';
export const ACCOUNT_BROWSER_TIMEOUT_MS = 10 * 60_000;

export type AccountMode = 'sign-in' | 'sign-up';

export interface AccountIdentity {
  userId: string;
  sessionId: string;
  displayName: string;
  firstName: string;
  lastName: string;
  email: string;
}

export interface AccountNameUpdate {
  firstName?: string;
  lastName?: string;
}

export interface AccountDeviceSession {
  id: string;
  deviceType: string;
  browserName: string;
  lastActiveAt: number;
}

export interface AccountEmailAction {
  kind: 'start' | 'password' | 'emailCode' | 'verify' | 'resend';
  value?: string;
}

export interface AccountEmailStep {
  kind: 'emailCode' | 'password' | 'mfaEmail' | 'totp' | 'backupCode' | 'hosted' | 'complete';
  passwordAvailable?: boolean;
  emailCodeAvailable?: boolean;
  identity?: AccountIdentity;
  error?: string;
}

export interface SavedAccount {
  issuer: string;
  clientToken: string;
  sessionId: string;
  userId: string;
}

export interface AccountStore {
  read(): Promise<SavedAccount | undefined>;
  save(account: SavedAccount): Promise<void>;
  clear(): Promise<void>;
  readAttempt(): Promise<SavedHostedAttempt | undefined>;
  saveAttempt(attempt: SavedHostedAttempt): void;
  consumeAttempt(state: string): boolean;
  clearAttempt(): void;
}

export interface AccountProof {
  state: string;
  verifier: string;
  challenge: string;
}

export interface SavedHostedAttempt {
  issuer: string;
  redirect: string;
  expiresAt: number;
  proof: AccountProof;
  clientToken: string;
}

export interface ClerkRequest {
  method: 'GET' | 'POST';
  path: string;
  clientToken: string;
  body?: Record<string, string>;
}

interface ClerkError {
  code?: string;
}

interface ClerkEmail {
  id?: string;
  email_address?: string;
}

interface ClerkUser {
  id?: string;
  first_name?: string | null;
  last_name?: string | null;
  primary_email_address_id?: string;
  email_addresses?: ClerkEmail[];
}

interface ClerkFactor {
  strategy?: string;
  email_address_id?: string;
}

interface ClerkResource extends ClerkUser {
  object?: string;
  url?: string;
  jwt?: string;
  status?: string;
  user?: ClerkUser;
  sessions?: ClerkResource[];
  created_session_id?: string;
  supported_first_factors?: ClerkFactor[];
  supported_second_factors?: ClerkFactor[];
  protect_check?: Object;
}

interface ClerkMetadata {
  client?: ClerkResource;
}

interface ClerkSessionActivity {
  device_type?: string;
  browser_name?: string;
}

export interface ClerkSessionWithActivity {
  object?: string;
  id?: string;
  status?: string;
  last_active_at?: number;
  latest_activity?: ClerkSessionActivity;
}

export interface ClerkPayload extends ClerkResource {
  response?: ClerkResource;
  client?: ClerkResource;
  meta?: ClerkMetadata;
  errors?: ClerkError[];
}

export interface ClerkReply {
  status: number;
  payload?: ClerkPayload;
  sessionList?: ClerkSessionWithActivity[];
  clientToken?: string;
}

interface HostedAttempt {
  expiresAt: number;
  proof?: AccountProof;
  clientToken?: string;
  consumed: boolean;
}

interface HostedCallback {
  nonce: string;
  sessionId: string;
}

interface EmailAttempt {
  identifier: string;
  clientToken: string;
  expiresAt: number;
  id: string;
  firstEmailId: string;
  secondEmailId: string;
  busy: boolean;
  step?: AccountEmailStep;
}

const SIGN_INS = '/client/sign_ins';

class AccountBrowserRequiredError extends Error {
  constructor() {
    super('请在浏览器中继续登录。');
  }
}

export class AccountSessionExpiredError extends Error {
  constructor() {
    super('T3 账号会话已过期，请重新登录。');
  }
}

export class AccountNetworkError extends Error {
  constructor() {
    super('无法连接 T3 账号服务，请检查网络后重试。');
  }
}

export class AccountSessionReverificationRequiredError extends Error {
  constructor() {
    super('此操作需要重新验证身份。请在支持身份验证的 T3 Code 客户端中完成。');
  }
}

export function matchesAccountRedirect(callback: string, redirect: string): boolean {
  return /^[a-z][a-z0-9+.-]*:\/\/[a-z0-9.-]+(?:\/[a-z0-9_/-]*)?$/.test(redirect) &&
    !/^https?:/.test(redirect) && !/[\s\u0000-\u001f\u007f]/.test(callback) &&
    callback.split(/[?#]/, 1)[0] === redirect;
}

function readCallback(callback: string, redirect: string, state: string): HostedCallback {
  if (!matchesAccountRedirect(callback, redirect)) throw new Error('登录回调地址无效，请重试。');
  const query = callback.startsWith(redirect + '?') ? callback.slice(redirect.length + 1).split('#', 1)[0] : '';
  const values = new Map<string, string>();
  for (const entry of query.split('&')) {
    const separator = entry.indexOf('=');
    if (separator === -1) continue;
    const name = decodeURIComponent(entry.slice(0, separator).replace(/\+/g, ' '));
    if (name !== 'state' && name !== 'rotating_token_nonce' && name !== 'created_session_id') continue;
    if (values.has(name)) throw new Error('登录回调参数重复，请重试。');
    values.set(name, decodeURIComponent(entry.slice(separator + 1).replace(/\+/g, ' ')));
  }
  if (values.get('state') !== state) throw new Error('登录回调与当前请求不匹配，请重试。');
  const nonce = values.get('rotating_token_nonce');
  const sessionId = values.get('created_session_id');
  if (!nonce || !credential(nonce) || !sessionId || !identifier(sessionId)) {
    throw new Error('登录回调缺少有效的会话凭据，请重试。');
  }
  return { nonce, sessionId };
}

function identifier(value: string): boolean {
  return typeof value === 'string' && /^[a-zA-Z0-9_-]{1,128}$/.test(value);
}

function credential(value: string): boolean {
  return typeof value === 'string' && /^[a-zA-Z0-9_~.-]{1,16384}$/.test(value);
}

function text(value?: string | null): string {
  return typeof value === 'string' ? value : '';
}

function identity(session?: ClerkResource): AccountIdentity | undefined {
  if (session?.status !== 'active' || !session.id || !identifier(session.id)) return undefined;
  return profileIdentity(session.user, session.id);
}

function profileIdentity(user: ClerkUser | undefined, sessionId: string): AccountIdentity | undefined {
  if (!user?.id || !identifier(user.id)) return undefined;
  const addresses = user.email_addresses;
  const primaryId = text(user.primary_email_address_id);
  const email = primaryId && Array.isArray(addresses)
    ? text(addresses.find((item: ClerkEmail) => item?.id === primaryId)?.email_address) : '';
  const firstName = text(user.first_name);
  const lastName = text(user.last_name);
  const name = `${firstName} ${lastName}`.trim();
  return { userId: user.id, sessionId, displayName: name || email || user.id, firstName, lastName, email };
}

function clientSession(client: ClerkResource | undefined, sessionId: string): AccountIdentity | undefined {
  if (client?.object !== 'client' || !Array.isArray(client.sessions)) {
    throw new Error('账号服务返回了无效的客户端信息。');
  }
  return identity(client.sessions.find((session: ClerkResource) => session?.id === sessionId));
}

function hasClerkError(reply: ClerkReply, code: string): boolean {
  const errors = reply.payload?.errors;
  return Array.isArray(errors) && errors.some((error: ClerkError) => error?.code === code);
}

function signedOut(reply: ClerkReply): boolean {
  return reply.status === 401 || (reply.status === 404 && hasClerkError(reply, 'session_not_found'));
}

function requireSuccess(reply: ClerkReply): void {
  if (signedOut(reply)) throw new AccountSessionExpiredError();
  if (reply.status < 200 || reply.status >= 300) throw new Error(`账号服务请求未成功（HTTP ${reply.status}）。`);
}

function requireEmailSuccess(reply: ClerkReply): void {
  if (hasClerkError(reply, 'requires_captcha') || hasClerkError(reply, 'captcha_missing_token') ||
    hasClerkError(reply, 'captcha_invalid') ||
    hasClerkError(reply, 'protect_check_required')) throw new AccountBrowserRequiredError();
  if (hasClerkError(reply, 'form_code_incorrect')) throw new Error('验证码不正确，请重试。');
  if (hasClerkError(reply, 'verification_expired')) throw new Error('验证码已过期，请重新发送。');
  if (hasClerkError(reply, 'form_password_incorrect') || hasClerkError(reply, 'form_identifier_not_found')) {
    throw new Error('邮箱地址或密码不正确，请重试。');
  }
  if (reply.status === 429) throw new Error('请求过于频繁，请稍后重试。');
  requireSuccess(reply);
}

function factor(factors: ClerkFactor[] | undefined, strategy: string): ClerkFactor | undefined {
  return Array.isArray(factors) ? factors.find((item: ClerkFactor) => item?.strategy === strategy) : undefined;
}

function codeAddress(factors: ClerkFactor[] | undefined): string {
  const id = text(factor(factors, 'email_code')?.email_address_id);
  return identifier(id) ? id : '';
}

function rotatedToken(reply: ClerkReply, previous: string): string {
  const next = text(reply.clientToken);
  if (!next) return previous;
  if (!credential(next)) throw new Error('账号服务返回了无效的客户端凭据。');
  return next;
}

function rotateAccount(saved: SavedAccount, clientToken: string): SavedAccount {
  return { issuer: saved.issuer, clientToken, sessionId: saved.sessionId, userId: saved.userId };
}

export function clerkFapiUrl(issuer: string, path: string): string {
  const separator = path.includes('?') ? '&' : '?';
  // Keep the native wire version aligned with the installed Clerk Expo and ClerkJS SDKs.
  return `${issuer}/v1${path}${separator}__clerk_api_version=2026-08-20&_clerk_js_version=6.42.3&_is_native=1`;
}

export class HostedAccountSession {
  private issuer: string;
  private template: string;
  private redirect: string;
  private store: AccountStore;
  private request: (input: ClerkRequest) => Promise<ClerkReply>;
  private createProof: () => Promise<AccountProof>;
  private now: () => number;
  private attempt: HostedAttempt | undefined;
  private emailAttempt: EmailAttempt | undefined;
  private active: SavedAccount | undefined;
  private epoch: number = 0;
  private attemptEpoch: number = 0;
  private signingOut: boolean = false;
  private operations: Promise<void> = Promise.resolve();

  constructor(issuer: string, template: string, redirect: string, store: AccountStore,
    request: (input: ClerkRequest) => Promise<ClerkReply>, createProof: () => Promise<AccountProof>,
    now: () => number = Date.now) {
    this.issuer = issuer;
    this.template = template;
    this.redirect = redirect;
    this.store = store;
    this.request = request;
    this.createProof = createProof;
    this.now = now;
  }

  private serialize<T>(run: () => Promise<T>): Promise<T> {
    const operation = this.operations.then(run);
    this.operations = operation.then(() => {}, () => {});
    return operation;
  }

  private checkAttempt(attempt: HostedAttempt): void {
    if (this.attempt !== attempt) throw new Error('登录已取消。');
    if (this.now() >= attempt.expiresAt) {
      this.attempt = undefined;
      this.store.clearAttempt();
      throw new Error('登录已超时，请重试。');
    }
  }

  async restore(): Promise<AccountIdentity | undefined> {
    const epoch = this.epoch;
    return this.serialize(async () => {
      if (epoch !== this.epoch || this.signingOut) return undefined;
      const saved = await this.store.read();
      if (epoch !== this.epoch || !saved) return undefined;
      if (saved.issuer !== this.issuer || !credential(saved.clientToken) || !identifier(saved.userId) ||
        !identifier(saved.sessionId)) {
        this.active = undefined;
        await this.store.clear();
        return undefined;
      }
      const reply = await this.request({ method: 'GET', path: '/client', clientToken: saved.clientToken });
      if (epoch !== this.epoch) return undefined;
      if (!signedOut(reply)) {
        requireSuccess(reply);
        const restored = clientSession(reply.payload?.response ?? reply.payload, saved.sessionId);
        if (restored?.userId === saved.userId) {
          const current = rotateAccount(saved, rotatedToken(reply, saved.clientToken));
          await this.store.save(current);
          if (epoch !== this.epoch) return undefined;
          this.active = current;
          return restored;
        }
      }
      this.active = undefined;
      await this.store.clear();
      return undefined;
    });
  }

  async start(mode: AccountMode): Promise<string> {
    if (this.active || this.signingOut) throw new Error('请先退出当前账号。');
    if (this.emailAttempt && this.now() < this.emailAttempt.expiresAt) throw new Error('已在进行邮箱登录。');
    if (this.attempt && this.now() < this.attempt.expiresAt) throw new Error('已在进行账号登录。');
    this.emailAttempt = undefined;
    this.attemptEpoch++;
    const attempt: HostedAttempt = { expiresAt: this.now() + ACCOUNT_BROWSER_TIMEOUT_MS, consumed: false };
    this.attempt = attempt;
    try {
      this.store.clearAttempt();
      const proof = await this.createProof();
      this.checkAttempt(attempt);
      const initial = await this.request({ method: 'GET', path: '/client', clientToken: '' });
      this.checkAttempt(attempt);
      if (initial.status !== 401) requireSuccess(initial);
      let clientToken = rotatedToken(initial, '');
      const body: Record<string, string> = {
        'redirect_url': this.redirect, 'code_challenge': proof.challenge, 'mode': mode, 'state': proof.state,
      };
      let reply = await this.request({ method: 'POST', path: '/client/hosted_auth', clientToken, body });
      this.checkAttempt(attempt);
      clientToken = rotatedToken(reply, clientToken);
      if (reply.status === 401 && hasClerkError(reply, 'signed_out')) {
        reply = await this.request({ method: 'POST', path: '/client/hosted_auth', clientToken, body });
        this.checkAttempt(attempt);
        clientToken = rotatedToken(reply, clientToken);
      }
      requireSuccess(reply);
      const hosted = reply.payload?.response;
      const browserUrl = text(hosted?.url);
      if (hosted?.object !== 'hosted_auth' || !/^https:\/\/[a-z0-9.-]+(?::[0-9]{1,5})?(?:[/?#]|$)/i.test(browserUrl) ||
        /[\\\s\u0000-\u001f\u007f]/.test(browserUrl)) {
        throw new Error('账号服务返回了无效的登录网址。');
      }
      this.store.saveAttempt({ issuer: this.issuer, redirect: this.redirect, expiresAt: attempt.expiresAt,
        proof, clientToken });
      attempt.clientToken = clientToken;
      attempt.proof = proof;
      return browserUrl;
    } catch (error) {
      if (this.attempt === attempt) this.attempt = undefined;
      throw error as Error;
    }
  }

  private async restoreAttempt(): Promise<HostedAttempt | undefined> {
    if (this.emailAttempt) return undefined;
    if (this.attempt) return this.attempt;
    const epoch = this.attemptEpoch;
    const saved = await this.store.readAttempt();
    if (epoch !== this.attemptEpoch || this.signingOut) return undefined;
    if (this.attempt || !saved) return this.attempt;
    if (saved.issuer !== this.issuer || saved.redirect !== this.redirect || !Number.isFinite(saved.expiresAt) ||
      (saved.clientToken !== '' && !credential(saved.clientToken)) ||
      !saved.proof || !identifier(saved.proof.state) || !/^[a-f0-9]{64}$/.test(saved.proof.verifier)) {
      this.store.clearAttempt();
      return undefined;
    }
    this.attempt = { expiresAt: saved.expiresAt, clientToken: saved.clientToken, proof: saved.proof, consumed: false };
    return this.attempt;
  }

  async complete(callback: string): Promise<AccountIdentity> {
    if (!matchesAccountRedirect(callback, this.redirect)) throw new Error('登录回调地址无效，请重试。');
    if (this.emailAttempt) throw new Error('已在进行邮箱登录。');
    const attempt = this.attempt ?? await this.restoreAttempt();
    if (!attempt?.proof || attempt.consumed) throw new Error('没有可完成的登录请求，请重新登录。');
    this.checkAttempt(attempt);
    let returned: HostedCallback;
    try {
      returned = readCallback(callback, this.redirect, attempt.proof.state);
    } catch (error) {
      if (error instanceof URIError) throw new Error('登录回调编码无效，请重试。');
      throw error as Error;
    }
    const verifier = attempt.proof.verifier;
    attempt.consumed = true;
    try {
      if (!this.store.consumeAttempt(attempt.proof.state)) throw new Error('登录请求已使用，请重新登录。');
      return await this.serialize(async () => {
        this.checkAttempt(attempt);
        if (this.active || this.signingOut) throw new Error('请先退出当前账号。');
        const redeemBody: Record<string, string> = {
          '_method': 'GET', 'rotating_token_nonce': returned.nonce, 'code_verifier': verifier,
        };
        const reply = await this.request({
          method: 'POST', path: '/client', clientToken: attempt.clientToken ?? '', body: redeemBody,
        });
        this.checkAttempt(attempt);
        requireSuccess(reply);
        const created = clientSession(reply.payload?.response, returned.sessionId);
        const clientToken = rotatedToken(reply, attempt.clientToken ?? '');
        if (!created || !clientToken) throw new Error('登录结果缺少可用的会话，请重试。');
        return this.activate(created, clientToken, () => this.checkAttempt(attempt));
      });
    } finally {
      if (this.attempt === attempt) this.attempt = undefined;
    }
  }

  private async activate(created: AccountIdentity, clientToken: string, check: () => void): Promise<AccountIdentity> {
    const activationBody: Record<string, string> = { 'intent': 'select_session' };
    const activation = await this.request({
      method: 'POST', path: `/client/sessions/${created.sessionId}/touch`, clientToken, body: activationBody,
    });
    check();
    requireSuccess(activation);
    const activated = identity(activation.payload?.response ?? activation.payload);
    if (activated?.sessionId !== created.sessionId || activated.userId !== created.userId) {
      throw new Error('账号服务未能启用本次登录的会话。');
    }
    const saved: SavedAccount = {
      issuer: this.issuer, sessionId: activated.sessionId, userId: activated.userId,
      clientToken: rotatedToken(activation, clientToken),
    };
    await this.store.save(saved);
    try {
      check();
    } catch (error) {
      await this.store.clear();
      throw error as Error;
    }
    this.active = saved;
    return activated;
  }

  private checkEmailAttempt(attempt: EmailAttempt): void {
    if (this.emailAttempt !== attempt) throw new Error('登录已取消。');
    if (this.now() >= attempt.expiresAt) {
      this.emailAttempt = undefined;
      throw new Error('登录已超时，请取消后重试。');
    }
  }

  private beginEmail(input: string): EmailAttempt {
    const email = input.trim();
    if (email.length > 254 || !/^[^\s@]+@[^\s@]+$/.test(email)) throw new Error('请输入有效的邮箱地址。');
    if (this.active || this.signingOut) throw new Error('请先退出当前账号。');
    const now = this.now();
    if ((this.attempt && now < this.attempt.expiresAt) || (this.emailAttempt && now < this.emailAttempt.expiresAt)) {
      throw new Error('已在进行账号登录。');
    }
    this.attemptEpoch++;
    this.attempt = undefined;
    this.store.clearAttempt();
    const attempt: EmailAttempt = {
      identifier: email, clientToken: '', expiresAt: now + ACCOUNT_BROWSER_TIMEOUT_MS,
      id: '', firstEmailId: '', secondEmailId: '', busy: false,
    };
    this.emailAttempt = attempt;
    return attempt;
  }

  private async emailRequest(attempt: EmailAttempt, method: 'GET' | 'POST', path: string,
    body?: Record<string, string>, bootstrap: boolean = false): Promise<ClerkReply> {
    this.checkEmailAttempt(attempt);
    const input: ClerkRequest = { method, path, clientToken: attempt.clientToken };
    if (body) input.body = body;
    const reply = await this.request(input);
    this.checkEmailAttempt(attempt);
    attempt.clientToken = rotatedToken(reply, attempt.clientToken);
    if (!bootstrap || reply.status !== 401) requireEmailSuccess(reply);
    return reply;
  }

  private signInResponse(attempt: EmailAttempt, reply: ClerkReply, allowNewId: boolean): ClerkResource {
    const response = reply.payload?.response;
    const id = text(response?.id);
    if (response?.object !== 'sign_in' || !identifier(id) || (!allowNewId && id !== attempt.id)) {
      throw new Error('账号服务返回了无效的登录请求。');
    }
    if (response.protect_check || response.status === 'needs_protect_check') throw new AccountBrowserRequiredError();
    attempt.id = id;
    return response;
  }

  private async sendEmailCode(attempt: EmailAttempt, second: boolean): Promise<AccountEmailStep> {
    const emailId = second ? attempt.secondEmailId : attempt.firstEmailId;
    const action = second ? 'prepare_second_factor' : 'prepare_first_factor';
    const body: Record<string, string> = { 'strategy': 'email_code', 'email_address_id': emailId };
    const response = this.signInResponse(attempt,
      await this.emailRequest(attempt, 'POST', `${SIGN_INS}/${attempt.id}/${action}`, body), false);
    const expected = second ? ['needs_second_factor', 'needs_client_trust'] : ['needs_first_factor'];
    if (!expected.includes(text(response.status))) throw new AccountBrowserRequiredError();
    if (second) return { kind: 'mfaEmail' };
    return { kind: 'emailCode', passwordAvailable: !!factor(response.supported_first_factors, 'password') };
  }

  private async initialCode(attempt: EmailAttempt, step: AccountEmailStep, second: boolean): Promise<AccountEmailStep> {
    try {
      return await this.sendEmailCode(attempt, second);
    } catch (error) {
      this.checkEmailAttempt(attempt);
      if (error instanceof AccountBrowserRequiredError) throw error;
      step.error = (error as Error).message || '无法发送验证码，请重试。';
      return step;
    }
  }

  private async finishEmail(attempt: EmailAttempt, reply: ClerkReply, allowNewId: boolean,
    chooseFirst: boolean): Promise<AccountEmailStep> {
    const response = this.signInResponse(attempt, reply, allowNewId);
    if (response.status === 'needs_first_factor' && chooseFirst) {
      const passwordAvailable = !!factor(response.supported_first_factors, 'password');
      attempt.firstEmailId = codeAddress(response.supported_first_factors);
      if (attempt.firstEmailId) return this.initialCode(attempt, { kind: 'emailCode', passwordAvailable }, false);
      if (passwordAvailable) return { kind: 'password', emailCodeAvailable: false };
    }
    if (response.status === 'needs_second_factor' || response.status === 'needs_client_trust') {
      attempt.secondEmailId = codeAddress(response.supported_second_factors);
      if (attempt.secondEmailId) return this.initialCode(attempt, { kind: 'mfaEmail' }, true);
      if (factor(response.supported_second_factors, 'totp')) return { kind: 'totp' };
      if (factor(response.supported_second_factors, 'backup_code')) return { kind: 'backupCode' };
    }
    if (response.status === 'complete') {
      const sessionId = text(response.created_session_id);
      if (!identifier(sessionId) || !attempt.clientToken) throw new Error('登录结果缺少可用的会话，请重试。');
      return this.serialize(async () => {
        this.checkEmailAttempt(attempt);
        if (this.active || this.signingOut) throw new Error('请先退出当前账号。');
        let client = reply.payload?.client ?? reply.payload?.meta?.client;
        if (!client) {
          const refreshed = await this.emailRequest(attempt, 'GET', '/client');
          client = refreshed.payload?.response ?? refreshed.payload;
        }
        const created = clientSession(client, sessionId);
        if (!created) throw new AccountBrowserRequiredError();
        const account = await this.activate(created, attempt.clientToken, () => this.checkEmailAttempt(attempt));
        const result: AccountEmailStep = { kind: 'complete', identity: account };
        return result;
      });
    }
    throw new AccountBrowserRequiredError();
  }

  private async advanceEmail(attempt: EmailAttempt, action: AccountEmailAction): Promise<AccountEmailStep> {
    if (action.kind === 'start') {
      await this.emailRequest(attempt, 'GET', '/client', undefined, true);
      const body: Record<string, string> = { 'identifier': attempt.identifier };
      return this.finishEmail(attempt, await this.emailRequest(attempt, 'POST', SIGN_INS, body), true, true);
    }
    const current = attempt.step;
    if (!current) throw new Error('请先开始邮箱登录。');
    if (action.kind === 'password' && current.kind === 'emailCode' && current.passwordAvailable) {
      return { kind: 'password', emailCodeAvailable: true };
    }
    if ((action.kind === 'emailCode' && current.kind === 'password' && current.emailCodeAvailable) ||
      (action.kind === 'resend' && (current.kind === 'emailCode' || current.kind === 'mfaEmail'))) {
      return this.sendEmailCode(attempt, current.kind === 'mfaEmail');
    }
    if (action.kind !== 'verify') throw new Error('当前登录方式不支持此操作。');
    const value = current.kind === 'password' ? text(action.value) : text(action.value).trim();
    if (!value) throw new Error('请输入登录凭据。');
    if (current.kind === 'password') {
      const body: Record<string, string> = { 'identifier': attempt.identifier, 'password': value };
      return this.finishEmail(attempt, await this.emailRequest(attempt, 'POST', SIGN_INS, body), true, false);
    }
    const strategy = current.kind === 'totp' ? 'totp' : current.kind === 'backupCode' ? 'backup_code' : 'email_code';
    const suffix = current.kind === 'emailCode' ? 'attempt_first_factor' : 'attempt_second_factor';
    const body: Record<string, string> = { 'strategy': strategy, 'code': value };
    return this.finishEmail(attempt,
      await this.emailRequest(attempt, 'POST', `${SIGN_INS}/${attempt.id}/${suffix}`, body), false, false);
  }

  async email(action: AccountEmailAction): Promise<AccountEmailStep> {
    const attempt = action.kind === 'start' ? this.beginEmail(text(action.value)) : this.emailAttempt;
    if (!attempt) throw new Error('没有可继续的邮箱登录，请重新开始。');
    this.checkEmailAttempt(attempt);
    if (attempt.busy) throw new Error('正在处理邮箱登录。');
    attempt.busy = true;
    try {
      const step = await this.advanceEmail(attempt, action);
      if (step.kind === 'complete') {
        if (this.emailAttempt === attempt) this.emailAttempt = undefined;
        return step;
      }
      this.checkEmailAttempt(attempt);
      attempt.step = step;
      return step;
    } catch (error) {
      this.checkEmailAttempt(attempt);
      if (error instanceof AccountBrowserRequiredError) {
        this.emailAttempt = undefined;
        return { kind: 'hosted' };
      }
      if (!attempt.step) this.emailAttempt = undefined;
      throw error as Error;
    } finally {
      attempt.busy = false;
    }
  }

  private requireActiveAccount(expected: AccountIdentity, epoch: number): SavedAccount {
    const saved = this.active;
    if (!saved || epoch !== this.epoch || saved.userId !== expected.userId || saved.sessionId !== expected.sessionId) {
      throw new AccountSessionExpiredError();
    }
    return saved;
  }

  private async checkActiveReply(reply: ClerkReply, epoch: number, targetsOtherSession: boolean = false): Promise<void> {
    if (epoch !== this.epoch) throw new AccountSessionExpiredError();
    if (hasClerkError(reply, 'session_reverification_required')) throw new AccountSessionReverificationRequiredError();
    if (targetsOtherSession && reply.status === 404 && hasClerkError(reply, 'session_not_found')) {
      throw new Error('该会话已不存在，请刷新会话列表。');
    }
    if (signedOut(reply)) {
      this.active = undefined;
      await this.store.clear();
    }
    requireSuccess(reply);
  }

  private async saveActiveCredential(reply: ClerkReply, saved: SavedAccount, epoch: number): Promise<void> {
    if (epoch !== this.epoch) throw new AccountSessionExpiredError();
    const next = rotatedToken(reply, saved.clientToken);
    if (next === saved.clientToken) return;
    const current = rotateAccount(saved, next);
    await this.store.save(current);
    if (epoch !== this.epoch) throw new AccountSessionExpiredError();
    this.active = current;
  }

  async updateProfileName(expected: AccountIdentity, update: AccountNameUpdate): Promise<AccountIdentity> {
    const epoch = this.epoch;
    const body: Record<string, string> = {};
    if (typeof update.firstName === 'string') body['first_name'] = update.firstName.trim();
    if (typeof update.lastName === 'string') body['last_name'] = update.lastName.trim();
    if (Object.keys(body).length === 0) throw new Error('请修改姓名后再保存。');
    return this.serialize(async () => {
      const saved = this.requireActiveAccount(expected, epoch);
      const path = `/me?_method=PATCH&_clerk_session_id=${encodeURIComponent(saved.sessionId)}`;
      const reply = await this.request({ method: 'POST', path, clientToken: saved.clientToken, body });
      await this.checkActiveReply(reply, epoch);
      const user = reply.payload?.response ?? reply.payload;
      const updated = user?.object === 'user' ? profileIdentity(user, saved.sessionId) : undefined;
      if (updated?.userId !== saved.userId) throw new Error('账号服务返回了无效的个人资料。');
      await this.saveActiveCredential(reply, saved, epoch);
      return updated;
    });
  }

  async listSessions(expected: AccountIdentity): Promise<AccountDeviceSession[]> {
    const epoch = this.epoch;
    return this.serialize(async () => {
      const saved = this.requireActiveAccount(expected, epoch);
      const path = `/me/sessions/active?_clerk_session_id=${encodeURIComponent(saved.sessionId)}`;
      const reply = await this.request({ method: 'GET', path, clientToken: saved.clientToken });
      await this.checkActiveReply(reply, epoch);
      const sessions = new Map<string, AccountDeviceSession>();
      for (const row of reply.sessionList ?? []) {
        if (row?.object !== 'session' || row.status !== 'active' || !row.id || !identifier(row.id)) continue;
        const lastActiveAt = row.last_active_at ?? 0;
        sessions.set(row.id, {
          id: row.id,
          deviceType: text(row.latest_activity?.device_type).trim(),
          browserName: text(row.latest_activity?.browser_name).trim(),
          lastActiveAt: Number.isFinite(lastActiveAt) && lastActiveAt > 0 ? lastActiveAt : 0,
        });
      }
      const current = sessions.get(saved.sessionId);
      if (!current) throw new Error('无法确认当前会话，请刷新会话列表。');
      sessions.delete(saved.sessionId);
      const others = Array.from(sessions.values()).sort((left: AccountDeviceSession, right: AccountDeviceSession) =>
        right.lastActiveAt - left.lastActiveAt);
      await this.saveActiveCredential(reply, saved, epoch);
      return [current, ...others];
    });
  }

  async revokeSession(expected: AccountIdentity, sessionId: string): Promise<void> {
    const epoch = this.epoch;
    return this.serialize(async () => {
      const saved = this.requireActiveAccount(expected, epoch);
      if (!identifier(sessionId)) throw new Error('会话标识无效，请刷新会话列表。');
      if (sessionId === saved.sessionId) throw new Error('请使用退出登录来结束当前会话。');
      const path = `/me/sessions/${encodeURIComponent(sessionId)}/revoke?_clerk_session_id=${encodeURIComponent(saved.sessionId)}`;
      const reply = await this.request({ method: 'POST', path, clientToken: saved.clientToken, body: {} });
      await this.checkActiveReply(reply, epoch, true);
      const revoked = reply.payload?.response ?? reply.payload;
      if (reply.status !== 204 && (revoked?.object !== 'session' || revoked.id !== sessionId ||
        revoked.status !== 'revoked')) {
        throw new Error('账号服务未确认该会话已退出，请刷新会话列表。');
      }
      await this.saveActiveCredential(reply, saved, epoch);
    });
  }

  async readRelayToken(): Promise<string> {
    const epoch = this.epoch;
    return this.serialize(async () => {
      const saved = this.active;
      if (!saved || epoch !== this.epoch) throw new AccountSessionExpiredError();
      const path = `/client/sessions/${saved.sessionId}/tokens/${encodeURIComponent(this.template)}`;
      const reply = await this.request({ method: 'POST', path, clientToken: saved.clientToken });
      await this.checkActiveReply(reply, epoch);
      await this.saveActiveCredential(reply, saved, epoch);
      const resource = reply.payload?.response ?? reply.payload;
      const token = text(resource?.jwt);
      if (!token || !credential(token)) throw new Error('账号服务未返回可用的 T3 Connect 令牌。');
      return token;
    });
  }

  async signOut(): Promise<void> {
    if (this.signingOut) throw new Error('正在退出账号。');
    this.signingOut = true;
    this.epoch++;
    const current = this.active;
    this.active = undefined;
    try {
      this.cancel();
      await this.serialize(async () => {
        const saved = current ?? await this.store.read();
        await this.store.clear();
        if (saved?.issuer !== this.issuer || !credential(saved.clientToken) || !identifier(saved.sessionId)) return;
        const reply = await this.request({ method: 'POST', path: `/client/sessions/${saved.sessionId}/remove`,
          clientToken: saved.clientToken });
        if (!signedOut(reply)) requireSuccess(reply);
      });
    } finally {
      this.signingOut = false;
    }
  }

  cancel(): void {
    this.attemptEpoch++;
    this.attempt = undefined;
    this.emailAttempt = undefined;
    this.store.clearAttempt();
  }
}
