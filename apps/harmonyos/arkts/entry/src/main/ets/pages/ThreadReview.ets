import type { NativeThreadReview, NativeThreadReviewFile, NativeThreadReviewPatch } from '../client/ThreadReviewProtocol';
import { buildThreadReviewLineSelection, parseThreadReviewDiffRows } from '../client/ThreadReviewCommentDraftProtocol';
import type { NativeThreadFileReviewCommentTarget, NativeThreadReviewDiffRow, NativeThreadReviewLineSelection } from
  '../client/ThreadReviewCommentDraftProtocol';
import type { NativeThreadCheckpointDiff, NativeThreadCheckpointDiffGroup } from '../client/ThreadCheckpointProtocol';

@Component
export struct ThreadReview {
  @Prop cwd: string = '';
  @Prop @Watch('reload') contextKey: string = '';
  @Prop historical: boolean = false;
  onBack: () => void = () => {};
  onLoad: () => Promise<NativeThreadReview> = async () => {
    throw new Error('当前环境无法读取未提交的变更。');
  };
  onLoadCheckpoint?: () => Promise<NativeThreadCheckpointDiff>;
  onCommentFile?: (target: NativeThreadFileReviewCommentTarget) => void;
  onLoadFile: (file: NativeThreadReviewFile, baseRef: string | null) => Promise<NativeThreadReviewPatch> = async () => {
    throw new Error('当前环境无法读取文件差异。');
  };

  @State private review: NativeThreadReview | undefined = undefined;
  @State private checkpoint: NativeThreadCheckpointDiff | undefined = undefined;
  @State private loading: boolean = true;
  @State private error: string = '';
  @State private expandedFileKey: string = '';
  @State private patch: NativeThreadReviewPatch | undefined = undefined;
  @State private patchRows: NativeThreadReviewDiffRow[] = [];
  @State private rangeAnchor: number = -1;
  @State private rangeCommentTarget: NativeThreadFileReviewCommentTarget | undefined = undefined;
  @State private fileLoading: boolean = false;
  @State private fileError: string = '';
  private reviewRequest: number = 0;
  private fileRequest: number = 0;
  private patches: Map<string, NativeThreadReviewPatch> = new Map<string, NativeThreadReviewPatch>();

  aboutToAppear(): void {
    this.reload();
  }

  aboutToDisappear(): void {
    this.reviewRequest += 1;
    this.fileRequest += 1;
    this.clearRangeSelection();
  }

  private reload(): void {
    void this.loadReview();
  }

  private async loadReview(): Promise<void> {
    const request = ++this.reviewRequest;
    this.fileRequest += 1;
    this.patches.clear();
    this.review = undefined;
    this.checkpoint = undefined;
    this.loading = true;
    this.error = '';
    this.expandedFileKey = '';
    this.setPatch(undefined);
    this.fileLoading = false;
    this.fileError = '';
    try {
      if (this.historical) {
        if (!this.onLoadCheckpoint) throw new Error('当前环境无法读取本轮变更。');
        const checkpoint = await this.onLoadCheckpoint();
        if (request === this.reviewRequest) this.checkpoint = checkpoint;
      } else {
        if (!this.cwd) throw new Error('当前任务没有可用的工作区。');
        const review = await this.onLoad();
        if (request === this.reviewRequest) this.review = review;
      }
    } catch (error) {
      if (request === this.reviewRequest) {
        this.error = (error as Error).message || (this.historical ? '无法读取本轮变更。' : '无法读取未提交的变更。');
      }
    } finally {
      if (request === this.reviewRequest) this.loading = false;
    }
  }

  private checkpointFileKey(group: string, path: string): string {
    return `${encodeURIComponent(group)}:${encodeURIComponent(path)}`;
  }

  private toggle(file: NativeThreadReviewFile, key: string): void {
    if (this.expandedFileKey === key) {
      this.fileRequest += 1;
      this.expandedFileKey = '';
      this.setPatch(undefined);
      return;
    }
    this.expandedFileKey = key;
    void this.loadFile(file, key);
  }

  private async loadFile(file: NativeThreadReviewFile, key: string): Promise<void> {
    const request = ++this.fileRequest;
    this.setPatch(file.patch ?? this.patches.get(key));
    this.fileError = '';
    this.fileLoading = !this.historical && this.patch === undefined;
    if (!this.fileLoading) return;
    try {
      const patch = await this.onLoadFile(file, this.review?.baseRef ?? null);
      if (request !== this.fileRequest) return;
      this.patches.set(key, patch);
      this.setPatch(patch);
    } catch (error) {
      if (request === this.fileRequest) this.fileError = (error as Error).message || '无法读取文件差异。';
    } finally {
      if (request === this.fileRequest) this.fileLoading = false;
    }
  }

