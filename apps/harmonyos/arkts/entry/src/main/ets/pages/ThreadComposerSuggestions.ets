import { UiLanguage, uiText } from './UiLanguage';
import type { ComposerCommandContextRecord, ComposerCommandTriggerKind } from '../client/ComposerCommandProtocol';

export interface ThreadComposerSuggestion {
  id: string;
  kind: 'model-picker' | 'command' | 'skill' | 'file' | 'directory' | 'model' | 'thread' | 'environment' | 'pull-request';
  label: string;
  description?: string;
  replacement: string;
  record?: ComposerCommandContextRecord;
}

type SuggestionStatus = 'loading' | 'ready' | 'error';

@Component
export struct ThreadComposerSuggestions {
  @Prop language: UiLanguage = 'zh';
  @Prop kind: ComposerCommandTriggerKind = 'path';
  @Prop status: SuggestionStatus = 'ready';
  @Prop items: ThreadComposerSuggestion[] = [];
  onChoose: (item: ThreadComposerSuggestion) => void = () => {};

  private title(): string {
    switch (this.kind) {
      case 'slash-command': return uiText(this.language, '命令', 'Commands');
      case 'skill': return uiText(this.language, '技能', 'Skills');
      case 'pull-request': return uiText(this.language, '拉取请求', 'Pull requests');
      default: return this.items.every((item: ThreadComposerSuggestion) =>
        item.kind === 'file' || item.kind === 'directory') ? uiText(this.language, '文件', 'Files') : uiText(this.language, '提及', 'Mentions');
    }
  }

  private emptyText(): string {
    if (this.status === 'error') return uiText(this.language, '无法读取候选项', 'Could not load suggestions');
    if (this.status === 'loading') return this.kind === 'path' ? uiText(this.language, '正在搜索文件…', 'Searching files…') : uiText(this.language, '正在加载…', 'Loading…');
    switch (this.kind) {
      case 'slash-command': return uiText(this.language, '没有匹配的命令', 'No matching commands');
      case 'skill': return uiText(this.language, '没有匹配的技能', 'No matching skills');
      case 'pull-request': return uiText(this.language, '没有匹配的拉取请求', 'No matching pull requests');
      default: return uiText(this.language, '没有匹配的提及', 'No matching mentions');
    }
  }

  private icon(item: ThreadComposerSuggestion): Resource {
    switch (item.kind) {
      case 'file': return $r('sys.symbol.doc_plaintext');
      case 'directory': return $r('sys.symbol.folder');
      case 'thread': return $r('sys.symbol.message_on_message');
      case 'pull-request': return $r('sys.symbol.link');
      case 'skill': return $r('sys.symbol.folder');
      case 'environment': return $r('sys.symbol.computer');
      case 'model': return $r('sys.symbol.grid');
      default: return $r('sys.symbol.code_square');
    }
  }

  build() {
    Column() {
      Text(this.title()).width('100%').fontSize(11).fontWeight(FontWeight.Bold).letterSpacing(0.8)
        .fontColor($r('sys.color.font_secondary')).padding({ left: 14, right: 14, top: 10, bottom: 4 })
      if (this.items.length > 0) {
        Scroll() {
          Column() {
            ForEach(this.items, (item: ThreadComposerSuggestion, index: number) => {
              Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                Row({ space: 10 }) {
                  SymbolGlyph(this.icon(item)).fontSize(16).fontColor([$r('sys.color.icon_secondary')])
                  Text(item.label).fontSize(16).fontWeight(FontWeight.Medium)
                    .fontColor($r('sys.color.font_primary')).constraintSize({ maxWidth: item.description ? '50%' : '90%' })
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (item.description) {
                    Text(item.description).fontSize(12).fontColor($r('sys.color.font_secondary'))
                      .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }.width('100%')
              }
              .id('thread-completion-' + item.id).width('100%').constraintSize({ minHeight: 44 })
              .padding({ left: 14, right: 14, top: 8, bottom: 8 }).focusable(false)
              .accessibilityText(item.description ? `${item.label}，${item.description}` : item.label)
              .onClick(() => this.onChoose(item))
              if (index + 1 < this.items.length) {
                Divider().strokeWidth(0.5).color($r('sys.color.comp_divider'))
              }
            }, (item: ThreadComposerSuggestion) => item.id)
          }.width('100%')
        }.width('100%').constraintSize({ maxHeight: 180 }).scrollBar(BarState.Off)
      } else {
        Row({ space: 8 }) {
          if (this.status === 'loading') LoadingProgress().width(16).height(16)
          Text(this.emptyText()).fontSize(12).fontColor($r('sys.color.font_secondary'))
        }.width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 })
      }
    }
    .id('thread-completions').width('100%').borderRadius(16).clip(true)
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
  }
}
