import { FrameCallback, LengthMetrics } from '@kit.ArkUI';
import { composerCommandContextReference, detectComposerCommandTrigger, replaceComposerCommandTrigger } from '../client/ComposerCommandProtocol';
import type { ComposerCommandContextRecord, ComposerCommandTrigger, ComposerCommandTriggerKind } from '../client/ComposerCommandProtocol';
import type { PickedThreadAttachment } from '../client/ThreadAttachmentProtocol';
import type { NativeQueuedMessage, NativeThreadUserInput, NativeThreadUserInputAnswers } from '../client/ThreadDetailProtocol';
import { ThreadComposerSuggestions } from './ThreadComposerSuggestions';
import type { ThreadComposerSuggestion } from './ThreadComposerSuggestions';
import { ThreadComposerContextSheet } from './ThreadComposerContextSheet';
import { ThreadQueuePanel } from './ThreadQueuePanel';
import { ThreadUserInputPanel } from './ThreadUserInputPanel';
import { UiLanguage, uiText } from './UiLanguage';

const MAX_DRAFT_LENGTH = 65_536;
const EDITOR_FONT_SIZE = 16;
const EDITOR_LINE_HEIGHT = 23;
const EDITOR_HORIZONTAL_PADDING = 8;
const EDITOR_VERTICAL_PADDING = 9;
const EDITOR_MAX_LINES = 4;
const EXPANDED_EDITOR_HEIGHT = EDITOR_LINE_HEIGHT * EDITOR_MAX_LINES + EDITOR_VERTICAL_PADDING * 2;
const CONTROL_SIZE = 42;

class ThreadComposerCaret extends FrameCallback {
  private place: () => void;

  constructor(place: () => void) {
    super();
    this.place = place;
  }

  onIdle(_timeLeftInNano: number): void {
    this.place();
  }
}

export interface ThreadDetailApprovalOption {
  requestId: string;
  decision: string;
  label: string;
}

@Component
export struct ThreadDetailComposer {
  @Prop @Watch('draftChanged') draft: string = '';
  @Prop placeholder: string = '';
  @Prop language: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  @Prop readOnly: boolean = false;
  @Prop canEditLocalDraft: boolean = false;
  @Prop error: string = '';
  @Prop sending: boolean = false;
  @Prop canSend: boolean = false;
  @Prop action: string = 'send';
  @Prop actionBusy: boolean = false;
  @Prop modelLabel: string = '';
  @Prop canPickModel: boolean = false;
  @Prop @Watch('suggestionScopeChanged') suggestionScope: string = '';
  @Prop @Watch('draftChanged') canAttach: boolean = false;
  @Prop pickingFiles: boolean = false;
  @Prop attachments: PickedThreadAttachment[] = [];
  @Prop contextRecords: ComposerCommandContextRecord[] = [];
  @Prop quotes: string[] = [];
  @Prop queuedCount: number = 0;
  @Prop queuedMessages: NativeQueuedMessage[] = [];
  @Prop @Watch('closeQueue') queueContext: number = 0;
  @Prop queueHeld: boolean = false;
  @Prop queueEditBlocked: boolean = false;
  @Prop queueCanWrite: boolean = false;
  @Prop queueBusy: boolean = false;
  @Prop queueError: string = '';
  @Prop userInput: NativeThreadUserInput | undefined = undefined;
  @Prop userInputCanWrite: boolean = false;
  @Prop userInputBusy: boolean = false;
  @State private showQueue: boolean = false;
  @State private suggestionKind?: ComposerCommandTriggerKind = undefined;
  @State private suggestionStatus: 'loading' | 'ready' | 'error' = 'ready';
  @State private suggestions: ThreadComposerSuggestion[] = [];
  @State private selectedContext?: ComposerCommandContextRecord = undefined;
  @State private editorExpanded: boolean = false;
  onReadSuggestions?: (trigger: ComposerCommandTrigger) => Promise<ThreadComposerSuggestion[]>;
  onSuggestionContext: (record: ComposerCommandContextRecord) => boolean = () => false;
  onOpenContextThread?: (environmentId: string, threadId: string) => void;
  onDraft: (value: string) => void = () => {};
  onAction: () => void = () => {};
  onPickModel: () => void = () => {};
  onPickAttachment: (photos: boolean) => void = () => {};
  onRemoveAttachment: (uri: string) => void = () => {};
  onRemoveQuote: (index: number) => void = () => {};
  onQueueSend: (runId: string) => void = () => {};
  onQueueEdit: (runId: string, text: string) => Promise<boolean> = async () => false;
  onQueueRemove: (runId: string) => void = () => {};
  onUserInputSubmit: (requestId: string, answers: NativeThreadUserInputAnswers) => void = () => {};
  onUserInputDismiss: (requestId: string) => void = () => {};
  onUserInputStop: (requestId: string) => void = () => {};

