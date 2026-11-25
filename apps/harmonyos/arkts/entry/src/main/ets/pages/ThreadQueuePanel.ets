import { UiLanguage, uiText } from './UiLanguage';
import {
  NativeQueuedMessage, queuedMessageEditorText, queuedMessagePreview, queuedMessageSubmissionText,
} from '../client/ThreadDetailProtocol';

@Component
export struct ThreadQueuePanel {
  @Prop language: UiLanguage = 'zh';
  @Prop @Watch('queueChanged') messages: NativeQueuedMessage[] = [];
  @Prop held: boolean = false;
  @Prop editBlocked: boolean = false;
  @Prop canWrite: boolean = false;
  @Prop busy: boolean = false;
  @Prop error: string = '';
  @State private editingRunId: string = '';
  @State private editText: string = '';
  @State private saving: boolean = false;
  onClose: () => void = () => {};
  onSend: (runId: string) => void = () => {};
  onEdit: (runId: string, text: string) => Promise<boolean> = async () => false;
  onRemove: (runId: string) => void = () => {};

  private queueChanged(): void {
    if (this.messages.length === 0 && !this.editingRunId) this.onClose();
  }

  private rowBeingEdited(): NativeQueuedMessage | undefined {
    return this.messages.find((message: NativeQueuedMessage): boolean => message.runId === this.editingRunId);
  }

  private beginEdit(message: NativeQueuedMessage): void {
    this.editText = queuedMessageEditorText(message.text);
    this.editingRunId = message.runId;
  }

  private endEdit(): void {
    this.editingRunId = '';
    this.editText = '';
    this.queueChanged();
  }

  private canSave(): boolean {
    const message = this.rowBeingEdited();
    return this.canWrite && !this.busy && !this.saving && !this.editBlocked &&
      message?.canEdit === true && (this.editText.trim().length > 0 || message.attachments.length > 0);
  }

  private async save(): Promise<void> {
    if (!this.canSave()) return;
    const text = queuedMessageSubmissionText(this.editText, (this.rowBeingEdited()?.attachments.length ?? 0) > 0);
    this.saving = true;
    try {
      if (await this.onEdit(this.editingRunId, text)) this.endEdit();
    } finally {
      this.saving = false;
    }
  }

  private preview(message: NativeQueuedMessage): string {
    return queuedMessagePreview(message.text) || (message.attachments.length > 0 ? uiText(this.language, '附件', 'Attachment') : uiText(this.language, '排队消息', 'Queued messages'));
  }

  @Builder
  private Attachments(names: string[]) {
    if (names.length > 0) {
      Text(names.join('、'))
        .width('100%')
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
        .wordBreak(WordBreak.BREAK_WORD)
        .accessibilityText(uiText(this.language, `附件 ${names.join('、')}`, `Attachments ${names.join(', ')}`))
    }
  }

