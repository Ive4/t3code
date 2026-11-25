import type { NativeThreadReviewDiffRow } from '../client/ThreadReviewCommentDraftProtocol';

@Component
export struct ThreadReviewCommentEditor {
  @Prop filePath: string = '';
  @Prop sourceTitle: string = '';
  @Prop selectionLabel: string = '';
  @Prop selectionRows: NativeThreadReviewDiffRow[] = [];
  @Prop comment: string = '';
  @Prop diff: string = '';
  @Prop adding: boolean = false;
  @Prop error: string = '';
  onChange: (comment: string) => void = () => {};
  onCancel: () => void = () => {};
  onAdd: (comment: string) => void = () => {};

  private canAdd(): boolean {
    return !this.adding && this.filePath.trim().length > 0 && this.comment.trim().length > 0;
  }

  private addComment(): void {
    if (this.canAdd()) this.onAdd(this.comment.trim());
  }

  @Builder
  private Header() {
    Row({ space: 10 }) {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([$r('sys.color.icon_primary')])
      }
      .id('thread-review-comment-cancel')
      .width(44)
      .height(44)
      .accessibilityText('取消添加评论')
      .enabled(!this.adding)
      .onClick(() => this.onCancel())
      Text('添加评论')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
    }.height(56).width('100%').padding({ left: 8, right: 20 })
  }

  @Builder
  private FileHeader() {
    Column({ space: 4 }) {
      Text(this.selectionLabel ? '行号 ' + this.selectionLabel.replace(' to ', ' 至 ') : '文件评论')
        .id('thread-review-comment-selection-label')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_secondary'))
      Text(this.filePath)
        .id('thread-review-comment-file')
        .fontFamily('monospace')
        .fontSize(13)
        .fontColor($r('sys.color.font_primary'))
        .wordBreak(WordBreak.BREAK_ALL)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.sourceTitle) {
        Text(this.sourceTitle)
          .id('thread-review-comment-source')
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 4, right: 4 })
  }

  @Builder
  private SelectedPreviewLine(row: NativeThreadReviewDiffRow) {
    Row({ space: 6 }) {
      Text(row.oldNumber?.toString() ?? '').width(34).textAlign(TextAlign.End)
        .fontFamily('monospace').fontSize(11).fontColor($r('sys.color.font_secondary'))
      Text(row.newNumber?.toString() ?? '').width(34).textAlign(TextAlign.End)
        .fontFamily('monospace').fontSize(11).fontColor($r('sys.color.font_secondary'))
      Text(row.content).layoutWeight(1).fontFamily('monospace').fontSize(12).lineHeight(20)
        .fontColor($r('sys.color.font_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(20)
    .padding({ right: 10 })
    .backgroundColor(row.kind === 'add' ? '#252F9E57' : row.kind === 'delete' ? '#25D44141' : Color.Transparent)
  }

  @Builder
  private Preview() {
    Scroll() {
      Column() {
        if (this.selectionRows.length > 0) {
          ForEach(this.selectionRows.slice(0, 32), (row: NativeThreadReviewDiffRow) => {
            this.SelectedPreviewLine(row)
          }, (row: NativeThreadReviewDiffRow, index: number) => `${index}:${row.text}`)
        } else {
          ForEach(this.diff.slice(0, 8192).replace(/\r\n/g, '\n').split('\n', 32), (line: string) => {
            Text(line)
              .width('100%')
              .fontFamily('monospace')
              .fontSize(12)
              .lineHeight(20)
              .fontColor($r('sys.color.font_primary'))
              .backgroundColor(line.startsWith('+') ? '#252F9E57' : line.startsWith('-') ? '#25D44141' : Color.Transparent)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 12, right: 12 })
          }, (line: string, index: number) => `${index}:${line}`)
        }
      }.width('100%')
    }
    .id('thread-review-comment-preview')
    .width('100%')
    .constraintSize({ maxHeight: 100 })
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.None)
    .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
    .border({ width: 1, color: $r('sys.color.comp_divider') })
    .borderRadius(16)
    .clip(true)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
  }

  @Builder
  private Input() {
    Column({ space: 8 }) {
      Text('评论')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
      TextArea({ text: this.comment, placeholder: '写下评论…' })
        .id('thread-review-comment-input')
        .defaultFocus(true)
        .width('100%')
        .height(132)
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .border({ width: 1, color: $r('sys.color.comp_divider') })
        .borderRadius(20)
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_secondary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .enterKeyType(EnterKeyType.NEW_LINE)
        .accessibilityText('评论')
        .enabled(!this.adding)
        .onChange((value: string) => this.onChange(value))
      if (this.error) {
        Text(this.error)
          .id('thread-review-comment-error')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
          .wordBreak(WordBreak.BREAK_WORD)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Toolbar() {
    Row() {
      Button({ type: ButtonType.Capsule }) {
        Row({ space: 6 }) {
          if (this.adding) {
            LoadingProgress().width(16).height(16).color($r('sys.color.icon_on_primary'))
          } else {
            SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(16).fontColor([$r('sys.color.icon_on_primary')])
          }
          Text('评论').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('sys.color.icon_on_primary'))
        }.padding({ left: 12, right: 12 })
      }
      .id('thread-review-comment-add')
      .height(44)
      .enabled(this.canAdd())
      .accessibilityText('添加评论到草稿')
      .onClick(() => this.addComment())
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
    .padding({ left: 20, right: 20, top: 6, bottom: 12 })
  }

  build() {
    Column() {
      this.Header()
      Scroll() {
        Column({ space: 16 }) {
          if (this.filePath.trim()) {
            this.FileHeader()
            if (this.selectionRows.length > 0 || this.diff.trim()) this.Preview()
            this.Input()
          } else {
            Text('未选择文件').fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary'))
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 20, right: 20, top: 12, bottom: 12 })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart).edgeEffect(EdgeEffect.None)
      if (this.filePath.trim()) this.Toolbar()
    }
    .id('thread-review-comment-editor')
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
