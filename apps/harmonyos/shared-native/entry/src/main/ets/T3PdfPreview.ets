import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { pdfService, pdfViewManager, PdfView } from '@kit.PDFKit';
import { ComponentBuilderContext, Descriptor, RNComponentContext, RNViewBase } from '@rnoh/react-native-openharmony';
import { PDF_CAPABILITY } from './FileActionsModule';
import { sandboxFilePath } from './SharingModule';

const UNSUPPORTED_DEVICE = 801;

interface PdfProps {
  nativeID: string;
  uri: string;
  initialPage: number;
}

interface PdfEvent {
  type: 'ready' | 'error' | 'unavailable' | 'link';
  href?: string;
}

@Builder
export function buildT3PdfPreview(ctx: ComponentBuilderContext) {
  T3PdfPreview({ ctx: ctx.rnComponentContext, tag: ctx.tag })
}

@Component
struct T3PdfPreview {
  ctx!: RNComponentContext;
  tag: number = 0;
  @State loaded: boolean = false;
  private mounted: boolean = false;
  private viewId: string = '';
  private directory?: string;
  private controller?: pdfViewManager.PdfController;

  aboutToAppear(): void {
    const props = this.ctx.descriptorRegistry.getDescriptor<Descriptor<string, Object, Object, PdfProps>>(this.tag).rawProps;
    this.viewId = props.nativeID;
    this.mounted = true;
    void this.open(props);
  }

  aboutToDisappear(): void {
    this.mounted = false;
    if (this.controller && this.directory) this.release(this.controller, this.directory);
  }

  private async open(props: PdfProps): Promise<void> {
    let directory: string | undefined;
    let controller: pdfViewManager.PdfController | undefined;
    try {
      const context = this.ctx.uiAbilityContext;
      const source = await sandboxFilePath(props.uri, context);
      if (!this.mounted) return;
      if (!canIUse(PDF_CAPABILITY)) {
        this.emit({ type: 'unavailable' });
        return;
      }
      try {
        controller = new pdfViewManager.PdfController();
      } catch {
        this.emit({ type: 'unavailable' });
        return;
      }
      // React can release its source as soon as the modal closes, while PDFKit still reads.
      directory = await fileIo.mkdtemp(context.cacheDir + '/t3-pdf-XXXXXX');
      if (!this.mounted) return;
      const documentPath = directory + '/preview.pdf';
      await fileIo.copyFile(source, documentPath);
      if (!this.mounted) return;
      const page = Math.min(props.initialPage, 0x7fffffff);
      const result = await controller.loadDocument(documentPath, '', page);
      if (!this.mounted) return;
      if (result === pdfService.ParseResult.PARSE_ERROR_HANDLER) {
        this.emit({ type: 'unavailable' });
        return;
      }
      if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
        this.emit({ type: 'error' });
        return;
      }
      controller.registerActionClickListener((redirect: pdfViewManager.RedirectInfo) => {
        if (redirect.actionType === pdfViewManager.RedirectType.URI) {
          this.emit({ type: 'link', href: redirect.content });
        }
      });
      this.controller = controller;
      this.directory = directory;
      this.loaded = true;
      this.emit({ type: 'ready' });
    } catch (error) {
      this.emit({ type: (error as BusinessError).code === UNSUPPORTED_DEVICE ? 'unavailable' : 'error' });
    } finally {
      if (directory && this.directory !== directory) this.release(controller, directory);
    }
  }

  private release(controller: pdfViewManager.PdfController | undefined, directory: string): void {
    try {
      controller?.releaseDocument();
    } catch {
      console.warn('[t3-pdf] Could not release the preview document.');
    } finally {
      void fileIo.rmdir(directory).catch(() => {});
    }
  }

  private emit(event: PdfEvent): void {
    if (this.mounted) this.ctx.rnInstance.emitDeviceEvent('T3PdfPreview:' + this.viewId, event);
  }

  build() {
    RNViewBase({ tag: this.tag, ctx: this.ctx }) {
      if (this.loaded && this.controller) {
        PdfView({
          controller: this.controller,
          pageLayout: pdfService.PageLayout.LAYOUT_SINGLE,
          pageFit: pdfService.PageFit.FIT_WIDTH,
          isContinuous: true,
          showScroll: true,
        })
          .width('100%')
          .height('100%')
      }
    }
  }
}
