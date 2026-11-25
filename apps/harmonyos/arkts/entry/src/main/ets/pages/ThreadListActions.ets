import {
  availableThreadLifecycleActions, customThreadSnooze, threadSnoozePresets,
} from '../client/ThreadLifecycleProtocol';
import type { ThreadLifecycleAction, ThreadSnoozePreset, ThreadSnoozePresetLabels } from '../client/ThreadLifecycleProtocol';
import type { NativeThread } from '../client/T3Protocol';
import { UiLanguage, uiText } from './UiLanguage';

const ENGLISH_SNOOZE_LABELS: ThreadSnoozePresetLabels = {
  oneHour: 'In 1 hour',
  threeHours: 'In 3 hours',
  thisEvening: 'This evening',
  tomorrow: 'Tomorrow',
  nextMonday: 'Next Monday',
};

@Component
export struct ThreadListActions {
  @Prop thread: NativeThread = { id: '', title: '' };
  @Prop canOperate: boolean = false;
  @Prop busy: boolean = false;
  @Prop error: string = '';
  @Prop language: UiLanguage = 'zh';
  @Prop startWithSnooze: boolean = false;
  @State private panel: 'menu' | 'rename' | 'snooze' = 'menu';
  @State private titleDraft: string = '';
  @State private minutesDraft: string = '';
  @State private presets: ThreadSnoozePreset[] = [];
  @State private confirmingDelete: boolean = false;
  private visible: boolean = false;
  onAction: (action: ThreadLifecycleAction, value?: string) => void = () => {};
  onClose: () => void = () => {};

  aboutToAppear(): void {
    this.visible = true;
    if (this.startWithSnooze) this.choose('snooze');
  }

  aboutToDisappear(): void {
    this.visible = false;
  }

  private copy(chinese: string, english: string): string {
    return uiText(this.language, chinese, english);
  }

  private actionLabel(action: ThreadLifecycleAction): string {
    switch (action) {
      case 'rename': return this.copy('重命名', 'Rename');
      case 'pin': return this.copy('置顶', 'Pin');
      case 'unpin': return this.copy('取消置顶', 'Unpin');
      case 'mark-unread': return this.copy('标为未读', 'Mark unread');
      case 'settle': return this.copy('收尾', 'Settle');
      case 'unsettle': return this.copy('取消收尾', 'Unsettle');
      case 'snooze': return this.copy('暂缓', 'Snooze');
      case 'unsnooze': return this.copy('唤醒会话', 'Unsnooze');
      case 'archive': return this.copy('归档', 'Archive');
      case 'unarchive': return this.copy('取消归档', 'Unarchive');
      case 'delete': return this.copy('删除', 'Delete');
    }
  }

  private panelTitle(): string {
    if (this.panel === 'rename') return this.copy('重命名会话', 'Rename chat');
    if (this.panel === 'snooze') return this.copy('暂缓会话', 'Snooze chat');
    return this.copy('会话操作', 'Chat actions');
  }

  private snoozePresets(now: Date): ThreadSnoozePreset[] {
    return threadSnoozePresets(now, this.language === 'en' ? ENGLISH_SNOOZE_LABELS : undefined);
  }

  private canChoose(action: ThreadLifecycleAction): boolean {
    return this.visible && !this.busy &&
      availableThreadLifecycleActions(this.thread, this.canOperate, Date.now()).includes(action);
  }

