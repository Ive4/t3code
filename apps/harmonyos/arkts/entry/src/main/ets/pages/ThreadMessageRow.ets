import { common } from '@kit.AbilityKit';
import { url } from '@kit.ArkTS';
import pasteboard from '@ohos.pasteboard';
import type { NativeMessage, NativeThreadAttachment } from '../client/T3Protocol';
import { isVideoThreadAttachment, threadAttachmentPreviewKind } from '../client/NativeThreadAttachmentPreview';
import type { NativeThreadCheckpointSummary } from '../client/ThreadCheckpointProtocol';
import type { NativeThreadForkSource } from '../client/ThreadForkProtocol';
import type { NativeThreadCitation, ThreadCitationSelector } from '../client/ThreadCitationProtocol';
import { canLocatePlainThreadCitation, createThreadCitationSelector, threadCitationPreview } from '../client/ThreadCitationProtocol';
import type { ThreadMarkdownSection, ThreadMarkdownSpan, ThreadMarkdownTableAlignment, ThreadMessageBlock } from './ThreadMessageFormat';
import { isMarkdownWebLink, threadMessageBlocks } from './ThreadMessageFormat';
import { ThreadHistoricalReviewCommentCard } from './ThreadHistoricalReviewCommentCard';
import { UiLanguage, uiText } from './UiLanguage';

const MESSAGE_FONT_SIZE = 16;
const MESSAGE_LINE_HEIGHT = 24;
const MESSAGE_PREVIEW_LINES = 7;
const USER_WIDTH = 0.85;
const USER_HORIZONTAL_PADDING = 12;
const MINIMUM_TABLE_CELL_WIDTH = 96;
const CODE_LINE_HEIGHT = 19;
const CODE_PREVIEW_HEIGHT = CODE_LINE_HEIGHT * 7;
const COPY_SOURCE_ACTION = 't3-copy-message-source';
const QUOTE_ACTION = 't3-quote-selection';

@Component
struct ThreadCodeBlock {
  @Prop rowId: string = '';
  @Prop text: string = '';
  @Prop language: string = '';
  @Prop expanded: boolean = false;
  @Prop languageMode: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  @State private contentHeight: number = 0;
  onToggle: () => void = () => {};