  @Builder
  private QueueRow(message: NativeQueuedMessage, index: number) {
    Column({ space: 6 }) {
      if (message.sender) {
        Text(message.sender)
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
      }
      Text(this.preview(message))
        .width('100%')
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
        .wordBreak(WordBreak.BREAK_WORD)
        .copyOption(CopyOptions.LocalDevice)
      this.Attachments(message.attachments)
      if (this.canWrite) {
        Row({ space: 6 }) {
          if (message.canSendNow) {
            Button(uiText(this.language, '立即发送', 'Send now'))
              .id(`thread-queue-send-${index}`)
              .height(44)
              .accessibilityText(uiText(this.language, `立即发送第 ${index + 1} 条排队消息`,
                `Send queued message ${index + 1} now`))
              .enabled(!this.busy)
              .onClick(() => this.onSend(message.runId))
          }
          Button(uiText(this.language, '编辑', 'Edit'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .id(`thread-queue-edit-${index}`)
            .height(44)
            .accessibilityText(uiText(this.language, `编辑第 ${index + 1} 条排队消息`, `Edit queued message ${index + 1}`))
            .enabled(!this.busy && !this.editBlocked && message.canEdit)
            .onClick(() => this.beginEdit(message))
          Button(uiText(this.language, '移除', 'Remove'), { buttonStyle: ButtonStyleMode.TEXTUAL, role: ButtonRole.ERROR })
            .id(`thread-queue-remove-${index}`)
            .height(44)
            .accessibilityText(uiText(this.language, `移除第 ${index + 1} 条排队消息`, `Remove queued message ${index + 1}`))
            .enabled(!this.busy)
            .onClick(() => this.onRemove(message.runId))
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, bottom: 12 })
    Divider()
  }

  @Builder
  private Editor() {
    if (this.rowBeingEdited() === undefined) {
      Text(uiText(this.language, '这条消息已离开队列。你可以复制编辑内容。', 'This message is no longer queued. You can copy your edits.'))
        .fontColor($r('sys.color.font_secondary'))
        .fontSize(14)
      Text(this.editText)
        .width('100%')
        .wordBreak(WordBreak.BREAK_WORD)
        .copyOption(CopyOptions.LocalDevice)
    } else {
      TextArea({ text: this.editText, placeholder: uiText(this.language, '排队消息', 'Queued messages') })
        .id('thread-queue-edit-text')
        .width('100%')
        .constraintSize({ minHeight: 96, maxHeight: 192 })
        .accessibilityText(uiText(this.language, '排队消息内容', 'Queued message text'))
        .enterKeyType(EnterKeyType.NEW_LINE)
        .enabled(this.canWrite && !this.busy && !this.saving && !this.editBlocked)
        .onChange((text: string) => { this.editText = text; })
      this.Attachments(this.rowBeingEdited()?.attachments ?? [])
    }
    Row({ space: 8 }) {
      Button(uiText(this.language, '返回队列', 'Back to queue'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .height(44)
        .enabled(!this.saving)
        .onClick(() => this.endEdit())
      if (this.rowBeingEdited() !== undefined && this.canWrite) {
        Button(this.saving ? uiText(this.language, '正在保存…', 'Saving…') : uiText(this.language, '保存', 'Save'))
          .id('thread-queue-save')
          .height(44)
          .enabled(this.canSave())
          .accessibilityText(uiText(this.language, '保存排队消息', 'Save queued message'))
          .onClick(() => { void this.save(); })
      }
    }
  }

  build() {
    Column() {
      Row() {
        Text(this.editingRunId ? uiText(this.language, '编辑排队消息', 'Edit queued message') : uiText(this.language, '排队消息', 'Queued messages'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .fontColor($r('sys.color.font_primary'))
        Button(uiText(this.language, '关闭', 'Close'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('thread-queue-close')
          .height(44)
          .onClick(() => this.onClose())
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })

      Scroll() {
        Column({ space: 8 }) {
          if (this.error) {
            Text(this.error)
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
              .wordBreak(WordBreak.BREAK_WORD)
          }
          if (this.canWrite && this.editBlocked) {
            Text(uiText(this.language, '回答待处理的问题后即可编辑排队消息。', 'Answer the pending question to edit queued messages.'))
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
          }
          if (this.editingRunId) {
            this.Editor()
          } else {
            if (this.held && this.messages.length > 0) {
              Text(uiText(this.language, '队列已暂停', 'Queue paused'))
                .fontSize(14)
                .fontColor($r('sys.color.font_secondary'))
            }
            if (this.messages.length === 0) {
              Text(uiText(this.language, '没有正在排队的消息。', 'No queued messages.'))
                .fontSize(14)
                .fontColor($r('sys.color.font_secondary'))
            }
            ForEach(this.messages, (message: NativeQueuedMessage, index: number) => {
              this.QueueRow(message, index)
            }, (message: NativeQueuedMessage): string => `${message.runId}:${message.revision}`)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
