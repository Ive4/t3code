import { ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import type { Configuration } from '@kit.AbilityKit';
import { ColorMetrics, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { workspaceForegroundColor } from '../pages/UiTheme';
import { ACCOUNT_REDIRECT_URL, matchesAccountRedirect } from '../client/AccountProtocol';
import { parseIncomingShareWant } from '../client/IncomingShareProtocol';
import { parseNotificationLaunchLink } from '../client/PushNotificationProtocol';
import { resolveSidebarWidthVp, resolveWorkspaceLayoutMode } from '../client/FoldableLayoutProtocol';
import { parseThreadLink, THREAD_LINK_STORAGE_KEY } from '../client/ThreadLinkProtocol';

const PAIRING_LINK = 't3.arkts.pairingLink';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | undefined;
  private darkAppearance: boolean = false;
  private windowSizeChange = (size: window.Size): void => {
    const widthVp = px2vp(size.width);
    const heightVp = px2vp(size.height);
    const mode = resolveWorkspaceLayoutMode({ widthVp, heightVp, foldPosture: 'unknown' });
    const sidebarWidth = resolveSidebarWidthVp(widthVp);
    AppStorage.setOrCreate<string>('t3.arkts.layoutMode', mode);
    AppStorage.setOrCreate<number>('t3.arkts.sidebarWidthVp', sidebarWidth);
  };
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
    this.updateSystemBars();
  }

  onBackground(): void {
    AppStorage.setOrCreate<boolean>('t3.arkts.foreground', false);
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    try {
      this.mainWindow = stage.getMainWindowSync();
      this.mainWindow.on('keyboardHeightChange', this.keyboardHeightChange);
      this.mainWindow.on('windowSizeChange', this.windowSizeChange);
      this.windowSizeChange(this.mainWindow.getWindowProperties().windowRect);
      this.updateSystemBars();
    } catch (_) {
      hilog.warn(0x0000, 'T3ArkTS', 'Could not observe keyboard visibility.');
    }
    stage.loadContent('pages/Index').then(() => {
      this.updateSystemBars();
    }).catch(() => {
      hilog.error(0x0000, 'T3ArkTS', 'Could not load the main page.');
    });
  }

  onWindowStageDestroy(): void {
    try {
      this.mainWindow?.off('keyboardHeightChange', this.keyboardHeightChange);
      this.mainWindow?.off('windowSizeChange', this.windowSizeChange);
    } catch (_) {
      hilog.warn(0x0000, 'T3ArkTS', 'Could not remove the keyboard listener.');
    }
    this.mainWindow = undefined;
    this.keyboardHeightChange(0);
  }

  private updateSystemBars(): void {
    const mainWindow = this.mainWindow;
    if (!mainWindow) return;
    const foreground = workspaceForegroundColor(this.darkAppearance);
    try {
      void mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: foreground,
        navigationBarColor: '#00000000',
        navigationBarContentColor: foreground,
      }).then(() => {
        return mainWindow.setStatusBarColor(ColorMetrics.resourceColor(foreground));
      }).catch(() => {
        hilog.warn(0x0000, 'T3ArkTS', 'Could not set the system bar colors.');
      });
    } catch (_) {
      hilog.warn(0x0000, 'T3ArkTS', 'Could not update the window colors.');
    }
  }

  private captureLink(want: Want): void {
    const share = parseIncomingShareWant(
      want.action ?? '',
      (want.parameters ?? {}) as Record<string, Object | undefined>,
      want.uri,
    );
    if (share) {
      AppStorage.setOrCreate<string>('t3.arkts.incomingShare', JSON.stringify(share));
      return;
    }
    const notificationTarget = parseNotificationLaunchLink(
      (want.parameters ?? {}) as Record<string, Object | undefined>,
    );
    if (notificationTarget) {
      AppStorage.setOrCreate<string>('t3.arkts.notificationTarget', JSON.stringify(notificationTarget));
      return;
    }
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
