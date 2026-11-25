import { url } from '@kit.ArkTS';
import { REQUEST_ID } from './T3Protocol';

const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const MAX_FILE_BYTES = 50 * 1024 * 1024;
const IMAGE_MIME_TYPES = new Set<string>(['image/gif', 'image/jpeg', 'image/png', 'image/webp']);
const IMAGE_EXTENSIONS = new Map<string, string>([
  ['gif', 'image/gif'], ['jpeg', 'image/jpeg'], ['jpg', 'image/jpeg'], ['png', 'image/png'], ['webp', 'image/webp'],
]);

export interface ThreadAttachmentMetadata {
  type: 'file' | 'image';
  name: string;
  mimeType: string;
  sizeBytes: number;
}

export interface PickedThreadAttachment extends ThreadAttachmentMetadata {
  uri: string;
}

export interface UploadedThreadAttachment extends ThreadAttachmentMetadata {
  id: string;
}

export interface ThreadAttachmentEnvironment {
  origin: () => string;
  rpc: (request: Object) => Promise<Object | undefined>;
}

export type AttachmentBinaryPost = (target: string, mimeType: string, body: ArrayBuffer) => Promise<number>;

interface AttachmentRpcRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: Object;
  headers: string[][];
}

interface AttachmentUploadSlot {
  attachmentId: string;
  relativeUrl: string;
  expiresAt: number;
}

interface DeleteAttachmentInput {
  attachmentId: string;
}

