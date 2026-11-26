import { common, Want, wantConstant } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { UITurboModule } from '@rnoh/react-native-openharmony';

const SEND_DATA_ACTION = 'ohos.want.action.sendData';
const SHARE_CAPABILITY = 'SystemCapability.Collaboration.SystemShare';
const CHANGE_EVENT = 'T3IncomingShareChanged';
const MAX_FILE_BYTES = 50 * 1024 * 1024;
const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const MAX_HANDOFF_BYTES = 100 * 1024 * 1024;
const MAX_HANDOFFS = 4;

interface ShareStagingIssue {
  maxBytes?: number;
}

class ShareFileLimitError extends Error {}

interface SharePayload {
  value: string;
  shareType: string;
  mimeType: string;
  originalName: string | null;
  stagingIssue?: ShareStagingIssue;
}

interface ResolvedSharePayload extends SharePayload {
  contentUri: string | null;
  contentType: string;
  contentMimeType: string | null;
  contentSize: number | null;
}

interface IncomingShare {
  payloads: ResolvedSharePayload[];
  directory: string | null;
}

const incomingShares: IncomingShare[] = [];
let watchIncomingShares: (() => void) | undefined;
let captureQueue: Promise<void> = Promise.resolve();
let pendingCaptures = 0;

function fileAuthority(uri: string): string | undefined {
  return /^file:\/\/([a-z0-9._-]+)\//i.exec(uri)?.[1];
}

function localFileUrl(path: string): string {
  return 'file://' + path.split('/').map((part: string) => encodeURIComponent(part)).join('/');
}

function mimeTypeFor(utdId: string, name: string): string {
  const mime = utd.getTypeDescriptor(utdId)?.mimeTypes.find((type: string) => !type.includes('*'));
  if (mime) return mime;
  const dot = name.lastIndexOf('.');
  if (dot > 0 && dot < name.length - 1) {
    const extensionType = utd.getUniformDataTypeByFilenameExtension(name.slice(dot).toLowerCase());
    const inferred = utd.getTypeDescriptor(extensionType)?.mimeTypes.find((type: string) => !type.includes('*'));
    if (inferred) return inferred;
  }
  return 'application/octet-stream';
}

function classifiedFileType(mimeType: string): string {
  const family = mimeType.split('/')[0];
  return family === 'image' || family === 'video' || family === 'audio' ? family : 'file';
}

async function copySharedFile(uri: string, path: string, maxBytes: number): Promise<number> {
  const source = await fs.open(uri, fs.OpenMode.READ_ONLY | fs.OpenMode.NONBLOCK);
  try {
    const info = await fs.stat(source.fd);
    if (!info.isFile()) throw new Error('Shared item cannot be opened as a file.');
    if (info.size > maxBytes) throw new ShareFileLimitError();
    const destination = await fs.open(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      const buffer = new ArrayBuffer(64 * 1024);
      let size = 0;
      while (true) {
        const count = await fs.read(source.fd, buffer, { length: Math.min(buffer.byteLength, maxBytes - size + 1) });
        if (count === 0) return size;
        if (count > maxBytes - size) throw new ShareFileLimitError();
        const written = await fs.write(destination.fd, buffer, { length: count });
        if (written !== count) throw new Error('Unable to write the complete shared file.');
        size += count;
      }
    } finally {
      await fs.close(destination);
    }
  } finally {
    await fs.close(source);
  }
}

async function recordsFromWant(want: Want): Promise<systemShare.SharedRecord[]> {
  try {
    return (await systemShare.getSharedData(want)).getRecords();
  } catch (error) {
    if (!want.uri || !((want.flags ?? 0) & wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION)) {
      throw new Error('Share Kit did not expose readable records for this request.');
    }
    return [{
      utd: want.type ? utd.getUniformDataTypeByMIMEType(want.type) : utd.UniformDataType.FILE,
      uri: want.uri,
    }];
  }
}

function releaseStaging(directory: string | null): void {
  if (directory === null) return;
  void fs.rmdir(directory).catch(() => {
    console.warn('[t3-sharing] Could not remove the shared-file staging directory.');
  });
}

