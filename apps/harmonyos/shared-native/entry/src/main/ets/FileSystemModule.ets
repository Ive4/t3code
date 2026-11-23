import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import { UITurboModule } from '@rnoh/react-native-openharmony';

interface Roots {
  document: string;
  cache: string;
}

interface FileInfo {
  isDirectory: boolean;
  size: number;
  modificationTime: number;
}

interface DirectoryEntry {
  name: string;
  isDirectory: boolean;
}

interface SyncResult<T> {
  value?: T;
  error?: string;
}

interface UploadResult {
  status: number;
  body: string;
  headers: string;
  bytesSent: number;
}

interface OpenHandle {
  file: fileIo.File;
  offset: number;
}

const MISSING = 13900002;
const CHUNK_SIZE = 64 * 1024;
const MAX_BUFFERED_BYTES = 64 * 1024 * 1024;
const WRITE_MODE = fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE;

function result<T>(operation: () => T): SyncResult<T> {
  try {
    return { value: operation() };
  } catch (cause) {
    const error = cause as BusinessError;
    return { error: error.message || 'Filesystem operation failed' };
  }
}

function entryStat(path: string): fileIo.Stat | null {
  try {
    return fileIo.lstatSync(path);
  } catch (cause) {
    if ((cause as BusinessError).code === MISSING) return null;
    throw new Error((cause as BusinessError).message || 'Filesystem operation failed');
  }
}

function isGrantedUri(uri: string): boolean {
  return /^file:\/\/[^/]+\//.test(uri);
}

export class FileSystemModule extends UITurboModule {
  private readonly base64 = new util.Base64Helper();
  private readonly handles = new Map<number, OpenHandle>();
  private readonly transfers = new Map<number, http.HttpRequest>();
  private nextHandle = 1;

  public getRoots(): Roots {
    const context = this.ctx.uiAbilityContext;
    return { document: context.filesDir, cache: context.cacheDir };
  }

  private sandboxPath(uri: string, allowRoot: boolean): string {
    const path = uri.startsWith('file:///') ? decodeURIComponent(uri.slice(7)) : uri;
    const roots = this.getRoots();
    const root = [roots.document, roots.cache].find((value: string): boolean =>
      path === value || path.startsWith(value + '/'));
    if (root === undefined || path.includes('\0') || (!allowRoot && path === root)) {
      throw new Error('Expected a path inside the app document or cache directory');
    }
    if (path !== root) {
      let current = root;
      for (const segment of path.slice(root.length + 1).split('/')) {
        if (!segment || segment === '.' || segment === '..') throw new Error('Invalid sandbox path');
        current += '/' + segment;
        if (entryStat(current)?.isSymbolicLink()) throw new Error('Symbolic links are unsupported');
      }
    }
    return path;
  }

  private readablePath(uri: string): string {
    return isGrantedUri(uri) ? uri : this.sandboxPath(uri, false);
  }

  public stat(uri: string): SyncResult<FileInfo | null> {
    return result<FileInfo | null>(() => {
      let stat: fileIo.Stat | null;
      if (isGrantedUri(uri)) {
        try {
          const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
          try {
            stat = fileIo.statSync(file.fd);
          } finally {
            fileIo.closeSync(file);
          }
        } catch (cause) {
          if ((cause as BusinessError).code === MISSING) return null;
          throw new Error((cause as BusinessError).message || 'Filesystem operation failed');
        }
      } else {
        stat = entryStat(this.sandboxPath(uri, true));
      }
      if (stat === null) return null;
      return { isDirectory: stat.isDirectory(), size: stat.size, modificationTime: stat.mtime * 1000 };
    });
  }

  public list(uri: string): SyncResult<DirectoryEntry[]> {
    return result<DirectoryEntry[]>(() => {
      const path = this.sandboxPath(uri, true);
      const entries: DirectoryEntry[] = [];
      for (const name of fileIo.listFileSync(path)) {
        const stat = entryStat(path + '/' + name);
        if (stat !== null && !stat.isSymbolicLink()) entries.push({ name, isDirectory: stat.isDirectory() });
      }
      return entries;
    });
  }

