import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import { ReviewDiffPreviewInput, ReviewDiffPreviewResult, WS_METHODS } from "@t3tools/contracts";
import * as Schema from "effect/Schema";

const client = new URL("../entry/src/main/ets/client/", import.meta.url);
const loader = NodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith("./") && context.parentURL?.startsWith(client.href)) {
      return nextResolve(`${specifier}.ets`, context);
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (!url.startsWith(client.href) || !url.endsWith(".ets")) return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(new URL(url), "utf8")),
    };
  },
});
const protocol = import(new URL("ThreadReviewProtocol.ets", client).href);
void protocol.catch(() => {});
NodeTest.after(() => loader.deregister());

const decodeRequest = Schema.decodeUnknownSync(ReviewDiffPreviewInput);
const decodeResult = Schema.decodeUnknownSync(Schema.toCodecJson(ReviewDiffPreviewResult));
const cwd = "/worktrees/Android 对齐";
const renamed = {
  path: "src/ 新 名.ets",
  previousPath: "src/old name.ets",
  changeType: "rename-changed",
  additions: 2,
  deletions: 1,
};
const removed = {
  path: "src/obsolete.txt",
  previousPath: null,
  changeType: "deleted",
  additions: 0,
  deletions: 1,
};
const binary = {
  path: "assets/a b/image.png",
  previousPath: null,
  additions: 0,
  deletions: 0,
};
const renameDiff = [
  'diff --git a/src/old name.ets "b/src/ \\346\\226\\260 \\345\\220\\215.ets"',
  "similarity index 60%",
  "rename from src/old name.ets",
  'rename to "src/ \\346\\226\\260 \\345\\220\\215.ets"',
  "--- a/src/old name.ets\t",
  '+++ "b/src/ \\346\\226\\260 \\345\\220\\215.ets"',
  "@@ -1 +1,2 @@",
  "-before",
  "+after",
  "++++ b/literal-content",
  "",
].join("\n");
const deleteDiff = [
  "diff --git a/src/obsolete.txt b/src/obsolete.txt",
  "deleted file mode 100644",
  "--- a/src/obsolete.txt",
  "+++ /dev/null",
  "@@ -1 +0,0 @@",
  "-obsolete",
  "",
].join("\n");
const binaryDiff = [
  "diff --git a/assets/a b/image.png b/assets/a b/image.png",
  "Binary files a/assets/a b/image.png and b/assets/a b/image.png differ",
  "",
].join("\n");

function result(fields, others = []) {
  const working = {
    id: "working-tree",
    kind: "working-tree",
    title: "Uncommitted",
    baseRef: "HEAD",
    headRef: null,
    diff: "",
    diffHash: "review-fixture",
    truncated: false,
    ...fields,
  };
  const wire = {
    cwd,
    generatedAt: "2026-11-25T00:00:00.000Z",
    sources: fields === null ? [] : [working, ...others],
  };
  decodeResult(wire);
  return wire;
}

NodeTest.test(
  "uses the read-only working tree RPC and preserves literal rename paths",
  async () => {
    const { threadReviewRequest } = await protocol;
    const request = threadReviewRequest(cwd);
    NodeAssert.equal(request.tag, WS_METHODS.reviewGetDiffPreview);
    NodeAssert.deepEqual(decodeRequest(request.payload), { cwd, sourceKind: "working-tree" });
    const patch = threadReviewRequest(cwd, renamed, "HEAD");
    NodeAssert.equal(patch.tag, WS_METHODS.reviewGetDiffPreview);
    NodeAssert.deepEqual(decodeRequest(patch.payload), {
      cwd,
      baseRef: "HEAD",
      file: {
        path: "src/ 新 名.ets",
        previousPath: "src/old name.ets",
        changeType: "rename-changed",
        sourceKind: "working-tree",
      },
    });
    NodeAssert.throws(() => threadReviewRequest(`${cwd}\0invalid`));
    NodeAssert.throws(() => threadReviewRequest(cwd, { ...renamed, path: "../elsewhere" }));
  },
);

