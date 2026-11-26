import { webview } from '@kit.ArkWeb';
import { normalizeBrowserPreviewUrl } from '../client/BrowserPreviewProtocol';
import type { BrowserPreviewCommand, BrowserPreviewTab } from '../client/BrowserPreviewProtocol';
import { UiLanguage, uiText } from './UiLanguage';
import { workspaceForegroundColor, workspaceHeaderColor, workspaceMutedColor, workspaceSurfaceColor } from './WorkspaceChrome';

@Component
export struct BrowserPreviewView {
  @Prop language: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  @Prop tabs: BrowserPreviewTab[] = [];
  @Prop selectedTabId: string = '';
  @Prop initialUrl: string = '';
  onBack: () => void = () => {};
  onSelectTab: (tabId: string) => void = () => {};
  onCommand: (command: BrowserPreviewCommand) => void = () => {};

  @State private addressDraft: string = '';
  @State private canGoBack: boolean = false;
  @State private canGoForward: boolean = false;
  @State private loading: boolean = false;
  @State private errorText: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    const active = this.tabs.find((tab) => tab.tabId === this.selectedTabId) ?? this.tabs[0];
    this.addressDraft = active?.url ?? this.initialUrl;
  }

  private text(zh: string, en: string): string {
    return uiText(this.language, zh, en);
  }

  private submitAddress(): void {
    const normalized = normalizeBrowserPreviewUrl(this.addressDraft);
    if (!normalized) {
      this.errorText = this.text('请输入有效的 http 或 https 地址。', 'Enter a valid http or https URL.');
      return;
    }
    this.errorText = '';
    this.addressDraft = normalized;
    try {
      this.controller.loadUrl(normalized);
    } catch (_) {
      // Remote stream tabs route navigation through onCommand.
    }
    this.onCommand({ type: 'navigate', url: normalized });
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.arrow_left')).fontSize(22).fontColor([workspaceForegroundColor(this.dark)])
        }
        .width(40)
        .height(40)
        .onClick(() => this.onBack())

        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20).fontColor([
            this.canGoBack ? workspaceForegroundColor(this.dark) : workspaceMutedColor(this.dark),
          ])
        }
        .width(36)
        .height(36)
        .enabled(this.canGoBack)
        .onClick(() => {
          try {
            this.controller.backward();
          } catch (_) {}
          this.onCommand({ type: 'history', delta: -1 });
        })

        TextInput({ text: this.addressDraft, placeholder: 'https://...' })
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .fontColor(workspaceForegroundColor(this.dark))
          .placeholderColor(workspaceMutedColor(this.dark))
          .onChange((value: string) => {
            this.addressDraft = value;
          })
          .onSubmit(() => this.submitAddress())

        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor([workspaceForegroundColor(this.dark)])
        }
        .width(36)
        .height(36)
        .onClick(() => {
          try {
            this.controller.refresh();
          } catch (_) {}
          this.onCommand({ type: 'reload' });
        })
      }
      .width('100%')
      .padding({ left: 8, right: 12, top: 8, bottom: 8 })
      .backgroundColor(workspaceHeaderColor(this.dark))

      if (this.tabs.length > 1) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.tabs, (tab: BrowserPreviewTab) => {
              Button(tab.title || tab.url || tab.tabId)
                .fontSize(13)
                .height(30)
                .backgroundColor(tab.tabId === this.selectedTabId ? workspaceSurfaceColor(this.dark) : Color.Transparent)
                .fontColor(workspaceForegroundColor(this.dark))
                .onClick(() => {
                  this.addressDraft = tab.url;
                  this.onSelectTab(tab.tabId);
                })
            }, (tab: BrowserPreviewTab) => tab.tabId)
          }
          .padding({ left: 12, right: 12, bottom: 8 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .backgroundColor(workspaceHeaderColor(this.dark))
      }

      if (this.errorText) {
        Text(this.errorText)
          .fontSize(13)
          .fontColor('#E5484D')
          .width('100%')
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      }

      if (this.addressDraft) {
        Web({ src: this.addressDraft, controller: this.controller })
          .layoutWeight(1)
          .width('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onPageBegin(() => {
            this.loading = true;
          })
          .onPageEnd(() => {
            this.loading = false;
            try {
              this.canGoBack = this.controller.accessBackward();
              this.canGoForward = this.controller.accessForward();
            } catch (_) {}
          })
      } else {
        Column() {
          Text(this.text('输入地址以开始浏览器预览。', 'Enter a URL to start browser preview.'))
            .fontSize(15)
            .fontColor(workspaceMutedColor(this.dark))
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(workspaceSurfaceColor(this.dark))
  }
}