  build() {
    Column({ space: 4 }) {
      if (this.language) {
        Text(this.language)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Scroll() {
        Text(this.text)
          .width('100%')
          .fontFamily('monospace')
          .fontSize(13)
          .lineHeight(CODE_LINE_HEIGHT)
          .fontColor($r('sys.color.font_primary'))
          .wordBreak(WordBreak.BREAK_ALL)
          .copyOption(CopyOptions.LocalDevice)
          .onSizeChange((_previous: SizeOptions, current: SizeOptions) => {
            if (typeof current.height === 'number') this.contentHeight = current.height;
          })
      }
      .width('100%')
      .constraintSize({ maxHeight: this.expanded ? 304 : CODE_PREVIEW_HEIGHT })
      .align(Alignment.TopStart)
      .enableScrollInteraction(this.expanded)
      .scrollBar(this.expanded ? BarState.Auto : BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .nestedScroll({
        scrollForward: NestedScrollMode.SELF_FIRST,
        scrollBackward: NestedScrollMode.SELF_FIRST,
      })
      if (this.contentHeight > CODE_PREVIEW_HEIGHT + 1) {
        Button(this.expanded ? uiText(this.languageMode, '收起代码', 'Collapse code') :
          uiText(this.languageMode, '展开代码', 'Expand code'), { type: ButtonType.Normal })
          .id(`thread-code-toggle-${this.rowId}`)
          .height(44)
          .padding({ left: 8, right: 8 })
          .alignSelf(ItemAlign.End)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .backgroundColor(Color.Transparent)
          .accessibilityStateDescription(this.expanded ? uiText(this.languageMode, '已展开', 'Expanded') :
            uiText(this.languageMode, '已收起', 'Collapsed'))
          .onClick(() => this.onToggle())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 11, right: 11, top: 9, bottom: 9 })
    .border({ width: 1, color: this.dark ? '#262626' : '#E4E4E7' })
    .borderRadius(8)
    .backgroundColor(this.dark ? '#111111' : '#FFFFFF')
  }
}

@Component
export struct ThreadMessageRow {
  @Prop @Watch('updateBlocks') message: NativeMessage = { id: '', role: 'assistant', text: '' };
  @Prop expanded: boolean = false;
  @Prop expandedCodeBlocks: number[] = [];
  @Prop attachmentNames: string[] = [];
  @Prop quoteEnabled: boolean = false;
  @Prop citationEnabled: boolean = false;
  @Prop attachmentEnabled: boolean = false;
  @Prop checkpoint?: NativeThreadCheckpointSummary = undefined;
  @Prop checkpointEnabled: boolean = false;
  @Prop forkEnabled: boolean = false;
  @Prop forkBusy: boolean = false;
  @Prop language: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  @Prop isLastAssistant: boolean = false;
  onToggle: () => void = () => {};
  onToggleCode?: (index: number) => void;
  onQuote: (messageId: string, selector: ThreadCitationSelector) => void = () => {};
  onOpenCitation: (citation: NativeThreadCitation) => void = () => {};
  onOpenAttachment: (attachment: NativeThreadAttachment) => void = () => {};
  onOpenCheckpoint: (checkpoint: NativeThreadCheckpointSummary) => void = () => {};
  onFork: (source: NativeThreadForkSource) => void = () => {};
  @State private blocks: ThreadMessageBlock[] = [];
  @State private rowWidth: number = 0;
  @State private localExpandedCodes: number[] = [];
  private measuredText: string = '';
  private measuredWidth: number = 0;
  private measuredCanCollapse: boolean = false;
  private quoteSource: string = '';
  private selectionStart: number = -1;
  private selectionEnd: number = -1;
  private sourceMenu: EditMenuOptions = {
    onCreateMenu: (items: TextMenuItem[]): TextMenuItem[] => {
      const source: TextMenuItem = { id: TextMenuItemId.of(COPY_SOURCE_ACTION),
        content: uiText(this.language, '复制原文', 'Copy source') };
      return this.withQuoteAction([...items, source]);
    },
    onPrepareMenu: (items: TextMenuItem[]): TextMenuItem[] => this.withQuoteAction(items),
    onMenuItemClick: (item: TextMenuItem, range: TextRange): boolean => {
      if (item.id.equals(TextMenuItemId.of(COPY_SOURCE_ACTION))) {
        void this.copySource();
        return true;
      }
      if (item.id.equals(TextMenuItemId.of(QUOTE_ACTION))) {
        if (range.start === this.selectionStart && range.end === this.selectionEnd) {
          const selector = this.selectedQuote(range.start, range.end);
          if (selector !== undefined) this.onQuote(this.message.id, selector);
        }
        return true;
      }
      return false;
    },
  };

  aboutToAppear(): void {
    this.updateBlocks();
  }

  private updateBlocks(): void {
    this.blocks = threadMessageBlocks(this.message.text, this.message.role === 'user', this.message.context);
    this.selectionStart = -1;
    this.selectionEnd = -1;
    this.quoteSource = '';
    const block = this.blocks[0];
    if (this.message.role === 'assistant' && this.message.streaming !== true && this.blocks.length === 1 &&
      block?.kind === 'text' && block.prose === undefined && canLocatePlainThreadCitation(block.text)) {
      this.quoteSource = block.text;
    }
  }

  private selectedQuote(start?: number, end?: number): ThreadCitationSelector | undefined {
    if (!this.quoteEnabled || !this.quoteSource || this.message.streaming === true) return undefined;
    return createThreadCitationSelector(this.quoteSource, start, end);
  }

  private withQuoteAction(items: TextMenuItem[]): TextMenuItem[] {
    const id = TextMenuItemId.of(QUOTE_ACTION);
    const itemsWithoutQuote = items.filter((item: TextMenuItem) => !item.id.equals(id));
    if (this.selectedQuote(this.selectionStart, this.selectionEnd) === undefined) return itemsWithoutQuote;
    const action: TextMenuItem = { id, content: uiText(this.language, '引用选中文字', 'Quote selected text') };
    return [...itemsWithoutQuote, action];
  }

  private async copySource(feedback: boolean = false): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.message.text);
      await pasteboard.getSystemPasteboard().setData(data);
      if (feedback) this.getUIContext().getPromptAction().showToast({ message: uiText(this.language, '已复制', 'Copied') });
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: uiText(this.language, '无法复制原文', 'Could not copy message') });
    }
  }

  private async openWebLink(value: string): Promise<void> {
    if (!isMarkdownWebLink(value)) return;
    try {
      const parsed = url.URL.parseURL(value);
      if ((parsed.protocol !== 'https:' && parsed.protocol !== 'http:') ||
        !parsed.hostname || parsed.username || parsed.password) return;
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (!context) return;
      await context.startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: parsed.toString(),
      });
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: uiText(this.language, '无法打开链接', 'Could not open link') });
    }
  }

  private canCollapseMessage(): boolean {
    const width = Math.floor(this.rowWidth * USER_WIDTH) - USER_HORIZONTAL_PADDING * 2;
    if (this.message.role !== 'user' || width < 1 || this.blocks.length === 0 ||
      this.blocks.some((block: ThreadMessageBlock) => block.kind === 'review-comment')) return false;
    const text = this.message.text;
    if (this.measuredWidth === width && this.measuredText === text) return this.measuredCanCollapse;

    const context = this.getUIContext();
    const measured = context.getMeasureUtils().measureTextSize({
      textContent: text,
      constraintWidth: width,
      fontSize: MESSAGE_FONT_SIZE,
      lineHeight: MESSAGE_LINE_HEIGHT,
      maxLines: MESSAGE_PREVIEW_LINES * 2,
      wordBreak: WordBreak.BREAK_WORD,
    });
    this.measuredWidth = width;
    this.measuredText = text;
    this.measuredCanCollapse = typeof measured.height === 'number' &&
      context.px2vp(measured.height) >= MESSAGE_LINE_HEIGHT * (MESSAGE_PREVIEW_LINES * 2 - 1);
    return this.measuredCanCollapse;
  }

  private codeIsExpanded(index: number): boolean {
    const codes = this.onToggleCode ? this.expandedCodeBlocks : this.localExpandedCodes;
    return codes.includes(index);
  }

  private toggleCode(index: number): void {
    if (this.onToggleCode) {
      this.onToggleCode(index);
      return;
    }
    this.localExpandedCodes = this.localExpandedCodes.includes(index)
      ? this.localExpandedCodes.filter((value: number) => value !== index)
      : [...this.localExpandedCodes, index];
  }

  private headingSize(section?: ThreadMarkdownSection): number {
    if (section?.kind !== 'heading') return MESSAGE_FONT_SIZE;
    return Math.max(17, 23 - section.level);
  }

  private canCopyReply(): boolean {
    return this.isLastAssistant && this.message.role === 'assistant' && !this.message.streaming && !!this.message.text;
  }

  private standaloneMedia(attachment: NativeThreadAttachment): boolean {
    return this.message.role === 'user' &&
      (threadAttachmentPreviewKind(attachment) === 'image' || isVideoThreadAttachment(attachment));
  }

  private hasMessageBody(): boolean {
    return this.blocks.length > 0 || this.message.streaming === true || this.checkpoint !== undefined ||
      this.message.forkSource !== undefined || (this.message.attachments ?? []).some((attachment: NativeThreadAttachment) =>
        !this.standaloneMedia(attachment)) || this.attachmentNames.some((name: string) =>
        !this.message.attachments?.some((attachment: NativeThreadAttachment) => attachment.name === name));
  }

  private sectionAt(block: number, section: number): ThreadMarkdownSection | undefined {
    return this.blocks[block]?.prose?.[section];
  }

  private spanAt(block: number, section: number, span: number, column?: number): ThreadMarkdownSpan | undefined {
    return column === undefined ? this.sectionAt(block, section)?.spans[span] :
      this.blocks[block]?.table?.rows[section]?.[column]?.[span];
  }

  private citationLabel(block: number, section: number, span: number, column?: number): string {
    const citation = this.spanAt(block, section, span, column)?.citation;
    return citation === undefined ? '' : threadCitationPreview(citation);
  }

  private openCitation(block: number, section: number, span: number, column?: number): void {
    const citation = this.spanAt(block, section, span, column)?.citation;
    if (this.citationEnabled && this.message.streaming !== true && citation !== undefined) {
      this.onOpenCitation(citation);
    }
  }

  @Builder
  private MarkdownSpan(block: number, section: number, span: number, column?: number) {
    if (this.spanAt(block, section, span, column)?.kind === 'link') {
      Span(this.spanAt(block, section, span, column)?.text ?? '')
        .fontColor($r('sys.color.icon_emphasize'))
        .decoration({ type: TextDecorationType.Underline })
        .onClick(() => void this.openWebLink(this.spanAt(block, section, span, column)?.href ?? ''))
    } else if (this.spanAt(block, section, span, column)?.kind === 'code') {
      Span(this.spanAt(block, section, span, column)?.text ?? '')
        .fontFamily('monospace')
        .fontSize(14)
        .textBackgroundStyle({ color: $r('sys.color.comp_background_tertiary'), radius: 3 })
    } else if (this.citationEnabled && this.message.streaming !== true &&
      this.spanAt(block, section, span, column)?.citation !== undefined) {
      Span(this.citationLabel(block, section, span, column))
        .fontWeight(FontWeight.Medium)
        .textBackgroundStyle({ color: '#268A70DD', radius: 4 })
        .onClick(() => this.openCitation(block, section, span, column))
    } else if (this.spanAt(block, section, span, column)?.kind === 'citation') {
      Span(this.spanAt(block, section, span, column)?.text ?? '')
        .fontColor($r('sys.color.font_secondary'))
        .fontStyle(FontStyle.Italic)
    } else {
      Span(this.spanAt(block, section, span, column)?.text ?? '')
        .fontWeight(this.spanAt(block, section, span, column)?.kind === 'strong' ||
          this.spanAt(block, section, span, column)?.kind === 'strong-emphasis' ||
          (column === undefined ? this.sectionAt(block, section)?.kind === 'heading' : section === 0) ?
          FontWeight.Bold : FontWeight.Regular)
        .fontStyle(this.spanAt(block, section, span, column)?.kind === 'emphasis' ||
          this.spanAt(block, section, span, column)?.kind === 'strong-emphasis' ? FontStyle.Italic : FontStyle.Normal)
    }
  }

  private tableCellWidth(block: number): number {
    const available = this.message.role === 'user' ?
      this.rowWidth * USER_WIDTH - USER_HORIZONTAL_PADDING * 2 : this.rowWidth;
    const columns = this.blocks[block]?.table?.alignments.length ?? 1;
    return Math.max(MINIMUM_TABLE_CELL_WIDTH, Math.floor((available - 2) / columns));
  }

  private tableTextAlign(block: number, column: number): TextAlign {
    const value = this.blocks[block]?.table?.alignments[column];
    return value === 'right' ? TextAlign.End : value === 'center' ? TextAlign.Center : TextAlign.Start;
  }

  @Builder
  private MarkdownTable(block: number) {
    Scroll() {
      Column() {
        ForEach(this.blocks[block]?.table?.rows ?? [], (_row: ThreadMarkdownSpan[][], rowIndex: number) => {
          Flex({ alignItems: ItemAlign.Stretch }) {
            ForEach(this.blocks[block]?.table?.alignments ?? [],
              (_alignment: ThreadMarkdownTableAlignment, column: number) => {
                Column() {
                  Text() {
                    ForEach(this.blocks[block]?.table?.rows[rowIndex]?.[column] ?? [],
                      (_span: ThreadMarkdownSpan, index: number) => this.MarkdownSpan(block, rowIndex, index, column),
                      (_span: ThreadMarkdownSpan, index: number) => index.toString())
                  }
                  .width('100%')
                  .fontSize(14)
                  .lineHeight(20)
                  .fontColor(this.dark ? '#F5F5F5' : '#27272A')
                  .textAlign(this.tableTextAlign(block, column))
                  .wordBreak(WordBreak.BREAK_WORD)
                  .copyOption(CopyOptions.LocalDevice)
                  .editMenuOptions(this.sourceMenu)
                }
                .width(this.tableCellWidth(block))
                .constraintSize({ minHeight: 32 })
                .padding({ left: 9, right: 9, top: 6, bottom: 6 })
                .border({ width: { left: column === 0 ? 0 : 1 }, color: this.dark ? '#262626' : '#E4E4E7' })
              }, (_alignment: ThreadMarkdownTableAlignment, column: number) => column.toString())
          }
          .width(this.tableCellWidth(block) * (this.blocks[block]?.table?.alignments.length ?? 1))
          .backgroundColor(rowIndex === 0 ? (this.dark ? '#1A1B1B' : '#F4F4F5') : Color.Transparent)
          .border({ width: { top: rowIndex === 0 ? 0 : 1 }, color: this.dark ? '#262626' : '#E4E4E7' })
        }, (_row: ThreadMarkdownSpan[][], rowIndex: number) => rowIndex.toString())
      }
      .alignItems(HorizontalAlign.Start)
    }
    .id(`thread-table-${this.message.id}-${block}`)
    .width('100%')
    .align(Alignment.TopStart)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Auto)
    .border({ width: 1, color: this.dark ? '#262626' : '#E4E4E7' })
    .borderRadius(8)
    .clip(true)
  }

  @Builder
  private MarkdownSection(block: number, section: number) {
    Row({ space: 6 }) {
      if (this.sectionAt(block, section)?.kind === 'list') {
        Text(this.sectionAt(block, section)?.marker ?? '')
          .fontSize(MESSAGE_FONT_SIZE)
          .lineHeight(MESSAGE_LINE_HEIGHT)
          .fontColor($r('sys.color.font_secondary'))
      }
      Text() {
        ForEach(this.sectionAt(block, section)?.spans ?? [], (_span: ThreadMarkdownSpan, index: number) => {
          this.MarkdownSpan(block, section, index)
        }, (_span: ThreadMarkdownSpan, index: number) => index.toString())
      }
      .layoutWeight(this.sectionAt(block, section)?.kind === 'list' ? 1 : 0)
      .fontSize(this.headingSize(this.sectionAt(block, section)))
      .lineHeight(this.headingSize(this.sectionAt(block, section)) + 8)
      .fontColor(this.sectionAt(block, section)?.kind === 'quote'
        ? $r('sys.color.font_secondary') : $r('sys.color.font_primary'))
      .wordBreak(WordBreak.BREAK_WORD)
      .copyOption(CopyOptions.LocalDevice)
      .editMenuOptions(this.sourceMenu)
    }
    .alignItems(VerticalAlign.Top)
    .padding({ left: this.sectionAt(block, section)?.kind === 'quote' ? 8 :
      (this.sectionAt(block, section)?.kind === 'list' ? (this.sectionAt(block, section)?.level ?? 0) * 14 : 0) })
    .margin({ top: this.sectionAt(block, section)?.separated ? 6 : 0 })
    .border({ width: { left: this.sectionAt(block, section)?.kind === 'quote' ? 2 : 0 },
      color: $r('sys.color.comp_divider') })
  }

  @Builder
  private MessageText(index?: number) {
    Text(index === undefined ? this.message.text : this.blocks[index]?.text ?? '')
      .fontSize(MESSAGE_FONT_SIZE)
      .lineHeight(MESSAGE_LINE_HEIGHT)
      .fontColor($r('sys.color.font_primary'))
      .wordBreak(WordBreak.BREAK_WORD)
      .copyOption(CopyOptions.LocalDevice)
      .editMenuOptions(this.sourceMenu)
      .onTextSelectionChange((start: number, end: number) => {
        if (!this.quoteSource) return;
        this.selectionStart = start;
        this.selectionEnd = end;
      })
      .maxLines(index === undefined ? MESSAGE_PREVIEW_LINES : 2147483647)
      .textOverflow({ overflow: index === undefined ? TextOverflow.Ellipsis : TextOverflow.Clip })
  }

  @Builder
  private Checkpoint(checkpoint: NativeThreadCheckpointSummary) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 8 }) {
        if (checkpoint.repositories.length > 0) {
          Text(checkpoint.repositories.length === 1 && checkpoint.files.length === 0 ? checkpoint.repositories[0].name :
            uiText(this.language,
              `${checkpoint.repositories.length + (checkpoint.files.length > 0 ? 1 : 0)} 个仓库`,
              `${checkpoint.repositories.length + (checkpoint.files.length > 0 ? 1 : 0)} repositories`))
            .fontSize(12).fontColor($r('sys.color.font_secondary')).constraintSize({ maxWidth: 112 })
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Text(`+${checkpoint.totals.additions}`).fontSize(12).fontWeight(FontWeight.Medium).fontColor('#249E64')
        Text(`−${checkpoint.totals.deletions}`).fontSize(12).fontWeight(FontWeight.Medium).fontColor('#DB575D')
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([$r('sys.color.icon_secondary')])
      }
    }
    .id(`thread-checkpoint-${checkpoint.ordinal}`).height(44).padding({ left: 8, right: 8 })
    .enabled(this.checkpointEnabled)
    .accessibilityText(uiText(this.language,
      `审查 ${checkpoint.totals.count} 个文件，新增 ${checkpoint.totals.additions} 行，删除 ${checkpoint.totals.deletions} 行`,
      `Review ${checkpoint.totals.count} files, ${checkpoint.totals.additions} additions, ${checkpoint.totals.deletions} deletions`))
    .onClick(() => this.onOpenCheckpoint(checkpoint))
  }

  @Builder
  private ReplyFork(source: NativeThreadForkSource) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      if (this.forkBusy) LoadingProgress().height(18).width(18)
      else SymbolGlyph($r('sys.symbol.arrow_triangle_merge')).fontSize(17).fontColor([$r('sys.color.icon_secondary')])
    }
    .id(`thread-reply-fork-${this.message.id}`).width(44).height(44)
    .enabled(this.forkEnabled && !this.forkBusy)
    .accessibilityText(this.forkBusy ? uiText(this.language, '正在从此回复分叉', 'Forking from this reply') :
      uiText(this.language, '从此回复分叉', 'Fork from this reply'))
    .onClick(() => this.onFork(source))
  }

  @Builder
  private Block(index: number) {
    if (index < this.blocks.length) {
      if (this.blocks[index].kind === 'code') {
        ThreadCodeBlock({
          rowId: `${this.message.id}-${index}`,
          text: this.blocks[index].text,
          language: this.blocks[index].language,
          languageMode: this.language,
          dark: this.dark,
          expanded: this.codeIsExpanded(index),
          onToggle: () => this.toggleCode(index),
        })
      } else if (this.blocks[index].kind === 'table') {
        this.MarkdownTable(index)
      } else if (this.blocks[index].reviewComment) {
        ThreadHistoricalReviewCommentCard({
          language: this.language,
          filePath: this.blocks[index].reviewComment?.filePath ?? '',
          rangeLabel: this.blocks[index].reviewComment?.rangeLabel ?? '',
          diff: this.blocks[index].reviewComment?.diff ?? '',
          comment: this.blocks[index].reviewComment?.text ?? '',
          sectionTitle: this.blocks[index].reviewComment?.sectionTitle ?? '',
        })
      } else if (this.blocks[index].prose) {
        Column({ space: 2 }) {
          ForEach(this.blocks[index].prose, (section: ThreadMarkdownSection) => {
            this.MarkdownSection(index, section.index)
          }, (section: ThreadMarkdownSection) => section.index.toString())
        }
        .alignItems(HorizontalAlign.Start)
      } else {
        this.MessageText(index)
      }
    }
  }

  @Builder
  private Attachment(attachment: NativeThreadAttachment, media: boolean) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 8 }) {
        SymbolGlyph(isVideoThreadAttachment(attachment) ? $r('sys.symbol.play_fill') : $r('sys.symbol.doc_plaintext'))
          .fontSize(media ? 20 : 16).fontColor([$r('sys.color.icon_secondary')])
        Text(attachment.name).fontSize(14).fontColor($r('sys.color.font_primary')).wordBreak(WordBreak.BREAK_WORD)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .id('thread-attachment-' + attachment.id)
    .constraintSize({ minHeight: media ? 52 : 44, maxWidth: media ? '85%' : '100%' })
    .borderRadius(media ? 12 : 8)
    .padding({ left: 10, right: 10 })
    .backgroundColor(media ? (this.dark ? '#1A1B1B' : '#F4F4F5') : $r('sys.color.comp_background_tertiary'))
    .enabled(this.attachmentEnabled)
    .accessibilityText(uiText(this.language, `打开附件 ${attachment.name}`, `Open attachment ${attachment.name}`))
    .onClick(() => this.onOpenAttachment(attachment))
  }

  build() {
    Column({ space: 8 }) {
      ForEach((this.message.attachments ?? []).filter((attachment: NativeThreadAttachment) =>
        this.standaloneMedia(attachment)), (attachment: NativeThreadAttachment) => {
        this.Attachment(attachment, true)
      }, (attachment: NativeThreadAttachment) => attachment.id)
      if (this.hasMessageBody()) {
        Column({ space: 8 }) {
          if (this.canCollapseMessage() && !this.expanded) {
            this.MessageText()
          } else {
            ForEach(this.blocks, (block: ThreadMessageBlock) => {
              this.Block(block.index)
            }, (block: ThreadMessageBlock) => block.index.toString())
          }
          ForEach((this.message.attachments ?? []).filter((attachment: NativeThreadAttachment) =>
            !this.standaloneMedia(attachment)), (attachment: NativeThreadAttachment) => {
            this.Attachment(attachment, false)
          }, (attachment: NativeThreadAttachment) => attachment.id)
          ForEach(this.attachmentNames.filter((name: string) =>
            !this.message.attachments?.some((attachment: NativeThreadAttachment) => attachment.name === name)), (name: string) => {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.doc_plaintext'))
                .fontSize(16)
                .fontColor([$r('sys.color.icon_secondary')])
              Text(name)
                .fontSize(14)
                .fontColor($r('sys.color.font_primary'))
                .wordBreak(WordBreak.BREAK_WORD)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .borderRadius(8)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
          }, (name: string, index: number) => index.toString() + name)
          if (this.canCollapseMessage()) {
            Button(this.expanded ? uiText(this.language, '收起消息', 'Show less') :
              uiText(this.language, '显示完整消息', 'Show full message'), { type: ButtonType.Normal })
              .id(`thread-message-toggle-${this.message.id}`)
              .alignSelf(ItemAlign.End)
              .height(44)
              .padding({ left: 8, right: 8 })
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
              .backgroundColor(Color.Transparent)
              .accessibilityStateDescription(this.expanded ? uiText(this.language, '已展开', 'Expanded') :
                uiText(this.language, '已收起', 'Collapsed'))
              .onClick(() => this.onToggle())
          }
          if (this.checkpoint) this.Checkpoint(this.checkpoint)
          if (this.canCopyReply() || this.message.forkSource) {
            Row() {
              if (this.canCopyReply()) {
                Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                  SymbolGlyph($r('sys.symbol.square_on_square_fill')).fontSize(17)
                    .fontColor([this.dark ? '#A3A3A3' : '#71717B'])
                }
                .id(`thread-reply-copy-${this.message.id}`)
                .width(44)
                .height(44)
                .backgroundColor(Color.Transparent)
                .accessibilityText(uiText(this.language, '复制消息', 'Copy message'))
                .onClick(() => void this.copySource(true))
              }
              if (this.message.forkSource) this.ReplyFork(this.message.forkSource)
            }
          }
          if (this.blocks.length === 0 && this.message.streaming) {
            Text(uiText(this.language, '正在回复…', 'Replying…')).fontSize(13).fontColor($r('sys.color.font_secondary'))
          }
        }
        .constraintSize({ maxWidth: this.message.role === 'user' ? '85%' : '100%' })
        .alignItems(HorizontalAlign.Start)
        .padding(this.message.role === 'user'
          ? { left: USER_HORIZONTAL_PADDING, right: USER_HORIZONTAL_PADDING, top: 10, bottom: 10 }
          : { top: 5, bottom: 5 })
        .borderRadius(20)
        .backgroundColor(this.message.role === 'user' ? (this.dark ? '#161616' : '#EFEFF1') : Color.Transparent)
      }
    }
    .width('100%')
    .alignItems(this.message.role === 'user' ? HorizontalAlign.End : HorizontalAlign.Start)
    .onSizeChange((_previous: SizeOptions, current: SizeOptions) => {
      if (typeof current.width === 'number' && this.rowWidth !== current.width) {
        this.rowWidth = current.width;
      }
    })
  }
}

