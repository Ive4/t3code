import { pullRequestGuideExcerpt, pullRequestGuideIsStale } from '../client/PullRequestGuideProtocol';
import type {
  NativePullRequestGuide, NativePullRequestGuideExcerpt, NativePullRequestGuideFile, NativePullRequestGuideNote,
  NativePullRequestGuideResult, NativePullRequestGuideStop, NativePullRequestGuideTarget,
} from '../client/PullRequestGuideProtocol';
import type { NativePullRequestFile } from '../client/PullRequestProtocol';
import { ThreadMessageRow } from './ThreadMessageRow';

const EXCERPT_PATCH_LIMIT = 40000;
type GuideNoticeAction = 'read' | 'generate' | 'rewrite' | 'retry-generation';

function stopPaths(stop: NativePullRequestGuideStop): string[] {
  return Array.from(new Set<string>([...stop.excerpts.map((excerpt: NativePullRequestGuideExcerpt) => excerpt.path),
    ...stop.files.map((file: NativePullRequestGuideFile) => file.path)]));
}

function fileCount(guide: NativePullRequestGuide): number {
  return new Set<string>(guide.stops.flatMap((stop: NativePullRequestGuideStop) => stopPaths(stop))).size;
}

function attentionLabel(kind: string): string {
  switch (kind) {
    case 'tradeoff': return '需要权衡';
    case 'contract': return '需要核对的契约';
    case 'product': return '需要确认的产品决策';
    case 'risk': return '需要评估的风险';
    case 'accessibility': return '需要检查的无障碍问题';
    default: return '需要留意';
  }
}

@Component
struct GuideMarkdown {
  @Prop text: string = '';
  @Prop contentId: string = '';
  @State private expanded: boolean = true;

  build() {
    ThreadMessageRow({
      message: { id: this.contentId, role: 'assistant', text: this.text },
      expanded: this.expanded,
      onToggle: () => { this.expanded = !this.expanded; },
    })
  }
}

@Component
struct GuideExcerptCode {
  @Prop @Watch('updateSnippet') files: NativePullRequestFile[] = [];
  @Prop @Watch('updateSnippet') excerpt?: NativePullRequestGuideExcerpt = undefined;
  @Prop loading: boolean = false;
  @State private snippet: string = '';

  aboutToAppear(): void {
    this.updateSnippet();
  }

  private updateSnippet(): void {
    const excerpt = this.excerpt;
    const file = this.files.find((entry: NativePullRequestFile) => entry.path === excerpt?.path) ??
      this.files.find((entry: NativePullRequestFile) => entry.previousPath === excerpt?.path);
    if (!excerpt || !file || file.withheld) {
      this.snippet = '';
      return;
    }
    const patch = file.patch.length > EXCERPT_PATCH_LIMIT
      ? file.patch.slice(0, file.patch.lastIndexOf('\n', EXCERPT_PATCH_LIMIT) + 1) : file.patch;
    this.snippet = pullRequestGuideExcerpt(patch, excerpt);
  }

  build() {
    if (this.snippet) {
      Text(this.snippet).fontSize(12).fontFamily('monospace').lineHeight(18).wordBreak(WordBreak.BREAK_ALL)
        .copyOption(CopyOptions.LocalDevice).fontColor($r('sys.color.font_primary')).width('100%').padding(12)
    } else {
      Text(this.loading ? '正在读取片段…' : '打开完整差异查看此范围。')
        .fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%').padding(12)
    }
  }
}

@Component
export struct WorkspacePullRequestGuide {
  @Prop result?: NativePullRequestGuideResult = undefined;
  @Prop stopIndex: number = -1;
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop canGenerate: boolean = false;
  @Prop starting: boolean = false;
  @Prop startError: string = '';
  @Prop jumpLoading: boolean = false;
  @Prop jumpError: string = '';
  @Prop files: NativePullRequestFile[] = [];
  @Prop diffLoading: boolean = false;
  @Prop diffError: string = '';
  onSelect: (position: number) => void = (_position: number) => {};
  onRetry: () => void = () => {};
  onStart: () => void = () => {};
  onOpenFile: (target: NativePullRequestGuideTarget) => void = (_target: NativePullRequestGuideTarget) => {};
  onFinishReview?: () => void;

  private stale(): boolean {
    return this.result !== undefined && pullRequestGuideIsStale(this.result);
  }

  private failed(): boolean {
    return this.result?.run?._tag === 'Failed' && this.result.run.headSha === this.result.currentHeadSha;
  }