  public create(uri: string, kind: string, intermediates: boolean, whenExists: string): SyncResult<null> {
    return result<null>(() => {
      const path = this.sandboxPath(uri, whenExists === 'keep');
      const existing = entryStat(path);
      if (existing !== null) {
        if (existing.isDirectory() !== (kind === 'directory')) throw new Error('Entry has the wrong type');
        if (whenExists === 'keep') return null;
        if (whenExists !== 'overwrite') throw new Error('Entry already exists');
        if (kind === 'directory') fileIo.rmdirSync(path);
      }
      if (kind === 'directory') {
        fileIo.mkdirSync(path, intermediates);
      } else {
        const parent = path.slice(0, path.lastIndexOf('/'));
        if (intermediates && entryStat(parent) === null) fileIo.mkdirSync(parent, true);
        fileIo.closeSync(fileIo.openSync(path, WRITE_MODE | fileIo.OpenMode.TRUNC));
      }
      return null;
    });
  }

  public remove(uri: string, directory: boolean): SyncResult<null> {
    return result<null>(() => {
      const path = this.sandboxPath(uri, false);
      if (directory) {
        if (!fileIo.statSync(path).isDirectory()) throw new Error('Expected a directory');
        fileIo.rmdirSync(path);
      } else {
        fileIo.unlinkSync(path);
      }
      return null;
    });
  }

  private destination(from: string, uri: string, overwrite: boolean): string {
    const to = this.sandboxPath(uri, false);
    if (from === to) throw new Error('Source and destination refer to the same path');
    if (!overwrite && entryStat(to) !== null) throw new Error('Destination already exists');
    return to;
  }

  public move(source: string, destination: string, overwrite: boolean): SyncResult<null> {
    return result<null>(() => {
      const from = this.sandboxPath(source, false);
      const to = this.destination(from, destination, overwrite);
      // POSIX rename replaces a destination file atomically on the same filesystem.
      fileIo.renameSync(from, to);
      return null;
    });
  }

  public copySync(source: string, destination: string, overwrite: boolean): SyncResult<null> {
    return result<null>(() => {
      const from = this.readablePath(source);
      const to = this.destination(from, destination, overwrite);
      const file = fileIo.openSync(from, fileIo.OpenMode.READ_ONLY);
      try {
        fileIo.copyFileSync(file.fd, to);
      } finally {
        fileIo.closeSync(file);
      }
      return null;
    });
  }

  public async copy(source: string, destination: string, overwrite: boolean): Promise<void> {
    const from = this.readablePath(source);
    const to = this.destination(from, destination, overwrite);
    const file = await fileIo.open(from, fileIo.OpenMode.READ_ONLY);
    try {
      await fileIo.copyFile(file.fd, to);
    } finally {
      await fileIo.close(file);
    }
  }

  private readResult(bytes: Uint8Array, encoding: string): string {
    if (encoding === 'utf8') return util.TextDecoder.create('utf-8').decodeToString(bytes);
    return bytes.length === 0 ? '' : this.base64.encodeToStringSync(bytes);
  }

  private bufferLimit(length: number): void {
    if (!Number.isSafeInteger(length) || length < 0 || length > MAX_BUFFERED_BYTES) {
      throw new RangeError('Buffered filesystem operations are limited to 64 MiB');
    }
  }

  private joinChunks(chunks: Uint8Array[], size: number): Uint8Array {
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    return bytes;
  }

  public readSync(uri: string, encoding: string): SyncResult<string> {
    return result<string>(() => {
      const file = fileIo.openSync(this.readablePath(uri), fileIo.OpenMode.READ_ONLY);
      try {
        const chunks: Uint8Array[] = [];
        let size = 0;
        for (;;) {
          const buffer = new ArrayBuffer(CHUNK_SIZE);
          const length = fileIo.readSync(file.fd, buffer);
          if (length === 0) return this.readResult(this.joinChunks(chunks, size), encoding);
          size += length;
          this.bufferLimit(size);
          chunks.push(new Uint8Array(buffer, 0, length));
        }
      } finally {
        fileIo.closeSync(file);
      }
    });
  }

  private async readAll(uri: string): Promise<Uint8Array> {
    const file = await fileIo.open(this.readablePath(uri), fileIo.OpenMode.READ_ONLY);
    try {
      const chunks: Uint8Array[] = [];
      let size = 0;
      for (;;) {
        const buffer = new ArrayBuffer(CHUNK_SIZE);
        const length = await fileIo.read(file.fd, buffer);
        if (length === 0) return this.joinChunks(chunks, size);
        size += length;
        this.bufferLimit(size);
        chunks.push(new Uint8Array(buffer, 0, length));
      }
    } finally {
      await fileIo.close(file);
    }
  }

