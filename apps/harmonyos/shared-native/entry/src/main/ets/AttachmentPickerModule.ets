import { dataSharePredicates, uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { UITurboModule } from '@rnoh/react-native-openharmony';

interface SelectedAttachment {
  uri: string;
  name: string;
  mimeType?: string;
  size?: number;
  type?: string;
  width?: number;
  height?: number;
}

function validateLimit(limit: number): void {
  if (!Number.isInteger(limit) || limit < 1 || limit > 500) {
    throw new RangeError('Invalid attachment selection limit');
  }
}

function filename(uri: string): string {
  try {
    return new fileUri.FileUri(uri).name || 'attachment';
  } catch {
    return 'attachment';
  }
}

function mimeType(name: string): string | undefined {
  const dot = name.lastIndexOf('.');
  if (dot <= 0 || dot === name.length - 1) return undefined;
  try {
    const typeId = utd.getUniformDataTypeByFilenameExtension(name.slice(dot).toLowerCase());
    return utd.getTypeDescriptor(typeId)?.mimeTypes.find((type: string) => !type.includes('*'));
  } catch {
    return undefined;
  }
}

async function documentMetadata(uri: string): Promise<SelectedAttachment> {
  const name = filename(uri);
  const attachment: SelectedAttachment = { uri, name, mimeType: mimeType(name) };
  try {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NONBLOCK);
    try {
      attachment.size = (await fileIo.stat(file.fd)).size;
    } finally {
      await fileIo.close(file);
    }
  } catch {
    // The composer reports unreadable files individually when it copies the selection.
  }
  return attachment;
}

async function mediaMetadata(
  helper: photoAccessHelper.PhotoAccessHelper,
  uri: string,
  allowVideo: boolean,
): Promise<SelectedAttachment> {
  const name = filename(uri);
  const inferredMimeType = mimeType(name);
  const attachment: SelectedAttachment = { uri, name, mimeType: inferredMimeType };
  if (inferredMimeType?.startsWith('video/')) {
    attachment.type = 'video';
  } else if (!allowVideo || inferredMimeType?.startsWith('image/')) {
    attachment.type = 'image';
  }

  try {
    const predicates = new dataSharePredicates.DataSharePredicates();
    predicates.equalTo(photoAccessHelper.PhotoKeys.URI, uri);
    const result = await helper.getAssets({
      predicates,
      fetchColumns: [
        photoAccessHelper.PhotoKeys.SIZE,
        photoAccessHelper.PhotoKeys.WIDTH,
        photoAccessHelper.PhotoKeys.HEIGHT,
      ],
    });
    try {
      if (result.getCount() === 0) return attachment;
      const asset = await result.getFirstObject();
      attachment.name = asset.displayName || name;
      attachment.mimeType = mimeType(attachment.name);
      attachment.type = asset.photoType === photoAccessHelper.PhotoType.VIDEO ? 'video' : 'image';
      const size = asset.get(photoAccessHelper.PhotoKeys.SIZE);
      const width = asset.get(photoAccessHelper.PhotoKeys.WIDTH);
      const height = asset.get(photoAccessHelper.PhotoKeys.HEIGHT);
      if (typeof size === 'number') attachment.size = size;
      if (typeof width === 'number') attachment.width = width;
      if (typeof height === 'number') attachment.height = height;
    } finally {
      result.close();
    }
  } catch {
    // Picker metadata is optional. The URI still goes through the composer's file checks.
  }
  return attachment;
}

export class AttachmentPickerModule extends UITurboModule {
  public async pickDocuments(limit: number): Promise<SelectedAttachment[]> {
    validateLimit(limit);
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = limit;
    const uris = await new picker.DocumentViewPicker(this.ctx.uiAbilityContext).select(options);
    const attachments: SelectedAttachment[] = [];
    for (const uri of uris) {
      attachments.push(await documentMetadata(uri));
    }
    return attachments;
  }

  public async pickMedia(limit: number, allowVideo: boolean): Promise<SelectedAttachment[]> {
    validateLimit(limit);
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.maxSelectNumber = limit;
    options.MIMEType = allowVideo
      ? photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE
      : photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    const selection = await new photoAccessHelper.PhotoViewPicker().select(options);
    const attachments: SelectedAttachment[] = [];
    if (selection.photoUris.length === 0) return attachments;
    const helper = photoAccessHelper.getPhotoAccessHelper(this.ctx.uiAbilityContext);
    for (const uri of selection.photoUris) {
      attachments.push(await mediaMetadata(helper, uri, allowVideo));
    }
    return attachments;
  }
}