  private editor: TextAreaController = new TextAreaController();
  private editing: boolean = false;
  private suggestionKey: string = '';
  private suggestionTimer: number = -1;
  private suggestionRequest: number = 0;
  private caretRequest: number = 0;
  private composerWidth: number = 0;
  private controlsWidth: number = 0;

  aboutToAppear(): void {
    this.updateEditorLayout(this.draft);
  }

  aboutToDisappear(): void {
    this.closeSuggestions();
  }

  private closeSuggestions(): void {
    this.editing = false;
    this.caretRequest++;
    this.updateSuggestions(this.draft);
  }

  private draftChanged(): void {
    this.updateEditorLayout(this.draft);
    this.updateSuggestions(this.draft);
  }

  private updateEditorLayout(value: string): void {
    const width = this.composerWidth - Math.max(CONTROL_SIZE, this.controlsWidth) -
      (this.canAttach ? CONTROL_SIZE : 0) - EDITOR_HORIZONTAL_PADDING * 2;
    const context = this.getUIContext();
    const expanded = value.includes('\n') || (width > 0 && value.length > 0 && context.px2vp(
      context.getMeasureUtils().measureText({ textContent: value, fontSize: EDITOR_FONT_SIZE }),
    ) > width);
    if (this.editorExpanded !== expanded) this.editorExpanded = expanded;
  }

  private suggestionScopeChanged(): void {
    this.selectedContext = undefined;
    this.updateSuggestions(this.draft);
  }

  private activeTrigger(value: string, start?: number, end?: number): ComposerCommandTrigger | undefined {
    if (!this.editing || this.readOnly || !this.suggestionScope || !this.onReadSuggestions || this.sending || this.userInput) {
      return undefined;
    }
    const selection = this.editor.getSelection();
    return detectComposerCommandTrigger(value, start ?? selection?.start ?? -1, end ?? selection?.end ?? -1);
  }

  private updateSuggestions(value: string, start?: number, end?: number): void {
    const trigger = this.activeTrigger(value, start, end);
    const key = trigger ? JSON.stringify([this.suggestionScope, trigger.kind, trigger.query, trigger.rangeStart]) : '';
    if (key === this.suggestionKey) return;
    this.suggestionKey = key;
    clearTimeout(this.suggestionTimer);
    const request = ++this.suggestionRequest;
    this.suggestionKind = trigger?.kind;
    this.suggestions = [];
    if (!trigger) return;
    this.suggestionStatus = 'loading';
    this.suggestionTimer = setTimeout(() => { void this.readSuggestions(trigger, request); }, 220);
  }

  private async readSuggestions(trigger: ComposerCommandTrigger, request: number): Promise<void> {
    if (!this.onReadSuggestions || request !== this.suggestionRequest) return;
    try {
      const items = await this.onReadSuggestions(trigger);
      const current = this.activeTrigger(this.draft);
      if (request !== this.suggestionRequest || !current || current.kind !== trigger.kind ||
        current.rangeStart !== trigger.rangeStart || current.rangeEnd !== trigger.rangeEnd || current.query !== trigger.query) return;
      this.suggestions = items;
      this.suggestionStatus = 'ready';
    } catch (_) {
      if (request === this.suggestionRequest) this.suggestionStatus = 'error';
    }
  }

