import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';
import { UITurboModule } from '@rnoh/react-native-openharmony';

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

  private async digest(algorithm: string, input: Uint8Array): Promise<number[]> {
    const md = cryptoFramework.createMd(algorithm.replace('-', ''));
    await md.update({ data: input });
    return Array.from((await md.digest()).data);
  }
}