function failedFile(name: string | null, stagingIssue: ShareStagingIssue): ResolvedSharePayload {
  return {
    value: '',
    shareType: 'file',
    mimeType: 'application/octet-stream',
    originalName: name,
    stagingIssue,
    contentUri: null,
    contentType: 'file',
    contentMimeType: null,
    contentSize: null,
  };
}

async function stageWant(want: Want, cacheDir: string): Promise<void> {
  const owner = fileAuthority(fileUri.getUriFromPath(cacheDir));
  const share: IncomingShare = { payloads: [], directory: null };
  let records: systemShare.SharedRecord[] = [];
  try {
    records = await recordsFromWant(want);
  } catch {
    share.payloads.push(failedFile(null, {}));
  }
  let stagedBytes = 0;
  for (const record of records) {
    const content = record.content ?? '';
    if (content && (record.utd === utd.UniformDataType.HYPERLINK || record.utd === utd.UniformDataType.PLAIN_TEXT || record.utd === utd.UniformDataType.TEXT)) {
      const hyperlink = record.utd === utd.UniformDataType.HYPERLINK;
      share.payloads.push({
        value: content,
        shareType: hyperlink ? 'url' : 'text',
        mimeType: hyperlink ? 'text/uri-list' : 'text/plain',
        originalName: null,
        contentUri: hyperlink ? content : null,
        contentType: hyperlink ? 'website' : 'text',
        contentMimeType: null,
        contentSize: null,
      });
      continue;
    }

    const uri = record.uri;
    const source = uri ? fileAuthority(uri) : undefined;
    if (!uri || !owner || !source || source.toLowerCase() === owner.toLowerCase()) {
      share.payloads.push(failedFile(null, {}));
      continue;
    }
    let path: string | undefined;
    let name: string | null = null;
    let maxBytes = 0;
    try {
      name = new fileUri.FileUri(uri).name.split(/[\/\\]/).pop() || 'attachment';
      const mimeType = mimeTypeFor(record.utd, name);
      const shareType = classifiedFileType(mimeType);
      maxBytes = Math.min(shareType === 'image' ? MAX_IMAGE_BYTES : MAX_FILE_BYTES, MAX_HANDOFF_BYTES - stagedBytes);
      if (maxBytes <= 0) throw new ShareFileLimitError();
      share.directory ??= await fs.mkdtemp(cacheDir + '/t3-incoming-share-XXXXXX');
      path = share.directory + '/' + share.payloads.length;
      const size = await copySharedFile(uri, path, maxBytes);
      if (size === 0) throw new Error('Shared file is empty.');
      stagedBytes += size;
      const value = localFileUrl(path);
      share.payloads.push({
        value,
        shareType,
        mimeType,
        originalName: name,
        contentUri: value,
        contentType: shareType,
        contentMimeType: mimeType,
        contentSize: size,
      });
    } catch (error) {
      if (path) await fs.unlink(path).catch(() => {});
      share.payloads.push(failedFile(name, error instanceof ShareFileLimitError ? { maxBytes } : {}));
    }
  }
  if (share.payloads.length === 0) {
    releaseStaging(share.directory);
    return;
  }
  incomingShares.push(share);
  watchIncomingShares?.();
}

// Incoming file grants belong to the Want, so stage them before exposing a draft to JavaScript.
export function captureIncomingShare(want: Want, context: common.UIAbilityContext): boolean {
  if (want.action !== SEND_DATA_ACTION) return false;
  if (!canIUse(SHARE_CAPABILITY)) return true;
  if (pendingCaptures + incomingShares.length >= MAX_HANDOFFS) {
    console.warn('[t3-sharing] Too many pending shares.');
    return true;
  }
  pendingCaptures += 1;
  captureQueue = captureQueue.then(() => stageWant(want, context.cacheDir)).catch(() => {
    console.warn('[t3-sharing] Could not read the share handoff.');
  }).finally(() => {
    pendingCaptures -= 1;
  });
  return true;
}

