export type ThreadBackgroundWorkKind = 'subagent' | 'command' | 'monitor' | 'background_task';

export interface ThreadBackgroundWorkTask {
  taskId: string;
  kind: ThreadBackgroundWorkKind;
  description?: string;
  childThreadId?: string;
  awaited?: boolean;
}

const KIND_ORDER: ThreadBackgroundWorkKind[] = ['subagent', 'command', 'monitor', 'background_task'];
const KIND_LABELS: Record<ThreadBackgroundWorkKind, string> = {
  'subagent': '子代理',
  'command': '命令',
  'monitor': '监视器',
  'background_task': '后台任务',
};

function taskLabel(task: ThreadBackgroundWorkTask): string {
  return task.description?.trim() || KIND_LABELS[task.kind];
}

function waitingForTasks(tasks: ThreadBackgroundWorkTask[]): boolean {
  return tasks.some((task: ThreadBackgroundWorkTask) =>
    task.awaited === true || task.kind === 'subagent' || task.kind === 'background_task');
}

function taskSummary(tasks: ThreadBackgroundWorkTask[], waiting: boolean): string {
  const activity = waiting ? '正在等待' : '正在运行';
  if (tasks.length === 1) {
    const task = tasks[0];
    const kind = KIND_LABELS[task.kind];
    const label = taskLabel(task);
    return label === kind ? `${activity}${kind}` : `${activity} · ${label}`;
  }
  const groups: string[] = [];
  for (const kind of KIND_ORDER) {
    const count = tasks.filter((task: ThreadBackgroundWorkTask) => task.kind === kind).length;
    if (count > 0) groups.push(`${count} 个${KIND_LABELS[kind]}`);
  }
  return `${activity} ${groups.join('、')}`;
}

function childThreadId(task: ThreadBackgroundWorkTask): string {
  const child = task.childThreadId ?? '';
  if (task.kind !== 'subagent' || !task.taskId.trim() || !child || child !== child.trim() ||
    /[\x00-\x1f\x7f]/.test(child)) return '';
  return child;
}

@Component
export struct ThreadBackgroundWorkStatus {
  @Prop tasks: ThreadBackgroundWorkTask[] = [];
  @Prop canStop: boolean = false;
  @Prop stopping: boolean = false;
  onOpen: () => void = () => {};
  onStop: () => void = () => {};

  private summary(): string {
    return taskSummary(this.tasks, waitingForTasks(this.tasks));
  }

  build() {
    if (this.tasks.length > 0) {
      Row({ space: 6 }) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 6 }) {
            SymbolGlyph(waitingForTasks(this.tasks) ? $r('sys.symbol.person_head_on_circle') : $r('sys.symbol.code_square'))
              .fontSize(13).fontColor([$r('sys.color.icon_secondary')])
            Text(this.summary()).fontSize(12).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
          }
        }
        .id('thread-background-work-open')
        .height(28)
        .padding(0)
        .flexShrink(1)
        .accessibilityText(this.summary() + '，' + this.tasks.map((task: ThreadBackgroundWorkTask) => taskLabel(task)).join('、'))
        .onClick(() => this.onOpen())
        Text('·').fontSize(12).fontColor($r('sys.color.font_secondary'))
        Button(this.stopping ? '正在停止…' : '停止', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('thread-background-work-stop')
          .height(28)
          .padding({ left: 4, right: 4 })
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .accessibilityText(this.stopping ? '正在停止后台工作' : '停止后台工作')
          .enabled(this.canStop && !this.stopping)
          .onClick(() => this.onStop())
      }
      .width('100%')
      .padding({ left: 4, right: 4, top: 4, bottom: 4 })
      .margin({ bottom: 12 })
    }
  }
}

@Component
export struct ThreadBackgroundWorkSheet {
  @Prop tasks: ThreadBackgroundWorkTask[] = [];
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop openingThreadId: string = '';
  onClose: () => void = () => {};
  onOpenThread: (threadId: string) => void = () => {};
  onRetry?: () => void;

