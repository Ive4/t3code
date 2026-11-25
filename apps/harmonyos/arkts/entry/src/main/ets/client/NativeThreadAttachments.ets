import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { http } from '@kit.NetworkKit';
import type { PickedThreadAttachment, ThreadAttachmentEnvironment, UploadedThreadAttachment } from './ThreadAttachmentProtocol';
import {
  deletePendingThreadAttachment, describeThreadAttachment, uploadThreadAttachment, validateThreadAttachment,
} from './ThreadAttachmentProtocol';

export type { PickedThreadAttachment, ThreadAttachmentEnvironment, UploadedThreadAttachment } from './ThreadAttachmentProtocol';

function validatePickerLimit(limit: number): void {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new Error('附件选择数量无效。');
}

function pickerName(uri: string): string {
  try {
    return new fileUri.FileUri(uri).name || 'attachment';
  } catch (_) {
    return 'attachment';
  }
}

function pickerMime(name: string): string | undefined {
  const dot = name.lastIndexOf('.');
  if (dot < 0 || dot === name.length - 1) return undefined;
  try {
    const type = utd.getUniformDataTypeByFilenameExtension(name.slice(dot).toLowerCase());
    return utd.getTypeDescriptor(type)?.mimeTypes.find((mimeType: string) => !mimeType.includes('*'));
  } catch (_) {
    return undefined;
  }
}

async function openReadOnly(uri: string, name: string): Promise<fileIo.File> {
  try {
    return await fileIo.open(uri, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NONBLOCK);
  } catch (_) {
    throw new Error(`无法读取「${name}」，请重新选择。`);
  }
}

async function readSelectedAttachment(attachment: PickedThreadAttachment): Promise<ArrayBuffer> {
  validateThreadAttachment(attachment);
  const file = await openReadOnly(attachment.uri, attachment.name);
  try {
    const stat = await fileIo.stat(file.fd);
    if (!stat.isFile() || stat.size !== attachment.sizeBytes) throw new Error('附件已变更，请重新选择。');
    const bytes = new Uint8Array(attachment.sizeBytes);
    const chunk = new ArrayBuffer(64 * 1024);
    let offset = 0;
    while (offset < bytes.length) {
      const length = await fileIo.read(file.fd, chunk, { length: Math.min(chunk.byteLength, bytes.length - offset) });
      if (length <= 0) throw new Error('附件已变更，请重新选择。');
      bytes.set(new Uint8Array(chunk, 0, length), offset);
      offset += length;
    }
    return bytes.buffer;
  } finally {
    await fileIo.close(file);
  }
}

async function postAttachmentBytes(target: string, mimeType: string, body: ArrayBuffer): Promise<number> {
  const request = http.createHttp();
  try {
    const response = await request.request(target, {
      method: http.RequestMethod.POST,
      header: { 'content-type': mimeType },
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      maxRedirects: 0,
      remoteValidation: 'system',
      connectTimeout: 15000,
      readTimeout: 60000,
      maxLimit: 64 * 1024,
    });
    return response.responseCode;
  } catch (_) {
    throw new Error('无法上传附件，请检查环境连接后重试。');
  } finally {
    request.destroy();
  }
}

export class NativeThreadAttachments {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async pickDocuments(limit: number): Promise<PickedThreadAttachment[]> {
    validatePickerLimit(limit);
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = limit;
    const uris = await new picker.DocumentViewPicker(this.context).select(options);
    return this.describeSelection(uris, false);
  }

  async pickPhotos(limit: number): Promise<PickedThreadAttachment[]> {
    validatePickerLimit(limit);
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.maxSelectNumber = limit;
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    const selected = await new photoAccessHelper.PhotoViewPicker().select(options);
    return this.describeSelection(selected.photoUris, true);
  }

  async upload(attachment: PickedThreadAttachment, environment: ThreadAttachmentEnvironment): Promise<UploadedThreadAttachment> {
    const bytes = await readSelectedAttachment(attachment);
    return uploadThreadAttachment(attachment, bytes, environment, postAttachmentBytes);
  }

  async deletePending(attachmentId: string, environment: ThreadAttachmentEnvironment): Promise<void> {
    await deletePendingThreadAttachment(attachmentId, environment);
  }

  private async describeSelection(uris: string[], photosOnly: boolean): Promise<PickedThreadAttachment[]> {
    const attachments: PickedThreadAttachment[] = [];
    for (const uri of uris) {
      const name = pickerName(uri);
      const handle = await openReadOnly(uri, name);
      try {
        const stat = await fileIo.stat(handle.fd);
        if (!stat.isFile()) throw new Error('请选择一个可读取的文件。');
        const metadata = describeThreadAttachment(name, pickerMime(name), stat.size, photosOnly);
        attachments.push({
          uri, name: metadata.name, mimeType: metadata.mimeType, type: metadata.type, sizeBytes: metadata.sizeBytes,
        });
      } finally {
        await fileIo.close(handle);
      }
    }
    return attachments;
  }
}