  public async read(uri: string, encoding: string): Promise<string> {
    return this.readResult(await this.readAll(uri), encoding);
  }

  private inputBytes(payload: string, encoding: string): Uint8Array {
    const bytes = encoding === 'utf8' ? new util.TextEncoder().encodeInto(payload) :
      payload.length === 0 ? new Uint8Array(0) : this.base64.decodeSync(payload);
    this.bufferLimit(bytes.length);
    return bytes;
  }

  private writeAllSync(fd: number, bytes: Uint8Array): void {
    let offset = 0;
    while (offset < bytes.length) {
      const length = fileIo.writeSync(fd, offset === 0 && bytes.byteOffset === 0 && bytes.buffer.byteLength === bytes.length ? bytes.buffer : bytes.slice(offset).buffer);
      if (length <= 0) throw new Error('File write made no progress');
      offset += length;
    }
  }

  private async writeAll(fd: number, bytes: Uint8Array): Promise<void> {
    let offset = 0;
    while (offset < bytes.length) {
      const length = await fileIo.write(fd, offset === 0 && bytes.byteOffset === 0 && bytes.buffer.byteLength === bytes.length ? bytes.buffer : bytes.slice(offset).buffer);
      if (length <= 0) throw new Error('File write made no progress');
      offset += length;
    }
  }

  public writeSync(uri: string, payload: string, option: string): SyncResult<null> {
    return result<null>(() => {
      const bytes = this.inputBytes(payload, option.split(':')[0]);
      const mode = option.endsWith(':append') ? fileIo.OpenMode.APPEND : fileIo.OpenMode.TRUNC;
      const file = fileIo.openSync(this.sandboxPath(uri, false), WRITE_MODE | mode);
      try {
        this.writeAllSync(file.fd, bytes);
        return null;
      } finally {
        fileIo.closeSync(file);
      }
    });
  }

  public async write(uri: string, payload: string, option: string): Promise<void> {
    const bytes = this.inputBytes(payload, option.split(':')[0]);
    const mode = option.endsWith(':append') ? fileIo.OpenMode.APPEND : fileIo.OpenMode.TRUNC;
    const file = await fileIo.open(this.sandboxPath(uri, false), WRITE_MODE | mode);
    try {
      await this.writeAll(file.fd, bytes);
    } finally {
      await fileIo.close(file);
    }
  }

  public open(uri: string, mode: string): SyncResult<number> {
    return result<number>(() => {
      let flags = fileIo.OpenMode.READ_ONLY;
      if (mode === 'rw') flags = fileIo.OpenMode.READ_WRITE;
      if (mode === 'w' || mode === 'wa') flags = fileIo.OpenMode.WRITE_ONLY;
      if (mode === 'wt') flags = fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC;
      const path = mode === 'r' ? this.readablePath(uri) : this.sandboxPath(uri, false);
      const file = fileIo.openSync(path, flags);
      const id = this.nextHandle++;
      this.handles.set(id, { file, offset: 0 });
      return id;
    });
  }

  private handle(id: number): OpenHandle {
    const handle = this.handles.get(id);
    if (handle === undefined) throw new Error('File handle is closed');
    return handle;
  }

  public close(id: number): SyncResult<null> {
    return result<null>(() => {
      const handle = this.handle(id);
      this.handles.delete(id);
      fileIo.closeSync(handle.file);
      return null;
    });
  }

  public handleSize(id: number): SyncResult<number> {
    return result<number>(() => fileIo.statSync(this.handle(id).file.fd).size);
  }

  private position(id: number, offset: number): OpenHandle {
    const handle = this.handle(id);
    if (!Number.isSafeInteger(offset) || offset < 0) throw new RangeError('Invalid file offset');
    if (handle.offset !== offset) handle.offset = fileIo.lseek(handle.file.fd, offset);
    return handle;
  }

  public readChunkSync(id: number, offset: number, length: number): SyncResult<string> {
    return result<string>(() => {
      this.bufferLimit(length);
      const handle = this.position(id, offset);
      const buffer = new ArrayBuffer(length);
      const read = length === 0 ? 0 : fileIo.readSync(handle.file.fd, buffer);
      handle.offset += read;
      return this.readResult(new Uint8Array(buffer, 0, read), 'base64');
    });
  }

