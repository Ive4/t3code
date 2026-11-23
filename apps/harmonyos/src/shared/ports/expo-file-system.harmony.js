import { fromBase64, toBase64 } from "@exodus/bytes/base64.js";
import { TurboModuleRegistry } from "react-native";

const native = TurboModuleRegistry.getEnforcing("T3FileSystem");
const CHUNK_SIZE = 64 * 1024;
let roots;
let transferId = 0;

export const EncodingType = { UTF8: "utf8", Base64: "base64" };
export const FileMode = {
  ReadWrite: "rw",
  ReadOnly: "r",
  WriteOnly: "w",
  Append: "wa",
  Truncate: "wt",
};
export const UploadType = { BINARY_CONTENT: 0, MULTIPART: 1 };

function unwrap(result) {
  if (result.error !== undefined) throw new Error(result.error);
  return result.value;
}

function joinUri(first, ...components) {
  let uri = first instanceof Entry ? first.uri : first;
  if (typeof uri !== "string") throw new TypeError("Expected a filesystem URI");
  if (uri.startsWith("/")) uri = "file://" + uri.split("/").map(encodeURIComponent).join("/");
  if (!/^file:\/\/[^/]*\//.test(uri))
    throw new TypeError("Expected a sandbox path or HarmonyOS file URI");
  uri = uri.replace(/\/+$/, "");
  for (const component of components) {
    if (typeof component !== "string" || component.startsWith("/"))
      throw new TypeError("Expected a relative path");
    for (const segment of component.split("/")) {
      if (!segment) continue;
      if (segment === "." || segment === ".." || segment.includes("\0"))
        throw new TypeError("Invalid filesystem path segment");
      uri += "/" + encodeURIComponent(segment);
    }
  }
  return uri;
}

function bytesToBase64(bytes) {
  if (!(bytes instanceof Uint8Array)) throw new TypeError("Expected Uint8Array");
  return toBase64(bytes);
}

function writeArguments(value, { encoding = EncodingType.UTF8, append = false } = {}) {
  if (typeof value !== "string") {
    value = bytesToBase64(value instanceof ArrayBuffer ? new Uint8Array(value) : value);
    encoding = EncodingType.Base64;
  }
  if (!Object.values(EncodingType).includes(encoding))
    throw new TypeError("Unsupported file encoding");
  return [value, encoding + (append ? ":append" : "")];
}

function stat(uri) {
  return unwrap(native.stat(uri)) ?? null;
}

class Entry {
  #uri;

  constructor(...components) {
    this.#uri = joinUri(...components);
  }

  get uri() {
    return this.#uri;
  }

  get name() {
    const name = this.uri.slice(this.uri.lastIndexOf("/") + 1).split(/[?#]/, 1)[0];
    try {
      return decodeURIComponent(name);
    } catch {
      return name;
    }
  }

  get parentDirectory() {
    return new Directory(this.uri.slice(0, this.uri.lastIndexOf("/")));
  }

  get exists() {
    const entry = stat(this.uri);
    return entry !== null && entry.isDirectory === this instanceof Directory;
  }

  info() {
    const entry = stat(this.uri);
    if (!entry || entry.isDirectory !== this instanceof Directory) return { exists: false };
    return {
      exists: true,
      uri: this.uri,
      size: entry.size,
      modificationTime: entry.modificationTime,
    };
  }

  create({ idempotent = false, intermediates = false, overwrite = false } = {}) {
    const policy = idempotent ? "keep" : overwrite ? "overwrite" : "error";
    const kind = this instanceof Directory ? "directory" : "file";
    unwrap(native.create(this.uri, kind, intermediates, policy));
  }

  delete() {
    unwrap(native.remove(this.uri, this instanceof Directory));
  }

  moveSync(destination, { overwrite = false } = {}) {
    const target = relocationTarget(this, destination);
    unwrap(native.move(this.uri, target.uri, overwrite));
    this.#uri = target.uri;
  }

  async move(destination, options) {
    this.moveSync(destination, options);
  }
}

function relocationTarget(entry, destination) {
  if (destination instanceof Directory) return new entry.constructor(destination, entry.name);
  if (entry instanceof File && destination instanceof File) return destination;
  throw new TypeError("Expected a filesystem destination");
}

export class Directory extends Entry {
  list() {
    return unwrap(native.list(this.uri)).map(({ name, isDirectory }) =>
      isDirectory ? new Directory(this, name) : new File(this, name),
    );
  }
}

class FileHandle {
  #id;
  #offset;
  #mode;
  #pending;

  constructor(id, mode) {
    this.#id = id;
    this.#mode = mode;
    this.#offset = mode === FileMode.Append ? this.size : 0;
  }

  get offset() {
    return this.#id === null ? null : this.#offset;
  }

  set offset(value) {
    this.#check();
    if (!Number.isSafeInteger(value) || value < 0) throw new RangeError("Invalid file offset");
    this.#offset = value;
  }

  get size() {
    return this.#id === null ? null : unwrap(native.handleSize(this.#id));
  }

  #check() {
    if (this.#id === null) throw new Error("File handle is closed");
    if (this.#pending) throw new Error("Await the pending file operation first");
  }

  #readCheck(length) {
    this.#check();
    if (!Number.isSafeInteger(length) || length < 0)
      throw new RangeError("Invalid file read length");
    if (this.#mode !== FileMode.ReadOnly && this.#mode !== FileMode.ReadWrite)
      throw new Error("File handle is write-only");
  }

  #writeOffset() {
    this.#check();
    if (this.#mode === FileMode.ReadOnly) throw new Error("File handle is read-only");
    return Math.min(this.#offset, this.size);
  }

  async readBytes(length) {
    this.#readCheck(length);
    this.#pending = native.readChunk(this.#id, this.#offset, length);
    try {
      const bytes = fromBase64(await this.#pending);
      this.#offset += bytes.length;
      return bytes;
    } finally {
      this.#pending = undefined;
    }
  }

  readBytesSync(length) {
    this.#readCheck(length);
    const bytes = fromBase64(unwrap(native.readChunkSync(this.#id, this.#offset, length)));
    this.#offset += bytes.length;
    return bytes;
  }

  async writeBytes(bytes) {
    const offset = this.#writeOffset();
    this.#pending = native.writeChunk(this.#id, offset, bytesToBase64(bytes));
    try {
      await this.#pending;
      this.#offset = offset + bytes.length;
    } finally {
      this.#pending = undefined;
    }
  }

  writeBytesSync(bytes) {
    const offset = this.#writeOffset();
    unwrap(native.writeChunkSync(this.#id, offset, bytesToBase64(bytes)));
    this.#offset = offset + bytes.length;
  }

  close() {
    if (this.#id === null) return;
    this.#check();
    const id = this.#id;
    this.#id = null;
    unwrap(native.close(id));
  }

  async closeAfterRead() {
    if (this.#pending) await this.#pending.catch(() => {});
    this.close();
  }
}

function aborted() {
  const error = new Error("File transfer aborted");
  error.name = "AbortError";
  return error;
}

async function transfer(signal, operation) {
  if (signal?.aborted) throw aborted();
  const id = ++transferId;
  let cancel;
  const cancellation = new Promise((_, reject) => {
    cancel = () => {
      native.cancelTransfer(id);
      reject(aborted());
    };
  });
  signal?.addEventListener("abort", cancel, { once: true });
  try {
    const result = await Promise.race([operation(id), cancellation]);
    if (signal?.aborted) throw aborted();
    return result;
  } catch (error) {
    if (signal?.aborted) throw aborted();
    throw error;
  } finally {
    signal?.removeEventListener("abort", cancel);
  }
}

export class File extends Entry {
  get size() {
    const entry = stat(this.uri);
    return entry && !entry.isDirectory ? entry.size : null;
  }

  get modificationTime() {
    return this.info().modificationTime ?? null;
  }

  get extension() {
    const name = this.name;
    const dot = name.lastIndexOf(".");
    return dot > 0 ? name.slice(dot) : "";
  }

  text() {
    return native.read(this.uri, EncodingType.UTF8);
  }
  textSync() {
    return unwrap(native.readSync(this.uri, EncodingType.UTF8));
  }
  base64() {
    return native.read(this.uri, EncodingType.Base64);
  }
  base64Sync() {
    return unwrap(native.readSync(this.uri, EncodingType.Base64));
  }
  async bytes() {
    return fromBase64(await this.base64());
  }
  bytesSync() {
    return fromBase64(this.base64Sync());
  }
  async arrayBuffer() {
    return (await this.bytes()).buffer;
  }

  async write(value, options) {
    await native.write(this.uri, ...writeArguments(value, options));
  }

  writeSync(value, options) {
    unwrap(native.writeSync(this.uri, ...writeArguments(value, options)));
  }

  copy(destination, { overwrite = false } = {}) {
    const target = relocationTarget(this, destination);
    return native.copy(this.uri, target.uri, overwrite);
  }

  copySync(destination, { overwrite = false } = {}) {
    const target = relocationTarget(this, destination);
    unwrap(native.copySync(this.uri, target.uri, overwrite));
  }

  open(mode = /^file:\/\/[^/]/.test(this.uri) ? FileMode.ReadOnly : FileMode.ReadWrite) {
    if (!Object.values(FileMode).includes(mode)) throw new TypeError("Unsupported file mode");
    const id = unwrap(native.open(this.uri, mode));
    try {
      return new FileHandle(id, mode);
    } catch (error) {
      unwrap(native.close(id));
      throw error;
    }
  }

  readableStream() {
    const handle = this.open(FileMode.ReadOnly);
    let cancelled = false;
    return new ReadableStream({
      async pull(controller) {
        try {
          const bytes = await handle.readBytes(CHUNK_SIZE);
          if (cancelled) return;
          if (bytes.length > 0) {
            controller.enqueue(bytes);
          } else {
            handle.close();
            controller.close();
          }
        } catch (error) {
          handle.close();
          throw error;
        }
      },
      cancel() {
        cancelled = true;
        return handle.closeAfterRead();
      },
    });
  }

  async upload(
    url,
    {
      httpMethod = "POST",
      uploadType = UploadType.BINARY_CONTENT,
      headers = {},
      signal,
      onProgress,
    } = {},
  ) {
    if (uploadType !== UploadType.BINARY_CONTENT)
      throw new Error("HarmonyOS filesystem supports binary uploads");
    const result = await transfer(signal, (id) =>
      native.upload(this.uri, url, httpMethod, JSON.stringify(headers), id),
    );
    onProgress?.({ bytesSent: result.bytesSent, totalBytes: result.bytesSent });
    return { status: result.status, headers: JSON.parse(result.headers), body: result.body };
  }

  static async downloadFileAsync(
    url,
    destination,
    { headers = {}, idempotent = false, signal } = {},
  ) {
    if (!(destination instanceof File)) throw new TypeError("Expected a file download destination");
    await transfer(signal, (id) =>
      native.download(url, destination.uri, JSON.stringify(headers), idempotent, id),
    );
    return destination;
  }
}

export const Paths = {
  get document() {
    roots ??= native.getRoots();
    return new Directory(roots.document);
  },
  get cache() {
    roots ??= native.getRoots();
    return new Directory(roots.cache);
  },
  get appleSharedContainers() {
    return {};
  },
};
