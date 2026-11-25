import { threadAttachmentCachePath } from './ThreadAttachmentCachePath';
import { wantConstant } from '@kit.AbilityKit';
import type { common, Want } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { filePreview } from '@kit.PreviewKit';
import { systemShare } from '@kit.ShareKit';

const FILE_PREVIEW_CAPABILITY = 'SystemCapability.FileManagement.FilePreview.Core';
const SHARE_CAPABILITY = 'SystemCapability.Collaboration.SystemShare';
const PHOTO_CAPABILITY = 'SystemCapability.FileManagement.PhotoAccessHelper.Core';
const GENERIC_MIME = 'application/octet-stream';

export interface ThreadAttachmentActionFile {
  uri: string;
  name: string;
  mimeType: string;
}

function normalizedMimeType(value: string): string {
  const type = value.split(';', 1)[0].trim().toLowerCase();
  return /^[a-z0-9][a-z0-9!#$&^_.+-]*\/[a-z0-9][a-z0-9!#$&^_.+-]*$/.test(type) ? type : GENERIC_MIME;
}

function attachmentName(value: string): string {
  const basename = value.split(/[\\/]/).pop() ?? '';
  return Array.from(basename.replace(/[\x00-\x1f\x7f-\x9f]/g, '').trim()).slice(0, 120).join('') || '附件';
}

function attachmentDataType(name: string, mimeType: string): string {
  if (mimeType !== GENERIC_MIME) return utd.getUniformDataTypeByMIMEType(mimeType);
  const extension = /\.([a-z0-9]{1,16})$/i.exec(name)?.[1];
  return extension ? utd.getUniformDataTypeByFilenameExtension(extension.toLowerCase()) : utd.UniformDataType.FILE;
}

function imageExtension(mimeType: string): string | undefined {
  const extension = /^image\/(png|jpe?g|gif|webp|heic|heif)$/.exec(normalizedMimeType(mimeType))?.[1];
  return extension === 'jpeg' ? 'jpg' : extension;
}

export class ThreadAttachmentFileActions {
  private sharing: boolean = false;
  private saving: boolean = false;

  canShare(): boolean {
    return canIUse(SHARE_CAPABILITY);
  }

  canSaveImage(mimeType: string): boolean {
    return canIUse(PHOTO_CAPABILITY) && imageExtension(mimeType) !== undefined;
  }

  async open(context: common.UIAbilityContext, file: ThreadAttachmentActionFile): Promise<void> {
    const path = await threadAttachmentCachePath(file.uri, context.cacheDir);
    const uri = fileUri.getUriFromPath(path);
    const mimeType = normalizedMimeType(file.mimeType);
    if (canIUse(FILE_PREVIEW_CAPABILITY)) {
      try {
        if (await filePreview.canPreview(context, uri)) {
          await filePreview.openPreview(context, { uri, mimeType: mimeType === GENERIC_MIME ? '' : mimeType });
          return;
        }
      } catch (_) {}
    }
    const want: Want = {
      action: 'ohos.want.action.viewData', uri, flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION,
    };
    if (mimeType !== GENERIC_MIME) want.type = mimeType;
    try {
      await context.startAbility(want);
    } catch (_) {
      throw new Error('无法在文件查看器中打开此附件。');
    }
  }

  async share(context: common.UIAbilityContext, file: ThreadAttachmentActionFile): Promise<void> {
    if (!this.canShare()) throw new Error('当前设备不支持系统分享。');
    if (this.sharing) throw new Error('分享面板已打开。');
    this.sharing = true;
    try {
      const path = await threadAttachmentCachePath(file.uri, context.cacheDir);
      const name = attachmentName(file.name);
      const data = new systemShare.SharedData({
        utd: attachmentDataType(name, normalizedMimeType(file.mimeType)),
        uri: fileUri.getUriFromPath(path),
        title: name,
      });
      const controller = new systemShare.ShareController(data);
      await new Promise<void>((resolve, reject) => {
        const onDismiss = (): void => {
          controller.off('dismiss', onDismiss);
          resolve();
        };
        controller.on('dismiss', onDismiss);
        void controller.show(context, { selectionMode: systemShare.SelectionMode.SINGLE }).catch((error: Error) => {
          controller.off('dismiss', onDismiss);
          reject(error);
        });
      });
    } finally {
      this.sharing = false;
    }
  }

  async saveImage(context: common.UIAbilityContext, file: ThreadAttachmentActionFile): Promise<boolean> {
    const extension = imageExtension(file.mimeType);
    if (!canIUse(PHOTO_CAPABILITY) || !extension) throw new Error('当前设备不支持保存此图片格式。');
    if (this.saving) throw new Error('保存确认面板已打开。');
    this.saving = true;
    try {
      const path = await threadAttachmentCachePath(file.uri, context.cacheDir);
      const title = attachmentName(file.name).replace(/\.[a-z0-9]+$/i, '')
        .replace(/[<>{}\[\]:*?"'`|.]/g, '_').trim();
      const config: photoAccessHelper.PhotoCreationConfig = {
        fileNameExtension: extension, photoType: photoAccessHelper.PhotoType.IMAGE,
      };
      if (title) config.title = Array.from(title).slice(0, 60).join('');
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const assetUris = await helper.showAssetsCreationDialog([fileUri.getUriFromPath(path)], [config]);
      const assetUri = assetUris[0];
      if (!assetUri) return false;
      const destination = await fileIo.open(assetUri, fileIo.OpenMode.WRITE_ONLY);
      try {
        await fileIo.copyFile(path, destination.fd);
      } finally {
        await fileIo.close(destination);
      }
      return true;
    } finally {
      this.saving = false;
    }
  }
}
