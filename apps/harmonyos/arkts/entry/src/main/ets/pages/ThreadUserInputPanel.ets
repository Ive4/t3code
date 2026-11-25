import { UiLanguage, uiText } from './UiLanguage';
import {
  NativeThreadUserInput,
  NativeThreadUserInputAnswers,
  NativeThreadUserInputDraft,
  NativeThreadUserInputOption,
  NativeThreadUserInputQuestion,
  buildUserInputAnswers,
  userInputCustomAnswer,
  userInputOptionValue,
} from '../client/ThreadDetailProtocol';

@Component
export struct ThreadUserInputPanel {
  @Prop language: UiLanguage = 'zh';
  @Prop @Watch('requestChanged') request: NativeThreadUserInput | undefined = undefined;
  @Prop @Watch('requestChanged') context: number = 0;
  @Prop canWrite: boolean = false;
  @Prop busy: boolean = false;
  @State private drafts: Map<string, NativeThreadUserInputDraft> = new Map();
  @State private expanded: boolean = true;
  private draftRequestId: string = '';
  private draftContext: number = 0;
  onSubmit: (requestId: string, answers: NativeThreadUserInputAnswers) => void = () => {};
  onDismiss: (requestId: string) => void = () => {};
  onStop: (requestId: string) => void = () => {};

  aboutToAppear(): void {
    this.requestChanged();
  }

  private requestChanged(): void {
    const requestId = this.request?.id ?? '';
    if (this.draftRequestId === requestId && this.draftContext === this.context) return;
    this.draftRequestId = requestId;
    this.draftContext = this.context;
    this.drafts = new Map();
    this.expanded = true;
  }

  private canRespond(): boolean {
    return this.canWrite && !this.busy && this.request?.canRespond === true;
  }

  private answers(): NativeThreadUserInputAnswers | undefined {
    const request = this.request;
    return request ? buildUserInputAnswers(request.questions, this.drafts, request.dismissible) : undefined;
  }

  private isSelected(question: NativeThreadUserInputQuestion, option: NativeThreadUserInputOption): boolean {
    const draft = this.drafts.get(question.id);
    return !userInputCustomAnswer(question, draft).trim() && draft?.selected?.includes(userInputOptionValue(option)) === true;
  }

  private setDraft(questionId: string, draft: NativeThreadUserInputDraft): void {
    const next = new Map<string, NativeThreadUserInputDraft>(this.drafts);
    next.set(questionId, draft);
    this.drafts = next;
  }

  private select(question: NativeThreadUserInputQuestion, option: NativeThreadUserInputOption): void {
    if (!this.canRespond()) return;
    const value = userInputOptionValue(option);
    const previous = this.drafts.get(question.id)?.selected ?? [];
    let selected = [value];
    if (question.multiSelect) {
      selected = previous.includes(value) ? previous.filter((entry: string): boolean => entry !== value) :
        previous.concat([value]);
    } else if (question.required === false && previous.includes(value)) {
      selected = [];
    }
    this.setDraft(question.id, { selected, custom: '' });
  }

  private typeAnswer(question: NativeThreadUserInputQuestion, custom: string): void {
    const draft = this.drafts.get(question.id);
    if (!this.canRespond() || question.allowCustomAnswer === false ||
      userInputCustomAnswer(question, draft) === custom) return;
    this.setDraft(question.id, {
      custom,
      selected: custom.trim() || question.initialAnswer !== undefined ? undefined : draft?.selected,
    });
  }

  private submit(): void {
    const request = this.request;
    if (!request || !this.canRespond()) return;
    const answers = this.answers();
    if (answers) this.onSubmit(request.id, answers);
  }

  private dismiss(): void {
    const request = this.request;
    if (request?.dismissible && this.canRespond()) this.onDismiss(request.id);
  }

  private stop(): void {
    const request = this.request;
    if (request?.stopRunId && this.canWrite && !this.busy) this.onStop(request.id);
  }

