import { Want, wantConstant } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { filePreview } from '@kit.PreviewKit';
import { UITurboModule } from '@rnoh/react-native-openharmony';
import { sandboxFilePath } from './SharingModule';

const PREVIEW_CAPABILITY = 'SystemCapability.FileManagement.FilePreview.Core';
export const PDF_CAPABILITY = 'SystemCapability.OfficeService.PDFService.Core';
const IMAGE_EXTENSION = /^(png|jpe?g|gif|webp|heic|heif)$/;

export class FileActionsModule extends UITurboModule {
  private saving = false;

  public isInlinePdfAvailable(): boolean {
    return canIUse(PDF_CAPABILITY);
  }

  public async openFile(uri: string, mimeType: string): Promise<void> {
    const context = this.ctx.uiAbilityContext;
    const path = await sandboxFilePath(uri, context);
    const viewerUri = fileUri.getUriFromPath(path);
    const type = mimeType === 'application/octet-stream' ? '' : mimeType;
    if (canIUse(PREVIEW_CAPABILITY)) {
      try {
        if (await filePreview.canPreview(context, viewerUri)) {
          await filePreview.openPreview(context, { uri: viewerUri, mimeType: type });
          return;
        }
      } catch (error) {
        console.warn('[t3-file-actions] Preview Kit could not open the file.');
      }
    }

    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: viewerUri,
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION,
    };
    if (type) want.type = type;
    try {
      await context.startAbility(want);
    } catch (error) {
      throw new Error('The file cannot be previewed.');
    }
  }

  public async saveImageToLibrary(uri: string, mimeType: string, name: string): Promise<boolean> {
    const imageType = mimeType.toLowerCase().split('/');
    const format = imageType[1] ?? '';
    if (imageType[0] !== 'image' || imageType.length !== 2 || !IMAGE_EXTENSION.test(format)) {
      throw new Error('Unsupported image format.');
    }
    if (this.saving) throw new Error('The photo save confirmation is already open.');
    this.saving = true;
    try {
      const context = this.ctx.uiAbilityContext;
      const path = await sandboxFilePath(uri, context);
      const sourceUri = fileUri.getUriFromPath(path);
      const title = name.split(/[\\/]/).pop()?.replace(/\.[a-z0-9]+$/i, '')
        .replace(/[<>{}\[\]:*?"'`|.\x00-\x1f\x7f-\x9f]/g, '_').trim();
      const config: photoAccessHelper.PhotoCreationConfig = {
        fileNameExtension: format === 'jpeg' ? 'jpg' : format,
        photoType: photoAccessHelper.PhotoType.IMAGE,
      };
      if (title) config.title = Array.from(title).slice(0, 60).join('');
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const assetUris = await helper.showAssetsCreationDialog([sourceUri], [config]);
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