  private chooseSuggestion(item: ThreadComposerSuggestion): void {
    const trigger = this.activeTrigger(this.draft);
    if (!trigger || !this.suggestions.some((current: ThreadComposerSuggestion) => current.id === item.id)) return;
    const next = replaceComposerCommandTrigger(this.draft, trigger, item.replacement);
    if (next.text.length > MAX_DRAFT_LENGTH || (item.record && !this.onSuggestionContext(item.record))) return;
    this.onDraft(next.text);
    this.updateSuggestions(next.text, next.cursor, next.cursor);
    if (item.kind === 'model-picker') {
      this.onPickModel();
      return;
    }
    const request = ++this.caretRequest;
    this.getUIContext().postFrameCallback(new ThreadComposerCaret(() => {
      if (request === this.caretRequest && this.draft === next.text) this.editor.caretPosition(next.cursor);
    }));
  }

  private closeQueue(): void {
    this.showQueue = false;
  }

  private isDraftAction(): boolean {
    return this.action === 'send' || this.action === 'queue';
  }

  private busy(): boolean {
    return this.actionBusy || (this.isDraftAction() && this.sending);
  }

  private actionLabel(): string {
    switch (this.action) {
      case 'queue': return uiText(this.language, '排队发送', 'Queue message');
      case 'stop': return uiText(this.language, '停止代理', 'Stop agent');
      case 'resume': return uiText(this.language, '恢复队列', 'Resume thread');
      default: return uiText(this.language, '发送消息', 'Send message');
    }
  }

  private actionEnabled(): boolean {
    return !this.readOnly && !this.busy() && (!this.isDraftAction() || this.canSend);
  }

  private actionColor(): string {
    if (!this.actionEnabled() && !this.busy()) return this.dark ? '#27272A' : '#E4E4E7';
    if (this.action === 'stop') return this.dark ? '#9B1C1F' : '#C10007';
    return this.dark ? '#F5F5F5' : '#27272A';
  }

  private actionIconColor(): string {
    if (!this.actionEnabled() && !this.busy()) return this.dark ? '#A3A3A3' : '#71717B';
    return this.dark && this.action !== 'stop' ? '#0A0A0A' : '#FCFCFC';
  }

  private queueLabel(count: number): string {
    return uiText(this.language, `排队 ${count} 条`, count === 1 ? '1 queued message' : `${count} queued messages`);
  }

  private actionIcon(): Resource {
    switch (this.action) {
      case 'queue': return $r('sys.symbol.list_number');
      case 'stop': return $r('sys.symbol.square_fill');
      case 'resume': return $r('sys.symbol.play_fill');
      default: return $r('sys.symbol.arrow_up');
    }
  }

  @Builder
  private QueueSheet() {
    ThreadQueuePanel({
      language: this.language,
      messages: this.queuedMessages,
      held: this.queueHeld,
      editBlocked: this.queueEditBlocked,
      canWrite: this.queueCanWrite,
      busy: this.queueBusy,
      error: this.queueError || this.error,
      onClose: () => this.closeQueue(),
      onSend: (runId: string) => this.onQueueSend(runId),
      onEdit: (runId: string, text: string) => this.onQueueEdit(runId, text),
      onRemove: (runId: string) => this.onQueueRemove(runId),
    })
  }

