import { url } from '@kit.ArkTS';
import { readThreadAttachment, REQUEST_ID } from './T3Protocol';
import type { NativeThreadAttachment } from './T3Protocol';
import type { ThreadAttachmentEnvironment } from './ThreadAttachmentProtocol';

export type ThreadAttachmentDisposition = 'inline' | 'attachment';

export interface ThreadAttachmentAssetUrl {
  url: string;
  expiresAt: number;
}

interface AttachmentResource {
  _tag: 'attachment';
  attachmentId: string;
  fileName: string;
  mimeType: string;
  disposition?: ThreadAttachmentDisposition;
}

interface AssetUrlPayload {
  resource: AttachmentResource;
}

interface AssetUrlRequest {
  _tag: 'Request';
  id: string;
  tag: string;
  payload: AssetUrlPayload;
  headers: string[][];
}

interface AssetUrlResult {
  relativeUrl: string;
  expiresAt: number;
}

const ASSET_ROUTE = /^\/api\/assets\/(?!\.{1,2}\/)[\w.-]+\/(?!(?:\.|%2[eE]){1,2}$)[^/\\?#\s\x00-\x1f\x7f]+$/u;

export async function requestThreadAttachmentAssetUrl(attachment: NativeThreadAttachment,
  environment: ThreadAttachmentEnvironment, disposition?: ThreadAttachmentDisposition): Promise<ThreadAttachmentAssetUrl> {
  const metadata = readThreadAttachment(attachment);
  if (!metadata) throw new Error('消息附件信息无效。');
  const resource: AttachmentResource = { _tag: 'attachment', attachmentId: metadata.id,
    fileName: metadata.name, mimeType: metadata.mimeType };
  if (disposition) resource.disposition = disposition;
  const request: AssetUrlRequest = {
    _tag: 'Request', id: REQUEST_ID, tag: 'assets.createUrl', payload: { resource }, headers: [],
  };
  const reply = await environment.rpc(request) as AssetUrlResult | undefined;
  const origin = environment.origin();
  if (!reply || typeof reply.relativeUrl !== 'string' || reply.relativeUrl.length > 4096 ||
    !ASSET_ROUTE.test(reply.relativeUrl) || !Number.isFinite(reply.expiresAt) || reply.expiresAt <= Date.now() ||
    !/^https?:\/\/[^/\\?#\s]+\/?$/i.test(origin)) throw new Error('环境返回的附件预览地址无效或已过期。');
  const base = url.URL.parseURL(origin);
  if (!base.hostname || base.username || base.password || (base.protocol !== 'https:' && base.protocol !== 'http:')) {
    throw new Error('环境返回的附件预览地址无效。');
  }
  return { url: base.protocol + '//' + base.host + reply.relativeUrl, expiresAt: reply.expiresAt };
}