  private orderedTasks(): ThreadBackgroundWorkTask[] {
    return this.tasks.slice().sort((left: ThreadBackgroundWorkTask, right: ThreadBackgroundWorkTask) =>
      KIND_ORDER.indexOf(left.kind) - KIND_ORDER.indexOf(right.kind));
  }

  private taskSymbol(kind: ThreadBackgroundWorkKind): Resource {
    if (kind === 'subagent') return $r('sys.symbol.person_head_on_circle');
    if (kind === 'monitor') return $r('sys.symbol.clock');
    return $r('sys.symbol.code_square');
  }

  @Builder
  private Header() {
    Row({ space: 10 }) {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([$r('sys.color.icon_primary')])
      }
      .id('thread-background-work-close')
      .width(44)
      .height(44)
      .padding(0)
      .accessibilityText('关闭后台工作')
      .onClick(() => this.onClose())
      Text('后台工作').fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
    }.width('100%').height(56).padding({ left: 8, right: 20 })
  }

  @Builder
  private TaskContent(task: ThreadBackgroundWorkTask, target: string) {
    Row({ space: 12 }) {
      SymbolGlyph(this.taskSymbol(task.kind)).fontSize(15).fontColor([$r('sys.color.icon_secondary')])
      Column({ space: 2 }) {
        Text(taskLabel(task)).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          .width('100%').wordBreak(WordBreak.BREAK_WORD)
        Text(KIND_LABELS[task.kind]).fontSize(12).fontColor($r('sys.color.font_secondary'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (target && target === this.openingThreadId) {
        LoadingProgress().width(12).height(12).color($r('sys.color.icon_secondary'))
      } else if (target) {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([$r('sys.color.icon_secondary')])
      }
    }.width('100%').padding({ top: 14, bottom: 14 })
  }

  @Builder
  private TaskRow(task: ThreadBackgroundWorkTask, target: string) {
    if (target) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        this.TaskContent(task, target)
      }
      .id('thread-background-work-row-' + task.taskId)
      .width('100%')
      .padding(0)
      .enabled(!this.openingThreadId)
      .accessibilityText((target === this.openingThreadId ? '正在打开子代理 ' : '打开子代理 ') + taskLabel(task))
      .onClick(() => this.onOpenThread(target))
    } else {
      Column() { this.TaskContent(task, '') }
        .id('thread-background-work-row-' + task.taskId)
        .width('100%')
    }
    Divider().color($r('sys.color.comp_divider'))
  }

  build() {
    Column() {
      this.Header()
      Scroll() {
        Column() {
          if (this.loading) {
            LoadingProgress().id('thread-background-work-loading').width(24).height(24)
              .color($r('sys.color.icon_secondary')).margin({ top: 24, bottom: 12 })
              .accessibilityText('正在加载后台工作')
          } else if (this.error) {
            Text(this.error).id('thread-background-work-error').fontSize(14).fontColor($r('sys.color.font_secondary'))
              .textAlign(TextAlign.Center).margin({ top: 24, bottom: 8 })
            if (this.onRetry) {
              Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL })
                .id('thread-background-work-retry').height(44).onClick(() => this.onRetry?.())
            }
          } else if (this.tasks.length === 0) {
            Text('没有正在后台运行的工作。').id('thread-background-work-empty')
              .fontSize(14).fontColor($r('sys.color.font_secondary')).margin({ top: 24 })
          }
          ForEach(this.orderedTasks(), (task: ThreadBackgroundWorkTask) => this.TaskRow(task, childThreadId(task)),
            (task: ThreadBackgroundWorkTask) => JSON.stringify(task))
        }.width('100%').padding({ left: 20, right: 20, bottom: 24 })
      }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
    }.id('thread-background-work-sheet').width('100%').height('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
