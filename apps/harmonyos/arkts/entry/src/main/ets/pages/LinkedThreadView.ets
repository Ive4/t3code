import type { NativeThreadWork } from '../client/ThreadDetailProtocol';
import type { NativeMessage } from '../client/T3Protocol';
import { ThreadWorkRow } from './ThreadMessageRow';

@Component
struct LinkedThreadWorkRow {
  @Prop item: NativeThreadWork = { id: '', threadId: '', type: '', wantsOutput: false, title: '', detail: '', status: '',
    timestamp: '' };
  readOutput: (item: NativeThreadWork) => Promise<string> = () => Promise.resolve('');
  @State private expanded: boolean = false;
  @State private loading: boolean = false;
  @State private error: string = '';
  @State private output: string | undefined = undefined;
  private request: number = 0;

  aboutToDisappear(): void {
    this.request++;
  }

  private async loadOutput(): Promise<void> {
    if (this.loading || !this.item.wantsOutput) return;
    const id = ++this.request;
    this.loading = true;
    this.error = '';
    try {
      const output = await this.readOutput(this.item);
      if (this.request === id) this.output = output || '没有命令输出';
    } catch (_) {
      if (this.request === id) this.error = '无法读取命令输出';
    } finally {
      if (this.request === id) this.loading = false;
    }
  }

  build() {
    Column() {
      ThreadWorkRow({
        rowId: this.item.id,
        title: this.item.title,
        status: this.item.status,
        detail: this.output ?? this.item.detail,
        loading: this.loading,
        expandable: this.item.wantsOutput,
        expanded: this.expanded,
        onToggle: () => {
          this.expanded = !this.expanded;
          if (this.expanded && this.output === undefined) void this.loadOutput();
        },
      })
      if (this.expanded && this.error) {
        Row({ space: 8 }) {
          Text(this.error).fontSize(12).fontColor($r('sys.color.font_secondary'))
          Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('linked-thread-retry-work-' + this.item.id)
            .onClick(() => { void this.loadOutput(); })
        }.width('100%').padding({ left: 30 })
      }
    }.width('100%')
  }
}

@Component
export struct LinkedThreadView {
  @Prop title: string = '';
  @Prop label: string = '';
  @Prop via: string = '';
  @Prop loading: boolean = false;
  @Prop working: boolean = false;
  @Prop connecting: boolean = false;
  @Prop connectionError: string = '';
  @Prop error: string = '';
  @Prop hasHistory: boolean = false;
  @Prop historyLoading: boolean = false;
  @Prop historyError: string = '';
  @Prop messages: NativeMessage[] = [];
  @Prop work: NativeThreadWork[] = [];
  onClose: () => void = () => {};
  onMaximize?: () => void = undefined;
  onRetry: () => void = () => {};
  onConnect: () => void = () => {};
  onLoadEarlier: () => void = () => {};
  onReadOutput: (item: NativeThreadWork) => Promise<string> = () => Promise.resolve('');