function validMime(value: string): boolean {
  return typeof value === 'string' && value.length <= 100 &&
    /^[a-z0-9!#$&^_.+-]+\/[a-z0-9!#$&^_.+-]+$/i.test(value);
}

export function validateThreadAttachment(metadata: ThreadAttachmentMetadata): void {
  if (!metadata.name || metadata.name.length > 255 || metadata.name.trim() !== metadata.name ||
    /[\x00-\x1f\x7f/]/.test(metadata.name)) throw new Error('附件文件名无效。');
  const image = metadata.type === 'image';
  if ((!image && metadata.type !== 'file') || !validMime(metadata.mimeType) ||
    (image && !IMAGE_MIME_TYPES.has(metadata.mimeType))) throw new Error('附件文件类型无效。');
  if (!Number.isSafeInteger(metadata.sizeBytes) || metadata.sizeBytes < 1 ||
    metadata.sizeBytes > (image ? MAX_IMAGE_BYTES : MAX_FILE_BYTES)) {
    throw new Error(image ? '图片需小于或等于 10 MB，且不能为空。' : '文件需小于或等于 50 MB，且不能为空。');
  }
}

export function describeThreadAttachment(name: string, mimeType: string | undefined, sizeBytes: number,
  photosOnly: boolean = false): ThreadAttachmentMetadata {
  const normalizedMime = mimeType?.trim().toLowerCase() ?? '';
  const extension = name.slice(name.lastIndexOf('.') + 1).toLowerCase();
  const imageMime = IMAGE_MIME_TYPES.has(normalizedMime) ? normalizedMime : IMAGE_EXTENSIONS.get(extension);
  if (photosOnly && !imageMime) throw new Error('请选择 JPEG、PNG、GIF 或 WebP 图片。');
  const metadata: ThreadAttachmentMetadata = {
    name: name.trim(),
    mimeType: imageMime ?? (validMime(normalizedMime) ? normalizedMime : 'application/octet-stream'),
    sizeBytes,
    type: photosOnly || (imageMime !== undefined && sizeBytes <= MAX_IMAGE_BYTES) ? 'image' : 'file',
  };
  validateThreadAttachment(metadata);
  return metadata;
}

export function attachmentUploadRequest(metadata: ThreadAttachmentMetadata): AttachmentRpcRequest {
  validateThreadAttachment(metadata);
  const payload: ThreadAttachmentMetadata = {
    type: metadata.type, name: metadata.name, mimeType: metadata.mimeType, sizeBytes: metadata.sizeBytes,
  };
  return { _tag: 'Request', id: REQUEST_ID, tag: 'attachments.createUploadUrl', payload, headers: [] };
}

function validAttachmentId(value: string): boolean {
  return typeof value === 'string' && /^pending-[a-z0-9_-]{1,120}$/i.test(value);
}

export async function deletePendingThreadAttachment(attachmentId: string,
  environment: ThreadAttachmentEnvironment): Promise<void> {
  if (!validAttachmentId(attachmentId)) throw new Error('暂存附件标识无效。');
  const payload: DeleteAttachmentInput = { attachmentId };
  const request: AttachmentRpcRequest = {
    _tag: 'Request', id: REQUEST_ID, tag: 'attachments.delete', payload, headers: [],
  };
  await environment.rpc(request);
}

function attachmentUploadTarget(origin: string, relativeUrl: string): string {
  if (typeof relativeUrl !== 'string' || relativeUrl.length > 4096 ||
    !/^\/api\/attachments\/upload\/(?!\.{1,2}$)[\w.-]+$/.test(relativeUrl) ||
    !/^https?:\/\/[^/\\?#\s]+\/?$/i.test(origin)) throw new Error('环境返回的附件上传地址无效。');
  const base = url.URL.parseURL(origin);
  if (!base.hostname || base.username || base.password || (base.protocol !== 'https:' && base.protocol !== 'http:')) {
    throw new Error('环境返回的附件上传地址无效。');
  }
  return base.protocol + '//' + base.host + relativeUrl;
}

function imageHeaderMatches(bytes: Uint8Array, mimeType: string): boolean {
  switch (mimeType) {
    case 'image/jpeg':
      return bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
    case 'image/png':
      return bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 && bytes[3] === 71 &&
        bytes[4] === 13 && bytes[5] === 10 && bytes[6] === 26 && bytes[7] === 10;
    case 'image/gif':
      return bytes[0] === 71 && bytes[1] === 73 && bytes[2] === 70 && bytes[3] === 56 &&
        (bytes[4] === 55 || bytes[4] === 57) && bytes[5] === 97;
    case 'image/webp':
      return bytes[0] === 82 && bytes[1] === 73 && bytes[2] === 70 && bytes[3] === 70 &&
        bytes[8] === 87 && bytes[9] === 69 && bytes[10] === 66 && bytes[11] === 80;
    default:
      return false;
  }
}

export async function uploadThreadAttachment(metadata: ThreadAttachmentMetadata, bytes: ArrayBuffer,
  environment: ThreadAttachmentEnvironment, post: AttachmentBinaryPost): Promise<UploadedThreadAttachment> {
  const request = attachmentUploadRequest(metadata);
  if (bytes.byteLength !== metadata.sizeBytes) throw new Error('附件大小已更改，请重新选择。');
  if (metadata.type === 'image' && !imageHeaderMatches(new Uint8Array(bytes), metadata.mimeType)) {
    throw new Error('图片格式与文件内容不符。');
  }
  const slot = await environment.rpc(request) as AttachmentUploadSlot | undefined;
  if (!slot || !validAttachmentId(slot.attachmentId)) throw new Error('环境返回的附件上传标识无效。');
  try {
    if (!Number.isSafeInteger(slot.expiresAt) || slot.expiresAt <= Date.now()) {
      throw new Error('附件上传凭据已失效，请重试。');
    }
    const target = attachmentUploadTarget(environment.origin(), slot.relativeUrl);
    const status = await post(target, metadata.mimeType, bytes);
    if (status !== 204) throw new Error(`附件上传失败（HTTP ${status}）。`);
    environment.origin();
    return {
      id: slot.attachmentId, name: metadata.name, mimeType: metadata.mimeType,
      sizeBytes: metadata.sizeBytes, type: metadata.type,
    };
  } catch (error) {
    try {
      await deletePendingThreadAttachment(slot.attachmentId, environment);
    } catch (_) {
      // The environment expires pending uploads when it can no longer be reached.
    }
    throw error as Error;
  }
}
