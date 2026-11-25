import { UiLanguage, uiText } from './UiLanguage';

const MAX_DIFF_HEIGHT = 360;
const MAX_DIFF_ROWS = 240;
const MAX_DIFF_CHARS = 48_000;
const MAX_LINE_CHARS = 1024;

type HistoricalReviewDiffTone = 'add' | 'remove' | 'hunk' | 'neutral';

interface HistoricalReviewDiffLine {
  index: number;
  text: string;
  tone: HistoricalReviewDiffTone;
}

interface HistoricalReviewDiff {
  rows: HistoricalReviewDiffLine[];
  truncated: boolean;
}

function readHistoricalReviewDiff(diff: string): HistoricalReviewDiff {
  const bounded = diff.slice(0, MAX_DIFF_CHARS).replace(/[\ud800-\udbff]$/, '');
  if (!bounded.trim()) return { rows: [], truncated: bounded.length < diff.length };
  const lines = bounded.replace(/\r\n/g, '\n').replace(/\n+$/, '').split('\n');
  let truncated = bounded.length < diff.length || lines.length > MAX_DIFF_ROWS;
  let inHunk = false;
  const rows = lines.slice(0, MAX_DIFF_ROWS).map((line: string, index: number): HistoricalReviewDiffLine => {
    let tone: HistoricalReviewDiffTone = 'neutral';
    if (line.startsWith('@@ ')) {
      inHunk = true;
      tone = 'hunk';
    } else if (line.startsWith('diff --git ')) {
      inHunk = false;
    } else if (line.startsWith('+') && (inHunk || !line.startsWith('+++ '))) {
      tone = 'add';
    } else if (line.startsWith('-') && (inHunk || !line.startsWith('--- '))) {
      tone = 'remove';
    }
    if (line.length <= MAX_LINE_CHARS) return { index, text: line, tone };
    truncated = true;
    const clipped = line.slice(0, MAX_LINE_CHARS - 1).replace(/[\ud800-\udbff]$/, '');
    return { index, text: clipped + '…', tone };
  });
  return { rows, truncated };
}

@Component
export struct ThreadHistoricalReviewCommentCard {
  @Prop language: UiLanguage = 'zh';
  @Prop filePath: string = '';
  @Prop sectionTitle: string = '';
  @Prop rangeLabel: string = '';
  @Prop comment: string = '';
  @Prop @Watch('updateDiff') diff: string = '';
  @State private snippet: HistoricalReviewDiff = { rows: [], truncated: false };

  aboutToAppear(): void {
    this.updateDiff();
  }

  private updateDiff(): void {
    this.snippet = readHistoricalReviewDiff(this.diff);
  }

  private lineBackground(tone: HistoricalReviewDiffTone): ResourceColor {
    if (tone === 'add') return '#252F9E57';
    if (tone === 'remove') return '#25D44141';
    if (tone === 'hunk') return $r('sys.color.comp_background_secondary');
    return Color.Transparent;
  }

  @Builder
  private Header() {
    Row({ space: 8 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.doc_plaintext')).fontSize(13).fontColor([$r('sys.color.icon_secondary')])
      }
      .width(24)
      .height(24)
      .borderRadius(7)
      .backgroundColor($r('sys.color.comp_background_secondary'))

      Column({ space: 2 }) {
        Text(this.filePath)
          .fontFamily('monospace')
          .fontSize(12)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.sectionTitle || this.rangeLabel) {
          Text([this.sectionTitle, this.rangeLabel].filter((part: string) => part.length > 0).join(' · '))
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
  }

  @Builder
  private Snippet() {
    Scroll() {
      Column() {
        ForEach(this.snippet.rows, (row: HistoricalReviewDiffLine) => {
          Text(row.text)
            .width('100%')
            .padding({ left: 10, right: 10, top: 1, bottom: 1 })
            .fontFamily('monospace')
            .fontSize(13)
            .lineHeight(18)
            .fontColor(row.tone === 'hunk' ? $r('sys.color.font_secondary') : $r('sys.color.font_primary'))
            .wordBreak(WordBreak.BREAK_ALL)
            .copyOption(CopyOptions.LocalDevice)
            .backgroundColor(this.lineBackground(row.tone))
        }, (row: HistoricalReviewDiffLine) => `${row.index}:${row.tone}:${row.text}`)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .constraintSize({ maxHeight: MAX_DIFF_HEIGHT })
    .align(Alignment.TopStart)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .edgeEffect(EdgeEffect.None)
    .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
  }

  build() {
    Column() {
      this.Header()
      if (this.comment.trim()) {
        Divider().color($r('sys.color.comp_divider'))
        Text(this.comment)
          .width('100%')
          .padding(12)
          .fontSize(15)
          .lineHeight(22)
          .fontColor($r('sys.color.font_primary'))
          .wordBreak(WordBreak.BREAK_WORD)
          .copyOption(CopyOptions.LocalDevice)
      }
      if (this.snippet.rows.length > 0) {
        Divider().color($r('sys.color.comp_divider'))
        this.Snippet()
      }
      if (this.snippet.truncated) {
        Text(uiText(this.language, '仅显示部分差异', 'Showing part of the diff'))
          .width('100%')
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
      }
    }
    .id('thread-historical-review-comment')
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .border({ width: 1, color: $r('sys.color.comp_divider') })
    .borderRadius(16)
    .clip(true)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
