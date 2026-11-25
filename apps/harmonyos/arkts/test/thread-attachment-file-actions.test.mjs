import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeOS from "node:os";
import * as NodePath from "node:path";
import * as NodeTest from "node:test";
import * as NodeURL from "node:url";

const kitSources = new Map([
  [
    "@kit.AbilityKit",
    "export const wantConstant = { Flags: { FLAG_AUTH_READ_URI_PERMISSION: 1 } };",
  ],
  ["@kit.ArkData", "export const uniformTypeDescriptor = {};"],
  [
    "@kit.CoreFileKit",
    "export { default as fileIo } from 'node:fs/promises'; " +
      "import { pathToFileURL } from 'node:url'; " +
      "export const fileUri = { getUriFromPath: (path) => pathToFileURL(path).href };",
  ],
  ["@kit.MediaLibraryKit", "export const photoAccessHelper = {};"],
  ["@kit.PreviewKit", "export const filePreview = {};"],
  ["@kit.ShareKit", "export const systemShare = {};"],
]);

const client = new URL("../entry/src/main/ets/client/", import.meta.url);
const loader = NodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    if (kitSources.has(specifier)) return { url: specifier, shortCircuit: true };
    if (specifier.startsWith("./") && context.parentURL?.startsWith(client.href)) {
      return nextResolve(`${specifier}.ets`, context);
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (kitSources.has(url)) {
      return { format: "module", shortCircuit: true, source: kitSources.get(url) };
    }
    if (!url.startsWith(client.href) || !url.endsWith(".ets")) return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(new URL(url), "utf8")),
    };
  },
});

const actions = import(new URL("ThreadAttachmentFileActions.ets", client).href);
void actions.catch(() => {});
NodeTest.after(() => loader.deregister());

NodeTest.test(
  "opens a regular cache file and rejects remote, escaped, and linked paths",
  async (t) => {
    const { ThreadAttachmentFileActions } = await actions;
    const cacheDir = NodeFS.mkdtempSync(NodePath.join(NodeOS.tmpdir(), "attachment-actions-"));
    t.after(() => NodeFS.rmSync(cacheDir, { recursive: true, force: true }));
    globalThis.canIUse = () => false;
    t.after(() => Reflect.deleteProperty(globalThis, "canIUse"));
    const path = NodePath.join(cacheDir, "预览 image.png");
    const uri = NodeURL.pathToFileURL(path).href;
    NodeFS.writeFileSync(path, "file bytes");
    const alias = NodePath.join(cacheDir, "alias.png");
    NodeFS.symlinkSync(path, alias);
    const directory = NodePath.join(cacheDir, "folder.png");
    NodeFS.mkdirSync(directory);
    const linkedDirectory = NodePath.join(cacheDir, "linked-folder");
    NodeFS.symlinkSync(cacheDir, linkedDirectory);

    const opened = [];
    const context = { cacheDir, startAbility: async (want) => opened.push(want) };
    const viewer = new ThreadAttachmentFileActions();
    const file = { name: "image.png", mimeType: "IMAGE/PNG; charset=utf-8" };
    await viewer.open(context, { ...file, uri });
    NodeAssert.equal(opened[0]?.uri, uri);
    NodeAssert.equal(opened[0]?.type, "image/png");

    for (const badUri of [
      "https://example.test/api/assets/token/image.png",
      `${uri}?token=secret`,
      `${NodeURL.pathToFileURL(cacheDir).href}/%2e%2e/private.png`,
      `${NodeURL.pathToFileURL(cacheDir).href}/bad%2Ffile.png`,
      `${NodeURL.pathToFileURL(cacheDir).href}-other/private.png`,
      NodeURL.pathToFileURL(alias).href,
      NodeURL.pathToFileURL(directory).href,
      NodeURL.pathToFileURL(NodePath.join(linkedDirectory, "预览 image.png")).href,
    ]) {
      await NodeAssert.rejects(viewer.open(context, { ...file, uri: badUri }));
    }
    NodeAssert.equal(opened.length, 1);
  },
);
