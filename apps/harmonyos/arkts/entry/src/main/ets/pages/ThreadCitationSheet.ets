import pasteboard from '@ohos.pasteboard';
import type { NativeThreadCitation } from '../client/ThreadCitationProtocol';

@Component
export struct ThreadCitationSheet {
  @Prop citation: NativeThreadCitation | undefined = undefined;
  onClose: () => void = () => {};
  onJump: (citation: NativeThreadCitation) => void = () => {};

  private jumpToMessage(): void {
    const citation = this.citation;
    if (citation === undefined) return;
    this.onClose();
    this.onJump(citation);
  }

  private async copyQuote(): Promise<void> {
    const text = this.citation?.text;
    if (text === undefined) return;
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '无法复制引用' });
    }
  }

  @Builder
  private Header() {
    Row({ space: 12 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(22)
          .fontColor([$r('sys.color.icon_primary')])
      }
      .id('thread-citation-close')
      .accessibilityText('关闭引用')
      .height(44)
      .width(44)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.onClose())
      Text('引用')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
    }
    .height(56)
    .width('100%')
    .padding({ left: 8, right: 20 })
  }

  @Builder
  private Quote() {
    Text() {
      Span((this.citation?.prefix ?? '').replace(/\s+/g, ' ').trimStart())
        .fontColor($r('sys.color.font_secondary'))
      Span(this.citation?.text ?? '')
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
      Span((this.citation?.suffix ?? '').replace(/\s+/g, ' ').trimEnd())
        .fontColor($r('sys.color.font_secondary'))
    }
    .id('thread-citation-quote')
    .padding({ left: 12 })
    .border({ width: { left: 4 }, color: $r('sys.color.icon_emphasize'), radius: 2 })
    .fontSize(16)
    .lineHeight(24)
    .wordBreak(WordBreak.BREAK_WORD)
    .width('100%')
    .copyOption(CopyOptions.LocalDevice)
  }

  @Builder
  private Actions() {
    Column() {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 14 }) {
          Text('↗').fontSize(21).width(22).textAlign(TextAlign.Center)
            .fontColor($r('sys.color.icon_primary'))
          Text('转到消息').fontSize(16).fontColor($r('sys.color.font_primary')).layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .id('thread-citation-jump')
      .width('100%')
      .height(52)
      .backgroundColor(Color.Transparent)
      .enabled(this.citation !== undefined)
      .onClick(() => this.jumpToMessage())
      Divider().margin({ left: 52 }).color($r('sys.color.comp_divider'))
      Button({ type: ButtonType.Normal }) {
        Row({ space: 14 }) {
          SymbolGlyph($r('sys.symbol.square_on_square_fill'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_primary')])
          Text('复制引用').fontSize(16).fontColor($r('sys.color.font_primary')).layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .id('thread-citation-copy')
      .width('100%')
      .height(52)
      .backgroundColor(Color.Transparent)
      .enabled(this.citation !== undefined)
      .onClick(() => { void this.copyQuote(); })
    }
    .width('100%')
    .borderRadius(16)
    .clip(true)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
  }

  build() {
    Column() {
      this.Header()
      Scroll() {
        Column({ space: 24 }) {
          Column() {
            this.Quote()
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .borderRadius(16)
          if (this.citation?.comment) {
            Column({ space: 8 }) {
              Text('评论').fontSize(14).fontColor($r('sys.color.font_secondary'))
                .padding({ left: 16 })
              Text(this.citation?.comment ?? '')
                .width('100%')
                .fontSize(16)
                .lineHeight(24)
                .fontColor($r('sys.color.font_primary'))
                .backgroundColor($r('sys.color.comp_background_tertiary'))
                .borderRadius(16)
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .wordBreak(WordBreak.BREAK_WORD)
                .copyOption(CopyOptions.LocalDevice)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          this.Actions()
        }
        .padding({ left: 20, right: 20, top: 12, bottom: 20 })
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
