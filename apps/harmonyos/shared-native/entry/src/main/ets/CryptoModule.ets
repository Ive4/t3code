import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';
import { UITurboModule } from '@rnoh/react-native-openharmony';

const DPOP_SIGNATURE_ALGORITHM = 'ECC|SHA256';

function readInteger(bytes: number[]): bigint {
  let value = 0n;
  for (const byte of bytes) {
    if (!Number.isInteger(byte) || byte < 0 || byte > 255) {
      throw new Error('Invalid P-256 key byte');
    }
    value = (value << 8n) | BigInt(byte);
  }
  return value;
}

function writeInteger(bytes: Uint8Array, offset: number, value: bigint | string | number): void {
  if (typeof value !== 'bigint' || value < 0n || (value >> 256n) !== 0n) {
    throw new Error('Invalid P-256 key parameter');
  }
  for (let index = offset + 31; index >= offset; index--) {
    bytes[index] = Number(value & 255n);
    value >>= 8n;
  }
}

async function signP256(
  privateKey: number[],
  input: cryptoFramework.DataBlob,
): Promise<cryptoFramework.DataBlob> {
  if (privateKey.length !== 32) {
    throw new Error('Invalid P-256 private key length');
  }
  const params = cryptoFramework.ECCKeyUtil.genECCCommonParamsSpec('NID_X9_62_prime256v1');
  const sk = readInteger(privateKey);
  if (sk <= 0n || sk >= params.n) {
    throw new Error('Invalid P-256 private key scalar');
  }
  const spec: cryptoFramework.ECCPriKeySpec = {
    algName: 'ECC',
    specType: cryptoFramework.AsyKeySpecType.PRIVATE_KEY_SPEC,
    params,
    sk,
  };
  const key = await cryptoFramework.createAsyKeyGeneratorBySpec(spec).generatePriKey();
  const signer = cryptoFramework.createSign(DPOP_SIGNATURE_ALGORITHM);
  await signer.init(key);
  return signer.sign(input);
}

export class CryptoModule extends UITurboModule {
  public randomUUID(): string {
    return util.generateRandomUUID();
  }

  public randomBytes(length: number): number[] {
    if (!Number.isInteger(length) || length < 0 || length > 65536) {
      throw new Error('Invalid random byte length');
    }
    if (length === 0) return [];
    return Array.from(cryptoFramework.createRandom().generateRandomSync(length).data);
  }

  public async digestBytes(algorithm: string, input: number[]): Promise<number[]> {
    return this.digest(algorithm, Uint8Array.from(input));
  }

  public async digestText(algorithm: string, input: string): Promise<number[]> {
    return this.digest(algorithm, new util.TextEncoder().encodeInto(input));
  }

  public async generateDpopKey(): Promise<number[]> {
    const key = await cryptoFramework.createAsyKeyGenerator('ECC256').generateKeyPair();
    const bytes = new Uint8Array(97);
    bytes[32] = 0x04;
    writeInteger(bytes, 0, key.priKey.getAsyKeySpec(cryptoFramework.AsyKeySpecItem.ECC_SK_BN));
    writeInteger(bytes, 33, key.pubKey.getAsyKeySpec(cryptoFramework.AsyKeySpecItem.ECC_PK_X_BN));
    writeInteger(bytes, 65, key.pubKey.getAsyKeySpec(cryptoFramework.AsyKeySpecItem.ECC_PK_Y_BN));
    return Array.from(bytes);
  }

  public async dpopKeyMatches(privateKey: number[], publicKey: number[]): Promise<boolean> {
    if (publicKey.length !== 65 || publicKey[0] !== 0x04) {
      return false;
    }
    const params = cryptoFramework.ECCKeyUtil.genECCCommonParamsSpec('NID_X9_62_prime256v1');
    const pk: cryptoFramework.Point = {
      x: readInteger(publicKey.slice(1, 33)),
      y: readInteger(publicKey.slice(33)),
    };
    const spec: cryptoFramework.ECCPubKeySpec = {
      algName: 'ECC',
      specType: cryptoFramework.AsyKeySpecType.PUBLIC_KEY_SPEC,
      params,
      pk,
    };
    const key = await cryptoFramework.createAsyKeyGeneratorBySpec(spec).generatePubKey();
    if (
      key.getAsyKeySpec(cryptoFramework.AsyKeySpecItem.ECC_PK_X_BN) !== pk.x ||
      key.getAsyKeySpec(cryptoFramework.AsyKeySpecItem.ECC_PK_Y_BN) !== pk.y
    ) {
      return false;
    }

    // Verify a local challenge against the independently imported public key.
    const challenge: cryptoFramework.DataBlob = {
      data: cryptoFramework.createRandom().generateRandomSync(32).data,
    };
    const signature = await signP256(privateKey, challenge);
    const verifier = cryptoFramework.createVerify(DPOP_SIGNATURE_ALGORITHM);
    await verifier.init(key);
    return verifier.verify(challenge, signature);
  }

  public async signDpop(privateKey: number[], signingInput: number[]): Promise<number[]> {
    const signature = await signP256(privateKey, { data: Uint8Array.from(signingInput) });
    return Array.from(signature.data);
  }

  private async digest(algorithm: string, input: Uint8Array): Promise<number[]> {
    const md = cryptoFramework.createMd(algorithm.replace('-', ''));
    await md.update({ data: input });
    return Array.from((await md.digest()).data);
  }
}
