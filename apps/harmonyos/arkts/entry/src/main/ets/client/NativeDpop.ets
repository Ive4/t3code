import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { url, util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

import { derToJose } from './DpopEncoding';

interface PublicJwk {
  crv: string;
  kty: string;
  x: string;
  y: string;
}

interface StoredJwk extends PublicJwk {
  d: string;
}

interface DpopHeader {
  typ: string;
  alg: string;
  jwk: PublicJwk;
}

interface DpopClaims {
  htm: string;
  htu: string;
  jti: string;
  iat: number;
  ath?: string;
}

interface InstallationKey {
  privateKey: cryptoFramework.PriKey;
  header: string;
  thumbprint: string;
}

const KEY_ALIAS = 't3code.cloud.dpop-proof-key';
const SIGNATURE_ALGORITHM = 'ECC|SHA256';
const BASE64 = new util.Base64Helper();
const UTF8 = new util.TextEncoder();

function encodeBase64Url(bytes: Uint8Array): string {
  return BASE64.encodeToStringSync(bytes, util.Type.BASIC_URL_SAFE).replace(/=+$/, '');
}

function encodeInteger(value: bigint | string | number): string {
  if (typeof value !== 'bigint' || value < 0n || (value >> 256n) !== 0n) {
    throw new Error('Invalid P-256 key parameter');
  }
  const bytes = new Uint8Array(32);
  for (let index = bytes.length - 1; index >= 0; index--) {
    bytes[index] = Number(value & 255n);
    value >>= 8n;
  }
  return encodeBase64Url(bytes);
}

function decodeInteger(value: string): bigint {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(value)) {
    throw new Error('Invalid P-256 key parameter');
  }
  const bytes = BASE64.decodeSync(value.replace(/-/g, '+').replace(/_/g, '/') + '=');
  if (bytes.length !== 32 || encodeBase64Url(bytes) !== value) {
    throw new Error('Invalid P-256 key parameter');
  }
  let scalar = 0n;
  for (const byte of bytes) scalar = (scalar << 8n) | BigInt(byte);
  return scalar;
}

function normalizedTarget(target: string): string {
  try {
    const parsed = url.URL.parseURL(target);
    if (/^https?:$/.test(parsed.protocol) && parsed.hostname && !parsed.username && !parsed.password) {
      parsed.search = '';
      parsed.hash = '';
      return parsed.toString();
    }
  } catch {
    // Report the invalid URL without exposing its query or credentials.
  }
  throw new Error('DPoP 请求地址无效。');
}

async function sha256(value: string): Promise<string> {
  const digest = cryptoFramework.createMd('SHA256');
  await digest.update({ data: UTF8.encodeInto(value) });
  return encodeBase64Url((await digest.digest()).data);
}

async function sign(privateKey: cryptoFramework.PriKey, data: cryptoFramework.DataBlob):
  Promise<cryptoFramework.DataBlob> {
  const signer = cryptoFramework.createSign(SIGNATURE_ALGORITHM);
  await signer.init(privateKey);
  return signer.sign(data);
}

async function installationKey(privateKey: cryptoFramework.PriKey, x: string, y: string): Promise<InstallationKey> {
  // RFC 7638 hashes the public members in lexicographic order.
  const jwk: PublicJwk = { crv: 'P-256', kty: 'EC', x, y };
  const header: DpopHeader = { typ: 'dpop+jwt', alg: 'ES256', jwk };
  return {
    privateKey,
    header: encodeBase64Url(UTF8.encodeInto(JSON.stringify(header))),
    thumbprint: await sha256(JSON.stringify(jwk)),
  };
}

