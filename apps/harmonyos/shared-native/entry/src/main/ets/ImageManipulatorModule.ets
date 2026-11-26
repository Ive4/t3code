import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { UITurboModule } from '@rnoh/react-native-openharmony';
import { FileSystemModule } from './FileSystemModule';

const MAX_SOURCE_BYTES = 64 * 1024 * 1024;
const MAX_SOURCE_PIXELS = 64 * 1024 * 1024;
const MAX_OUTPUT_EDGE = 2048;

interface Orientation {
  rotation: number;
  flipHorizontal?: boolean;
  flipVertical?: boolean;
}

async function readOrientation(source: image.ImageSource): Promise<Orientation> {
  const value = await source.getImageProperty(image.PropertyKey.ORIENTATION).catch((): string => '');
  switch (value) {
    case 'Top-right': return { rotation: 0, flipHorizontal: true };
    case 'Bottom-right': return { rotation: 180 };
    case 'Bottom-left': return { rotation: 0, flipVertical: true };
    case 'Left-top': return { rotation: 270, flipHorizontal: true };
    case 'Right-top': return { rotation: 90 };
    case 'Right-bottom': return { rotation: 90, flipVertical: true };
    case 'Left-bottom': return { rotation: 270 };
    default: return { rotation: 0 };
  }
}

export class ImageManipulatorModule extends UITurboModule {
  private async withSource<T>(uri: string, operation: (source: image.ImageSource) => Promise<T>): Promise<T> {
    const path = new FileSystemModule(this.ctx).readablePath(uri);
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = await fileIo.stat(file.fd);
      if (!stat.isFile() || stat.size <= 0 || stat.size > MAX_SOURCE_BYTES) {
        throw new Error('Invalid photo file size');
      }
      const source = image.createImageSource(file.fd);
      try {
        return await operation(source);
      } finally {
        await source.release();
      }
    } finally {
      await fileIo.close(file);
    }
  }

  public async getSize(uri: string): Promise<image.Size> {
    return this.withSource(uri, async (source: image.ImageSource): Promise<image.Size> => {
      const size = (await source.getImageInfo()).size;
      const rotation = (await readOrientation(source)).rotation;
      return rotation % 180 === 0 ? size : { width: size.height, height: size.width };
    });
  }

  public async render(uri: string, width: number, height: number, format: string, compress: number): Promise<string> {
    if (!Number.isInteger(width) || !Number.isInteger(height) ||
      width < 1 || height < 1 || width > MAX_OUTPUT_EDGE || height > MAX_OUTPUT_EDGE ||
      (format !== 'jpeg' && format !== 'png') || !Number.isFinite(compress) || compress < 0 || compress > 1) {
      throw new Error('Invalid photo render options');
    }
    const path = this.ctx.uiAbilityContext.cacheDir + '/t3-photo-' + util.generateRandomUUID() + '.' + format;
    let created = false;
    try {
      await this.withSource(uri, async (source: image.ImageSource): Promise<void> => {
        const size = (await source.getImageInfo()).size;
        // Some codecs allocate intermediate buffers based on the original dimensions.
        if (size.width < 1 || size.height < 1 || size.width * size.height > MAX_SOURCE_PIXELS) {
          throw new Error('Invalid photo dimensions');
        }
        const orientation = await readOrientation(source);
        const swap = orientation.rotation % 180 !== 0;
        const pixels = await source.createPixelMap({
          desiredSize: swap ? { width: height, height: width } : { width, height },
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
          desiredDynamicRange: image.DecodingDynamicRange.SDR,
          editable: true,
        });
        try {
          if (orientation.flipHorizontal || orientation.flipVertical) {
            await pixels.flip(orientation.flipHorizontal ?? false, orientation.flipVertical ?? false);
          }
          if (orientation.rotation !== 0) await pixels.rotate(orientation.rotation);
          const file = await fileIo.open(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
          created = true;
          try {
            const packer = image.createImagePacker();
            try {
              await packer.packToFile(pixels, file.fd, {
                format: 'image/' + format,
                quality: Math.round(compress * 100),
              });
            } finally {
              await packer.release();
            }
          } finally {
            await fileIo.close(file);
          }
        } finally {
          await pixels.release();
        }
      });
    } catch (error) {
      if (created) await fileIo.unlink(path);
      throw new Error((error as Error).message || 'Could not render photo');
    }
    return 'file://' + path;
  }
}