  build() {
    Column({ space: 6 }) {
      if (this.error) {
        Text(this.error)
          .width('100%')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
          .wordBreak(WordBreak.BREAK_WORD)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.queuedMessages.length > 0) {
        Row() {
          Button(this.queueLabel(this.queuedMessages.length), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('thread-queue-open')
            .height(44)
            .onClick(() => { this.showQueue = true; })
        }.width('100%')
      } else if (this.queuedCount > 0) {
        Text(this.queueLabel(this.queuedCount))
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 8, bottom: 2 })
      }
      if (this.userInput) {
        ThreadUserInputPanel({
          language: this.language,
          request: this.userInput,
          context: this.queueContext,
          canWrite: this.userInputCanWrite,
          busy: this.userInputBusy,
          onSubmit: (requestId: string, answers: NativeThreadUserInputAnswers) => this.onUserInputSubmit(requestId, answers),
          onDismiss: (requestId: string) => this.onUserInputDismiss(requestId),
          onStop: (requestId: string) => this.onUserInputStop(requestId),
        })
      } else {
        if (this.suggestionKind && !this.sending && !this.readOnly) {
          ThreadComposerSuggestions({
            language: this.language,
            kind: this.suggestionKind,
            status: this.suggestionStatus,
            items: this.suggestions,
            onChoose: (item: ThreadComposerSuggestion) => this.chooseSuggestion(item),
          })
        }
        this.MessageEditor()
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(this.dark ? '#0A0A0A' : '#FCFCFC')
    .bindSheet(this.showQueue, this.QueueSheet(), {
      height: SheetSize.LARGE,
      showClose: false,
      onDisappear: () => this.closeQueue(),
    })
  }

  @Builder
  private ContextSheet() {
    ThreadComposerContextSheet({
      language: this.language,
      record: this.selectedContext,
      onClose: () => { this.selectedContext = undefined; },
      onRemove: this.readOnly ? undefined : (record: ComposerCommandContextRecord) => {
        const reference = composerCommandContextReference(record);
        this.onDraft(this.draft.split(reference + ' ').join('').split(reference).join(''));
      },
      onOpenThread: this.onOpenContextThread,
    })
  }

  @Builder
  private MessageEditor() {
    if (this.contextRecords.length > 0) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.contextRecords, (record: ComposerCommandContextRecord) => {
            Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
              Row({ space: 6 }) {
                SymbolGlyph(record.kind === 'thread' ? $r('sys.symbol.message_on_message') :
                  record.kind === 'environment' ? $r('sys.symbol.computer') : $r('sys.symbol.link'))
                  .fontSize(14).fontColor([$r('sys.color.icon_secondary')])
                Text(record.label).fontSize(13).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .id('thread-draft-context-' + record.contextId).height(36).constraintSize({ maxWidth: 208 })
            .borderRadius(12).backgroundColor($r('sys.color.comp_background_secondary'))
            .padding({ left: 10, right: 10 }).enabled(!this.sending)
            .accessibilityText(uiText(this.language, `查看上下文 ${record.label}`, `View context ${record.label}`))
            .onClick(() => { this.selectedContext = record; })
          }, (record: ComposerCommandContextRecord) => record.contextId)
        }
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      .bindSheet(this.selectedContext !== undefined, this.ContextSheet(), {
        height: SheetSize.MEDIUM, detents: [SheetSize.MEDIUM, SheetSize.LARGE], showClose: false,
        onDisappear: () => { this.selectedContext = undefined; },
      })
    }
    if (this.quotes.length > 0) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.quotes, (quote: string, index: number) => {
            Row({ space: 2 }) {
              Text('“' + quote + '”').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 180 }).fontSize(13)
              Button('×', { buttonStyle: ButtonStyleMode.TEXTUAL })
                .width(36).height(36).accessibilityText(uiText(this.language, '移除引用', 'Remove quote'))
                .enabled(!this.sending && !this.readOnly).onClick(() => this.onRemoveQuote(index))
            }.backgroundColor($r('sys.color.comp_background_secondary')).borderRadius(12).padding({ left: 10 })
          }, (quote: string, index: number) => index + ':' + quote)
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
    }
    if (this.attachments.length > 0) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.attachments, (attachment: PickedThreadAttachment) => {
            Row({ space: 2 }) {
              Text(attachment.name)
                .constraintSize({ maxWidth: 148 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontSize(13)
              Button('×', { buttonStyle: ButtonStyleMode.TEXTUAL })
                .width(36)
                .height(36)
                .accessibilityText(uiText(this.language, `移除附件 ${attachment.name}`, `Remove ${attachment.name}`))
                .enabled(!this.sending && !this.readOnly)
                .onClick(() => this.onRemoveAttachment(attachment.uri))
            }.backgroundColor($r('sys.color.comp_background_secondary')).borderRadius(12).padding({ left: 10 })
          }, (attachment: PickedThreadAttachment) => attachment.uri)
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
    }
    Stack({ alignContent: Alignment.BottomStart }) {
      Flex({
        direction: this.editorExpanded ? FlexDirection.Column : FlexDirection.Row,
        alignItems: this.editorExpanded ? ItemAlign.End : ItemAlign.Center,
      }) {
        TextArea({
          text: this.draft, controller: this.editor,
          placeholder: this.placeholder || uiText(this.language, '输入消息', 'Ask anything'),
        })
          .id('thread-draft')
          .width(this.editorExpanded ? '100%' : undefined)
          .layoutWeight(this.editorExpanded ? 0 : 1)
          .margin({ left: !this.editorExpanded && this.canAttach ? CONTROL_SIZE : 0 })
          .constraintSize({
            minHeight: CONTROL_SIZE,
            maxHeight: this.editorExpanded ? EXPANDED_EDITOR_HEIGHT : CONTROL_SIZE,
          })
          .padding({
            left: EDITOR_HORIZONTAL_PADDING, right: EDITOR_HORIZONTAL_PADDING,
            top: EDITOR_VERTICAL_PADDING, bottom: EDITOR_VERTICAL_PADDING,
          })
          .fontSize(EDITOR_FONT_SIZE)
          .lineHeight(EDITOR_LINE_HEIGHT)
          .fontColor(this.dark ? '#F5F5F5' : '#27272A')
          .placeholderColor(this.dark ? '#A3A3A3' : '#6F6F79')
          .backgroundColor(Color.Transparent)
          .enabled(!this.readOnly || this.canEditLocalDraft)
          .enterKeyType(EnterKeyType.NEW_LINE)
          .accessibilityText(this.placeholder || uiText(this.language, '输入消息', 'Message'))
          .onFocus(() => {
            this.editing = true;
            this.draftChanged();
          })
          .onBlur(() => this.closeSuggestions())
          .onTextSelectionChange((start: number, end: number) => this.updateSuggestions(this.draft, start, end))
          .onChange((value: string) => {
            this.updateEditorLayout(value);
            this.onDraft(value);
            this.updateSuggestions(value);
          })
        this.MessageActions()
      }
      .width('100%')
      .constraintSize({ maxHeight: this.editorExpanded ? EXPANDED_EDITOR_HEIGHT + CONTROL_SIZE : CONTROL_SIZE })
      .onSizeChange((_previous: SizeOptions, current: SizeOptions) => {
        if (typeof current.width !== 'number' || this.composerWidth === current.width) return;
        this.composerWidth = current.width;
        this.updateEditorLayout(this.draft);
      })

      if (this.canAttach) {
        Button({ type: ButtonType.Circle }) {
          if (this.pickingFiles) {
            LoadingProgress().width(18).height(18)
          } else {
            SymbolGlyph($r('sys.symbol.plus')).fontSize(22)
              .fontColor([this.dark ? '#F5F5F5' : '#27272A'])
          }
        }
        .id('thread-attach')
        .width(CONTROL_SIZE)
        .height(CONTROL_SIZE)
        .backgroundColor(Color.Transparent)
        .accessibilityText(uiText(this.language, '添加附件', 'Add to message'))
        .enabled(!this.readOnly && !this.sending && !this.pickingFiles)
        .bindMenu([
          { value: uiText(this.language, '照片', 'Photos'), action: () => this.onPickAttachment(true) },
          { value: uiText(this.language, '文件', 'Files'), action: () => this.onPickAttachment(false) },
        ])
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 52 })
    .padding({ left: 4, right: 4, top: 4, bottom: 4 })
    .border({ width: 1, color: this.dark ? '#242424' : '#E4E4E7' })
    .borderRadius(27)
    .backgroundColor(this.dark ? '#1A1B1B' : '#F4F4F5')
  }

  @Builder
  private MessageActions() {
    Row({ space: 4 }) {
      if (this.canPickModel) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 4 }) {
            Text(this.modelLabel || uiText(this.language, '模型', 'Model'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.dark ? '#F5F5F5' : '#27272A')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 76 })
            SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(10)
              .fontColor([this.dark ? '#A3A3A3' : '#71717B'])
          }
        }
        .id('thread-model')
        .backgroundColor(Color.Transparent)
        .height(CONTROL_SIZE)
        .padding({ left: 5, right: 5 })
        .borderRadius(12)
        .enabled(!this.readOnly)
        .accessibilityText(this.modelLabel ?
          uiText(this.language, `选择模型，${this.modelLabel}`, `Choose model, ${this.modelLabel}`) :
          uiText(this.language, '选择模型', 'Choose model'))
        .onClick(() => this.onPickModel())
      } else if (this.modelLabel) {
        Text(this.modelLabel)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dark ? '#A3A3A3' : '#6F6F79')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 86 })
      }
      Button({ type: ButtonType.Circle }) {
        if (this.busy()) {
          LoadingProgress().width(20).height(20).color(this.actionIconColor())
        } else {
          SymbolGlyph(this.actionIcon()).fontSize(this.action === 'stop' ? 15 : 20)
            .fontColor([this.actionIconColor()])
        }
      }
      .id(this.isDraftAction() ? 'thread-send' : `thread-${this.action}`)
      .width(CONTROL_SIZE)
      .height(CONTROL_SIZE)
      .backgroundColor(this.actionColor())
      .enabled(this.actionEnabled())
      .accessibilityGroup(true)
      .accessibilityText(this.busy() ?
        uiText(this.language, '正在处理，' + this.actionLabel(), this.actionLabel() + ', in progress') :
        this.actionLabel())
      .onClick(() => this.onAction())
    }
    .alignItems(VerticalAlign.Center)
    .onSizeChange((_previous: SizeOptions, current: SizeOptions) => {
      if (typeof current.width !== 'number' || this.controlsWidth === current.width) return;
      this.controlsWidth = current.width;
      this.updateEditorLayout(this.draft);
    })
  }
}

