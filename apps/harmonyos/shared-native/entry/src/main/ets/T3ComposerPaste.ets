import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import pasteboard from '@ohos.pasteboard';
import { ComponentBuilderContext, Descriptor, RNComponentContext, RNViewBase } from '@rnoh/react-native-openharmony';
import {
  discardComposerPasteImages,
  holdComposerPasteImages,
  isComposerPasteImageMaterializing,
  releaseClipboardBitmap,
} from './ComposerPasteImages';

interface PasteProps {
  nativeID: string;
  textOnly?: boolean;
}

interface ComposerPasteData {
  text: string;
  html: string;
  uris: string[];
  imageToken?: string;
}

const MAX_BITMAP_BYTES = 64 * 1024 * 1024;
const MAX_BITMAPS_PER_PASTE = 4;
const imageFileExtension = /\.(avif|bmp|gif|heic|heif|jpe?g|png|webp)(?:[?#]|$)/i;
const externalFileUri = /^file:\/\/[^/]+\//;

async function readTextEntry(record: pasteboard.PasteDataRecord, type: string): Promise<string> {
  if (record.getValidTypes([type]).length === 0) return '';
  const value = await record.getData(type);
  return typeof value === 'string' ? value : '';
}

async function readPixelMap(record: pasteboard.PasteDataRecord): Promise<image.PixelMap | undefined> {
  const bitmap = record.pixelMap;
  if (bitmap) return bitmap;
  if (record.getValidTypes([pasteboard.MIMETYPE_PIXELMAP]).length === 0) return undefined;
  return await record.getData(pasteboard.MIMETYPE_PIXELMAP) as image.PixelMap;
}

@Builder
export function buildT3ComposerPaste(ctx: ComponentBuilderContext) {
  if (ctx.componentName === 'T3ComposerPaste') {
    T3ComposerPaste({ ctx: ctx.rnComponentContext, tag: ctx.tag })
  }
}

@Component
struct T3ComposerPaste {
  ctx!: RNComponentContext;
  tag: number = 0;
  private viewId: string = '';
  private owner: string = '';
  private pasting: boolean = false;
  private textOnly: boolean = false;

  aboutToAppear(): void {
    const descriptor = this.ctx.descriptorRegistry.getDescriptor<Descriptor<string, Object, Object, PasteProps>>(this.tag);
    this.viewId = descriptor.rawProps.nativeID;
    this.textOnly = descriptor.rawProps.textOnly === true;
    this.owner = util.generateRandomUUID();
  }

  aboutToDisappear(): void {
    discardComposerPasteImages(this.owner);
    this.owner = '';
    this.viewId = '';
  }

  private async paste(): Promise<void> {
    const owner = this.owner;
    const viewId = this.viewId;
    if (!owner || !viewId || this.pasting || isComposerPasteImageMaterializing(owner)) return;
    this.pasting = true;
    const bitmaps: image.PixelMap[] = [];
    let transferred = false;
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      if (this.owner !== owner) return;
      discardComposerPasteImages(owner);
      const uris = new Set<string>();
      const texts: string[] = [];
      let html = '';
      let bitmapBytes = 0;
      for (let i = 0; i < data.getRecordCount(); i++) {
        if (this.owner !== owner) return;
        const record = data.getRecord(i);
        if (!this.textOnly && !html) html = record.htmlText || await readTextEntry(record, pasteboard.MIMETYPE_TEXT_HTML);
        const uri = record.uri || await readTextEntry(record, pasteboard.MIMETYPE_TEXT_URI);
        if (!this.textOnly && externalFileUri.test(uri) &&
          (record.mimeType.startsWith('image/') || imageFileExtension.test(uri))) {
          uris.add(uri);
        } else if (!this.textOnly && bitmaps.length < MAX_BITMAPS_PER_PASTE && bitmapBytes < MAX_BITMAP_BYTES) {
          const bitmap = await readPixelMap(record).catch((): undefined => undefined);
          if (bitmap) {
            let keep = false;
            try {
              const bytes = bitmap.getPixelBytesNumber();
              keep = bytes > 0 && bitmapBytes + bytes <= MAX_BITMAP_BYTES;
              if (keep) {
                bitmaps.push(bitmap);
                bitmapBytes += bytes;
              }
            } finally {
              if (!keep) await releaseClipboardBitmap(bitmap);
            }
          }
        }
        const text = record.plainText || await readTextEntry(record, pasteboard.MIMETYPE_TEXT_PLAIN);
        if (text) texts.push(text);
        else if (record.htmlText) texts.push(record.toPlainText());
        else if (/^https?:\/\//i.test(uri)) texts.push(uri);
      }
      if (this.owner !== owner) return;
      const result: ComposerPasteData = { text: texts.join('\n'), html, uris: Array.from(uris) };
      if (bitmaps.length > 0) {
        result.imageToken = holdComposerPasteImages(owner, this.ctx.uiAbilityContext.cacheDir, bitmaps);
        transferred = true;
      }
      this.ctx.rnInstance.emitDeviceEvent('T3ComposerPaste:' + viewId, result);
    } catch (error) {
      if (transferred) discardComposerPasteImages(owner);
      throw new Error((error as Error).message || 'Could not paste clipboard content');
    } finally {
      this.pasting = false;
      if (!transferred) {
        for (const bitmap of bitmaps) await releaseClipboardBitmap(bitmap);
      }
    }
  }

  build() {
    RNViewBase({ tag: this.tag, ctx: this.ctx }) {
      PasteButton({ icon: PasteIconStyle.LINES, buttonType: ButtonType.Circle })
        .width('100%')
        .height('100%')
        .iconSize(16)
        .padding(8)
        .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
          if (result === PasteButtonOnClickResult.SUCCESS) this.paste().catch(() => {});
        })
    }
  }
}
