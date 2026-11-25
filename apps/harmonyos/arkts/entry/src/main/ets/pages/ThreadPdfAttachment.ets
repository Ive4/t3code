import { threadAttachmentCachePath } from '../client/ThreadAttachmentCachePath';
import { url } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { pdfService, pdfViewManager, PdfView } from '@kit.PDFKit';

const PDF_CAPABILITY = 'SystemCapability.OfficeService.PDFService.Core';
const PDF_INVALID_DOCUMENT = '此文件无法渲染，可能已损坏或受密码保护。';
const PDF_UNAVAILABLE = '此设备暂不支持在应用内预览 PDF。';

type PdfState = 'idle' | 'loading' | 'ready' | 'error' | 'unavailable';

async function hasPdfHeader(path: string): Promise<boolean> {
  const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
  try {
    const header = new Uint8Array(5);
    const count = await fileIo.read(file.fd, header.buffer);
    return count === header.length && header[0] === 37 && header[1] === 80 && header[2] === 68 &&
      header[3] === 70 && header[4] === 45;
  } finally {
    await fileIo.close(file);
  }
}

@Component
export struct ThreadPdfAttachment {
  @Prop @Watch('selectDocument') uri: string = '';
  @Prop @Watch('selectDocument') initialPage: number = 0;
  onRetry?: () => void;
  onOpen?: () => void;
  onLink?: (href: string) => void;
  onLoadingChange?: (loading: boolean) => void;
  onError?: (message: string, unavailable: boolean) => void;

  @State private state: PdfState = 'idle';
  @State private message: string = '';
  private mounted: boolean = false;
  private generation: number = 0;
  private controller?: pdfViewManager.PdfController = undefined;
  private directory: string = '';

  aboutToAppear(): void {
    this.mounted = true;
    this.selectDocument();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.generation++;
    this.closeDocument();
  }

  private current(generation: number): boolean {
    return this.mounted && this.generation === generation;
  }

  private selectDocument(): void {
    if (!this.mounted) return;
    const generation = ++this.generation;
    this.closeDocument();
    this.message = '';
    this.state = this.uri ? 'loading' : 'idle';
    this.onLoadingChange?.(this.state === 'loading');
    if (this.uri) void this.loadDocument(this.uri, this.initialPage, generation);
  }

  private closeDocument(): void {
    this.release(this.controller, this.directory);
    this.controller = undefined;
    this.directory = '';
  }

  private release(controller: pdfViewManager.PdfController | undefined, directory: string): void {
    try {
      controller?.releaseDocument();
    } catch (_) {
      // The controller can be released before PDFKit has finished opening the file.
    } finally {
      if (directory) void fileIo.rmdir(directory).catch(() => {});
    }
  }

  private fail(generation: number, message: string, unavailable: boolean = false): void {
    if (!this.current(generation)) return;
    this.state = unavailable ? 'unavailable' : 'error';
    this.message = message;
    this.onLoadingChange?.(false);
    this.onError?.(message, unavailable);
  }

  private async loadDocument(uri: string, page: number, generation: number): Promise<void> {
    let controller: pdfViewManager.PdfController | undefined;
    let directory = '';
    try {
      if (!canIUse(PDF_CAPABILITY)) {
        this.fail(generation, PDF_UNAVAILABLE, true);
        return;
      }
      const cacheDir = this.getUIContext().getHostContext()?.cacheDir ?? '';
      const source = await threadAttachmentCachePath(uri, cacheDir);
      if (!this.current(generation)) return;
      // PDFKit may keep reading after the parent releases its download.
      directory = await fileIo.mkdtemp(cacheDir + '/t3-thread-pdf-XXXXXX');
      const path = directory + '/preview.pdf';
      await fileIo.copyFile(source, path);
      if (!this.current(generation)) return;
      if (!await hasPdfHeader(path)) {
        this.fail(generation, '环境未返回有效的 PDF 文件。');
        return;
      }
      if (!this.current(generation)) return;

      controller = new pdfViewManager.PdfController();
      const initialPage = Number.isInteger(page) ? Math.min(0x7fffffff, Math.max(0, page)) : 0;
      const result = await controller.loadDocument(path, '', initialPage);
      if (!this.current(generation)) return;
      if (result === pdfService.ParseResult.PARSE_ERROR_HANDLER) {
        this.fail(generation, PDF_UNAVAILABLE, true);
        return;
      }
      if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
        this.fail(generation, PDF_INVALID_DOCUMENT);
        return;
      }

      controller.registerActionClickListener((redirect: pdfViewManager.RedirectInfo) => {
        if (this.current(generation) && redirect.actionType === pdfViewManager.RedirectType.URI) {
          this.openLink(redirect.content);
        }
      });
      this.controller = controller;
      this.directory = directory;
      this.state = 'ready';
      this.onLoadingChange?.(false);
    } catch (error) {
      const unsupported = (error as BusinessError).code === 801;
      this.fail(generation, unsupported ? PDF_UNAVAILABLE : PDF_INVALID_DOCUMENT, unsupported);
    } finally {
      if (directory !== this.directory) this.release(controller, directory);
    }
  }

  private openLink(href: string): void {
    if (!this.onLink) return;
    try {
      const parsed = url.URL.parseURL(href);
      if ((parsed.protocol === 'https:' || parsed.protocol === 'http:') && parsed.hostname &&
        !parsed.username && !parsed.password) this.onLink(parsed.toString());
    } catch (_) {
      // Only absolute web links from the local PDF are actionable.
    }
  }

  build() {
    Stack() {
      if (this.state === 'ready' && this.controller) {
        PdfView({
          controller: this.controller,
          pageLayout: pdfService.PageLayout.LAYOUT_SINGLE,
          pageFit: pdfService.PageFit.FIT_WIDTH,
          isContinuous: true,
          showScroll: true,
        }).id('thread-attachment-pdf-document').width('100%').height('100%')
      } else if (this.state === 'loading') {
        Column({ space: 10 }) {
          LoadingProgress().width(26).height(26).color($r('sys.color.icon_emphasize'))
          Text('正在加载 PDF…').fontSize(14).fontColor($r('sys.color.font_secondary'))
        }.id('thread-attachment-pdf-loading')
      } else if (this.state === 'error' || this.state === 'unavailable') {
        Column({ space: 10 }) {
          Text('无法打开 PDF').fontWeight(FontWeight.Medium).fontSize(17)
            .fontColor($r('sys.color.font_primary'))
          Text(this.message).fontSize(14).fontColor($r('sys.color.font_secondary')).textAlign(TextAlign.Center)
          if (this.state === 'unavailable' && this.onOpen) {
            Button('打开 PDF').id('thread-attachment-pdf-open').height(44).onClick(() => this.onOpen?.())
          } else if (this.state === 'error' && this.onRetry) {
            Button('重试').id('thread-attachment-pdf-retry').height(44).onClick(() => this.onRetry?.())
          }
        }.id('thread-attachment-pdf-error').width('100%').padding(24)
      }
    }.id('thread-attachment-pdf').width('100%').height('100%').backgroundColor($r('sys.color.comp_background_primary'))
  }
}
