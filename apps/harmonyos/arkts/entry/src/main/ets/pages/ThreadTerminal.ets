import { webview } from '@kit.ArkWeb';
import pasteboard from '@ohos.pasteboard';
import { readThreadTerminalMessage, THREAD_TERMINAL_CONTEXT_MAX_CHARS, ThreadTerminalAttachment,
  threadTerminalCaptureLines, ThreadTerminalOutput, ThreadTerminalOutputCursor,
  threadTerminalSelectionText } from './ThreadTerminalOutput';

export { ThreadTerminalOutput } from './ThreadTerminalOutput';

export interface ThreadTerminalSession {
  terminalId: string;
  label: string;
  cwd: string;
  status: string;
  hasRunningSubprocess?: boolean;
}

interface TerminalKey {
  label: string;
  key: string;
  code?: string;
  ctrlKey?: boolean;
}

interface TerminalConfiguration {
  arktsBridge: boolean;
  epoch: number;
  appearanceScheme: string;
  backgroundColor: string;
  foregroundColor: string;
  cursor: string;
  palette: string[];
  fontSize: number;
  sharedGrid: number[];
  readOnly: boolean;
  copyLabel: string;
  selectAllLabel: string;
}

interface TerminalCommand {
  type: string;
  config?: TerminalConfiguration;
  id?: number;
  data?: string;
  reset?: boolean;
  replay?: boolean;
  key?: string;
  code?: string;
  ctrlKey?: boolean;
}

const TERMINAL_BACKGROUND = '#0a0a0a';
const TERMINAL_FOREGROUND = '#dedee1';
const TERMINAL_PALETTE = [
  '#141415', '#ff464d', '#2dd461', '#ffce32', '#339fff', '#d142e4', '#27c8f0', '#c6c6c8',
  '#7d7d84', '#ff464d', '#2dd461', '#ffce32', '#339fff', '#d142e4', '#27c8f0', '#f2f2f3',
];
const TERMINAL_KEYS: TerminalKey[] = [
  { label: '↑', key: 'ArrowUp' },
  { label: '↓', key: 'ArrowDown' },
  { label: '←', key: 'ArrowLeft' },
  { label: '→', key: 'ArrowRight' },
  { label: 'Esc', key: 'Escape' },
  { label: 'Tab', key: 'Tab' },
  { label: 'Ctrl+C', key: 'c', code: 'KeyC', ctrlKey: true },
  { label: 'Ctrl+D', key: 'd', code: 'KeyD', ctrlKey: true },
];
const RENDERER_TIMEOUT_MS = 12000;
const RENDERER_FAILURE = '终端渲染器未响应';

class ThreadTerminalBridge {
  private receive: (data: string) => void;

  constructor(receive: (data: string) => void) {
    this.receive = receive;
  }

  postMessage(data: string): void {
    if (typeof data === 'string') this.receive(data);
  }
}

