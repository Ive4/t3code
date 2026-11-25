import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";

const source = new URL("../entry/src/main/ets/client/PullRequestReviewDraft.ets", import.meta.url);
const loader = NodeModule.registerHooks({
  load(url, context, nextLoad) {
    if (url !== source.href) return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(source, "utf8")),
    };
  },
});
NodeTest.after(() => loader.deregister());

const target = {
  projectId: "project",
  host: "git.example.test",
  repository: "team/code",
  number: 7,
};
const line = { path: "src/app.ts", side: "RIGHT", line: 18, headSha: "current", code: "changed" };

NodeTest.test(
  "keeps drafts scoped to their account, environment, and PR after a disk round trip",
  async () => {
    const { emptyPullRequestReviewDraft, pullRequestReviewDraftKey, readPullRequestReviewDrafts } =
      await import(source.href);
    const key = pullRequestReviewDraftKey("owner", "env", target);
    NodeAssert.notEqual(key, pullRequestReviewDraftKey("", "env", target));
    NodeAssert.notEqual(key, pullRequestReviewDraftKey("owner", "other-env", target));
    NodeAssert.notEqual(
      key,
      pullRequestReviewDraftKey("owner", "env", { ...target, host: "mirror.example.test" }),
    );
    const draft = {
      ...emptyPullRequestReviewDraft(),
      summary: "🧪".repeat(30_000),
      comment: "A comment",
    };
    const saved = readPullRequestReviewDrafts(
      JSON.stringify({ version: 1, drafts: { [key]: draft } }),
    );
    NodeAssert.deepEqual(saved[key], draft);
    NodeAssert.throws(() => readPullRequestReviewDrafts('{"version":2,"drafts":{}}'));
  },
);

NodeTest.test(
  "repositions an existing line draft and validates branch and provider rules",
  async () => {
    const { emptyPullRequestReviewDraft, withPullRequestLineDraft, pullRequestReviewDraftProblem } =
      await import(source.href);
    const draft = withPullRequestLineDraft(emptyPullRequestReviewDraft(), line, "Check this", "a");
    NodeAssert.equal(
      pullRequestReviewDraftProblem(draft, "new-head", "comment", true, false),
      "stale",
    );
    NodeAssert.equal(
      pullRequestReviewDraftProblem(draft, "current", "comment", false, false),
      "inline-unavailable",
    );
    NodeAssert.equal(
      pullRequestReviewDraftProblem(draft, "current", "request-changes", true, true),
      "summary-required",
    );
    const amended = withPullRequestLineDraft(
      draft,
      { ...line, draftId: "a", line: 20, headSha: "new-head" },
      "Check this here",
      "a",
    );
    NodeAssert.deepEqual(JSON.parse(JSON.stringify(amended.comments)), [
      { ...line, id: "a", line: 20, headSha: "new-head", body: "Check this here" },
    ]);
    NodeAssert.equal(
      pullRequestReviewDraftProblem(amended, "new-head", "comment", true, false),
      "",
    );
    NodeAssert.equal(
      pullRequestReviewDraftProblem(
        emptyPullRequestReviewDraft(),
        "new-head",
        "approve",
        true,
        false,
      ),
      "",
    );
  },
);
