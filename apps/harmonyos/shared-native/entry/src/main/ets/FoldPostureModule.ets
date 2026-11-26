import { display, window } from '@kit.ArkUI';
import { UITurboModule } from '@rnoh/react-native-openharmony';

interface VerticalHinge {
  x: number;
  width: number;
}

export class FoldPostureModule extends UITurboModule {
  private observing = false;
  private readonly onPosture = (): void => {
    this.ctx.rnInstance.emitDeviceEvent('T3FoldPostureChanged', null);
  };

  public async readVerticalHinge(): Promise<VerticalHinge | null> {
    if (!display.isFoldable()) return null;

    if (!this.observing) {
      display.on('foldStatusChange', this.onPosture);
      display.on('foldDisplayModeChange', this.onPosture);
      this.observing = true;
    }
    if (display.getFoldStatus() !== display.FoldStatus.FOLD_STATUS_HALF_FOLDED) return null;

    const appWindow = await window.getLastWindow(this.ctx.uiAbilityContext);
    const bounds = appWindow.getWindowProperties().windowRect;
    const region = display.getCurrentFoldCreaseRegion();
    if (!region || region.displayId !== display.getDefaultDisplaySync().id) return null;

    const crease = region.creaseRects.find((rect) =>
      rect.width > 0 && rect.height > rect.width && rect.left > bounds.left &&
      rect.left + rect.width < bounds.left + bounds.width &&
      rect.top < bounds.top + bounds.height && rect.top + rect.height > bounds.top
    );
    if (!crease) return null;

    const uiContext = appWindow.getUIContext();
    return { x: uiContext.px2vp(crease.left - bounds.left), width: uiContext.px2vp(crease.width) };
  }

  public override __onDestroy__(): void {
    if (this.observing) {
      display.off('foldStatusChange', this.onPosture);
      display.off('foldDisplayModeChange', this.onPosture);
    }
  }
}