  @Builder
  private Header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([$r('sys.color.icon_primary')])
      }
      .id('linked-thread-close').accessibilityText('关闭关联会话')
      .width(44).height(44).backgroundColor(Color.Transparent).onClick(() => this.onClose())
      Text(this.title || '关联会话').fontSize(18).fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.onMaximize) {
        Button('最大化', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('linked-thread-maximize').onClick(() => this.onMaximize?.())
      }
    }
    .height(56).width('100%').padding({ left: 4, right: 16 })
  }

  @Builder
  private ErrorCard() {
    Column({ space: 6 }) {
      Text(this.error).fontSize(14).fontColor($r('sys.color.font_primary'))
      if (this.messages.length > 0 || this.work.length > 0) {
        Text('显示上次读取的内容').fontSize(13).fontColor($r('sys.color.font_secondary'))
      }
      Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL }).id('linked-thread-retry').onClick(() => this.onRetry())
    }
    .alignItems(HorizontalAlign.Start).width('100%').padding(12).borderRadius(12)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
  }

  @Builder
  private Message(message: NativeMessage) {
    Row() {
      Text(message.text)
        .fontSize(14).lineHeight(21).fontColor($r('sys.color.font_primary'))
        .copyOption(CopyOptions.LocalDevice).wordBreak(WordBreak.BREAK_WORD)
        .padding(message.role === 'user' ? { left: 14, right: 14, top: 10, bottom: 10 } : 0)
        .constraintSize({ maxWidth: message.role === 'user' ? '88%' : '100%' })
        .backgroundColor(message.role === 'user' ? $r('sys.color.comp_background_tertiary') : Color.Transparent)
        .borderRadius(16)
    }
    .width('100%').justifyContent(message.role === 'user' ? FlexAlign.End : FlexAlign.Start)
  }

  build() {
    Column() {
      this.Header()
      List({ space: 12 }) {
        if (this.hasHistory) {
          ListItem() {
            Column({ space: 4 }) {
              Row({ space: 6 }) {
                if (this.historyLoading) LoadingProgress().width(16).height(16)
                Button('加载较早的内容', { buttonStyle: ButtonStyleMode.TEXTUAL })
                  .id('linked-thread-load-earlier')
                  .enabled(!this.historyLoading)
                  .onClick(() => this.onLoadEarlier())
              }
              if (this.historyError) {
                Text(this.historyError).fontSize(12).fontColor($r('sys.color.font_secondary'))
                  .textAlign(TextAlign.Center)
              }
            }.width('100%')
          }
        }
        if (this.loading && this.messages.length === 0 && this.work.length === 0) {
          ListItem() {
            Row({ space: 8 }) {
              LoadingProgress().width(18).height(18)
              Text('正在从 ' + this.label + ' 读取会话…').fontSize(14).fontColor($r('sys.color.font_secondary'))
            }.width('100%').padding({ top: 12 })
          }
        }
        if (!this.loading && !this.error && this.messages.length === 0 && this.work.length === 0) {
          ListItem() {
            Text('此会话暂无内容').fontSize(14).fontColor($r('sys.color.font_secondary'))
          }
        }
        ForEach(this.messages, (message: NativeMessage) => {
          if (message.text.trim()) {
            ListItem() { this.Message(message) }
          }
        }, (message: NativeMessage) => message.id)
        ForEach(this.work, (item: NativeThreadWork) => {
          ListItem() {
            LinkedThreadWorkRow({ item, readOutput: (row: NativeThreadWork) => this.onReadOutput(row) })
          }
        }, (item: NativeThreadWork) => item.id)
        if (this.error) {
          ListItem() { this.ErrorCard() }
        }
      }
      .id('linked-thread-feed').layoutWeight(1).width('100%').padding({ left: 20, right: 20, top: 12, bottom: 12 })
      .maintainVisibleContentPosition(true)
      Column({ space: 6 }) {
        if (this.connectionError) {
          Text(this.connectionError).fontSize(12).fontColor($r('sys.color.font_secondary'))
        }
        Row({ space: 8 }) {
          Column({ space: 3 }) {
            Text('只读').fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary'))
            Text(this.label + ' · 经由 ' + this.via + (this.working ? ' · 运行中' : ''))
              .fontSize(12).fontColor($r('sys.color.font_secondary')).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.connecting) LoadingProgress().width(16).height(16)
          Button(this.connecting ? '正在连接…' : '连接以交互', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('linked-thread-connect').enabled(!this.connecting).onClick(() => this.onConnect())
        }.width('100%')
      }
      .id('linked-thread-read-only').width('100%').alignItems(HorizontalAlign.Start).padding(14)
      .backgroundColor($r('sys.color.comp_background_tertiary')).borderRadius(16)
      .margin({ left: 12, right: 12, top: 6, bottom: 12 })
    }
    .width('100%').height('100%').backgroundColor($r('sys.color.background_primary'))
  }
}