  public async readChunk(id: number, offset: number, length: number): Promise<string> {
    this.bufferLimit(length);
    const handle = this.position(id, offset);
    const buffer = new ArrayBuffer(length);
    const read = length === 0 ? 0 : await fileIo.read(handle.file.fd, buffer);
    handle.offset += read;
    return this.readResult(new Uint8Array(buffer, 0, read), 'base64');
  }

  public writeChunkSync(id: number, offset: number, payload: string): SyncResult<null> {
    return result<null>(() => {
      const bytes = this.inputBytes(payload, 'base64');
      const handle = this.position(id, offset);
      this.writeAllSync(handle.file.fd, bytes);
      handle.offset += bytes.length;
      return null;
    });
  }

  public async writeChunk(id: number, offset: number, payload: string): Promise<void> {
    const bytes = this.inputBytes(payload, 'base64');
    const handle = this.position(id, offset);
    await this.writeAll(handle.file.fd, bytes);
    handle.offset += bytes.length;
  }

  private transfer(id: number, url: string): http.HttpRequest {
    if (!/^https?:\/\//i.test(url)) throw new Error('Expected an HTTP or HTTPS attachment URL');
    if (this.transfers.has(id)) throw new Error('Transfer ID already in use');
    const request = http.createHttp();
    this.transfers.set(id, request);
    return request;
  }

  private checkTransfer(id: number): void {
    if (!this.transfers.has(id)) throw new Error('File transfer aborted');
  }

  private finishTransfer(id: number): void {
    const request = this.transfers.get(id);
    if (request === undefined) return;
    this.transfers.delete(id);
    request.destroy();
  }

  public cancelTransfer(id: number): SyncResult<null> {
    return result<null>(() => {
      this.finishTransfer(id);
      return null;
    });
  }

  public async upload(uri: string, url: string, method: string, headers: string, id: number): Promise<UploadResult> {
    let requestMethod: http.RequestMethod;
    switch (method.toUpperCase()) {
      case 'POST': requestMethod = http.RequestMethod.POST; break;
      case 'PUT': requestMethod = http.RequestMethod.PUT; break;
      case 'PATCH': requestMethod = http.RequestMethod.PATCH; break;
      default: throw new Error('Attachment uploads support POST, PUT and PATCH');
    }
    const request = this.transfer(id, url);
    try {
      const bytes = await this.readAll(uri);
      this.checkTransfer(id);
      const response = await request.request(url, {
        method: requestMethod,
        header: JSON.parse(headers) as Object,
        extraData: bytes.buffer,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
      });
      this.checkTransfer(id);
      const body = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      const responseHeaders = typeof response.header === 'string' ? response.header : JSON.stringify(response.header);
      return { status: response.responseCode, body, headers: responseHeaders, bytesSent: bytes.length };
    } finally {
      this.finishTransfer(id);
    }
  }

  public async download(url: string, uri: string, headers: string, overwrite: boolean, id: number): Promise<void> {
    const destination = this.destination('', uri, overwrite);
    const staging = destination.slice(0, destination.lastIndexOf('/') + 1) +
      '.t3-download-' + util.generateRandomUUID();
    const request = this.transfer(id, url);
    let stagingCreated = false;
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: JSON.parse(headers) as Object,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        maxLimit: MAX_BUFFERED_BYTES,
        usingCache: false,
      });
      this.checkTransfer(id);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error('Attachment download failed with HTTP ' + response.responseCode);
      }
      if (!(response.result instanceof ArrayBuffer)) throw new Error('Expected a binary HTTP response');
      const bytes = new Uint8Array(response.result);
      this.bufferLimit(bytes.length);
      const file = await fileIo.open(staging, WRITE_MODE);
      stagingCreated = true;
      try {
        await this.writeAll(file.fd, bytes);
      } finally {
        await fileIo.close(file);
      }
      this.checkTransfer(id);
      this.destination(staging, uri, overwrite);
      fileIo.renameSync(staging, destination);
      stagingCreated = false;
    } finally {
      this.finishTransfer(id);
      if (stagingCreated) fileIo.unlinkSync(staging);
    }
  }

}
