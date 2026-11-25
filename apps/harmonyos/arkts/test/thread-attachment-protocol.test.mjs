import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import {
  AssetCreateUrlInput,
  AssetCreateUrlResult,
  AttachmentCreateUploadUrlInput,
  AttachmentCreateUploadUrlResult,
  AttachmentDeleteInput,
  ChatAttachment,
  WS_METHODS,
} from "@t3tools/contracts";
import * as Schema from "effect/Schema";

const client = new URL("../entry/src/main/ets/client/", import.meta.url);
const loader = NodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === "@kit.ArkTS") return { url: specifier, shortCircuit: true };
    if (specifier.startsWith("./") && context.parentURL?.startsWith(client.href)) {
      return nextResolve(`${specifier}.ets`, context);
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url === "@kit.ArkTS") {
      return {
        format: "module",
        shortCircuit: true,
        source: "export const url={URL:{parseURL:(value)=>new URL(value)}};",
      };
    }
    if (!url.startsWith(client.href) || !url.endsWith(".ets")) return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(new URL(url), "utf8")),
    };
  },
});
const protocol = import(new URL("ThreadAttachmentProtocol.ets", client).href);
void protocol.catch(() => {});
const assetProtocol = import(new URL("ThreadAttachmentAssetProtocol.ets", client).href);
void assetProtocol.catch(() => {});
const messages = import(new URL("T3Protocol.ets", client).href);
void messages.catch(() => {});
NodeTest.after(() => loader.deregister());

const decodeCreate = Schema.decodeUnknownSync(AttachmentCreateUploadUrlInput);
const decodeSlot = Schema.decodeUnknownSync(AttachmentCreateUploadUrlResult);
const decodeDelete = Schema.decodeUnknownSync(AttachmentDeleteInput);
const decodeAttachment = Schema.decodeUnknownSync(ChatAttachment);
const decodeAssetInput = Schema.decodeUnknownSync(AssetCreateUrlInput);
const decodeAssetResult = Schema.decodeUnknownSync(AssetCreateUrlResult);
const attachmentId = "pending-2b5ac017-bba3-4632-9d12-0f0bb994e30a-txt";
const origin = "https://tunnel.example.test";
const path = "/api/attachments/upload/encoded-claims.signature";
const slot = decodeSlot({ attachmentId, relativeUrl: path, expiresAt: Number.MAX_SAFE_INTEGER });
const file = { type: "file", name: "说明.txt", mimeType: "text/plain", sizeBytes: 3 };
const bytes = Uint8Array.of(0, 255, 10).buffer;

NodeTest.test(
  "preserves typed message attachments and the display name of older attachments",
  async () => {
    const { readMessage } = await messages;
    const attachment = { id: attachmentId, ...file };
    const photo = {
      id: "legacy-photo",
      name: "image.heic",
      type: "image",
      mimeType: "image/heic",
      sizeBytes: 0,
    };
    const message = readMessage({
      id: "message-1",
      role: "user",
      text: "Check these files",
      attachments: [attachment, photo, { name: "legacy.txt" }, { ...file, id: "invalid/id" }, null],
    });
    NodeAssert.deepEqual(message.attachments, [
      decodeAttachment(attachment),
      decodeAttachment(photo),
    ]);
    NodeAssert.deepEqual(message.attachmentNames, [
      file.name,
      "image.heic",
      "legacy.txt",
      file.name,
    ]);
  },
);

NodeTest.test(
  "authorizes a fresh attachment link at the environment route current after minting",
  async () => {
    const { requestThreadAttachmentAssetUrl } = await assetProtocol;
    const expiresAt = Number.MAX_SAFE_INTEGER;
    const relativeUrl = "/api/assets/encoded-claims.signature/%E8%AF%B4%E6%98%8E.txt";
    const reply = decodeAssetResult({ relativeUrl, expiresAt });
    let currentOrigin = "https://previous.example.test";
    const result = await requestThreadAttachmentAssetUrl(
      { id: attachmentId, ...file },
      {
        origin: () => currentOrigin,
        rpc: async (request) => {
          NodeAssert.equal(request.tag, WS_METHODS.assetsCreateUrl);
          NodeAssert.deepEqual(decodeAssetInput(request.payload), {
            resource: {
              _tag: "attachment",
              attachmentId,
              fileName: file.name,
              mimeType: file.mimeType,
              disposition: "inline",
            },
          });
          currentOrigin = origin;
          return reply;
        },
      },
      "inline",
    );
    NodeAssert.deepEqual(result, { url: origin + relativeUrl, expiresAt });
  },
);

