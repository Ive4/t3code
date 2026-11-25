import { ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import type { Configuration } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { workspaceForegroundColor, workspaceHeaderColor, workspaceNavigationBarColor } from '../pages/UiTheme';
import { ACCOUNT_REDIRECT_URL, matchesAccountRedirect } from '../client/AccountProtocol';
import { parseThreadLink, THREAD_LINK_STORAGE_KEY } from '../client/ThreadLinkProtocol';

const PAIRING_LINK = 't3.arkts.pairingLink';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | undefined;
  private darkAppearance: boolean = false;
  private keyboardHeightChange = (height: number): void => {
    const visible = height > 0;
    if (AppStorage.get<boolean>('t3.arkts.keyboardVisible') !== visible) {
      AppStorage.setOrCreate<boolean>('t3.arkts.keyboardVisible', visible);
    }
  };

  onCreate(want: Want): void {
    this.onConfigurationUpdate(this.context.config);
    this.captureLink(want);
  }

  onConfigurationUpdate(config: Configuration): void {
    if (config.language) AppStorage.setOrCreate<string>('t3.arkts.systemLanguage', config.language);
    if (config.colorMode !== undefined) {
      this.darkAppearance = config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      AppStorage.setOrCreate<boolean>('t3.arkts.darkAppearance', this.darkAppearance);
      this.updateSystemBars();
    }
  }

  onNewWant(want: Want): void {
    this.captureLink(want);
  }

  onForeground(): void {
    AppStorage.setOrCreate<boolean>('t3.arkts.foreground', true);
  }

  onBackground(): void {
    AppStorage.setOrCreate<boolean>('t3.arkts.foreground', false);
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    try {
      this.mainWindow = stage.getMainWindowSync();
      this.mainWindow.on('keyboardHeightChange', this.keyboardHeightChange);
      this.updateSystemBars();
    } catch (_) {
      hilog.warn(0x0000, 'T3ArkTS', 'Could not observe keyboard visibility.');
    }
    stage.loadContent('pages/Index').catch(() => {
      hilog.error(0x0000, 'T3ArkTS', 'Could not load the main page.');
    });
  }

  onWindowStageDestroy(): void {
    try {
      this.mainWindow?.off('keyboardHeightChange', this.keyboardHeightChange);
    } catch (_) {
      hilog.warn(0x0000, 'T3ArkTS', 'Could not remove the keyboard listener.');
    }
    this.mainWindow = undefined;
    this.keyboardHeightChange(0);
  }

  private updateSystemBars(): void {
    const mainWindow = this.mainWindow;
    if (!mainWindow) return;
    const header = workspaceHeaderColor(this.darkAppearance);
    const foreground = workspaceForegroundColor(this.darkAppearance);
    try {
      mainWindow.setWindowBackgroundColor(header);
      void mainWindow.setWindowSystemBarProperties({
        statusBarColor: header,
        statusBarContentColor: foreground,
        navigationBarColor: workspaceNavigationBarColor(this.darkAppearance),
        navigationBarContentColor: foreground,
      }).catch(() => {
        hilog.warn(0x0000, 'T3ArkTS', 'Could not set the system bar colors.');
      });
    } catch (_) {
      hilog.warn(0x0000, 'T3ArkTS', 'Could not update the window colors.');
    }
  }

  private captureLink(want: Want): void {
    const uri = want.uri;
    if (!uri) return;
    if (matchesAccountRedirect(uri, ACCOUNT_REDIRECT_URL)) {
      AppStorage.setOrCreate<string>('t3.arkts.accountCallback', uri);
    } else if (/^t3code(?:-dev|-preview)?:\/\/pair(?:[?#/]|$)/.test(uri)) {
      AppStorage.setOrCreate<string>(PAIRING_LINK, uri);
    } else if (parseThreadLink(uri)) {
      AppStorage.setOrCreate<string>(THREAD_LINK_STORAGE_KEY, uri);
    }
  }
}