export async function sandboxFilePath(uri: string, context: common.UIAbilityContext): Promise<string> {
  const encodedPath = /^file:\/\/\/([^?#]+)$/.exec(uri)?.[1];
  if (!encodedPath) throw new Error('Only local sandbox file URLs can be shared.');
  const parts = encodedPath.split('/').map((part: string) => decodeURIComponent(part));
  if (parts.some((part: string) => !part || part === '.' || part === '..' || /[\/\\\x00]/.test(part))) {
    throw new Error('The file URL is invalid.');
  }
  const path = '/' + parts.join('/');
  const root = [context.cacheDir, context.filesDir].find((candidate: string) => path.startsWith(candidate + '/'));
  if (!root) throw new Error('The file is outside app-owned storage.');

  const segments = path.slice(root.length + 1).split('/');
  let candidate = root;
  for (let i = 0; i < segments.length; i++) {
    candidate += '/' + segments[i];
    const stat = await fs.lstat(candidate);
    if (i === segments.length - 1 ? !stat.isFile() : !stat.isDirectory()) {
      throw new Error('Only regular files in app-owned storage can be shared.');
    }
  }
  return path;
}

function outgoingDataType(path: string, mime: string): string {
  if (mime && mime !== 'application/octet-stream') {
    return utd.getUniformDataTypeByMIMEType(mime);
  }
  const dot = path.lastIndexOf('.');
  return dot > path.lastIndexOf('/') && dot < path.length - 1
    ? utd.getUniformDataTypeByFilenameExtension(path.slice(dot).toLowerCase())
    : utd.UniformDataType.FILE;
}

export class SharingModule extends UITurboModule {
  private sharing = false;

  private readonly onIncomingShare = (): void => {
    this.ctx.rnInstance.emitDeviceEvent(CHANGE_EVENT, null);
  };

  public isIncomingSharingAvailable(): boolean {
    return canIUse(SHARE_CAPABILITY);
  }

  public async isAvailableAsync(): Promise<boolean> {
    return canIUse(SHARE_CAPABILITY);
  }

  public async shareAsync(uri: string, mimeType: string): Promise<void> {
    if (!await this.isAvailableAsync()) throw new Error('System sharing is unavailable on this device.');
    if (this.sharing) throw new Error('A sharing panel is already open.');
    this.sharing = true;
    try {
      const context = this.ctx.uiAbilityContext;
      const path = await sandboxFilePath(uri, context);
      const data = new systemShare.SharedData({
        utd: outgoingDataType(path, mimeType),
        uri: fileUri.getUriFromPath(path),
      });
      const controller = new systemShare.ShareController(data);
      await new Promise<void>((resolve, reject) => {
        const onDismiss = (): void => {
          controller.off('dismiss', onDismiss);
          resolve();
        };
        controller.on('dismiss', onDismiss);
        void controller.show(context, {
          selectionMode: systemShare.SelectionMode.SINGLE,
        }).catch((error: Error) => {
          controller.off('dismiss', onDismiss);
          reject(error);
        });
      });
    } finally {
      this.sharing = false;
    }
  }

  public getSharedPayloads(): SharePayload[] {
    return (incomingShares[0]?.payloads ?? []).map((payload: ResolvedSharePayload): SharePayload => ({
      value: payload.value,
      shareType: payload.shareType,
      mimeType: payload.mimeType,
      originalName: payload.originalName,
      stagingIssue: payload.stagingIssue,
    }));
  }

  public async getResolvedSharedPayloadsAsync(): Promise<ResolvedSharePayload[]> {
    return incomingShares[0]?.payloads ?? [];
  }

  public clearSharedPayloads(): void {
    const acknowledged = incomingShares.shift();
    if (acknowledged === undefined) return;
    releaseStaging(acknowledged.directory);
    if (incomingShares.length > 0) watchIncomingShares?.();
  }

  public startWatching(): void {
    watchIncomingShares = this.onIncomingShare;
  }

  public stopWatching(): void {
    if (watchIncomingShares === this.onIncomingShare) watchIncomingShares = undefined;
  }

  public override __onDestroy__(): void {
    this.stopWatching();
  }
}
