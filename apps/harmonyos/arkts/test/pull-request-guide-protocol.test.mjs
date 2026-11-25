import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import { PullRequestRef, PullRequestReviewGuideResult, WS_METHODS } from "@t3tools/contracts";
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
NodeTest.after(() => loader.deregister());

const protocol = () => import(new URL("PullRequestGuideProtocol.ets", client).href);
const decodeRef = Schema.decodeUnknownSync(Schema.toCodecJson(PullRequestRef));
const decodeGuideResult = Schema.decodeUnknownSync(
  Schema.toCodecJson(PullRequestReviewGuideResult),
);
const ref = { projectId: "project-2", host: "forge.example", repository: "team/code", number: 17 };
const path = "src/client protocol.ts";
const stop = {
  title: "Check the request boundary",
  summary: "Compare the target scope.",
  attention: { kind: "contract", note: "Check legacy data." },
  excerpts: [{ path, side: "new", start: 11, end: 12, caption: "Read both rows." }],
  files: [{ path }, { path: "src/server.ts", note: "Check the caller." }],
  notes: [{ path, line: 11, title: "Check scope", body: "Use the selected project." }],
  questions: ["Is this backward compatible?"],
};
const guide = {
  modelSelection: { instanceId: "codex", model: "gpt-5" },
  headSha: "draft-commit",
  generatedAt: "2025-02-01T12:00:00.000Z",
  stops: [stop],
};
const patch = [
  `diff --git a/${path} b/${path}`,
  `--- a/${path}`,
  `+++ b/${path}`,
  "@@ -9,3 +10,3 @@",
  " preceding context",
  "-old content",
  "+new content",
  " subsequent context",
  "@@ -30 +32,0 @@",
  "-removed at a different hunk",
  "@@ -40,0 +50 @@",
  "+addition at a different hunk",
  "\\ No newline at end of file",
].join("\n");

NodeTest.test(
  "scopes Guide reads and generation to the pull request and uses the target environment setting",
  async () => {
    const { generatePullRequestGuideRequest, pullRequestGuideRequest, pullRequestGuidesEnabled } =
      await protocol();
    const request = pullRequestGuideRequest(ref);
    NodeAssert.equal(request.tag, WS_METHODS.pullRequestsReviewGuide);
    NodeAssert.deepEqual(decodeRef(request.payload), ref);
    NodeAssert.throws(() => pullRequestGuideRequest({ ...ref, host: "" }), /项目/);
    const generation = generatePullRequestGuideRequest(ref);
    NodeAssert.equal(generation.tag, WS_METHODS.pullRequestsGenerateReviewGuide);
    NodeAssert.deepEqual(decodeRef(generation.payload), ref);
    NodeAssert.throws(() => generatePullRequestGuideRequest({ ...ref, projectId: "" }), /项目/);
    NodeAssert.equal(pullRequestGuidesEnabled({ settings: { reviewGuidesEnabled: true } }), true);
    NodeAssert.equal(
      pullRequestGuidesEnabled({ settings: { reviewGuidesEnabled: "true" } }),
      false,
    );
    NodeAssert.equal(pullRequestGuidesEnabled({ reviewGuidesEnabled: true }), false);
    NodeAssert.equal(pullRequestGuidesEnabled(undefined), false);
  },
);