@Component
export struct ThreadWorkGroupToggle {
  @Prop rowId: string = '';
  @Prop summary: string = '';
  @Prop expanded: boolean = false;
  @Prop hasFailure: boolean = false;
  @Prop language: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  onToggle: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.code_square')).fontSize(16)
          .fontColor([this.hasFailure ? (this.dark ? '#FFA2A6' : '#C10007') : (this.dark ? '#A3A3A3' : '#71717B')])
        Text(this.summary)
          .fontSize(14).fontColor(this.dark ? '#A3A3A3' : '#6F6F79')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph(this.expanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(11).fontColor([this.dark ? '#A3A3A3' : '#71717B'])
      }
    }
    .id(`thread-work-group-${this.rowId}`)
    .constraintSize({ minHeight: 32, maxWidth: '100%' })
    .padding({ left: 2, right: 6 })
    .backgroundColor(Color.Transparent)
    .accessibilityText(this.hasFailure ? uiText(this.language, `${this.summary}，有工具调用失败`,
      `${this.summary}, tool call failed`) : this.summary)
    .accessibilityStateDescription(this.expanded ? uiText(this.language, '已展开', 'Expanded') :
      uiText(this.language, '已收起', 'Collapsed'))
    .onClick(() => this.onToggle())
  }
}

