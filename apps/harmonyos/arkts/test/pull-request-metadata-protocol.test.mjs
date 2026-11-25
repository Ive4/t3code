import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import {
  PullRequestLabelCandidateList,
  PullRequestRef,
  PullRequestReviewerCandidateList,
  PullRequestReviewerCandidatesInput,
  WS_METHODS,
} from "@t3tools/contracts";
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

const protocol = () => import(new URL("PullRequestMetadataProtocol.ets", client).href);
const decodeRef = Schema.decodeUnknownSync(Schema.toCodecJson(PullRequestRef));
const decodeReviewerInput = Schema.decodeUnknownSync(
  Schema.toCodecJson(PullRequestReviewerCandidatesInput),
);
const decodeReviewers = Schema.decodeUnknownSync(
  Schema.toCodecJson(PullRequestReviewerCandidateList),
);
const decodeLabels = Schema.decodeUnknownSync(Schema.toCodecJson(PullRequestLabelCandidateList));
const ref = { projectId: "project-2", host: "forge.example", repository: "team/code", number: 17 };

NodeTest.test(
  "binds candidate reads to the pull request and only sends bounded reviewer searches",
  async () => {
    const { pullRequestMetadataRequest } = await protocol();
    const labels = pullRequestMetadataRequest(ref, "labels", " documentation ");
    NodeAssert.equal(labels.tag, WS_METHODS.pullRequestsLabelCandidates);
    NodeAssert.deepEqual(labels.payload, ref);
    NodeAssert.deepEqual(decodeRef(labels.payload), ref);

    const reviewers = pullRequestMetadataRequest(ref, "reviewers", " team-dev ");
    NodeAssert.equal(reviewers.tag, WS_METHODS.pullRequestsReviewerCandidates);
    NodeAssert.deepEqual(decodeReviewerInput(reviewers.payload), { ...ref, query: "team-dev" });
    NodeAssert.deepEqual(pullRequestMetadataRequest(ref, "reviewers", "   ").payload, ref);
    const longQuery = `${"x".repeat(99)} more`;
    const bounded = pullRequestMetadataRequest(ref, "reviewers", longQuery);
    NodeAssert.equal(decodeReviewerInput(bounded.payload).query, "x".repeat(99));
    NodeAssert.throws(() => pullRequestMetadataRequest({ ...ref, host: "" }, "reviewers"), /项目/);
  },
);

NodeTest.test(
  "converts real candidate pages while keeping selection, reviewer identity, and truncation",
  async () => {
    const { readPullRequestMetadata } = await protocol();
    const reviewers = decodeReviewers({
      candidates: [
        {
          id: "17",
          kind: "user",
          login: "alice-dev",
          name: "Alice",
          avatarUrl: null,
          isRequested: true,
        },
        {
          id: "17",
          kind: "team",
          login: "core-team",
          name: null,
          avatarUrl: null,
          isRequested: false,
        },
      ],
      truncated: true,
    });
    NodeAssert.deepEqual(readPullRequestMetadata(reviewers, "reviewers"), {
      candidates: [
        { key: "user:17", title: "Alice", subtitle: "alice-dev", selected: true, kind: "user" },
        {
          key: "team:17",
          title: "core-team",
          subtitle: "core-team",
          selected: false,
          kind: "team",
        },
      ],
      truncated: true,
    });
    const labels = decodeLabels({
      candidates: [
        { name: "regression", description: "Needs attention", color: "BD2C00", isApplied: true },
        { name: "design", description: null, color: null, isApplied: false },
      ],
      truncated: false,
    });
    NodeAssert.deepEqual(readPullRequestMetadata(labels, "labels"), {
      candidates: [
        {
          key: "regression",
          title: "regression",
          subtitle: "Needs attention",
          color: "#BD2C00",
          selected: true,
        },
        { key: "design", title: "design", subtitle: "", selected: false },
      ],
      truncated: false,
    });
    NodeAssert.throws(() => readPullRequestMetadata(reviewers, "labels"), /候选/);
    NodeAssert.throws(() => readPullRequestMetadata(undefined, "reviewers"), /候选/);
  },
);
