import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';

const MAX_OUTPUT_EDGE = 2000;
const MAX_PACKED_BYTES = 20 * 1024 * 1024;

interface ClipboardImages {
  owner: string;
  cacheDir: string;
  bitmaps: image.PixelMap[];
}

const unclaimed = new Map<string, ClipboardImages>();
const materializing = new Set<string>();

export function isComposerPasteImageMaterializing(owner: string): boolean {
  return materializing.has(owner);
}

export async function releaseClipboardBitmap(bitmap: image.PixelMap): Promise<void> {
  try {
    await bitmap.release();
  } catch (_) {}
}

export function holdComposerPasteImages(owner: string, cacheDir: string, bitmaps: image.PixelMap[]): string {
  const token = util.generateRandomUUID();
  unclaimed.set(token, { owner, cacheDir, bitmaps });
  return token;
}

export function discardComposerPasteImages(owner: string): void {
  unclaimed.forEach((batch, token) => {
    if (batch.owner !== owner) return;
    unclaimed.delete(token);
    batch.bitmaps.forEach(bitmap => {
      releaseClipboardBitmap(bitmap);
    });
  });
}

async function saveBitmap(cacheDir: string, bitmap: image.PixelMap): Promise<string> {
  const size = (await bitmap.getImageInfo()).size;
  if (size.width < 1 || size.height < 1 || size.width * size.height > 16 * 1024 * 1024) return '';
  const scale = MAX_OUTPUT_EDGE / Math.max(size.width, size.height);
  const resized = scale < 1 ? await bitmap.createScaledPixelMap(
    Math.max(1 / size.width, scale),
    Math.max(1 / size.height, scale),
  ) : bitmap;
  const path = cacheDir + '/t3-clipboard-image-' + util.generateRandomUUID() + '.png';
  let created = false;
  try {
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
    created = true;
    try {
      const packer = image.createImagePacker();
      try {
        await packer.packToFile(resized, file.fd, { format: 'image/png', quality: 100 });
      } finally {
        await packer.release();
      }
      const size = (await fileIo.stat(file.fd)).size;
      if (size < 1 || size > MAX_PACKED_BYTES) throw new Error('Invalid clipboard image size');
    } finally {
      await fileIo.close(file);
    }
    return 'file://' + path;
  } catch (_) {
    if (created) await fileIo.unlink(path).catch(() => {});
    return '';
  } finally {
    if (resized !== bitmap) await releaseClipboardBitmap(resized);
  }
}

export async function takeComposerPasteImages(token: string, materialize: boolean): Promise<string[]> {
  const batch = unclaimed.get(token);
  if (!batch) return [];
  unclaimed.delete(token);
  const canMaterialize = materialize && !materializing.has(batch.owner);
  if (canMaterialize) materializing.add(batch.owner);
  const uris: string[] = [];
  try {
    for (const bitmap of batch.bitmaps) {
      try {
        if (canMaterialize) {
          const uri = await saveBitmap(batch.cacheDir, bitmap).catch((): string => '');
          if (uri) uris.push(uri);
        }
      } finally {
        await releaseClipboardBitmap(bitmap);
      }
    }
  } finally {
    if (canMaterialize) materializing.delete(batch.owner);
  }
  return uris;
}