  private setPatch(patch: NativeThreadReviewPatch | undefined): void {
    this.clearRangeSelection();
    this.patch = patch;
    this.patchRows = patch ? parseThreadReviewDiffRows(patch.lines) : [];
  }

  private clearRangeSelection(): void {
    this.rangeAnchor = -1;
    this.rangeCommentTarget = undefined;
  }

  private startRangeSelection(key: string, row: NativeThreadReviewDiffRow): void {
    if (this.onCommentFile && key === this.expandedFileKey && row.index !== null) {
      this.rangeAnchor = row.index;
      this.rangeCommentTarget = undefined;
    }
  }

  private commentTarget(file: NativeThreadReviewFile, relativePath: string,
    selection?: NativeThreadReviewLineSelection): NativeThreadFileReviewCommentTarget {
    return {
      filePath: relativePath && relativePath !== '.' ? relativePath + '/' + file.path : file.path,
      sectionId: this.checkpoint ? `turn:${this.checkpoint.toTurnCount}` : 'working-tree',
      sectionTitle: this.checkpoint ? '本轮变更' : '未提交的变更',
      diff: selection?.diff ?? this.patch?.lines.join('\n') ?? '',
      selection,
    };
  }

  private pressDiffLine(file: NativeThreadReviewFile, key: string, relativePath: string,
    row: NativeThreadReviewDiffRow): void {
    if (!this.onCommentFile || key !== this.expandedFileKey || row.index === null) return;
    if (this.rangeAnchor >= 0) {
      const selection = buildThreadReviewLineSelection(this.patchRows, this.rangeAnchor, row.index);
      this.rangeCommentTarget = selection && selection.startIndex !== selection.endIndex ?
        this.commentTarget(file, relativePath, selection) : undefined;
    } else {
      const selection = buildThreadReviewLineSelection(this.patchRows, row.index);
      if (selection) this.onCommentFile(this.commentTarget(file, relativePath, selection));
    }
  }

  private isSelectedDiffRow(row: NativeThreadReviewDiffRow): boolean {
    if (row.index === null) return false;
    const selection = this.rangeCommentTarget?.selection;
    return selection ? row.index >= selection.startIndex && row.index <= selection.endIndex :
      row.index === this.rangeAnchor;
  }

  private openRangeComment(): void {
    const target = this.rangeCommentTarget;
    this.clearRangeSelection();
    if (target) this.onCommentFile?.(target);
  }

  private lineBackground(row: NativeThreadReviewDiffRow): ResourceColor {
    if (this.isSelectedDiffRow(row)) return '#325A77BA';
    if (row.kind === 'add') return '#252F9E57';
    if (row.kind === 'delete') return '#25D44141';
    if (row.kind === 'hunk') return $r('sys.color.comp_background_secondary');
    return Color.Transparent;
  }

  private lineAccent(row: NativeThreadReviewDiffRow): ResourceColor {
    if (row.kind === 'add') return '#2F9E57';
    if (row.kind === 'delete') return '#D44141';
    return $r('sys.color.comp_divider');
  }

  private lineDescription(row: NativeThreadReviewDiffRow): string {
    const numbers = [row.oldNumber === null ? '' : `旧行 ${row.oldNumber}`,
      row.newNumber === null ? '' : `新行 ${row.newNumber}`].filter((label: string) => label.length > 0);
    return numbers.concat(row.content).join('，');
  }

