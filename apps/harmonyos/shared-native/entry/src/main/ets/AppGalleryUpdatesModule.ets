import { updateManager } from '@kit.AppGalleryKit';
import { UITurboModule } from '@rnoh/react-native-openharmony';

export class AppGalleryUpdatesModule extends UITurboModule {
  private supportsUpdates(): boolean {
    const info = this.ctx.uiAbilityContext.applicationInfo;
    return info.appDistributionType === 'app_gallery' &&
      info.appProvisionType === 'release' &&
      canIUse('SystemCapability.AppGalleryService.Distribution.Update');
  }

  public async isAvailable(): Promise<boolean> {
    return this.supportsUpdates();
  }

  public async checkForUpdate(): Promise<boolean> {
    if (!this.supportsUpdates()) throw new Error('AppGallery updates are unavailable.');
    const context = this.ctx.uiAbilityContext;
    const check = await updateManager.checkAppUpdate(context);
    if (check.updateAvailable !== updateManager.UpdateAvailableCode.LATER_VERSION_EXIST) return false;
    const result = await updateManager.showUpdateDialog(context);
    if (result !== updateManager.ShowUpdateResultCode.SHOW_DIALOG_SUCCESS) {
      throw new Error('AppGallery could not display the update dialog.');
    }
    return true;
  }
}
