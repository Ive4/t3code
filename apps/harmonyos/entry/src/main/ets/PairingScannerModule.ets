import { scanBarcode, scanCore } from '@kit.ScanKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { UITurboModule } from '@rnoh/react-native-openharmony';

export class PairingScannerModule extends UITurboModule {
  async scan(): Promise<string | null> {
    try {
      const result = await scanBarcode.startScanForResult(this.ctx.uiAbilityContext, {
        scanTypes: [scanCore.ScanType.QR_CODE],
      });
      return result.originalValue;
    } catch (error) {
      if ((error as BusinessError).code === 1000500002) {
        return null;
      }
      throw new Error('Scan Kit could not scan a pairing code.');
    }
  }
}