async function restoreKey(document: string): Promise<InstallationKey> {
  try {
    const jwk = JSON.parse(document) as StoredJwk;
    if (!jwk || jwk.crv !== 'P-256' || jwk.kty !== 'EC') {
      throw new Error('Invalid P-256 key type');
    }
    const params = cryptoFramework.ECCKeyUtil.genECCCommonParamsSpec('NID_X9_62_prime256v1');
    const sk = decodeInteger(jwk.d);
    if (sk <= 0n || sk >= params.n) throw new Error('Invalid P-256 private key');
    const privateSpec: cryptoFramework.ECCPriKeySpec = {
      algName: 'ECC',
      specType: cryptoFramework.AsyKeySpecType.PRIVATE_KEY_SPEC,
      params,
      sk,
    };
    const privateKey = await cryptoFramework.createAsyKeyGeneratorBySpec(privateSpec).generatePriKey();
    const publicSpec: cryptoFramework.ECCPubKeySpec = {
      algName: 'ECC',
      specType: cryptoFramework.AsyKeySpecType.PUBLIC_KEY_SPEC,
      params,
      pk: { x: decodeInteger(jwk.x), y: decodeInteger(jwk.y) },
    };
    const publicKey = await cryptoFramework.createAsyKeyGeneratorBySpec(publicSpec).generatePubKey();
    const challenge = cryptoFramework.createRandom().generateRandomSync(32);
    const signature = await sign(privateKey, challenge);
    const verifier = cryptoFramework.createVerify(SIGNATURE_ALGORITHM);
    await verifier.init(publicKey);
    if (!(await verifier.verify(challenge, signature))) throw new Error('Mismatched P-256 key pair');
    return await installationKey(privateKey, jwk.x, jwk.y);
  } catch {
    throw new Error('本机保存的 DPoP 密钥无效。');
  }
}

async function readStoredKey(database: relationalStore.RdbStore): Promise<string | undefined> {
  const result = await database.querySql('SELECT value FROM secrets WHERE key = ?', [KEY_ALIAS]);
  try {
    return result.goToFirstRow() ? result.getString(0) : undefined;
  } finally {
    result.close();
  }
}

export class NativeDpop {
  private static loadingKey: Promise<InstallationKey> | undefined;
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async proof(method: string, target: string, accessToken?: string): Promise<string> {
    if (!method || /[^!#$%&'*+\-.^_\x60|~0-9A-Za-z]/.test(method)) throw new Error('DPoP 请求方法无效。');
    const htu = normalizedTarget(target);
    const key = await this.key();
    const claims: DpopClaims = {
      htm: method.toUpperCase(),
      htu,
      jti: util.generateRandomUUID(),
      iat: Math.floor(Date.now() / 1000),
      ath: accessToken ? await sha256(accessToken) : undefined,
    };
    const input = key.header + '.' + encodeBase64Url(UTF8.encodeInto(JSON.stringify(claims)));
    const signature = await sign(key.privateKey, { data: UTF8.encodeInto(input) });
    return input + '.' + encodeBase64Url(derToJose(signature.data));
  }

  async thumbprint(): Promise<string> {
    return (await this.key()).thumbprint;
  }

  private key(): Promise<InstallationKey> {
    if (NativeDpop.loadingKey === undefined) {
      NativeDpop.loadingKey = this.loadOrCreateKey().catch((error: Error) => {
        NativeDpop.loadingKey = undefined;
        throw error;
      });
    }
    return NativeDpop.loadingKey;
  }

  private async loadOrCreateKey(): Promise<InstallationKey> {
    // Reuse the previous Harmony client's encrypted storage and private JWK format.
    const database = await relationalStore.getRdbStore(this.context, {
      name: 'secure-storage.db',
      securityLevel: relationalStore.SecurityLevel.S3,
      encrypt: true,
    });
    await database.executeSql('CREATE TABLE IF NOT EXISTS secrets (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)');
    const existing = await readStoredKey(database);
    if (existing !== undefined) return restoreKey(existing);

    const generated = await cryptoFramework.createAsyKeyGenerator('ECC256').generateKeyPair();
    const jwk: StoredJwk = {
      crv: 'P-256',
      kty: 'EC',
      x: encodeInteger(generated.pubKey.getAsyKeySpec(cryptoFramework.AsyKeySpecItem.ECC_PK_X_BN)),
      y: encodeInteger(generated.pubKey.getAsyKeySpec(cryptoFramework.AsyKeySpecItem.ECC_PK_Y_BN)),
      d: encodeInteger(generated.priKey.getAsyKeySpec(cryptoFramework.AsyKeySpecItem.ECC_SK_BN)),
    };
    const id = await database.insert('secrets', { key: KEY_ALIAS, value: JSON.stringify(jwk) },
      relationalStore.ConflictResolution.ON_CONFLICT_IGNORE);
    if (id === -1) {
      const persisted = await readStoredKey(database);
      if (persisted === undefined) throw new Error('无法保存本机 DPoP 密钥。');
      return restoreKey(persisted);
    }
    return installationKey(generated.priKey, jwk.x, jwk.y);
  }
}
