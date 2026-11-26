import { webview } from '@kit.ArkWeb';
import { ComponentBuilderContext, Descriptor, RNComponentContext, RNViewBase } from '@rnoh/react-native-openharmony';

interface WebSource {
  uri?: string;
  html?: string;
  baseUrl?: string;
  harmonyWebFrames?: boolean;
}

class WebOptions {
  source: WebSource = {};
  script: string = '';
  messaging: boolean = false;
  mixed: boolean = false;
  allowScript: boolean = true;
  storage: boolean = true;
  incognito: boolean = false;
  mediaGesture: boolean = true;
  windows: boolean = false;
}

interface RawProps {
  nativeID: string;
  options: string;
}

interface WebEvent {
  type: string;
  url?: string;
  data?: string;
  requestId?: string;
  progress?: number;
  description?: string;
  statusCode?: number;
  targetUrl?: string;
}

class MessageBridge {
  private send: (data: string) => void;
  constructor(send: (data: string) => void) {
    this.send = send;
  }
  postMessage(data: string): void {
    if (typeof data === 'string') this.send(data);
  }
}

let arkWebPreloaded = false;

function createWebViewController(): webview.WebviewController {
  if (!arkWebPreloaded) {
    arkWebPreloaded = true;
    try {
      webview.WebviewController.setAutoPreconnect(false);
      webview.WebviewController.initializeWebEngine();
    } catch (_) {
      console.warn('[t3-arkweb] Could not preload the web engine.');
    }
  }
  return new webview.WebviewController();
}

@Builder
export function buildT3WebView(ctx: ComponentBuilderContext) {
  if (ctx.componentName === 'T3WebView') {
    T3WebView({ ctx: ctx.rnComponentContext, tag: ctx.tag })
  }
}

@Component
struct T3WebView {
  ctx!: RNComponentContext;
  tag: number = 0;
  @State options: WebOptions = new WebOptions();
  private controller: webview.WebviewController = createWebViewController();
  private bridge: MessageBridge = new MessageBridge((data) => this.emit({ type: 'onMessage', data }));
  private stopCommands?: () => void;
  private attachTimeout?: number;
  private viewId: string = '';
  private pendingUrl: string = '';
  private pendingId: number = 0;
  private approvedUrl: string = '';
  private active: boolean = false;
  private startingHtml: boolean = false;

  aboutToAppear(): void {
    const descriptor = this.ctx.descriptorRegistry.getDescriptor<Descriptor<string, Object, Object, RawProps>>(this.tag);
    this.viewId = descriptor.rawProps.nativeID;
    this.options = JSON.parse(descriptor.rawProps.options) as WebOptions;
    this.active = true;
    this.attachTimeout = setTimeout(() => {
      this.attachTimeout = undefined;
      this.emit({ type: 'onError', description: 'ArkWeb did not initialize.' });
    }, 12000);
    this.stopCommands = this.ctx.componentCommandReceiver.registerCommandCallback(this.tag, (command: string, args: string[]) => {
      if (command === 'injectJavaScript') this.runScript(args[0]);
      if (command === 'navigate' && this.pendingUrl && args[0] === String(this.pendingId)) {
        const url = this.pendingUrl;
        this.pendingUrl = '';
        this.loadUrl(url);
      }
    });
  }

  aboutToDisappear(): void {
    this.active = false;
    this.clearAttachTimeout();
    this.stopCommands?.();
  }

  private clearAttachTimeout(): void {
    if (this.attachTimeout !== undefined) {
      clearTimeout(this.attachTimeout);
      this.attachTimeout = undefined;
    }
  }

  private emit(event: WebEvent): void {
    if (this.active) this.ctx.rnInstance.emitDeviceEvent('T3WebView:' + this.viewId, event);
  }

  private runScript(script: string): void {
    if (this.options.allowScript && script) {
      this.controller.runJavaScript(script).catch(() => {});
    }
  }

  private loadUrl(url: string): void {
    this.approvedUrl = url;
    try {
      this.controller.loadUrl(url);
    } catch (error) {
      this.emit({ type: 'onError', url, description: (error as Error).message });
    }
  }

  private start(): void {
    this.clearAttachTimeout();
    const source = this.options.source;
    if (source.html !== undefined) {
      this.startingHtml = true;
      this.approvedUrl = source.baseUrl ?? 'about:blank';
      try {
        this.controller.loadData(source.html, 'text/html', 'UTF-8', this.approvedUrl, this.approvedUrl);
      } catch (error) {
        this.emit({ type: 'onError', description: (error as Error).message });
      }
    } else if (source.uri) {
      this.loadUrl(source.uri);
    }
  }

  private intercept(request: WebResourceRequest): boolean {
    const url = request.getRequestUrl();
    if (!request.isMainFrame()) {
      // ArkWeb cannot resume a cancelled subframe. These callers explicitly permit web frames.
      return !(this.options.source.harmonyWebFrames &&
        (/^https?:\/\//i.test(url) || url === 'about:blank' || url === 'about:srcdoc'));
    }
    // loadData can report its first navigation as data:text/html even with a base URL.
    if (this.startingHtml && /^data:text\/html[;,]/i.test(url)) {
      this.startingHtml = false;
      this.approvedUrl = '';
      return false;
    }
    if (url === this.approvedUrl) {
      this.startingHtml = false;
      this.approvedUrl = '';
      return false;
    }
    this.pendingId++;
    this.pendingUrl = request.getRequestMethod().toUpperCase() === 'GET' ? url : '';
    if (this.pendingUrl) this.emit({ type: 'request', url, requestId: String(this.pendingId) });
    return true;
  }

  build() {
    RNViewBase({ tag: this.tag, ctx: this.ctx }) {
      Web({ src: '', controller: this.controller, incognitoMode: this.options.incognito })
        .width('100%')
        .height('100%')
        .javaScriptAccess(this.options.allowScript)
        .domStorageAccess(this.options.storage)
        .fileAccess(this.options.source.uri?.startsWith('file://') === true)
        .mixedMode(this.options.mixed ? MixedMode.All : MixedMode.None)
        .mediaPlayGestureAccess(this.options.mediaGesture)
        .multiWindowAccess(this.options.windows)
        .javaScriptProxy({ object: this.bridge, name: 'ReactNativeWebView',
          methodList: this.options.messaging ? ['postMessage'] : [], controller: this.controller })
        .onControllerAttached(() => this.start())
        .onLoadIntercept(event => this.intercept(event.data))
        .onPageBegin(event => {
          this.startingHtml = false;
          this.approvedUrl = '';
          this.emit({ type: 'onLoadStart', url: event.url });
        })
        .onProgressChange(event => this.emit({ type: 'onLoadProgress', progress: event.newProgress / 100 }))
        .onPageEnd(event => {
          this.runScript(this.options.script);
          this.emit({ type: 'onLoadEnd', url: event.url });
        })
        .onErrorReceive(event => {
          if (event.request.isMainFrame()) this.emit({ type: 'onError', url: event.request.getRequestUrl(),
            description: event.error.getErrorInfo() });
        })
        .onHttpErrorReceive(event => {
          if (event.request.isMainFrame()) this.emit({ type: 'onHttpError', url: event.request.getRequestUrl(),
            statusCode: event.response.getResponseCode() });
        })
        .onWindowNew(event => {
          this.emit({ type: 'onOpenWindow', targetUrl: event.targetUrl });
          event.handler.setWebController(null);
        })
        .onRenderExited(() => this.emit({ type: 'onRenderProcessGone' }))
    }
  }
}