@Component
export struct ThreadWorkRow {
  @Prop rowId: string = '';
  @Prop title: string = '';
  @Prop detail: string = '';
  @Prop status: string = '';
  @Prop expanded: boolean = false;
  @Prop loading: boolean = false;
  @Prop expandable: boolean = false;
  @Prop language: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  @Prop grouped: boolean = false;
  onToggle: () => void = () => {};

  private statusLabel(): string {
    switch (this.status) {
      case 'pending': return uiText(this.language, '待处理', 'Pending');
      case 'running': return uiText(this.language, '运行中', 'Running');
      case 'waiting': return uiText(this.language, '等待中', 'Waiting');
      case 'completed': return '';
      case 'failed': return uiText(this.language, '失败', 'Failed');
      case 'cancelled': return uiText(this.language, '已取消', 'Canceled');
      case 'interrupted': return uiText(this.language, '已停止', 'Stopped');
      default: return '';
    }
  }

  @Builder
  private Summary() {
    Row({ space: 8 }) {
      if (this.detail || this.loading || this.expandable) {
        SymbolGlyph(this.expanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(12)
          .fontColor([$r('sys.color.icon_secondary')])
      }
      Text(this.title)
        .fontSize(13)
        .fontFamily(this.grouped ? 'monospace' : 'sans-serif')
        .fontColor(this.dark ? '#F5F5F5' : '#27272A')
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.statusLabel()) {
        Text(this.statusLabel())
          .fontSize(12)
          .fontColor(this.status === 'failed' ? (this.dark ? '#FFA2A6' : '#C10007') :
            (this.dark ? '#A3A3A3' : '#6F6F79'))
      }
    }
    .width('100%')
  }

