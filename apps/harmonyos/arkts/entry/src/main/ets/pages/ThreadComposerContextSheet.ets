import { UiLanguage, uiText } from './UiLanguage';
import type { ComposerCommandContextRecord } from '../client/ComposerCommandProtocol';
import type { NativePullRequestState } from '../client/PullRequestProtocol';
import { readReviewCommentContextRecord } from '../client/ThreadHistoricalReviewCommentProtocol';
import type { NativeHistoricalReviewComment } from '../client/ThreadHistoricalReviewCommentProtocol';
import { ThreadHistoricalReviewCommentCard } from './ThreadHistoricalReviewCommentCard';

interface ComposerPullRequestPreview {
  number: number;
  title: string;
  url: string;
  headBranch: string;
  baseBranch: string;
  state: NativePullRequestState;
  isDraft: boolean;
}

interface ComposerPullRequestContext extends ComposerCommandContextRecord {
  pullRequest?: ComposerPullRequestPreview;
}

@Component
export struct ThreadComposerContextSheet {
  @Prop language: UiLanguage = 'zh';
  @Prop record: ComposerCommandContextRecord | undefined = undefined;
  onClose: () => void = () => {};
  onRemove?: (record: ComposerCommandContextRecord) => void;
  onOpenThread?: (environmentId: string, threadId: string) => void;
  onOpenPullRequest?: (url: string) => void;

  private openThread(record: ComposerCommandContextRecord): void {
    if (!record.environmentId || !record.threadId || !this.onOpenThread) return;
    this.onClose();
    this.onOpenThread(record.environmentId, record.threadId);
  }

  private openPullRequest(url: string): void {
    if (!this.onOpenPullRequest) return;
    this.onClose();
    this.onOpenPullRequest(url);
  }

  private pullRequest(): ComposerPullRequestPreview | undefined {
    return this.record?.kind === 'review-comment' ?
      (this.record as ComposerPullRequestContext).pullRequest : undefined;
  }

  private fileReview(): NativeHistoricalReviewComment | undefined {
    return this.record ? readReviewCommentContextRecord(this.record) : undefined;
  }

  private pullRequestState(pullRequest: ComposerPullRequestPreview): string {
    if (pullRequest.isDraft) return uiText(this.language, '草稿', 'Draft');
    if (pullRequest.state === 'closed') return uiText(this.language, '已关闭', 'Closed');
    if (pullRequest.state === 'merged') return uiText(this.language, '已合并', 'Merged');
    return uiText(this.language, '开放', 'Open');
  }

  @Builder
  private Header() {
    Row({ space: 12 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(22)
          .fontColor([$r('sys.color.icon_primary')])
      }
      .id('thread-composer-context-close')
      .accessibilityText(uiText(this.language, '关闭上下文', 'Close context'))
      .height(44)
      .width(44)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.onClose())
      Text(this.record?.label || uiText(this.language, '上下文', 'Context'))
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(56)
    .width('100%')
    .padding({ left: 8, right: 20 })
  }

  @Builder
  private Field(label: string, value: string) {
    Column({ space: 4 }) {
      Text(label).fontSize(12).fontColor($r('sys.color.font_secondary'))
      Text(value)
        .fontSize(16)
        .lineHeight(24)
        .fontColor($r('sys.color.font_primary'))
        .wordBreak(WordBreak.BREAK_WORD)
        .copyOption(CopyOptions.LocalDevice)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Action(label: string, id: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Text(label).fontSize(16).fontColor($r('sys.color.font_primary'))
    }
    .id(id)
    .width('100%')
    .height(48)
    .borderRadius(12)
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .onClick(() => action())
  }

  @Builder
  private PullRequest(pullRequest: ComposerPullRequestPreview) {
    this.Field(`#${pullRequest.number} · ${this.pullRequestState(pullRequest)}`,
      `${pullRequest.title}\n${pullRequest.headBranch} → ${pullRequest.baseBranch}`)
    if (this.onOpenPullRequest && /^https?:\/\//i.test(pullRequest.url)) {
      Button({ type: ButtonType.Normal }) {
        Text(/\/-\/merge_requests\//.test(pullRequest.url) ? uiText(this.language, '打开合并请求', 'Open merge request') : uiText(this.language, '打开拉取请求', 'Open pull request'))
          .fontSize(16).fontColor($r('sys.color.font_primary')).width('100%')
      }
      .id('thread-composer-context-open-pr')
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
      .borderRadius(12)
      .backgroundColor($r('sys.color.comp_background_secondary'))
      .onClick(() => this.openPullRequest(pullRequest.url))
    }
  }

  build() {
    Column() {
      this.Header()
      Scroll() {
        Column({ space: 16 }) {
          if (this.record?.kind === 'thread') {
            this.Field(uiText(this.language, '会话', 'Thread'), this.record.title ?? this.record.label)
            if (this.onOpenThread && this.record.environmentId && this.record.threadId) {
              this.Action(uiText(this.language, '打开会话', 'Open thread'), 'thread-composer-context-open-thread', () => {
                if (this.record) this.openThread(this.record);
              })
            }
          } else if (this.record?.kind === 'environment') {
            this.Field(uiText(this.language, '主机', 'Environment'), this.record.label)
          } else if (this.pullRequest()) {
            this.PullRequest(this.pullRequest()!)
          } else if (this.fileReview()) {
            ThreadHistoricalReviewCommentCard({
              language: this.language,
              filePath: this.fileReview()?.filePath ?? '', rangeLabel: this.fileReview()?.rangeLabel ?? '',
              diff: this.fileReview()?.diff ?? '', comment: this.fileReview()?.text ?? '',
              sectionTitle: this.fileReview()?.sectionTitle ?? '',
            })
          } else {
            Text(uiText(this.language, '上下文不可用。请从原消息重新复制，或移除此引用。', 'Context unavailable. Copy it again from the original message or remove it.'))
              .fontSize(16).fontColor($r('sys.color.font_primary'))
          }
          if (this.record && this.onRemove) {
            this.Action(uiText(this.language, '从草稿中移除', 'Remove from draft'), 'thread-composer-context-remove', () => {
              const record = this.record;
              if (!record) return;
              this.onClose();
              this.onRemove?.(record);
            })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 20, right: 20, top: 12, bottom: 20 })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
