import { UiLanguage, uiText } from './UiLanguage';

@Component
export struct ThreadDetailHeader {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop branchLabel: string = '';
  @Prop language: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  @Prop canOpenFiles: boolean = false;
  @Prop canOpenGit: boolean = false;
  @Prop canOpenTerminal: boolean = false;
  onBack: () => void = () => {};
  onOpenFiles: () => void = () => {};
  onOpenGit: () => void = () => {};
  onOpenReview?: () => void;
  onOpenTerminal: () => void = () => {};

  @Builder
  private GitMenu() {
    Menu() {
      if (this.branchLabel) {
        MenuItem({ content: this.branchLabel, labelInfo: uiText(this.language, '当前分支', 'Current branch') })
          .enabled(false)
      }
      if (this.onOpenReview) {
        MenuItem({ content: uiText(this.language, '审查变更', 'Review changes') })
          .id('thread-git-menu-review')
          .onClick(() => this.onOpenReview?.())
      }
      MenuItem({ content: uiText(this.language, '更多 Git 操作', 'More Git actions') })
        .id('thread-git-menu-overview')
        .onClick(() => this.onOpenGit())
    }
  }

  @Builder
  private TerminalMenu() {
    Menu() {
      MenuItem({ content: uiText(this.language, '打开终端', 'Open terminal') })
        .id('thread-terminal-open')
        .onClick(() => this.onOpenTerminal())
    }
  }

  build() {
    Row() {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.icon_primary')])
      }
      .id('thread-back')
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .accessibilityText(uiText(this.language, '返回', 'Back'))
      .onClick(() => this.onBack())

      Column() {
        Text(this.title)
          .fontSize(21)
          .lineHeight(28)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(13)
            .lineHeight(17)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .padding({ right: 4 })
      .alignItems(HorizontalAlign.Start)

      if (this.canOpenFiles) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(24)
            .fontColor([$r('sys.color.icon_primary')])
        }
        .id('thread-files')
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .accessibilityText(uiText(this.language, '打开文件', 'Open files'))
        .onClick(() => this.onOpenFiles())
      }

      if (this.canOpenGit) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_triangle_merge'))
            .fontSize(24)
            .fontColor([$r('sys.color.icon_primary')])
        }
        .id('thread-git')
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .accessibilityText(uiText(this.language, 'Git 操作', 'Git actions'))
        .bindMenu(this.GitMenu())
      }

      if (this.canOpenTerminal) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.code_square'))
            .fontSize(24)
            .fontColor([$r('sys.color.icon_primary')])
        }
        .id('thread-terminal')
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .accessibilityText(uiText(this.language, '终端操作', 'Terminal actions'))
        .bindMenu(this.TerminalMenu())
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 2, right: 4 })
    .backgroundColor(this.dark ? '#0A0A0A' : '#FCFCFC')
  }
}
