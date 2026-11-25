import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import {
  ACCOUNT_REDIRECT_URL, AccountNetworkError, AccountProof, AccountStore, ClerkPayload, ClerkReply, ClerkRequest,
  ClerkSessionWithActivity, HostedAccountSession, SavedAccount, SavedHostedAttempt, clerkFapiUrl, matchesAccountRedirect,
} from './AccountProtocol';

export {
  ACCOUNT_REDIRECT_URL, ACCOUNT_BROWSER_TIMEOUT_MS, AccountEmailAction, AccountEmailStep, AccountIdentity,
  AccountDeviceSession, AccountMode, AccountNameUpdate, AccountSessionExpiredError, AccountSessionReverificationRequiredError,
} from './AccountProtocol';

export interface NativeAccountConfig {
  publishableKey: string;
  jwtTemplate: string;
  redirectUrl?: string;
}

const DATABASE_CONFIG: relationalStore.StoreConfig = {
  name: 'arkts-account.db',
  securityLevel: relationalStore.SecurityLevel.S3,
  encrypt: true,
};
const CREATE_ACCOUNT_TABLE = 'CREATE TABLE IF NOT EXISTS clerk_account (id INTEGER PRIMARY KEY, document TEXT NOT NULL)';
const CREATE_ATTEMPT_TABLE = 'CREATE TABLE IF NOT EXISTS clerk_attempt (id INTEGER PRIMARY KEY, state TEXT NOT NULL, ' +
  'document TEXT NOT NULL)';

class EncryptedAccountStore implements AccountStore {
  private context: common.UIAbilityContext;
  private database: relationalStore.RdbStore | undefined;
  private opening: Promise<relationalStore.RdbStore> | undefined;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  private async open(): Promise<relationalStore.RdbStore> {
    if (this.database) return this.database;
    if (!this.opening) {
      this.opening = relationalStore.getRdbStore(this.context, DATABASE_CONFIG).then(async (database) => {
        await database.executeSql(CREATE_ACCOUNT_TABLE);
        await database.executeSql(CREATE_ATTEMPT_TABLE);
        this.database = database;
        return database;
      }).catch(() => {
        this.opening = undefined;
        throw new Error('无法打开本机加密账号存储。');
      });
    }
    return this.opening;
  }

  private openForAttempt(): relationalStore.RdbStore {
    if (this.database) return this.database;
    try {
      const database = relationalStore.getRdbStoreSync(this.context, DATABASE_CONFIG);
      database.executeSync(CREATE_ACCOUNT_TABLE);
      database.executeSync(CREATE_ATTEMPT_TABLE);
      this.database = database;
      return database;
    } catch (error) {
      throw new Error('无法打开本机关联的加密登录请求。');
    }
  }

  private async readDocument<T>(sql: string): Promise<T | undefined> {
    const database = await this.open();
    const result = await database.querySql(sql);
    try {
      if (!result.goToFirstRow()) return undefined;
      return JSON.parse(result.getString(0)) as T;
    } catch (error) {
      throw new Error('保存的 T3 账号数据无法读取。');
    } finally {
      result.close();
    }
  }

  read(): Promise<SavedAccount | undefined> {
    return this.readDocument<SavedAccount>('SELECT document FROM clerk_account WHERE id = 1');
  }