  @Builder
  private Option(question: NativeThreadUserInputQuestion, option: NativeThreadUserInputOption) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 3 }) {
        Text(option.label)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .wordBreak(WordBreak.BREAK_WORD)
        if (option.description !== option.label) {
          Text(option.description)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .wordBreak(WordBreak.BREAK_WORD)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .id(`thread-user-input-${question.id}-${userInputOptionValue(option)}`)
    .width('100%')
    .constraintSize({ minHeight: 44 })
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .backgroundColor($r('sys.color.comp_background_primary'))
    .border({ width: this.isSelected(question, option) ? 2 : 1,
      color: this.isSelected(question, option) ? $r('sys.color.icon_emphasize') : $r('sys.color.comp_divider') })
    .borderRadius(12)
    .accessibilityGroup(true)
    .accessibilitySelected(this.isSelected(question, option))
    .enabled(this.canRespond())
    .onClick(() => this.select(question, option))
    if (option.preview) {
      Text(option.preview)
        .width('100%')
        .padding({ left: 10, right: 10 })
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
        .wordBreak(WordBreak.BREAK_WORD)
        .copyOption(CopyOptions.LocalDevice)
    }
  }

  private answerPlaceholder(question: NativeThreadUserInputQuestion): string {
    return question.options.length > 0 ? uiText(this.language, '自定义答案', 'Custom answer') :
      uiText(this.language, '输入答案', 'Enter answer');
  }

  @Builder
  private Question(question: NativeThreadUserInputQuestion) {
    Column({ space: 6 }) {
      Text(question.required === false ? uiText(this.language, `${question.header}（可选）`, `${question.header} (optional)`) :
        question.header)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .wordBreak(WordBreak.BREAK_WORD)
      Text(question.question)
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
        .wordBreak(WordBreak.BREAK_WORD)
        .copyOption(CopyOptions.LocalDevice)
      ForEach(question.options, (option: NativeThreadUserInputOption) => {
        this.Option(question, option)
      }, (option: NativeThreadUserInputOption, index: number) => `${index}:${userInputOptionValue(option)}`)
      if (question.allowCustomAnswer !== false) {
        TextArea({
          text: userInputCustomAnswer(question, this.drafts.get(question.id)),
          placeholder: this.answerPlaceholder(question),
        })
          .id(`thread-user-input-text-${question.id}`)
          .width('100%')
          .constraintSize({ minHeight: 46, maxHeight: 120 })
          .enterKeyType(EnterKeyType.NEW_LINE)
          .accessibilityText(uiText(this.language, `${question.header}，${this.answerPlaceholder(question)}`,
            `${question.header}, ${this.answerPlaceholder(question)}`))
          .enabled(this.canRespond())
          .onChange((value: string) => this.typeAnswer(question, value))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    if (this.request) {
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Text(uiText(this.language, `需要回答 · ${this.request.questions.length} 个问题`,
            this.request.questions.length === 1 ? 'Answer requested · 1 question' :
              `Answer requested · ${this.request.questions.length} questions`))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          Button(this.expanded ? uiText(this.language, '收起', 'Collapse') : uiText(this.language, '展开', 'Expand'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('thread-user-input-toggle')
            .height(44)
            .accessibilityText(this.expanded ? uiText(this.language, '收起问题', 'Collapse questions') : uiText(this.language, '展开问题', 'Expand questions'))
            .onClick(() => { this.expanded = !this.expanded; })
          if (this.request.stopRunId && this.canWrite) {
            Button(uiText(this.language, '停止', 'Stop'), { buttonStyle: ButtonStyleMode.TEXTUAL, role: ButtonRole.ERROR })
              .id('thread-user-input-stop')
              .height(44)
              .enabled(!this.busy)
              .accessibilityText(uiText(this.language, '停止当前运行', 'Stop current run'))
              .onClick(() => this.stop())
          }
        }
        .width('100%')
        if (this.expanded) {
          Scroll() {
            Column({ space: 12 }) {
              if (!this.request.canRespond) {
                Text(this.request.reason || uiText(this.language, '提供方已无法接收此答复。可停止当前运行。', 'The provider can no longer accept an answer. You can stop the current run.'))
                  .width('100%')
                  .fontSize(14)
                  .fontColor($r('sys.color.font_secondary'))
                  .wordBreak(WordBreak.BREAK_WORD)
              }
              ForEach(this.request.questions, (question: NativeThreadUserInputQuestion) => {
                this.Question(question)
              }, (question: NativeThreadUserInputQuestion) => `${this.request?.id}:${question.id}`)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .constraintSize({ maxHeight: 220 })
          .align(Alignment.TopStart)
          Button(this.busy ? uiText(this.language, '正在处理…', 'Submitting…') : uiText(this.language, '提交答案', 'Submit answers'))
            .id('thread-user-input-submit')
            .width('100%')
            .constraintSize({ minHeight: 44 })
            .enabled(this.canRespond() && this.answers() !== undefined)
            .onClick(() => this.submit())
          if (this.request.dismissible && this.canWrite) {
            Button(uiText(this.language, '不回答并关闭', 'Dismiss without answering'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .id('thread-user-input-dismiss')
              .width('100%')
              .constraintSize({ minHeight: 44 })
              .enabled(this.canRespond())
              .onClick(() => this.dismiss())
          }
        }
      }
      .id('thread-user-input')
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(10)
      .border({ width: 1, color: $r('sys.color.comp_divider') })
      .borderRadius(16)
      .backgroundColor($r('sys.color.comp_background_secondary'))
    }
  }
}