@Component
export struct ThreadTerminal {
  @Prop threadTitle: string = '';
  @Prop cwd: string = '';
  @Prop @Watch('terminalChanged') terminalId: string = '';
  @Prop sessions: ThreadTerminalSession[] = [];
  @Prop @Watch('updateConfiguration') status: string = '';
  @Prop @Watch('updateConfiguration') cols: number = 0;
  @Prop @Watch('updateConfiguration') rows: number = 0;
  @Prop @Watch('loadingChanged') loading: boolean = false;
  @Prop error: string = '';
  @Prop @Watch('updateConfiguration') readOnly: boolean = false;
  @Prop @Watch('attachPermissionChanged') canAttachOutput: boolean = false;
  output: ThreadTerminalOutput = new ThreadTerminalOutput();
  onBack: () => void = () => {};
  onRetry: () => void = () => {};
  onNewSession: () => void = () => {};
  onSelectSession: (id: string) => void = () => {};
  onCloseSession: () => void = () => {};
  onClear: () => void = () => {};
  onAttachOutput: (selection: ThreadTerminalAttachment) => boolean = () => false;
  onInput: (data: string, reply: boolean) => void = () => {};
  onResize: (cols: number, rows: number) => void = () => {};
  @State private surfaceReady: boolean = false;
  @State private surfaceError: string = '';
  @State private fontSize: number = 13;
  @State private showCapture: boolean = false;
  @State private captureLines: string[] = [];
  @State private captureStart: number = 1;
  @State private captureEnd: number = 1;
  @State private capturedText: string = '';
  private captureSequence: number = 0;
  private captureRequest: number = 0;
  private captureAnchor: number = 0;
  private captureLabel: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: ThreadTerminalBridge = new ThreadTerminalBridge((data: string) => this.receive(data));
  private stopOutput?: () => void;
  private renderCursor?: ThreadTerminalOutputCursor;
  private pendingCursor?: ThreadTerminalOutputCursor;
  private renderTimer: number = -1;
  private timeout: number = -1;
  private commandId: number = 0;
  private epoch: number = 0;
  private pageLoaded: boolean = false;
  private active: boolean = false;
  private measuredCols: number = 0;
  private measuredRows: number = 0;
  private sentCols: number = 0;
  private sentRows: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.stopOutput = this.output.subscribe(() => this.scheduleRender());
    this.startRendererTimeout();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.stopOutput?.();
    this.clearRendererTimeout();
    this.cancelRender();
  }

  private terminalChanged(): void {
    this.epoch++;
    this.dismissCapture();
    this.sentCols = 0;
    this.sentRows = 0;
    this.updateConfiguration();
  }

  private loadingChanged(): void {
    if (this.loading) this.dismissCapture();
    this.updateConfiguration();
  }

  private attachPermissionChanged(): void {
    if (!this.canAttachOutput) this.dismissCapture();
  }

  private canSend(): boolean {
    return !this.readOnly && !this.loading && this.status === 'running';
  }

  private canCapture(): boolean {
    return this.canAttachOutput && this.surfaceReady && !this.loading && !!this.terminalId;
  }

  private scheduleRender(): void {
    if (!this.surfaceReady || this.pendingCursor || this.renderTimer >= 0) return;
    this.renderTimer = setTimeout(() => {
      this.renderTimer = -1;
      const frame = this.output.read(this.renderCursor);
      if (!frame) return;
      this.pendingCursor = frame.cursor;
      this.startRendererTimeout();
      this.command({
        type: 'write', id: ++this.commandId, data: frame.data, reset: frame.reset, replay: frame.replay,
      });
    }, 16);
  }

  private cancelRender(): void {
    if (this.renderTimer >= 0) clearTimeout(this.renderTimer);
    this.renderTimer = -1;
    this.pendingCursor = undefined;
  }

  private startRendererTimeout(): void {
    this.clearRendererTimeout();
    this.timeout = setTimeout(() => this.rendererFailed(), RENDERER_TIMEOUT_MS);
  }

  private clearRendererTimeout(): void {
    if (this.timeout >= 0) clearTimeout(this.timeout);
    this.timeout = -1;
  }

  private rendererFailed(): void {
    if (!this.active) return;
    this.clearRendererTimeout();
    this.cancelRender();
    this.dismissCapture();
    this.pageLoaded = false;
    this.surfaceReady = false;
    this.surfaceError = RENDERER_FAILURE;
  }

  private retryRenderer(): void {
    this.epoch++;
    this.controller = new webview.WebviewController();
    this.renderCursor = undefined;
    this.surfaceError = '';
    this.startRendererTimeout();
  }

  private command(command: TerminalCommand): void {
    const controller = this.controller;
    try {
      controller.runJavaScript('void window.terminalCommand(' + JSON.stringify(command) + ')').catch(() => {
        if (controller === this.controller) this.rendererFailed();
      });
    } catch (_) {
      if (controller === this.controller) this.rendererFailed();
    }
  }

  private configure(): void {
    this.command({
      type: 'configure',
      config: {
        arktsBridge: true, epoch: this.epoch, appearanceScheme: 'dark',
        backgroundColor: TERMINAL_BACKGROUND, foregroundColor: TERMINAL_FOREGROUND,
        cursor: '#339fff', palette: TERMINAL_PALETTE, fontSize: this.fontSize,
        sharedGrid: [this.cols, this.rows], readOnly: !this.canSend(),
        copyLabel: '复制', selectAllLabel: '全选',
      },
    });
  }

  private updateConfiguration(): void {
    if (this.surfaceReady) this.configure();
    this.reportSize();
  }

  private reportSize(): void {
    if (!this.surfaceReady || !this.canSend() || !this.measuredCols || !this.measuredRows ||
      (this.sentCols === this.measuredCols && this.sentRows === this.measuredRows)) return;
    this.sentCols = this.measuredCols;
    this.sentRows = this.measuredRows;
    this.onResize(this.sentCols, this.sentRows);
  }

  private receive(serialized: string): void {
    if (!this.active || !this.pageLoaded) return;
    const message = readThreadTerminalMessage(serialized);
    if (!message) return;
    if (message.type === 'failed') {
      this.rendererFailed();
    } else if (message.type === 'ready') {
      this.clearRendererTimeout();
      this.surfaceReady = true;
      this.updateConfiguration();
      this.scheduleRender();
    } else if (message.type === 'written' && this.pendingCursor && message.id === this.commandId) {
      this.clearRendererTimeout();
      this.renderCursor = this.pendingCursor;
      this.pendingCursor = undefined;
      this.scheduleRender();
    } else if (message.epoch === this.epoch) {
      if (message.type === 'resize') {
        this.measuredCols = message.cols ?? 0;
        this.measuredRows = message.rows ?? 0;
        this.reportSize();
      } else if (message.type === 'input' && this.canSend() && message.data) {
        this.onInput(message.data, message.reply === true);
      } else if (message.type === 'paste' && message.data) {
        this.requestPaste(message.data);
      } else if (message.type === 'copy' && message.data) {
        this.copy(message.data);
      } else if (message.type === 'capture' && this.captureRequest === message.id) {
        this.captureRequest = 0;
        this.showTerminalCapture(message.data ?? '');
      }
    }
  }

  private async copy(text: string): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
    } catch (_) {
      if (this.active) this.getUIContext().getPromptAction().showToast({ message: '无法复制终端输出' });
    }
  }

  private async paste(): Promise<void> {
    const epoch = this.epoch;
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      if (this.active && this.epoch === epoch) this.requestPaste(data.getPrimaryText());
    } catch (_) {
      if (this.active) this.getUIContext().getPromptAction().showToast({ message: '无法读取剪贴板' });
    }
  }

  private showKeyboard(): void {
    try {
      this.controller.requestFocus();
      this.command({ type: 'focus' });
    } catch (_) {}
  }

  private async requestPaste(data: string): Promise<void> {
    if (!data || !this.surfaceReady || !this.canSend()) return;
    const epoch = this.epoch;
    if (/[\r\n]/.test(data)) {
      try {
        const result = await this.getUIContext().getPromptAction().showDialog({
          title: '粘贴多行文本',
          message: '这些内容可能会直接在终端中执行。',
          buttons: [{ text: '取消', color: '#5070a1' }, { text: '粘贴', color: '#5070a1' }],
        });
        if (result.index !== 1) return;
      } catch (_) {
        return;
      }
    }
    if (this.active && this.epoch === epoch && this.surfaceReady && this.canSend()) {
      this.command({ type: 'paste', data });
    }
  }

  private async confirmClose(): Promise<void> {
    const epoch = this.epoch;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '结束终端？',
        message: '终端内正在运行的进程会停止。',
        buttons: [{ text: '取消', color: '#5070a1' }, { text: '结束', color: '#c8353c' }],
      });
      if (this.active && this.epoch === epoch && !this.readOnly && result.index === 1) this.onCloseSession();
    } catch (_) {}
  }

  private statusText(status: string, hasRunningSubprocess: boolean = false): string {
    switch (status) {
      case 'starting': return '正在启动';
      case 'running': return hasRunningSubprocess ? '任务运行中' : '就绪';
      case 'exited': return '已退出';
      case 'error': return '终端出错';
      case 'closed': return '已结束';
      default: return '未启动';
    }
  }

  private selectedBusy(): boolean {
    return this.sessions.some((session: ThreadTerminalSession) =>
      session.terminalId === this.terminalId && session.hasRunningSubprocess === true);
  }

  private sessionLabel(session: ThreadTerminalSession): string {
    return session.label || (session.terminalId === 'default' ? '默认终端' : session.terminalId);
  }

  private captureOutput(): void {
    if (!this.canCapture()) return;
    if (!this.output.isSnapshotRendered(this.renderCursor)) {
      this.captureNotice('终端输出正在加载，请稍后重试。');
      return;
    }
    this.captureRequest = ++this.captureSequence;
    this.command({ type: 'capture', id: this.captureRequest });
  }

  private showTerminalCapture(text: string): void {
    if (!this.canCapture() || !this.output.isSnapshotRendered(this.renderCursor)) return;
    if (!text.trim()) {
      this.captureNotice('没有可附加的可见终端输出。');
      return;
    }
    const lines = threadTerminalCaptureLines(text);
    if (!lines) {
      this.captureNotice('可见输出过多，请放大字号后重试。');
      return;
    }
    const session = this.sessions.find((entry: ThreadTerminalSession) => entry.terminalId === this.terminalId);
    this.captureLabel = session ? this.sessionLabel(session) : this.terminalId;
    this.captureLines = lines;
    this.captureAnchor = 0;
    this.setCaptureRange(1, lines.length);
    this.showCapture = true;
  }

  private captureNotice(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (_) {}
  }

  private setCaptureRange(start: number, end: number): void {
    this.captureStart = start;
    this.captureEnd = end;
    this.capturedText = threadTerminalSelectionText(this.captureLines, start, end);
  }

  private selectCaptureLine(line: number): void {
    if (this.captureAnchor === 0) {
      this.captureAnchor = line;
      this.setCaptureRange(line, line);
    } else {
      this.setCaptureRange(Math.min(this.captureAnchor, line), Math.max(this.captureAnchor, line));
      this.captureAnchor = 0;
    }
  }

  private isCaptureLineSelected(line: number): boolean {
    return line >= this.captureStart && line <= this.captureEnd;
  }

  private attachCapture(): void {
    if (!this.canCapture() || !this.showCapture || !this.capturedText.trim() ||
      this.capturedText.length > THREAD_TERMINAL_CONTEXT_MAX_CHARS) return;
    if (this.onAttachOutput({ terminalId: this.terminalId, terminalLabel: this.captureLabel,
      lineStart: this.captureStart, lineEnd: this.captureEnd, text: this.capturedText })) {
      this.dismissCapture();
    } else {
      this.captureNotice('无法附加选中的输出。请检查草稿的长度或上下文数量。');
    }
  }

  private dismissCapture(): void {
    this.captureRequest = 0;
    this.showCapture = false;
    this.captureLines = [];
    this.capturedText = '';
  }

  private changeFont(delta: number): void {
    this.fontSize = Math.min(24, Math.max(9, this.fontSize + delta));
    this.updateConfiguration();
  }

  @Builder
  private SessionMenu() {
    Menu() {
      ForEach(this.sessions, (session: ThreadTerminalSession) => {
        MenuItem({ content: this.sessionLabel(session), labelInfo: this.statusText(
          session.status, session.hasRunningSubprocess === true) })
          .selected(session.terminalId === this.terminalId)
          .onClick(() => this.onSelectSession(session.terminalId))
      }, (session: ThreadTerminalSession) => session.terminalId)
      if (!this.readOnly) {
        MenuItem({ content: '新建终端' }).onClick(() => this.onNewSession())
      }
      MenuItem({ content: '缩小终端字号' }).enabled(this.fontSize > 9).onClick(() => this.changeFont(-1))
      MenuItem({ content: '放大终端字号' }).enabled(this.fontSize < 24).onClick(() => this.changeFont(1))
    }
  }

  @Builder
  private Header() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.arrow_left')).fontSize(22).fontColor([$r('sys.color.icon_primary')])
      }
      .id('thread-terminal-back')
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .accessibilityText('返回任务')
      .onClick(() => this.onBack())

      Column({ space: 2 }) {
        Text('终端').fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
        if (this.threadTitle) {
          Text(this.threadTitle).fontSize(12).fontColor($r('sys.color.font_secondary')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)

      Button('会话')
        .id('thread-terminal-sessions')
        .controlSize(ControlSize.SMALL)
        .bindMenu(this.SessionMenu())
      if (!this.readOnly && this.terminalId && this.status !== 'closed') {
        Button('结束')
          .id('thread-terminal-close')
          .controlSize(ControlSize.SMALL)
          .enabled(!this.loading)
          .onClick(() => this.confirmClose())
      }
    }.width('100%').padding({ left: 4, right: 12, top: 4, bottom: 4 })
  }

  @Builder
  private Footer() {
    Row({ space: 8 }) {
      if (this.canCapture()) {
        Button('附加输出', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('thread-terminal-capture')
          .height(44)
          .onClick(() => this.captureOutput())
      }
      if (this.canSend()) {
        Button('键盘')
          .id('thread-terminal-keyboard')
          .controlSize(ControlSize.SMALL)
          .onClick(() => this.showKeyboard())
        Scroll() {
          Row({ space: 4 }) {
            ForEach(TERMINAL_KEYS, (key: TerminalKey) => {
              Button(key.label)
                .controlSize(ControlSize.SMALL)
                .onClick(() => this.command({ type: 'key', key: key.key, code: key.code, ctrlKey: key.ctrlKey }))
            }, (key: TerminalKey) => key.key)
            Button('清屏').id('thread-terminal-clear').controlSize(ControlSize.SMALL).onClick(() => this.onClear())
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).layoutWeight(1)
        PasteButton({ icon: PasteIconStyle.LINES, buttonType: ButtonType.Circle })
          .id('thread-terminal-paste')
          .width(44)
          .height(44)
          .iconSize(16)
          .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
            if (result === PasteButtonOnClickResult.SUCCESS) this.paste();
          })
      }
    }.width('100%').padding({ left: 8, right: 8, top: 4, bottom: 4 })
  }

  @Builder
  private CaptureSheet() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text('终端输出').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('取消', { buttonStyle: ButtonStyleMode.TEXTUAL }).height(44).onClick(() => this.dismissCapture())
      }.width('100%')
      Text('点击第一行和最后一行来选择范围。')
        .width('100%').fontSize(14).fontColor($r('sys.color.font_secondary'))
      List() {
        ForEach(this.captureLines, (line: string, index: number) => {
          ListItem() {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 10 }) {
                Text((index + 1).toString()).fontFamily('monospace').fontSize(13).width(32)
                  .textAlign(TextAlign.End).fontColor($r('sys.color.font_secondary'))
                Text(line || ' ').fontFamily('monospace').fontSize(13).layoutWeight(1)
                  .wordBreak(WordBreak.BREAK_ALL).fontColor($r('sys.color.font_primary'))
              }.width('100%').alignItems(VerticalAlign.Top)
            }
            .id(`thread-terminal-line-${index + 1}`)
            .width('100%')
            .constraintSize({ minHeight: 44 })
            .padding({ left: 8, right: 8, top: 8, bottom: 8 })
            .backgroundColor(this.isCaptureLineSelected(index + 1) ?
              $r('sys.color.comp_emphasize_secondary') : Color.Transparent)
            .accessibilityText(`第 ${index + 1} 行 ${line}`)
            .accessibilitySelected(this.isCaptureLineSelected(index + 1))
            .onClick(() => this.selectCaptureLine(index + 1))
          }
        }, (_line: string, index: number) => index.toString())
      }.width('100%').layoutWeight(1)
      if (this.capturedText.length > THREAD_TERMINAL_CONTEXT_MAX_CHARS) {
        Text('请选择更少的行以满足上下文长度限制。')
          .width('100%').fontSize(14).fontColor($r('sys.color.font_secondary'))
      }
      Button('附加选中输出')
        .id('thread-terminal-attach-output')
        .width('100%')
        .height(44)
        .enabled(!!this.capturedText.trim() && this.capturedText.length <= THREAD_TERMINAL_CONTEXT_MAX_CHARS)
        .onClick(() => this.attachCapture())
    }.width('100%').height('100%').padding({ left: 16, right: 16, top: 6, bottom: 16 })
  }

  @Builder
  private Surface() {
    if (this.surfaceError) {
      Column({ space: 12 }) {
        Text(this.surfaceError).fontColor($r('sys.color.font_primary'))
        Button('重新加载渲染器').controlSize(ControlSize.SMALL).onClick(() => this.retryRenderer())
      }.justifyContent(FlexAlign.Center).width('100%').layoutWeight(1)
    } else {
      Web({ src: $rawfile('thread-terminal.html'), controller: this.controller, incognitoMode: true })
        .id('thread-terminal-surface')
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(TERMINAL_BACKGROUND)
        .javaScriptAccess(true)
        .domStorageAccess(false)
        .fileAccess(false)
        .blockNetwork(true)
        .mixedMode(MixedMode.None)
        .multiWindowAccess(false)
        .javaScriptProxy({ object: this.bridge, name: 'ReactNativeWebView',
          methodList: ['postMessage'], controller: this.controller })
        .onLoadIntercept((event: OnLoadInterceptEvent) => {
          const url = event.data.getRequestUrl();
          const packagedUrl = url.startsWith('file:///') || url.startsWith('resource://rawfile/');
          return !event.data.isMainFrame() || !packagedUrl || !url.endsWith('/thread-terminal.html');
        })
        .onPageEnd(() => {
          if (this.pageLoaded) return;
          this.pageLoaded = true;
          this.configure();
        })
        .onErrorReceive((event) => {
          if (event.request.isMainFrame()) this.rendererFailed();
        })
        .onRenderExited(() => this.rendererFailed())
    }
  }

  build() {
    Column() {
      this.Header()
      Row({ space: 8 }) {
        if (this.loading) {
          LoadingProgress().width(16).height(16)
          Text('正在连接终端…').fontSize(12).fontColor($r('sys.color.font_secondary'))
        } else {
          Text(this.statusText(this.status, this.selectedBusy()))
            .id('thread-terminal-status')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        if (this.readOnly) {
          Text('只读').id('thread-terminal-read-only').fontSize(12).fontColor($r('sys.color.font_secondary'))
        }
        if (this.cwd) {
          Text(this.cwd).fontSize(12).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (!this.loading && !this.readOnly && !this.error &&
          (this.status === 'exited' || this.status === 'closed' || this.status === 'error')) {
          Button('重新启动').id('thread-terminal-restart').controlSize(ControlSize.SMALL)
            .onClick(() => this.onRetry())
        }
      }.width('100%').padding({ left: 16, right: 16, bottom: 8 })
      if (this.error) {
        Row({ space: 8 }) {
          Text(this.error).fontSize(14).fontColor($r('sys.color.font_primary')).layoutWeight(1)
          Button('重试').id('thread-terminal-retry').controlSize(ControlSize.SMALL)
            .enabled(!this.loading).onClick(() => this.onRetry())
        }.width('100%').padding({ left: 16, right: 16, bottom: 8 })
      }
      if (this.readOnly && !this.terminalId && !this.loading && !this.error) {
        Text('暂无可查看的终端会话。')
          .fontSize(14).fontColor($r('sys.color.font_secondary'))
          .width('100%').padding({ left: 16, right: 16, bottom: 8 })
      }
      this.Surface()
      if (this.surfaceReady && (this.canSend() || this.canCapture())) this.Footer()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
    .bindSheet(this.showCapture, this.CaptureSheet(), {
      height: SheetSize.LARGE, showClose: false,
      onDisappear: () => { if (this.showCapture) this.dismissCapture(); },
    })
  }
}