@Component
export struct ThreadDetailApproval {
  @Prop language: UiLanguage = 'zh';
  @Prop prompt: string = '';
  @Prop reason: string = '';
  @Prop busy: boolean = false;
  @Prop options: ThreadDetailApprovalOption[] = [];
  @Prop supportsFeedback: boolean = false;
  onDecision: (requestId: string, decision: string) => void = () => {};

  private optionLabel(option: ThreadDetailApprovalOption): string {
    switch (option.label) {
      case '允许一次': return uiText(this.language, option.label, 'Allow once');
      case '本次会话允许': return uiText(this.language, option.label, 'Allow for this session');
      case '拒绝': return uiText(this.language, option.label, 'Decline');
      default: return option.label;
    }
  }

  build() {
    if (this.options.length > 0 || this.supportsFeedback) {
      Column({ space: 8 }) {
        Scroll() {
          Column({ space: 4 }) {
            Text(this.prompt)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .wordBreak(WordBreak.BREAK_WORD)
              .copyOption(CopyOptions.LocalDevice)
            if (this.reason) {
              Text(this.reason)
                .fontSize(14)
                .fontColor($r('sys.color.font_secondary'))
                .wordBreak(WordBreak.BREAK_WORD)
                .copyOption(CopyOptions.LocalDevice)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 120 })
        .align(Alignment.TopStart)

        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(6) } }) {
          ForEach(this.options, (option: ThreadDetailApprovalOption) => {
            Button(this.optionLabel(option), { buttonStyle: ButtonStyleMode.NORMAL })
              .id(`thread-approval-${option.decision}`)
              .constraintSize({ minHeight: 44 })
              .enabled(!this.busy)
              .onClick(() => this.onDecision(option.requestId, option.decision))
          }, (option: ThreadDetailApprovalOption) => option.requestId + ':' + option.decision)
        }
      }
      .id('thread-approval')
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(12)
      .border({ width: 1, color: $r('sys.color.comp_divider') })
      .borderRadius(16)
      .backgroundColor($r('sys.color.comp_background_secondary'))
    }
  }
}
