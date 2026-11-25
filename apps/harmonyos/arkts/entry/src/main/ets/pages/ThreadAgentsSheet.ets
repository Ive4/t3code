export type ThreadAgentStatus = 'pending' | 'running' | 'waiting' | 'idle' | 'completed' | 'failed' |
  'cancelled' | 'interrupted';

export interface ThreadAgentSheetRow {
  id: string;
  title: string;
  status: ThreadAgentStatus;
  description?: string;
  elapsedText?: string;
  metadata?: string;
  canOpen: boolean;
  canStop: boolean;
}

@Component
export struct ThreadAgentsSheet {
  @Prop rows: ThreadAgentSheetRow[] = [];
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop openingId: string = '';
  @Prop stoppingId: string = '';
  @State private confirmingStopId: string = '';
  onClose: () => void = () => {};
  onOpen: (id: string) => void = () => {};
  onStop?: (id: string) => void;
  onRetry?: () => void;

  aboutToDisappear(): void {
    this.confirmingStopId = '';
  }

  private statusLabel(status: ThreadAgentStatus): string {
    switch (status) {
      case 'pending':
      case 'running': return '运行中';
      case 'waiting': return '等待中';
      case 'idle': return '空闲';
      case 'completed': return '已完成';
      case 'failed': return '失败';
      case 'cancelled': return '已取消';
      case 'interrupted': return '已中断';
    }
  }

  private statusColor(status: ThreadAgentStatus): ResourceColor {
    switch (status) {
      case 'completed': return '#26815D';
      case 'failed': return '#C8353C';
      case 'cancelled':
      case 'interrupted': return $r('sys.color.font_secondary');
      default: return $r('sys.color.font_emphasize');
    }
  }

  private rowAccessibility(row: ThreadAgentSheetRow): string {
    const action = this.openingId === row.id ? '正在打开子代理会话' : '打开子代理会话';
    return [action, row.title, this.statusLabel(row.status), row.elapsedText ?? '', row.metadata ?? '',
      row.description ?? ''].filter((part: string) => part.length > 0).join('，');
  }

  private async confirmStop(row: ThreadAgentSheetRow): Promise<void> {
    if (!row.canStop || !this.onStop || this.confirmingStopId || this.stoppingId || this.openingId) return;
    this.confirmingStopId = row.id;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '停止子代理？',
        message: `停止 ${row.title}？`,
        buttons: [
          { text: '取消', color: $r('sys.color.font_primary') },
          { text: '停止', color: '#C8353C' },
        ],
      });
      if (result.index === 1 && this.confirmingStopId === row.id && !this.stoppingId && !this.openingId &&
        this.rows.some((candidate: ThreadAgentSheetRow) => candidate.id === row.id && candidate.canStop)) {
        this.onStop?.(row.id);
      }
    } catch (_) {
    } finally {
      if (this.confirmingStopId === row.id) this.confirmingStopId = '';
    }
  }

  @Builder
  private Header() {
    Row({ space: 10 }) {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([$r('sys.color.icon_primary')])
      }
      .id('thread-agents-close')
      .width(44)
      .height(44)
      .padding(0)
      .accessibilityText('关闭子代理')
      .onClick(() => this.onClose())
      Text('子代理').fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
    }.height(56).width('100%').padding({ left: 8, right: 20 })
  }

  @Builder
  private AgentContent(row: ThreadAgentSheetRow) {
    Row({ space: 12 }) {
      Row() {
        Circle().width(8).height(8).fill(this.statusColor(row.status))
      }.height(20)
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Row({ space: 6 }) {
            Text(row.title).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
            Text('·').fontSize(12).fontColor($r('sys.color.font_secondary')).flexShrink(0)
            Text(this.statusLabel(row.status)).fontSize(12).fontWeight(FontWeight.Medium)
              .fontColor(this.statusColor(row.status)).flexShrink(0)
          }.layoutWeight(1)
          if (row.elapsedText) {
            Text(row.elapsedText).fontSize(12).fontColor($r('sys.color.font_secondary')).flexShrink(0)
          }
          if (this.openingId === row.id) {
            LoadingProgress().width(12).height(12).color($r('sys.color.icon_secondary'))
          } else if (row.canOpen) {
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([$r('sys.color.icon_secondary')])
          }
        }.constraintSize({ minHeight: 20 }).width('100%')
        if (row.metadata) {
          Text(row.metadata).fontSize(12).fontColor($r('sys.color.font_secondary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (row.description) {
          Text(row.description).fontSize(12).fontColor(row.status === 'failed' ? this.statusColor(row.status) :
            $r('sys.color.font_secondary')).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 14, bottom: 14 })
  }

  @Builder
  private StopButton(row: ThreadAgentSheetRow) {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL, role: ButtonRole.ERROR }) {
      if (this.stoppingId === row.id) {
        LoadingProgress().width(14).height(14).color(this.statusColor('failed'))
      } else {
        Row().width(10).height(10).borderRadius(1).backgroundColor(this.statusColor('failed'))
      }
    }
    .id('thread-agents-stop-' + row.id)
    .width(44)
    .height(44)
    .padding(0)
    .accessibilityText((this.stoppingId === row.id ? '正在停止子代理 ' : '停止子代理 ') + row.title)
    .enabled(!this.stoppingId && !this.confirmingStopId && !this.openingId)
    .onClick(() => { void this.confirmStop(row); })
  }

  @Builder
  private AgentRow(row: ThreadAgentSheetRow) {
    Row() {
      if (row.canOpen) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          this.AgentContent(row)
        }
        .id('thread-agents-row-' + row.id)
        .layoutWeight(1)
        .padding(0)
        .accessibilityText(this.rowAccessibility(row))
        .enabled(!this.openingId && !this.confirmingStopId)
        .onClick(() => this.onOpen(row.id))
      } else {
        Column() { this.AgentContent(row) }
          .id('thread-agents-row-' + row.id)
          .layoutWeight(1)
      }
      if (row.canStop && this.onStop) this.StopButton(row)
    }.width('100%')
    Divider().color($r('sys.color.comp_divider'))
  }

  build() {
    Column() {
      this.Header()
      Scroll() {
        Column() {
          if (this.loading) {
            LoadingProgress().id('thread-agents-loading').width(24).height(24)
              .color($r('sys.color.icon_secondary')).margin({ top: 24, bottom: 12 })
              .accessibilityText('正在加载子代理')
          } else if (this.error) {
            Text(this.error).id('thread-agents-error').fontSize(14).fontColor($r('sys.color.font_secondary'))
              .textAlign(TextAlign.Center).margin({ top: 24, bottom: 8 })
            if (this.onRetry) {
              Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL }).id('thread-agents-retry').height(44)
                .onClick(() => this.onRetry?.())
            }
          } else if (this.rows.length === 0) {
            Text('本轮没有子代理。').id('thread-agents-empty').fontSize(14)
              .fontColor($r('sys.color.font_secondary')).margin({ top: 24 })
          }
          ForEach(this.rows, (row: ThreadAgentSheetRow) => this.AgentRow(row),
            (row: ThreadAgentSheetRow) => JSON.stringify(row))
        }.width('100%').padding({ left: 20, right: 20, bottom: 24 })
      }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
    }.id('thread-agents-sheet').width('100%').height('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