  private running(): boolean {
    return this.starting || this.result?.run?._tag === 'Running';
  }

  private stopSubtitle(stop: NativePullRequestGuideStop): string {
    const paths = stopPaths(stop);
    if (paths.length === 0) return '背景说明';
    const path = paths[0];
    const name = path.slice(path.lastIndexOf('/') + 1);
    return paths.length > 1 ? `${name} +${paths.length - 1}` : name;
  }

  @Builder
  private Notice(id: string, title: string, message: string, busy: boolean = false, action?: GuideNoticeAction) {
    Column({ space: 9 }) {
      Row({ space: 8 }) {
        if (busy) {
          LoadingProgress().width(20).height(20).color($r('sys.color.icon_secondary'))
        }
        Text(title || message).fontSize(title ? 16 : 14).fontWeight(title ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(title ? $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
      }.width('100%')
      if (title) {
        Text(message).fontSize(14).lineHeight(20).fontColor($r('sys.color.font_secondary'))
      }
      if (action === 'read') {
        Button('重试', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('workspace-pr-guide-retry').height(44).enabled(!this.loading).onClick(() => this.onRetry())
      } else if (action && this.canGenerate) {
        Button(action === 'generate' ? '生成指南' : action === 'rewrite' ? '重写指南' : '重试',
          { type: ButtonType.Capsule })
          .id(action === 'retry-generation' ? 'workspace-pr-guide-retry-generate' : 'workspace-pr-guide-generate')
          .height(44).enabled(!this.loading).onClick(() => this.onStart())
      } else if (action) {
        Text('生成指南需要连接和会话操作权限。').fontSize(12).fontColor($r('sys.color.font_secondary'))
      }
    }.id(id).width('100%').alignItems(HorizontalAlign.Start).padding(14).borderRadius(16)
      .backgroundColor($r('sys.color.comp_background_secondary'))
  }

  @Builder
  private Status() {
    if (this.running()) {
      this.Notice('workspace-pr-guide-running', this.result?.guide ? '正在更新审查指南' : '正在编写审查指南',
        this.result?.guide ? '可以继续阅读已保存的指南。' : '指南生成后即可阅读。', true)
    } else if (this.startError) {
      this.Notice('workspace-pr-guide-start-error', '无法开始生成审查指南', this.startError, false, 'retry-generation')
    } else if (this.failed()) {
      this.Notice('workspace-pr-guide-failed', '审查指南生成失败', this.result?.run?.detail || '未能生成审查指南。',
        false, 'retry-generation')
    } else if (this.error) {
      this.Notice('workspace-pr-guide-error', '无法读取审查指南', this.error, false, 'read')
    } else if (!this.result || (this.loading && !this.result.guide)) {
      this.Notice('workspace-pr-guide-loading', '审查指南', '正在检查已保存的指南…', true)
    } else if (this.stale()) {
      this.Notice('workspace-pr-guide-stale', '指南基于旧版变更', '分支已有新变更，仍可阅读之前的指南。',
        false, 'rewrite')
    } else if (!this.result.guide?.stops.length) {
      this.Notice('workspace-pr-guide-empty', '审查指南', '生成导览，查看代码片段和需要重点审查的变更。',
        false, 'generate')
    }
  }

  @Builder
  private GuideOptions() {
    Menu() {
      MenuItem({ content: '重写指南' }).id('workspace-pr-guide-rewrite').onChange(() => this.onStart())
    }
  }

  @Builder
  private OutlineStop(stop: NativePullRequestGuideStop, position: number, total: number) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 12 }) {
        Column() {
          Text(`${position + 1}`).width(34).height(34).textAlign(TextAlign.Center)
            .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
            .borderRadius(17).border({ width: 1, color: $r('sys.color.comp_divider') })
            .backgroundColor($r('sys.color.comp_background_secondary'))
          if (position + 1 < total) {
            Column().width(1).height(16).backgroundColor($r('sys.color.comp_divider'))
          }
        }.width(34)
        Column({ space: 5 }) {
          Text(stop.title).fontSize(16).lineHeight(22).fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          Row({ space: 4 }) {
            if (stop.attention) {
              SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(13)
                .fontColor([$r('sys.color.icon_secondary')])
            }
            Text(this.stopSubtitle(stop)).fontSize(13).fontColor($r('sys.color.font_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start).padding({ bottom: 20 })
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([$r('sys.color.icon_secondary')])
      }.width('100%').alignItems(VerticalAlign.Top)
    }.id(`workspace-pr-guide-stop-${position}`).width('100%').constraintSize({ minHeight: 48 }).padding(0)
      .accessibilityText(`步骤 ${position + 1}，${stop.title}`).onClick(() => this.onSelect(position))
  }

  @Builder
  private Outline(guide: NativePullRequestGuide) {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Text(`${guide.stops.length} 个步骤`).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Text(`涉及 ${fileCount(guide)} 个文件`).fontSize(13).fontColor($r('sys.color.font_secondary'))
        Blank()
        if (this.canGenerate && !this.running() && !this.stale() && !this.startError && !this.error) {
          Button('···', { type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('workspace-pr-guide-options').width(44).height(44).padding(0).fontSize(22)
            .accessibilityText('审查指南选项').enabled(!this.loading).bindMenu(this.GuideOptions)
        }
      }.width('100%')
      if (guide.stops[0]?.summary) {
        GuideMarkdown({ text: guide.stops[0].summary, contentId: 'pr-guide-outline-summary' })
      }
      Column() {
        ForEach(guide.stops, (stop: NativePullRequestGuideStop, index: number) => {
          this.OutlineStop(stop, index, guide.stops.length)
        }, (_stop: NativePullRequestGuideStop, index: number) => `${guide.headSha}:${guide.generatedAt}:${index}`)
      }.width('100%')
      Button('开始导览', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
        .id('workspace-pr-guide-start').height(44).alignSelf(ItemAlign.End).onClick(() => this.onSelect(0))
    }.id('workspace-pr-guide-outline').width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Excerpt(excerpt: NativePullRequestGuideExcerpt, index: number) {
    Column({ space: 6 }) {
      if (excerpt.caption.trim()) {
        GuideMarkdown({ text: excerpt.caption, contentId: `pr-guide-${this.stopIndex}-excerpt-${index}` })
      }
      Column() {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 8 }) {
            Text(excerpt.path).fontSize(13).fontFamily('monospace').layoutWeight(1)
              .fontColor($r('sys.color.font_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${excerpt.start}–${excerpt.end}`).fontSize(12).fontColor($r('sys.color.font_secondary'))
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([$r('sys.color.icon_secondary')])
          }.width('100%')
        }.id(`workspace-pr-guide-excerpt-${index}`).width('100%').height(44).padding({ left: 12, right: 12 })
          .enabled(!this.jumpLoading).accessibilityText(`${excerpt.path}，打开第 ${excerpt.start} 行的变更`)
          .onClick(() => this.onOpenFile(excerpt))
        Divider().color($r('sys.color.comp_divider'))
        GuideExcerptCode({ excerpt, files: this.files, loading: this.diffLoading })
      }.width('100%').borderRadius(10).border({ width: 1, color: $r('sys.color.comp_divider') })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Note(note: NativePullRequestGuideNote, index: number) {
    Row({ space: 10 }) {
      Text(index < 26 ? String.fromCharCode(65 + index) : `${index + 1}`)
        .width(28).height(28).fontSize(13).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
        .borderRadius(8).backgroundColor($r('sys.color.comp_background_secondary'))
      Column({ space: 3 }) {
        Text(note.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
        Text(`${note.path.slice(note.path.lastIndexOf('/') + 1)}:${note.line}`).fontSize(12).fontFamily('monospace')
          .fontColor($r('sys.color.font_secondary'))
        if (note.body) {
          GuideMarkdown({ text: note.body, contentId: `pr-guide-${this.stopIndex}-note-${index}` })
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').alignItems(VerticalAlign.Top)
  }

  @Builder
  private FileLink(file: NativePullRequestGuideFile, index: number) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.doc_plaintext')).fontSize(17).fontColor([$r('sys.color.icon_secondary')])
        Column({ space: 3 }) {
          Text(file.path).fontSize(14).fontFamily('monospace').fontColor($r('sys.color.font_primary'))
            .wordBreak(WordBreak.BREAK_ALL)
          if (file.note) {
            Text(file.note).fontSize(13).fontColor($r('sys.color.font_secondary'))
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([$r('sys.color.icon_secondary')])
      }.width('100%')
    }.id(`workspace-pr-guide-file-${index}`).width('100%').constraintSize({ minHeight: 44 })
      .padding({ left: 12, right: 12, top: 8, bottom: 8 }).enabled(!this.jumpLoading)
      .accessibilityText(`查看 ${file.path} 的变更`).onClick(() => this.onOpenFile({ path: file.path }))
  }

  @Builder
  private Step(guide: NativePullRequestGuide, stop: NativePullRequestGuideStop) {
    Column({ space: 16 }) {
      Text(stop.title).id('workspace-pr-guide-step-title').fontSize(23).fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
      if (stop.summary) {
        GuideMarkdown({ text: stop.summary, contentId: `pr-guide-${this.stopIndex}-summary` })
      }
      if (stop.attention) {
        Column({ space: 6 }) {
          Row({ space: 7 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(16)
              .fontColor([$r('sys.color.icon_secondary')])
            Text(attentionLabel(stop.attention.kind)).fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
          }.width('100%')
          GuideMarkdown({ text: stop.attention.note, contentId: `pr-guide-${this.stopIndex}-attention` })
        }.width('100%').padding(12).borderRadius(12).backgroundColor($r('sys.color.comp_background_secondary'))
      }
      if (this.stale() && stop.excerpts.length > 0) {
        Text('新版指南生成后将恢复代码片段。').fontSize(13).fontColor($r('sys.color.font_secondary'))
      } else {
        ForEach(stop.excerpts, (excerpt: NativePullRequestGuideExcerpt, index: number) => {
          this.Excerpt(excerpt, index)
        }, (excerpt: NativePullRequestGuideExcerpt, index: number) => `${excerpt.path}:${excerpt.side}:${index}`)
      }
      if (this.diffError) {
        Text(this.diffError).fontSize(13).fontColor($r('sys.color.font_secondary'))
      }
      if (stop.notes.length > 0) {
        Column({ space: 10 }) {
          Text('本步骤的备注').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          ForEach(stop.notes, (note: NativePullRequestGuideNote, index: number) => {
            this.Note(note, index)
          }, (_note: NativePullRequestGuideNote, index: number) => index.toString())
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
      if (stop.files.length > 0) {
        Column() {
          ForEach(stop.files, (file: NativePullRequestGuideFile, index: number) => {
            this.FileLink(file, index)
            if (index + 1 < stop.files.length) Divider().color($r('sys.color.comp_divider'))
          }, (file: NativePullRequestGuideFile, index: number) => `${file.path}:${index}`)
        }.width('100%').borderRadius(12).backgroundColor($r('sys.color.comp_background_secondary'))
      }
      if (stop.questions.length > 0) {
        Column({ space: 4 }) {
          Text('需要考虑的问题').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          ForEach(stop.questions, (question: string, index: number) => {
            GuideMarkdown({ text: question, contentId: `pr-guide-${this.stopIndex}-question-${index}` })
          }, (_question: string, index: number) => index.toString())
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
      Divider().color($r('sys.color.comp_divider'))
      Row({ space: 8 }) {
        if (this.stopIndex > 0) {
          Button('上一步', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('workspace-pr-guide-previous').height(44).enabled(!this.jumpLoading)
            .onClick(() => this.onSelect(this.stopIndex - 1))
        }
        Blank()
        if (this.stopIndex + 1 < guide.stops.length) {
          Button(`下一步 · ${guide.stops[this.stopIndex + 1].title}`,
            { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('workspace-pr-guide-next').constraintSize({ minHeight: 44 }).enabled(!this.jumpLoading)
            .onClick(() => this.onSelect(this.stopIndex + 1))
        } else {
          Button(this.onFinishReview && !this.stale() ? '完成审查' : '结束导览',
            { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('workspace-pr-guide-finish').height(44).enabled(!this.jumpLoading)
            .onClick(() => {
              if (this.onFinishReview && !this.stale()) this.onFinishReview();
              else this.onSelect(-1);
            })
        }
      }.width('100%')
    }.id('workspace-pr-guide-step').width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 16 }) {
      this.Status()
      if (this.jumpLoading) {
        this.Notice('workspace-pr-guide-jump-loading', '', '正在定位变更文件…', true)
      } else if (this.jumpError) {
        this.Notice('workspace-pr-guide-jump-error', '', this.jumpError)
      }
      if (this.result?.guide && this.result.guide.stops.length > 0) {
        ForEach([this.result.guide], (guide: NativePullRequestGuide) => {
          if (this.stopIndex < 0) {
            this.Outline(guide)
          } else if (this.stopIndex < guide.stops.length) {
            this.Step(guide, guide.stops[this.stopIndex])
          } else {
            this.Notice('workspace-pr-guide-step-missing', '指南步骤已更新', '返回提纲可查看当前指南。')
          }
        }, (guide: NativePullRequestGuide) => `${guide.headSha}:${guide.generatedAt}:${this.stopIndex}`)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