  private async confirmDelete(): Promise<void> {
    if (this.confirmingDelete) return;
    this.confirmingDelete = true;
    const thread = this.thread;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: this.copy('删除会话？', 'Delete chat?'),
        message: this.copy(`将永久删除“${thread.title}”及其终端历史。`,
          `This will permanently delete “${thread.title}” and its terminal history.`),
        buttons: [
          { text: this.copy('取消', 'Cancel'), color: $r('sys.color.font_secondary') },
          { text: this.actionLabel('delete'), color: '#c8353c' },
        ],
      });
      if (result.index === 1 && this.thread === thread && this.canChoose('delete')) this.onAction('delete');
    } catch (_) {
    } finally {
      this.confirmingDelete = false;
    }
  }

  private choose(action: ThreadLifecycleAction): void {
    if (!this.canChoose(action)) return;
    if (action === 'delete') {
      void this.confirmDelete();
    } else if (action === 'rename') {
      this.titleDraft = this.thread.title;
      this.panel = 'rename';
    } else if (action === 'snooze') {
      this.minutesDraft = '';
      this.presets = this.snoozePresets(new Date());
      this.panel = 'snooze';
    } else {
      this.onAction(action);
    }
  }

  private submitRename(): void {
    const title = this.titleDraft.trim();
    if (!title || !this.canChoose('rename')) return;
    if (title === this.thread.title) {
      this.onClose();
    } else {
      this.onAction('rename', title);
    }
  }

  private submitSnooze(wakeAt?: string, minutes?: string): void {
    if (!this.canChoose('snooze')) return;
    const now = Date.now();
    const wake = minutes === undefined ? wakeAt : customThreadSnooze(minutes, now);
    if (wake && Date.parse(wake) > now) {
      this.onAction('snooze', wake);
    } else {
      this.presets = this.snoozePresets(new Date(now));
      if (wakeAt) {
        try {
          this.getUIContext().getPromptAction().showToast({
            message: this.copy('该暂缓时间已过，请选择其他时间。', 'That snooze time has passed. Choose another time.'),
          });
        } catch (_) {}
      }
    }
  }

  @Builder
  private ActionButton(action: ThreadLifecycleAction) {
    Button(this.actionLabel(action), { buttonStyle: ButtonStyleMode.TEXTUAL,
      role: action === 'delete' ? ButtonRole.ERROR : ButtonRole.NORMAL })
      .id('thread-lifecycle-' + action)
      .width('100%')
      .constraintSize({ minHeight: 48 })
      .enabled(!this.busy && !this.confirmingDelete)
      .onClick(() => this.choose(action))
  }

  @Builder
  private RenameForm() {
    TextInput({ text: this.titleDraft, placeholder: this.copy('会话标题', 'Chat title') })
      .id('thread-lifecycle-title')
      .accessibilityText(this.copy('会话标题', 'Chat title'))
      .width('100%')
      .enabled(!this.busy)
      .onChange((title: string) => { this.titleDraft = title; })
      .onSubmit(() => this.submitRename())
    Button(this.copy('保存名称', 'Save name'))
      .id('thread-lifecycle-save-title')
      .width('100%')
      .height(48)
      .enabled(!this.busy && this.titleDraft.trim().length > 0)
      .onClick(() => this.submitRename())
  }

  @Builder
  private SnoozeForm() {
    ForEach(this.presets, (preset: ThreadSnoozePreset) => {
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 12 }) {
          Text(preset.label)
            .layoutWeight(1)
            .fontSize(15)
          Text(new Date(preset.wakeAt).toLocaleString(this.language === 'zh' ? 'zh-CN' : 'en-US'))
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
      }
      .width('100%')
      .constraintSize({ minHeight: 48 })
      .enabled(!this.busy)
      .onClick(() => this.submitSnooze(preset.wakeAt, preset.minutes?.toString()))
    }, (preset: ThreadSnoozePreset) => preset.wakeAt)
    TextInput({ text: this.minutesDraft, placeholder: this.copy('自定义分钟数', 'Custom minutes') })
      .id('thread-lifecycle-snooze-minutes')
      .accessibilityText(this.copy('自定义分钟数', 'Custom minutes'))
      .type(InputType.Number)
      .width('100%')
      .enabled(!this.busy)
      .onChange((value: string) => { this.minutesDraft = value; })
      .onSubmit(() => this.submitSnooze(undefined, this.minutesDraft))
    Button(this.actionLabel('snooze'))
      .id('thread-lifecycle-save-snooze')
      .width('100%')
      .height(48)
      .enabled(!this.busy && !!customThreadSnooze(this.minutesDraft, Date.now()))
      .onClick(() => this.submitSnooze(undefined, this.minutesDraft))
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Button(this.copy('返回', 'Back'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('thread-lifecycle-back')
          .height(44)
          .enabled(!this.busy && !this.confirmingDelete)
          .onClick(() => {
            if (this.panel === 'menu') this.onClose();
            else this.panel = 'menu';
          })
        Text(this.panelTitle())
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        if (this.busy) {
          LoadingProgress().width(24).height(24).accessibilityText(this.copy('正在更新会话', 'Updating chat'))
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 16 })

      Scroll() {
        Column({ space: 8 }) {
          Text(this.thread.title)
            .width('100%')
            .fontSize(15)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.error) {
            Text(this.error)
              .width('100%')
              .fontSize(15)
              .fontColor('#c8353c')
          }
          if (!this.canOperate) {
            Text(this.copy('此连接仅可查看会话。', 'This connection has read-only access to chats.'))
              .width('100%').fontSize(15)
          } else if (this.panel === 'rename') {
            this.RenameForm()
          } else if (this.panel === 'snooze') {
            this.SnoozeForm()
          } else {
            ForEach(availableThreadLifecycleActions(this.thread, this.canOperate, Date.now()),
              (action: ThreadLifecycleAction) => {
                this.ActionButton(action)
              }, (action: ThreadLifecycleAction) => action)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