NodeTest.test("matches text, deletion and binary patches to their own file stats", async () => {
  const { readThreadReview } = await protocol;
  const review = readThreadReview(
    result({
      files: [binary, removed, renamed],
      diff: renameDiff + deleteDiff + binaryDiff,
    }),
    cwd,
  );
  NodeAssert.equal(review.totalFiles, 3);
  NodeAssert.deepEqual(
    review.files.map((file) => file.path),
    ["assets/a b/image.png", "src/obsolete.txt", "src/ 新 名.ets"],
  );
  NodeAssert.deepEqual(review.files[0].patch.lines, [
    "Binary files a/assets/a b/image.png and b/assets/a b/image.png differ",
  ]);
  NodeAssert.deepEqual(review.files[1].patch.lines, ["@@ -1 +0,0 @@", "-obsolete"]);
  NodeAssert.deepEqual(review.files[2].patch.lines, [
    "similarity index 60%",
    "@@ -1 +1,2 @@",
    "-before",
    "+after",
    "++++ b/literal-content",
  ]);
  NodeAssert.equal(review.files[2].previousPath, "src/old name.ets");
  NodeAssert.equal(review.files[2].additions, 2);
});

NodeTest.test(
  "retains stats for deferred or truncated previews and reads a single file on demand",
  async () => {
    const { readThreadReview, readThreadReviewPatch } = await protocol;
    for (const flags of [{ truncated: true, diff: "partial bytes" }, { patchesDeferred: true }]) {
      const review = readThreadReview(result({ files: [renamed, binary], ...flags }), cwd);
      NodeAssert.equal(review.incomplete, false);
      NodeAssert.equal(review.files[0].patch, undefined);
      NodeAssert.equal(review.files[0].deletions, 1);
    }
    const patch = readThreadReviewPatch(
      result({ files: [binary, renamed], diff: binaryDiff + renameDiff }),
      cwd,
      renamed,
    );
    NodeAssert.ok(patch.lines.includes("+after"));
    NodeAssert.ok(!patch.lines.includes(binaryDiff.split("\n")[1]));
    NodeAssert.throws(() =>
      readThreadReviewPatch(result({ files: [binary], diff: binaryDiff }), cwd, renamed),
    );
  },
);

NodeTest.test(
  "labels a partial file list and bounds long patches without discarding counts",
  async () => {
    const { readThreadReview, readThreadReviewPatch } = await protocol;
    const limited = readThreadReview(
      result({
        truncated: true,
        diff: renameDiff + deleteDiff + "\n\n[truncated]",
      }),
      cwd,
    );
    NodeAssert.equal(limited.incomplete, true);
    NodeAssert.deepEqual(
      limited.files.map((file) => file.path),
      ["src/ 新 名.ets", "src/obsolete.txt"],
    );
    NodeAssert.ok(!limited.files[1].patch.lines.includes("[truncated]"));
    const distinct = Array.from({ length: 104 }, (_, index) => ({
      ...binary,
      path: `path-${index}`,
    }));
    const withStats = readThreadReview(result({ files: distinct, patchesDeferred: true }), cwd);
    NodeAssert.equal(withStats.totalFiles, 104);
    NodeAssert.equal(withStats.files.length, 100);
    const lines = Array.from({ length: 308 }, (_, index) => "+" + String(index) + "x".repeat(650));
    const diff = renameDiff + lines.join("\n") + "\n";
    const patch = readThreadReviewPatch(result({ files: [renamed], diff }), cwd, renamed);
    NodeAssert.equal(patch.truncated, true);
    NodeAssert.equal(patch.lines.length, 300);
    NodeAssert.equal(patch.lines[5].length, 480);
    NodeAssert.ok(patch.lines[5].endsWith("…"));
  },
);

NodeTest.test(
  "distinguishes a clean repository from an invalid reply or wrong worktree",
  async () => {
    const { readThreadReview } = await protocol;
    NodeAssert.deepEqual(readThreadReview(result({ files: [] }), cwd).files, []);
    NodeAssert.deepEqual(readThreadReview(result(null), cwd).files, []);
    NodeAssert.throws(() => readThreadReview(result({ files: [] }), "/different/task"));
    NodeAssert.throws(() => readThreadReview({ ...result(null), sources: "unavailable" }, cwd));
    const malformed = result({ files: [renamed] });
    malformed.sources[0].files = [{ ...renamed, additions: -1 }];
    NodeAssert.throws(() => readThreadReview(malformed, cwd));
  },
);