NodeTest.test(
  "reads completed, running, failed and absent Guides and identifies older versions",
  async () => {
    const { readPullRequestGuide, pullRequestGuideIsStale } = await protocol();
    const empty = readPullRequestGuide(
      decodeGuideResult({ guide: null, run: null, currentHeadSha: null }),
    );
    NodeAssert.deepEqual(empty, { guide: null, run: null, currentHeadSha: null });
    NodeAssert.equal(pullRequestGuideIsStale(empty), false);

    const running = decodeGuideResult({
      guide,
      run: { _tag: "Running", headSha: "current-commit", startedAt: "2025-02-01T13:00:00.000Z" },
      currentHeadSha: "current-commit",
    });
    const older = readPullRequestGuide(running);
    NodeAssert.deepEqual(older.guide?.stops, [stop]);
    NodeAssert.equal(older.run?._tag, "Running");
    NodeAssert.equal(pullRequestGuideIsStale(older), true);
    NodeAssert.equal(pullRequestGuideIsStale({ ...older, currentHeadSha: guide.headSha }), false);
    NodeAssert.equal(pullRequestGuideIsStale({ ...older, currentHeadSha: null }), false);
    const failed = decodeGuideResult({
      guide: null,
      run: {
        _tag: "Failed",
        headSha: "current-commit",
        detail: "Generation failed",
        failedAt: "2025-02-01T13:00:00.000Z",
      },
      currentHeadSha: "current-commit",
    });
    NodeAssert.equal(readPullRequestGuide(failed).run?.detail, "Generation failed");
  },
);

NodeTest.test(
  "rejects malformed Guide routes and ranges but preserves missing workspace file names",
  async () => {
    const { readPullRequestGuide } = await protocol();
    const make = (entry) => ({
      guide: { ...guide, stops: [entry] },
      run: null,
      currentHeadSha: guide.headSha,
    });
    const invalidExcerpt = (changes) =>
      make({ ...stop, excerpts: [{ ...stop.excerpts[0], ...changes }] });
    NodeAssert.equal(
      readPullRequestGuide(make(stop)).guide?.stops[0]?.files[1]?.path,
      "src/server.ts",
    );
    NodeAssert.throws(() => readPullRequestGuide(invalidExcerpt({ start: 0 })), /导览/);
    NodeAssert.throws(() => readPullRequestGuide(invalidExcerpt({ start: 13 })), /导览/);
    NodeAssert.throws(
      () => readPullRequestGuide(invalidExcerpt({ end: Number.MAX_SAFE_INTEGER + 1 })),
      /导览/,
    );
    for (const path of [
      "/outside",
      "src/../outside",
      "src\\..\\outside",
      "https://host/file.ts",
      "C:\\file.ts",
    ]) {
      NodeAssert.throws(() => readPullRequestGuide(invalidExcerpt({ path })), /导览/);
    }
    NodeAssert.throws(
      () => readPullRequestGuide(make({ ...stop, notes: [{ ...stop.notes[0], line: 2.5 }] })),
      /导览/,
    );
    NodeAssert.throws(
      () => readPullRequestGuide({ guide: null, run: { _tag: "Failed" }, currentHeadSha: null }),
      /导览/,
    );
  },
);

NodeTest.test(
  "matches old and new Guide excerpts including neighboring paired changes and context",
  async () => {
    const { pullRequestGuideExcerpt } = await protocol();
    NodeAssert.equal(
      pullRequestGuideExcerpt(patch, { path, side: "new", start: 11, end: 12 }),
      "-old content\n+new content\n subsequent context",
    );
    NodeAssert.equal(
      pullRequestGuideExcerpt(patch, { path, side: "old", start: 9, end: 10 }),
      " preceding context\n-old content\n+new content",
    );
    NodeAssert.equal(
      pullRequestGuideExcerpt(patch, { path, side: "old", start: 30, end: 30 }),
      "-removed at a different hunk",
    );
    NodeAssert.equal(
      pullRequestGuideExcerpt(patch, { path, side: "new", start: 50, end: 50 }),
      "+addition at a different hunk",
    );
    NodeAssert.equal(pullRequestGuideExcerpt(patch, { path, side: "new", start: 11, end: 10 }), "");
    NodeAssert.equal(
      pullRequestGuideExcerpt(patch, { path, side: "new", start: 999, end: 999 }),
      "",
    );
    NodeAssert.equal(
      pullRequestGuideExcerpt("+line without a hunk", { path, side: "new", start: 1, end: 1 }),
      "",
    );
  },
);
