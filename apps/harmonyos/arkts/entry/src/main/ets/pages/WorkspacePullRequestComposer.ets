import { FrameCallback } from '@kit.ArkUI';
import {
  detectPullRequestComposerTrigger, insertPullRequestCompletion, pullRequestCompletions,
} from '../client/PullRequestReferenceProtocol';
import type {
  NativePullRequestCompletion, NativePullRequestCompletionOptions, NativePullRequestCompletionSupport,
  NativePullRequestComposerTrigger,
} from '../client/PullRequestReferenceProtocol';

const TEXT_LIMIT = 65_536;

class PlaceComposerCaret extends FrameCallback {
  private place: () => void;

  constructor(place: () => void) {
    super();
    this.place = place;
  }

  onIdle(_timeLeftInNano: number): void {
    this.place();
  }
}

@Component
export struct WorkspacePullRequestComposer {
  @Prop @Watch('contentChanged') value: string = '';
  @Prop @Watch('contentChanged') support?: NativePullRequestCompletionSupport = undefined;
  @Prop controlId: string = '';
  @Prop label: string = '';
  @Prop placeholder: string = '';
  @Prop inputHeight: number = 144;
  @Prop fixedHeight: boolean = true;
  @Prop @Watch('contentChanged') editable: boolean = true;
  onValueChange: (value: string) => void = () => {};
  onRead?: (trigger: NativePullRequestComposerTrigger) => Promise<NativePullRequestCompletionOptions>;

  @State private status: 'hidden' | 'loading' | 'error' | 'ready' = 'hidden';
  @State private candidates: NativePullRequestCompletion[] = [];
  private controller: TextAreaController = new TextAreaController();
  private focused: boolean = false;
  private selectionStart: number = -1;
  private selectionEnd: number = -1;
  private completionKey: string = '';
  private options?: NativePullRequestCompletionOptions = undefined;
  private timer: number = -1;
  private request: number = 0;
  private placement: number = 0;

  aboutToDisappear(): void {
    this.stopCompleting();
  }

  private stopCompleting(): void {
    this.focused = false;
    this.placement++;
    this.contentChanged();
  }

  private trigger(value: string): NativePullRequestComposerTrigger | undefined {
    if (!this.onRead || !this.focused || !this.editable || this.selectionStart < 0 ||
      this.selectionStart !== this.selectionEnd) return undefined;
    return detectPullRequestComposerTrigger(value, this.selectionStart, this.support);
  }

  private contentChanged(): void {
    this.updateCompletions(this.value);
  }

  private updateCompletions(value: string): void {
    const trigger = this.trigger(value);
    const key = trigger ? `${trigger.sigil}${trigger.query}` : '';
    if (key === this.completionKey) return;
    if (key[0] !== this.completionKey[0]) this.options = undefined;
    this.completionKey = key;
    clearTimeout(this.timer);
    const request = ++this.request;
    this.candidates = pullRequestCompletions(trigger, this.options);
    this.status = trigger ? 'loading' : 'hidden';
    if (trigger) this.timer = setTimeout(() => { void this.read(trigger, request); }, 250);
  }

  private async read(trigger: NativePullRequestComposerTrigger, request: number): Promise<void> {
    if (!this.onRead || request !== this.request) return;
    try {
      const options = await this.onRead(trigger);
      if (request !== this.request) return;
      this.options = options;
      this.candidates = pullRequestCompletions(this.trigger(this.value), options);
      this.status = 'ready';
    } catch (_) {
      if (request === this.request) this.status = 'error';
    }
  }

  private choose(candidate: NativePullRequestCompletion): void {
    const trigger = this.trigger(this.value);
    if (!trigger || !pullRequestCompletions(trigger, this.options)
      .some((entry: NativePullRequestCompletion) => entry.token === candidate.token)) return;
    const next = insertPullRequestCompletion(this.value, trigger, candidate.token);
    if (next.text.length > TEXT_LIMIT) return;
    this.selectionStart = next.cursor;
    this.selectionEnd = next.cursor;
    this.onValueChange(next.text);
    this.updateCompletions(next.text);
    const placement = ++this.placement;
    this.getUIContext().postFrameCallback(new PlaceComposerCaret(() => {
      if (placement === this.placement && this.value === next.text) this.controller.caretPosition(next.cursor);
    }));
  }

  @Builder
  private Suggestions() {
    if (this.status !== 'hidden') {
      Column() {
        if (this.candidates.length) {
          Scroll() {
            Column() {
              ForEach(this.candidates, (candidate: NativePullRequestCompletion) => {
                Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                  Row({ space: 8 }) {
                    Text(candidate.title).fontSize(15).fontWeight(FontWeight.Medium)
                      .fontColor($r('sys.color.font_primary')).maxLines(1)
                    Text(candidate.subtitle).fontSize(13).fontColor($r('sys.color.font_secondary'))
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                    if (candidate.state) {
                      Text(candidate.state === 'merged' ? '已合并' : candidate.state === 'closed' ? '已关闭' : '开放')
                        .fontSize(12).fontColor($r('sys.color.font_secondary'))
                    }
                  }.width('100%')
                }.id(`workspace-pr-completion-${candidate.token}`).width('100%').height(44)
                  .padding({ left: 12, right: 12 }).focusable(false).accessibilityText(`插入 ${candidate.token}`)
                  .onClick(() => this.choose(candidate))
              }, (candidate: NativePullRequestCompletion) => candidate.token)
            }.width('100%')
          }.width('100%').constraintSize({ maxHeight: 176 }).scrollBar(BarState.Off)
        } else {
          Row({ space: 8 }) {
            if (this.status === 'loading') LoadingProgress().width(18).height(18)
            Text(this.status === 'loading' ? '正在搜索…' : this.status === 'error' ? '无法从主机读取引用候选。'
              : this.completionKey.startsWith('@') ? '没有匹配的用户。' : '没有匹配的工单或拉取请求。')
              .fontSize(13).fontColor($r('sys.color.font_secondary'))
          }.width('100%').padding(12)
        }
      }.id('workspace-pr-completions').width('100%').borderRadius(16)
        .backgroundColor($r('sys.color.comp_background_secondary'))
    }
  }

  build() {
    Column({ space: 8 }) {
      this.Suggestions()
      TextArea({ text: this.value, placeholder: this.placeholder, controller: this.controller })
        .id(this.controlId).accessibilityText(this.label).width('100%')
        .constraintSize({ minHeight: this.inputHeight, maxHeight: this.fixedHeight ? this.inputHeight : undefined })
        .maxLength(TEXT_LIMIT).fontSize(16).padding(this.fixedHeight ? 14 : 16).borderRadius(this.fixedHeight ? 16 : 20)
        .backgroundColor($r('sys.color.comp_background_secondary')).enabled(this.editable)
        .onFocus(() => {
          this.focused = true;
          const selection = this.controller.getSelection();
          this.selectionStart = selection?.start ?? -1;
          this.selectionEnd = selection?.end ?? -1;
          this.contentChanged();
        })
        .onBlur(() => this.stopCompleting())
        .onTextSelectionChange((start: number, end: number) => {
          this.selectionStart = start;
          this.selectionEnd = end;
          this.contentChanged();
        })
        .onChange((value: string) => {
          this.onValueChange(value);
          this.updateCompletions(value);
        })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