  async save(account: SavedAccount): Promise<void> {
    const database = await this.open();
    await database.insert('clerk_account', { id: 1, document: JSON.stringify(account) },
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async clear(): Promise<void> {
    const database = await this.open();
    await database.executeSql('DELETE FROM clerk_account WHERE id = 1');
  }

  readAttempt(): Promise<SavedHostedAttempt | undefined> {
    return this.readDocument<SavedHostedAttempt>('SELECT document FROM clerk_attempt WHERE id = 1');
  }

  saveAttempt(attempt: SavedHostedAttempt): void {
    this.openForAttempt().insertSync('clerk_attempt', { id: 1, state: attempt.proof.state,
      document: JSON.stringify(attempt) }, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  consumeAttempt(state: string): boolean {
    const current = new relationalStore.RdbPredicates('clerk_attempt').equalTo('id', 1).equalTo('state', state);
    return this.openForAttempt().deleteSync(current) === 1;
  }

  clearAttempt(): void {
    this.openForAttempt().executeSync('DELETE FROM clerk_attempt WHERE id = 1');
  }
}

function clerkIssuer(publishableKey: string): string {
  try {
    const encoded = /^(?:pk_test_|pk_live_)([a-zA-Z0-9_+\/-]+={0,2})$/.exec(publishableKey.trim())?.[1];
    if (!encoded) throw new Error('Missing Clerk key.');
    const base64 = encoded.replace(/-/g, '+').replace(/_/g, '/');
    const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, '=');
    const host = util.TextDecoder.create('utf-8').decodeToString(new util.Base64Helper().decodeSync(padded));
    if (!/^(?:[a-z\d](?:[a-z\d-]{0,61}[a-z\d])?\.)+[a-z\d](?:[a-z\d-]{0,61}[a-z\d])?\$$/i.test(host)) {
      throw new Error('Invalid Clerk host.');
    }
    return 'https://' + host.slice(0, -1).toLowerCase();
  } catch (error) {
    throw new Error('此版本的 T3 账号配置无效。');
  }
}

async function createProof(): Promise<AccountProof> {
  const bytes = cryptoFramework.createRandom().generateRandomSync(32).data;
  const verifier = Array.from(bytes, (byte: number) => byte.toString(16).padStart(2, '0')).join('');
  const digest = cryptoFramework.createMd('SHA256');
  await digest.update({ data: new util.TextEncoder().encodeInto(verifier) });
  const challenge = new util.Base64Helper().encodeToStringSync((await digest.digest()).data)
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return { state: util.generateRandomUUID(), verifier, challenge };
}

async function requestClerk(issuer: string, input: ClerkRequest): Promise<ClerkReply> {
  const header: Record<string, string> = {
    'authorization': input.clientToken,
    'x-mobile': '1',
    'x-expo-sdk-version': '4.15.1',
    'accept': 'application/json',
  };
  if (input.method === 'POST') header['content-type'] = 'application/x-www-form-urlencoded';
  const body = input.body;
  const form = body ? Object.keys(body).map((name: string) =>
    `${encodeURIComponent(name)}=${encodeURIComponent(body[name])}`).join('&') : undefined;
  const request = http.createHttp();
  try {
    let response: http.HttpResponse;
    try {
      response = await request.request(clerkFapiUrl(issuer, input.path), {
        method: input.method === 'GET' ? http.RequestMethod.GET : http.RequestMethod.POST,
        header,
        extraData: form,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: 15000,
        readTimeout: 15000,
        maxRedirects: 0,
      });
    } catch (error) {
      throw new AccountNetworkError();
    }
    const responseHeaders = response.header as Record<string, Object>;
    const authorization = Object.keys(responseHeaders).find((name: string) => name.toLowerCase() === 'authorization');
    const value = authorization ? responseHeaders[authorization] : undefined;
    const clientToken = typeof value === 'string' ? value : undefined;
    const result = response.result;
    const reply: ClerkReply = { status: response.responseCode, clientToken };
    if (typeof result === 'string' && result.length > 0) {
      try {
        const payload = JSON.parse(result) as Object;
        if (Array.isArray(payload)) reply.sessionList = payload as ClerkSessionWithActivity[];
        else reply.payload = payload as ClerkPayload;
      } catch (error) {
        if (response.responseCode >= 200 && response.responseCode < 300) {
          throw new Error('T3 账号服务返回了无法解析的数据。');
        }
      }
    }
    return reply;
  } finally {
    request.destroy();
  }
}

export class NativeAccount extends HostedAccountSession {
  constructor(context: common.UIAbilityContext, config: NativeAccountConfig) {
    const issuer = clerkIssuer(config.publishableKey);
    const template = config.jwtTemplate.trim();
    const redirect = config.redirectUrl?.trim() || ACCOUNT_REDIRECT_URL;
    if (!template || !matchesAccountRedirect(redirect, redirect)) throw new Error('此版本的 T3 账号配置无效。');
    super(issuer, template, redirect, new EncryptedAccountStore(context),
      (input: ClerkRequest) => requestClerk(issuer, input), createProof);
  }
}
