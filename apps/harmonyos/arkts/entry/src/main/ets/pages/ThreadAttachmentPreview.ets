import { ThreadPdfAttachment } from './ThreadPdfAttachment';
import { ThreadVideoAttachment } from './ThreadVideoAttachment';

const IMAGE_TOOLBAR_BACKGROUND = '#B3000000';
const IMAGE_MUTED_TEXT = '#D1D5DB';

@Component
export struct ThreadAttachmentPreview {
  @Prop name: string = '';
  @Prop mimeType: string = '';
  @Prop kind: 'image' | 'file' = 'file';
  @Prop pdf: boolean = false;
  @Prop video: boolean = false;
  @Prop @Watch('resetImage') uri: string = '';
  @Prop sizeBytes: number = 0;
  @Prop text?: string = undefined;
  @Prop truncated: boolean = false;
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop actionBusy: boolean = false;
  onBack: () => void = () => {};
  onRetry?: () => void;
  onShare?: () => void;
  onSave?: () => void;
  onOpen?: () => void;
  onPrevious?: () => void;
  onNext?: () => void;

  @State private imageReady: boolean = false;
  @State private imageFailed: boolean = false;
  @State private zoom: number = 1;
  @State private offsetX: number = 0;
  @State private offsetY: number = 0;
  private imageWidth: number = 0;
  private imageHeight: number = 0;
  private viewportWidth: number = 0;
  private viewportHeight: number = 0;
  private pinchStart: number = 1;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private panning: boolean = false;

  private resetImage(): void {
    this.imageReady = false;
    this.imageFailed = false;
    this.imageWidth = 0;
    this.imageHeight = 0;
    this.setZoom(1);
  }

  private setZoom(value: number): void {
    this.zoom = Math.max(1, Math.min(3, value));
    this.positionImage(this.offsetX, this.offsetY);
  }

  private positionImage(x: number, y: number): void {
    if (!this.imageWidth || !this.imageHeight || this.zoom === 1) {
      this.offsetX = 0;
      this.offsetY = 0;
      return;
    }
    const fit = Math.min(this.viewportWidth / this.imageWidth, this.viewportHeight / this.imageHeight);
    const maxX = Math.max(0, (this.imageWidth * fit * this.zoom - this.viewportWidth) / 2);
    const maxY = Math.max(0, (this.imageHeight * fit * this.zoom - this.viewportHeight) / 2);
    this.offsetX = Math.max(-maxX, Math.min(maxX, x));
    this.offsetY = Math.max(-maxY, Math.min(maxY, y));
  }

  private finishPan(event: GestureEvent): void {
    if (this.panning || this.zoom !== 1 || Math.abs(event.offsetX) < 72 ||
      Math.abs(event.offsetX) <= Math.abs(event.offsetY) * 1.5) return;
    if (event.offsetX < 0) this.onNext?.();
    else this.onPrevious?.();
  }