  @Builder
  private Header() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.arrow_left')).fontSize(22).fontColor([$r('sys.color.icon_primary')])
      }
      .id('thread-review-back')
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .accessibilityText(this.historical ? '返回会话' : '返回 Git')
      .onClick(() => { this.clearRangeSelection(); this.onBack(); })

      Text(this.historical ? '本轮变更' : '未提交的变更')
        .id('thread-review-title')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(22).fontColor([$r('sys.color.icon_primary')])
      }
      .id('thread-review-refresh')
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .accessibilityText('刷新变更')
      .enabled(!this.loading)
      .onClick(() => this.reload())
    }.width('100%').padding(4)
  }

  @Builder
  private Notice(message: string) {
    Text(message)
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .fontSize(14)
      .fontColor($r('sys.color.font_secondary'))
  }

  @Builder
  private Loading(message: string) {
    Row({ space: 8 }) {
      LoadingProgress().width(18).height(18)
      Text(message).fontSize(14).fontColor($r('sys.color.font_secondary'))
    }.width('100%').padding(16)
  }

  @Builder
  private ErrorMessage(message: string, scope: string, retry: () => void) {
    Row({ space: 8 }) {
      Text(message).fontSize(14).fontColor($r('sys.color.font_primary')).layoutWeight(1)
      Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .id(`thread-review-retry-${scope}`)
        .height(44)
        .onClick(retry)
    }.width('100%').padding({ left: 16, right: 12 })
  }

  @Builder
  private DiffLineContent(row: NativeThreadReviewDiffRow) {
    Row() {
      Text(row.oldNumber?.toString() ?? '')
        .width(40).textAlign(TextAlign.End).padding({ right: 5 })
        .fontFamily('monospace').fontSize(11).fontColor($r('sys.color.font_secondary'))
      Text(row.newNumber?.toString() ?? '')
        .width(40).textAlign(TextAlign.End).padding({ right: 5 })
        .fontFamily('monospace').fontSize(11).fontColor($r('sys.color.font_secondary'))
      Text(row.content)
        .layoutWeight(1)
        .padding({ left: 6, right: 8 })
        .fontFamily('monospace').fontSize(12).lineHeight(18)
        .fontColor($r('sys.color.font_primary')).wordBreak(WordBreak.BREAK_ALL)
    }
    .width('100%')
    .constraintSize({ minHeight: 24 })
    .padding({ top: 3, bottom: 3 })
    .alignItems(VerticalAlign.Top)
    .backgroundColor(this.lineBackground(row))
    .border({ width: { left: 3 }, color: this.lineAccent(row) })
  }

  @Builder
  private DiffLine(file: NativeThreadReviewFile, key: string, relativePath: string, row: NativeThreadReviewDiffRow) {
    if (row.index !== null && this.onCommentFile) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        this.DiffLineContent(row)
      }
      .id(`thread-review-line-${row.index}`)
      .width('100%')
      .constraintSize({ minHeight: 24 })
      .padding(0)
      .borderRadius(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText(this.lineDescription(row))
      .accessibilityDescription(this.isSelectedDiffRow(row) ? '已选择' : '点按添加评论，长按选择起点')
      .onClick(() => this.pressDiffLine(file, key, relativePath, row))
      .priorityGesture(LongPressGesture({ repeat: false }).onAction(() => this.startRangeSelection(key, row)))
    } else if (row.index !== null) {
      this.DiffLineContent(row)
    } else {
      Text(row.text)
        .width('100%')
        .padding({ left: 12, right: 12, top: 2, bottom: 2 })
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor($r('sys.color.font_secondary'))
        .backgroundColor(this.lineBackground(row))
    }
  }

  @Builder
  private Patch(file: NativeThreadReviewFile, key: string, relativePath: string) {
    if (this.fileLoading) {
      this.Loading('正在加载文件差异…')
    } else if (this.fileError) {
      this.ErrorMessage(this.fileError, 'file', () => { void this.loadFile(file, key); })
    } else if (this.patch !== undefined) {
      if (this.patch.truncated) this.Notice('预览已截断，文件统计仍包含已返回的全部变更。')
      if (this.patch.lines.length === 0) this.Notice('此文件没有可显示的文本差异。')
      Column() {
        ForEach(this.patchRows, (row: NativeThreadReviewDiffRow) => {
          this.DiffLine(file, key, relativePath, row)
        }, (row: NativeThreadReviewDiffRow, index: number) => `${index}:${row.text}`)
      }
      .id('thread-review-patch')
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .clip(true)
      .borderRadius(8)
    } else if (this.historical) {
      this.Notice('此文件没有可显示的文本差异。')
    }
  }

  @Builder
  private FileRow(file: NativeThreadReviewFile, key: string, incomplete: boolean, relativePath: string = '') {
    Column() {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          SymbolGlyph(this.expandedFileKey === key ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([$r('sys.color.icon_secondary')])
          Column({ space: 2 }) {
            Text(file.path)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (file.previousPath !== null) {
              Text(`原路径 ${file.previousPath}`)
                .fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            } else if (file.changeType === 'new' || file.changeType === 'deleted') {
              Text(file.changeType === 'new' ? '新增' : '删除')
                .fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (!incomplete && (file.additions > 0 || file.deletions > 0)) {
            Text(`+${file.additions} −${file.deletions}`)
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
          }
        }.width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
      }
      .id(`thread-review-file-${key}`)
      .width('100%')
      .constraintSize({ minHeight: 48 })
      .borderRadius(8)
      .backgroundColor($r('sys.color.comp_background_secondary'))
      .accessibilityText(file.path)
      .accessibilityDescription(this.expandedFileKey === key ? '折叠差异' : '展开差异')
      .onClick(() => this.toggle(file, key))
      if (this.expandedFileKey === key) {
        this.Patch(file, key, relativePath)
        if (this.onCommentFile && !this.fileLoading && !this.fileError) {
          Button('添加文件评论', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('thread-review-comment-file-' + key).height(44).alignSelf(ItemAlign.End)
            .onClick(() => { this.clearRangeSelection(); this.onCommentFile?.(this.commentTarget(file, relativePath)); })
        }
      }
    }.width('100%')
  }

  @Builder
  private RangeActions() {
    Row({ space: 10 }) {
      if (this.rangeCommentTarget?.selection) {
        Button('评论 ' + this.rangeCommentTarget.selection.rangeLabel.replace(' to ', ' 至 '), { type: ButtonType.Capsule })
          .id('thread-review-comment-range')
          .height(48).layoutWeight(1)
          .onClick(() => this.openRangeComment())
      } else {
        Text('选择范围终点')
          .id('thread-review-comment-range-instruction')
          .height(48).layoutWeight(1)
          .backgroundColor($r('sys.color.comp_background_secondary')).borderRadius(24)
          .fontSize(15).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
          .fontColor($r('sys.color.font_primary'))
      }
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([$r('sys.color.icon_primary')])
      }
      .id('thread-review-comment-range-clear')
      .width(48).height(48)
      .accessibilityText('清除所选范围')
      .onClick(() => this.clearRangeSelection())
    }.width('100%').padding({ left: 18, right: 18, top: 6, bottom: 12 })
  }

  @Builder
  private CheckpointGroupHeader(group: NativeThreadCheckpointDiffGroup) {
    Column({ space: 4 }) {
      Text(group.name || '工作区')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
      if (group.repositoryPath !== null && group.relativePath) {
        Text(group.relativePath).fontSize(12).fontColor($r('sys.color.font_secondary'))
      }
    }
    .id(`thread-review-group-${encodeURIComponent(group.key)}`)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 8, bottom: 4 })
  }

  @Builder
  private CheckpointFiles(checkpoint: NativeThreadCheckpointDiff) {
    if (checkpoint.groups.every((group: NativeThreadCheckpointDiffGroup) =>
      group.files.length === 0 && !group.incomplete)) {
      this.Notice('本轮没有文件变更。')
    } else {
      List({ space: 6 }) {
        ForEach(checkpoint.groups, (group: NativeThreadCheckpointDiffGroup) => {
          if (group.files.length > 0 || group.incomplete) {
            if (checkpoint.groups.length > 1 || group.repositoryPath !== null) {
              ListItem() { this.CheckpointGroupHeader(group) }
            }
            if (group.incomplete) {
              ListItem() { this.Notice(group.files.length === 0 ? '没有可显示的文件。' : '环境只返回了部分变更。') }
            }
            if (group.totalFiles > group.files.length) {
              ListItem() { this.Notice(`显示前 ${group.files.length} 个文件，共返回 ${group.totalFiles} 个。`) }
            }
            ForEach(group.files, (file: NativeThreadReviewFile) => {
              ListItem() { this.FileRow(file, this.checkpointFileKey(group.key, file.path), group.incomplete, group.relativePath) }
            }, (file: NativeThreadReviewFile) => this.checkpointFileKey(group.key, file.path))
          }
        }, (group: NativeThreadCheckpointDiffGroup) => group.key)
      }
      .id('thread-review-files')
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, bottom: 12 })
    }
  }

  build() {
    Column() {
      this.Header()
      if (this.loading) {
        this.Loading(this.historical ? '正在加载本轮变更…' : '正在加载未提交的变更…')
      } else if (this.error) {
        this.ErrorMessage(this.error, 'review', () => this.reload())
      } else if (this.checkpoint !== undefined) {
        this.CheckpointFiles(this.checkpoint)
      } else if (this.review !== undefined) {
        if (this.review.incomplete) this.Notice('环境只返回了部分变更。')
        if (this.review.totalFiles > this.review.files.length) {
          this.Notice(`显示前 ${this.review.files.length} 个文件，共返回 ${this.review.totalFiles} 个。`)
        }
        if (this.review.files.length === 0) {
          this.Notice(this.review.incomplete ? '没有可显示的文件。' : '工作区没有未提交的变更。')
        } else {
          List({ space: 6 }) {
            ForEach(this.review.files, (file: NativeThreadReviewFile) => {
              ListItem() { this.FileRow(file, file.path, this.review?.incomplete === true) }
            }, (file: NativeThreadReviewFile) => file.path)
          }
          .id('thread-review-files')
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 12, right: 12, bottom: 12 })
        }
      }
      if (this.onCommentFile && this.rangeAnchor >= 0) this.RangeActions()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
