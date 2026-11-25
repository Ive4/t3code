import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import type { NativeThreadAttachment } from './T3Protocol';
import type { ThreadAttachmentAssetUrl } from './ThreadAttachmentAssetProtocol';

const MAX_TEXT_BYTES = 1024 * 1024;
const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
export const MAX_ATTACHMENT_ACTION_BYTES = 50 * 1024 * 1024;

export interface NativeThreadAttachmentPreview {
  uri?: string;
  text?: string;
  truncated?: boolean;
}

export function threadAttachmentPreviewKind(attachment: NativeThreadAttachment): 'image' | 'file' {
  return attachment.type === 'image' || /^image\//i.test(attachment.mimeType) ? 'image' : 'file';
}

export function isPdfThreadAttachment(attachment: NativeThreadAttachment): boolean {
  const mime = attachment.mimeType.toLowerCase().split(';')[0].trim();
  return mime === 'application/pdf' || (mime === 'application/octet-stream' && /\.pdf$/i.test(attachment.name));
}

export function isVideoThreadAttachment(attachment: NativeThreadAttachment): boolean {
  const mime = attachment.mimeType.toLowerCase().split(';')[0].trim();
  return mime.startsWith('video/') ||
    (mime === 'application/octet-stream' && /\.(mp4|m4v|mov|mkv|webm|ts)$/i.test(attachment.name));
}

export function isTextThreadAttachment(attachment: NativeThreadAttachment): boolean {
  const mime = attachment.mimeType.toLowerCase().split(';')[0].trim();
  return mime.startsWith('text/') || /^(application\/(json|[\w.-]+\+json|xml|[\w.-]+\+xml|javascript|yaml|toml|sql))$/.test(mime) ||
    (mime === 'application/octet-stream' && /\.(txt|md|log|json|csv|xml|yaml|yml|ini|ts|js|py|go|rs|diff|patch)$/i.test(attachment.name));
}

export class NativeThreadAttachmentPreviewRequest {
  private httpRequest?: http.HttpRequest = undefined;
  private cancelled: boolean = false;

  cancel(): void {
    this.cancelled = true;
    this.httpRequest?.destroy();
    this.httpRequest = undefined;
  }

  async read(asset: ThreadAttachmentAssetUrl, attachment: NativeThreadAttachment,
    cacheDir: string, fullFile: boolean = false): Promise<NativeThreadAttachmentPreview> {
    if (this.cancelled || asset.expiresAt <= Date.now()) throw new Error('附件链接已失效，请重试。');
    const image = threadAttachmentPreviewKind(attachment) === 'image';
    const ranged = !image && !fullFile;
    const limit = fullFile ? MAX_ATTACHMENT_ACTION_BYTES : image ? MAX_IMAGE_BYTES : MAX_TEXT_BYTES + 1;
    if (!ranged && attachment.sizeBytes > limit) {
      throw new Error(fullFile ? '附件超过 50 MB。' : '图片超过 10 MB，无法预览。');
    }
    const request = http.createHttp();
    this.httpRequest = request;
    const header: Record<string, string> = {};
    if (ranged) header['Range'] = `bytes=0-${MAX_TEXT_BYTES}`;
    let bytes: ArrayBuffer;
    try {
      const response = await request.request(asset.url, {
        method: http.RequestMethod.GET, header, expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false, maxRedirects: 0, remoteValidation: 'system',
        connectTimeout: 15000, readTimeout: 30000, maxLimit: limit,
      });
      if (this.cancelled || (response.responseCode !== 200 && (!ranged || response.responseCode !== 206)) ||
        !(response.result instanceof ArrayBuffer)) throw new Error('无法从当前环境读取附件。');
      bytes = response.result;
    } finally {
      if (this.httpRequest === request) {
        request.destroy();
        this.httpRequest = undefined;
      }
    }
    if (ranged) {
      const body = new Uint8Array(bytes, 0, Math.min(bytes.byteLength, MAX_TEXT_BYTES));
      const text = util.TextDecoder.create('utf-8').decodeToString(body);
      if (text.includes('\0')) throw new Error('此文件无法以文本打开。');
      return { text, truncated: bytes.byteLength > MAX_TEXT_BYTES || attachment.sizeBytes > body.byteLength };
    }
    if (bytes.byteLength > limit || bytes.byteLength !== attachment.sizeBytes) throw new Error('附件文件大小无效。');
    const basename = attachment.name.split(/[\\/]/).pop() ?? '';
    const safeName = Array.from(basename.replace(/[<>:"|?*%#\x00-\x1f\x7f]/g, '_').trim()).slice(0, 80).join('');
    const directory = await fileIo.mkdtemp(cacheDir + '/t3-thread-preview-XXXXXX');
    const path = directory + '/' + (safeName && safeName !== '.' && safeName !== '..' ? safeName : '附件');
    const uri = 'file://' + encodeURI(path);
    try {
      const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        if (await fileIo.write(file.fd, bytes) !== bytes.byteLength) throw new Error('图片写入不完整。');
      } finally {
        await fileIo.close(file);
      }
      if (this.cancelled) throw new Error('图片预览已关闭。');
      return { uri };
    } catch (error) {
      await removeThreadAttachmentPreview(uri);
      throw error as Error;
    }
  }
}

export async function removeThreadAttachmentPreview(uri: string | undefined): Promise<void> {
  if (!uri || !uri.startsWith('file://')) return;
  const path = decodeURI(uri.slice('file://'.length));
  const directory = path.slice(0, path.lastIndexOf('/'));
  if (!/\/t3-thread-preview-[^/]+$/.test(directory)) return;
  await fileIo.unlink(path).catch(() => {});
  await fileIo.rmdir(directory).catch(() => {});
}
