import { window } from '@kit.ArkUI';
import { UITurboModule } from '@rnoh/react-native-openharmony';

export class ScreenAwakeModule extends UITurboModule {
  private awakeWindow: window.Window | undefined;
  private destroyed = false;

  public async setKeepScreenOn(enabled: boolean): Promise<void> {
    if (!enabled) {
      await this.releaseWindow();
      return;
    }
    if (this.destroyed || this.awakeWindow !== undefined) return;
    const appWindow = await this.ctx.rnInstance.getRNWindow();
    if (this.destroyed || appWindow.getWindowProperties().isKeepScreenOn) return;
    await appWindow.setWindowKeepScreenOn(true);
    this.awakeWindow = appWindow;
    if (this.destroyed) await this.releaseWindow();
  }

  private async releaseWindow(): Promise<void> {
    if (this.awakeWindow === undefined) return;
    await this.awakeWindow.setWindowKeepScreenOn(false);
    this.awakeWindow = undefined;
  }

  public override __onDestroy__(): void {
    this.destroyed = true;
    void this.releaseWindow().catch((error: Error) => {
      this.ctx.logger.warn('Unable to release the Harmony screen wake lock', error);
    });
  }
}