  private fileSubtitle(): string {
    const bytes = this.sizeBytes;
    if (!Number.isFinite(bytes) || bytes <= 0) return '附件';
    if (bytes < 1024) return `附件 · ${bytes} B`;
    if (bytes < 1048576) return `附件 · ${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1073741824) return `附件 · ${(bytes / 1048576).toFixed(1)} MB`;
    return `附件 · ${(bytes / 1073741824).toFixed(1)} GB`;
  }

  private retry(): void {
    this.resetImage();
    this.onRetry?.();
  }

  @Builder
  private ActionsMenu() {
    Menu() {
      if (this.onOpen && this.kind === 'file') {
        MenuItem({ content: '在文件查看器中打开' }).id('thread-attachment-open').onClick(() => this.onOpen?.())
      }
      if (this.onSave) {
        MenuItem({ content: '保存' }).id('thread-attachment-save').onClick(() => this.onSave?.())
      }
      if (this.onShare) {
        MenuItem({ content: '分享' }).id('thread-attachment-share').onClick(() => this.onShare?.())
      }
    }
  }

  @Builder
  private Actions(dark: boolean) {
    if (!this.loading &&
      ((this.onOpen && !dark) || this.onSave || this.onShare)) {
      Button({ type: ButtonType.Normal }) {
        if (this.actionBusy) LoadingProgress().width(20).height(20)
        else Text('⋯').fontSize(22).fontColor(dark ? Color.White : $r('sys.color.icon_primary'))
      }
      .id('thread-attachment-actions').width(44).height(44).borderRadius(8)
      .enabled(!this.actionBusy)
      .backgroundColor(dark ? IMAGE_TOOLBAR_BACKGROUND : Color.Transparent)
      .accessibilityText(dark ? '媒体操作' : '文件操作')
      .bindMenu(this.ActionsMenu())
    }
  }

  @Builder
  private BackButton(dark: boolean) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(dark ? $r('sys.symbol.xmark') : $r('sys.symbol.arrow_left'))
        .fontSize(20).fontColor([dark ? Color.White : $r('sys.color.icon_primary')])
    }
    .id('thread-attachment-back').width(48).height(48).backgroundColor(Color.Transparent)
    .accessibilityText(dark ? '关闭图片' : '返回').onClick(() => this.onBack())
  }

  @Builder
  private Header(dark: boolean) {
    Row({ space: dark ? 12 : 6 }) {
      if (!dark) this.BackButton(false)
      Column({ space: 2 }) {
        Text(this.name || (dark ? '图片' : '附件'))
          .id('thread-attachment-title').fontSize(dark ? 16 : 20).fontWeight(FontWeight.Medium)
          .fontColor(dark ? Color.White : $r('sys.color.font_primary')).maxLines(dark ? 2 : 1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (!dark) {
          Text(this.fileSubtitle()).fontSize(13).fontColor($r('sys.color.font_secondary'))
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      this.Actions(dark)
      if (dark) this.BackButton(true)
    }
    .width('100%').constraintSize({ minHeight: 56 })
    .padding({ left: dark ? 16 : 4, right: 8, top: 4, bottom: 4 })
    .backgroundColor(dark ? IMAGE_TOOLBAR_BACKGROUND : $r('sys.color.comp_background_primary'))
  }

  @Builder
  private Loading(dark: boolean) {
    Column({ space: 10 }) {
      LoadingProgress().width(26).height(26).color(dark ? Color.White : $r('sys.color.icon_emphasize'))
      Text(dark ? '正在加载图片…' : '正在加载文件…').fontSize(14)
        .fontColor(dark ? IMAGE_MUTED_TEXT : $r('sys.color.font_secondary'))
    }.id('thread-attachment-loading')
  }

  @Builder
  private Notice(title: string, detail: string, dark: boolean, retry: boolean) {
    Column({ space: 10 }) {
      Text(title).fontSize(17).fontWeight(FontWeight.Medium)
        .fontColor(dark ? Color.White : $r('sys.color.font_primary')).textAlign(TextAlign.Center)
      if (detail) {
        Text(detail).fontSize(14).fontColor(dark ? IMAGE_MUTED_TEXT : $r('sys.color.font_secondary'))
          .textAlign(TextAlign.Center).wordBreak(WordBreak.BREAK_WORD)
      }
      if (retry && this.onRetry) {
        Button('重试').id('thread-attachment-retry').height(44).onClick(() => this.retry())
      }
    }.width('100%').padding(24)
  }

  @Builder
  private ImageSurface(uri: string) {
    Stack() {
      Image(uri).id('thread-attachment-image').width('100%').height('100%')
        .objectFit(ImageFit.Contain).accessibilityText(this.name || '图片')
        .scale({ x: this.zoom, y: this.zoom })
        .translate({ x: this.offsetX, y: this.offsetY })
        .onComplete((event) => {
          if (uri !== this.uri || !event || !event.width || !event.height) return;
          this.imageWidth = event.width;
          this.imageHeight = event.height;
          this.imageReady = true;
        })
        .onError(() => {
          if (uri === this.uri) this.imageFailed = true;
        })
      if (!this.imageReady) this.Loading(true)
    }
    .width('100%').height('100%').clip(true)
    .onAreaChange((_previous: Area, area: Area) => {
      this.viewportWidth = Number.parseFloat(area.width.toString());
      this.viewportHeight = Number.parseFloat(area.height.toString());
      this.positionImage(this.offsetX, this.offsetY);
    })
    .gesture(GestureGroup(GestureMode.Parallel,
      TapGesture({ count: 2 }).onAction(() => { if (this.imageReady) this.setZoom(this.zoom === 1 ? 2 : 1); }),
      PinchGesture({ fingers: 2 })
        .onActionStart(() => { this.pinchStart = this.zoom; })
        .onActionUpdate((event: GestureEvent) => { if (this.imageReady) this.setZoom(this.pinchStart * event.scale); }),
      PanGesture({ fingers: 1 })
        .onActionStart(() => {
          this.panning = this.zoom > 1;
          this.panStartX = this.offsetX;
          this.panStartY = this.offsetY;
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.panning) this.positionImage(this.panStartX + event.offsetX, this.panStartY + event.offsetY);
        })
        .onActionEnd((event: GestureEvent) => { if (this.imageReady) this.finishPan(event); }),
    ))
  }

  @Builder
  private ImageViewer() {
    Stack({ alignContent: Alignment.Top }) {
      Stack() {
        if (this.error || this.imageFailed) {
          this.Notice('图片无法打开', this.error || '图片加载失败。', true, true)
        } else if (this.loading) {
          this.Loading(true)
        } else if (this.uri) {
          this.ImageSurface(this.uri)
        } else {
          this.Notice('图片无法打开', '', true, true)
        }
      }.width('100%').height('100%')
      this.Header(true)
    }.width('100%').height('100%').backgroundColor(Color.Black)
  }

  @Builder
  private FileViewer() {
    Column() {
      this.Header(false)
      if (!this.loading && !this.error && this.text !== undefined) {
        if (this.truncated) {
          Text('仅显示文件的部分内容。').id('thread-attachment-partial').width('100%').padding(12)
            .fontSize(13).fontColor($r('sys.color.font_secondary'))
        }
        Scroll() {
          Text(this.text || '文件为空。').id('thread-attachment-text').width('100%').padding(16)
            .fontFamily('monospace').fontSize(13).lineHeight(19).fontColor($r('sys.color.font_primary'))
            .wordBreak(WordBreak.BREAK_ALL).copyOption(CopyOptions.LocalDevice)
        }.width('100%').layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Auto)
      } else if (this.pdf && this.uri && !this.error && !this.loading) {
        Stack() {
          ThreadPdfAttachment({ uri: this.uri, onOpen: this.onOpen, onRetry: this.onRetry })
        }.layoutWeight(1).width('100%')
      } else {
        Stack() {
          if (this.error) {
            this.Notice('文件不可用', this.error, false, true)
          } else if (this.loading) {
            this.Loading(false)
          } else {
            Column() {
              this.Notice('无法预览此文件', this.mimeType, false, false)
              if (this.onOpen) {
                Button('在文件查看器中打开').id('thread-attachment-open-viewer').height(44)
                  .onClick(() => this.onOpen?.())
              }
            }
          }
        }.width('100%').layoutWeight(1)
      }
    }.width('100%').height('100%').backgroundColor($r('sys.color.comp_background_primary'))
  }

  @Builder
  private VideoViewer() {
    Stack({ alignContent: Alignment.Top }) {
      Stack() {
        if (this.error) this.Notice('视频无法播放', this.error, true, true)
        else if (this.loading) this.Loading(true)
        else if (this.uri) ThreadVideoAttachment({ uri: this.uri, paused: this.actionBusy, onRetry: this.onRetry })
      }.width('100%').height('100%')
      this.Header(true)
    }.width('100%').height('100%').backgroundColor(Color.Black)
  }

  build() {
    Stack() {
      if (this.video) this.VideoViewer()
      else if (this.kind === 'image') this.ImageViewer()
      else this.FileViewer()
    }.id('thread-attachment-preview').width('100%').height('100%')
  }
}