NodeTest.test(
  "rejects an expired asset, a different destination, and a changed environment",
  async () => {
    const { requestThreadAttachmentAssetUrl } = await assetProtocol;
    for (const [relativeUrl, expiresAt, base] of [
      ["/api/assets/valid/file.txt", 0, origin],
      ["https://other.example.test/api/assets/valid/file.txt", Number.MAX_SAFE_INTEGER, origin],
      ["//other.example.test/api/assets/valid/file.txt", Number.MAX_SAFE_INTEGER, origin],
      ["/api/assets/../file.txt", Number.MAX_SAFE_INTEGER, origin],
      ["/api/assets/valid/%2e%2e", Number.MAX_SAFE_INTEGER, origin],
      [
        "/api/assets/valid/file.txt",
        Number.MAX_SAFE_INTEGER,
        "https://user:tunnel@wrong.example.test",
      ],
    ]) {
      await NodeAssert.rejects(
        requestThreadAttachmentAssetUrl(
          { id: attachmentId, ...file },
          {
            rpc: async () => ({ relativeUrl, expiresAt }),
            origin: () => base,
          },
        ),
      );
    }
    await NodeAssert.rejects(
      requestThreadAttachmentAssetUrl(
        { id: attachmentId, ...file },
        {
          rpc: async () => ({
            relativeUrl: "/api/assets/valid/file.txt",
            expiresAt: Number.MAX_SAFE_INTEGER,
          }),
          origin: () => {
            throw new Error("environment changed");
          },
        },
      ),
      /environment changed/,
    );
  },
);

NodeTest.test(
  "preserves a safe MIME type and uses the provider limits for photos and files",
  async () => {
    const { describeThreadAttachment, attachmentUploadRequest } = await protocol;
    const photo = describeThreadAttachment("Capture.JPG", undefined, 12, true);
    NodeAssert.deepEqual(decodeCreate(attachmentUploadRequest(photo).payload), {
      type: "image",
      name: "Capture.JPG",
      mimeType: "image/jpeg",
      sizeBytes: 12,
    });
    const document = describeThreadAttachment("large.JPG", "image/jpeg", 11 * 1024 ** 2);
    NodeAssert.equal(document.type, "file");
    NodeAssert.equal(document.mimeType, "image/jpeg");
    for (const [name, mimeType, size, imageOnly] of [
      ["Capture.JPG", "image/jpeg", 11 * 1024 ** 2, true],
      ["Capture.HEIC", "image/heic", 10, true],
      ["video.mp4", "video/mp4", 51 * 1024 ** 2, false],
      ["empty.txt", "text/plain", 0, false],
    ]) {
      NodeAssert.throws(() => describeThreadAttachment(name, mimeType, size, imageOnly));
    }
    NodeAssert.throws(() =>
      attachmentUploadRequest({ ...file, mimeType: "text/plain\r\nAuthorization: injected" }),
    );
  },
);

NodeTest.test(
  "posts the exact binary bytes to the signed route on the current environment",
  async () => {
    const { uploadThreadAttachment } = await protocol;
    const requests = [];
    const uploaded = await uploadThreadAttachment(
      file,
      bytes,
      {
        origin: () => origin,
        rpc: async (request) => {
          requests.push(request.tag);
          NodeAssert.deepEqual(decodeCreate(request.payload), file);
          return slot;
        },
      },
      async (target, mimeType, body) => {
        NodeAssert.equal(target, origin + path);
        NodeAssert.equal(mimeType, "text/plain");
        NodeAssert.deepEqual(new Uint8Array(body), Uint8Array.of(0, 255, 10));
        return 204;
      },
    );
    NodeAssert.deepEqual(decodeAttachment(uploaded), { id: attachmentId, ...file });
    NodeAssert.deepEqual(requests, [WS_METHODS.attachmentsCreateUploadUrl]);
  },
);

NodeTest.test(
  "deletes the minted attachment when the upload fails or its destination is invalid",
  async () => {
    const { uploadThreadAttachment } = await protocol;
    for (const [relativeUrl, expiresAt, shouldPost] of [
      ["https://other.example.test/api/attachments/upload/abc.def", Number.MAX_SAFE_INTEGER, false],
      ["//other.example.test/api/attachments/upload/abc.def", Number.MAX_SAFE_INTEGER, false],
      ["/api/attachments/upload/../other", Number.MAX_SAFE_INTEGER, false],
      [path, 0, false],
      [path, Number.MAX_SAFE_INTEGER, true],
    ]) {
      let posted = false;
      const cleanup = [];
      await NodeAssert.rejects(
        uploadThreadAttachment(
          file,
          bytes,
          {
            origin: () => origin,
            rpc: async (request) => {
              if (request.tag === WS_METHODS.attachmentsCreateUploadUrl) {
                return { ...slot, relativeUrl, expiresAt };
              }
              NodeAssert.equal(request.tag, WS_METHODS.attachmentsDelete);
              cleanup.push(decodeDelete(request.payload).attachmentId);
            },
          },
          async () => {
            posted = true;
            return 500;
          },
        ),
      );
      NodeAssert.equal(posted, shouldPost);
      NodeAssert.deepEqual(cleanup, [attachmentId]);
    }
  },
);

NodeTest.test(
  "rejects wrong-length input and mismatched image bytes before allocating an upload",
  async () => {
    const { uploadThreadAttachment } = await protocol;
    const environment = {
      origin: () => origin,
      rpc: async () => NodeAssert.fail("must not allocate an upload"),
    };
    const post = async () => NodeAssert.fail("must not send invalid bytes");
    await NodeAssert.rejects(
      uploadThreadAttachment({ ...file, sizeBytes: 2 }, bytes, environment, post),
      /大小/,
    );
    await NodeAssert.rejects(
      uploadThreadAttachment(
        { ...file, type: "image", mimeType: "image/png" },
        bytes,
        environment,
        post,
      ),
      /图片格式/,
    );
  },
);