  build() {
    Column() {
      if (this.detail || this.loading || this.expandable) {
        Button({ type: ButtonType.Normal }) {
          this.Summary()
        }
        .id(`thread-work-toggle-${this.rowId}`)
        .width('100%')
        .height(36)
        .padding({ left: 4, right: 6 })
        .backgroundColor(Color.Transparent)
        .accessibilityGroup(true)
        .accessibilityStateDescription(this.expanded ? uiText(this.language, '已展开', 'Expanded') :
          uiText(this.language, '已收起', 'Collapsed'))
        .onClick(() => this.onToggle())
        if (this.expanded) {
          if (this.loading) LoadingProgress().width(18).height(18).margin({ left: 8 })
          if (this.detail) {
            Text(this.detail)
              .width('100%')
              .fontFamily('monospace')
              .fontSize(13)
              .lineHeight(19)
              .fontColor(this.dark ? '#F5F5F5' : '#27272A')
              .wordBreak(WordBreak.BREAK_ALL)
              .copyOption(CopyOptions.LocalDevice)
              .padding({ left: 11, right: 11, top: 9, bottom: 9 })
              .backgroundColor(this.dark ? '#111111' : '#FFFFFF')
              .border({ width: 1, color: this.status === 'failed' ? (this.dark ? '#663031' : '#F4B6B8') :
                (this.dark ? '#262626' : '#E4E4E7') })
              .borderRadius(8)
          }
        }
      } else {
        Row() {
          this.Summary()
        }
        .width('100%')
        .height(32)
        .padding({ left: 4, right: 6 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
