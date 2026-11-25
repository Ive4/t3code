import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import { PullRequestFilterOptionsInput, WS_METHODS } from "@t3tools/contracts";
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

const protocol = () => import(new URL("PullRequestReferenceProtocol.ets", client).href);
const ref = { projectId: "project", host: "git.example.test", repository: "team/code", number: 17 };
const wire = {
  ...ref,
  projectTitle: "Test project",
  title: "Example",
  body: "",
  url: "https://git.example.test/team/code/pull/17",
  state: "open",
  headBranch: "example",
  baseBranch: "main",
  updatedAt: "2026-11-25T09:00:00Z",
};

NodeTest.test(
  "honors provider capabilities and matches only the token ending at the caret",
  async () => {
    const { detectPullRequestComposerTrigger, insertPullRequestCompletion } = await protocol();
    const { readPullRequestDetail } = await import(new URL("PullRequestProtocol.ets", client).href);
    const legacy = readPullRequestDetail(wire, ref).completion;
    const gitlab = readPullRequestDetail(
      { ...wire, capabilities: { mentions: true, referenceSigils: ["#", "!", "%"] } },
      ref,
    ).completion;
    NodeAssert.deepEqual(gitlab, { mentions: true, referenceSigils: ["#", "!"] });
    NodeAssert.equal(detectPullRequestComposerTrigger("@julius", 7, legacy), undefined);
    NodeAssert.equal(detectPullRequestComposerTrigger("mail@julius", 11, gitlab), undefined);
    NodeAssert.equal(detectPullRequestComposerTrigger("@julius", 3, gitlab), undefined);
    NodeAssert.equal(detectPullRequestComposerTrigger("## Heading", 2, gitlab), undefined);
    const text = "cc @प्रिया next line";
    const cursor = "cc @प्रिया".length;
    const trigger = detectPullRequestComposerTrigger(text, cursor, gitlab);
    NodeAssert.deepEqual(trigger, {
      kind: "mention",
      sigil: "@",
      query: "प्रिया",
      rangeStart: 3,
      rangeEnd: cursor,
    });
    NodeAssert.deepEqual(insertPullRequestCompletion(text, trigger, "@priya"), {
      text: "cc @priya next line",
      cursor: "cc @priya ".length,
    });
  },
);

NodeTest.test(
  "reads the Android filter-options request and legacy candidate response",
  async () => {
    const { pullRequestCompletionOptionsRequest, readPullRequestCompletionOptions } =
      await protocol();
    const decode = Schema.decodeUnknownSync(Schema.toCodecJson(PullRequestFilterOptionsInput));
    const mention = pullRequestCompletionOptionsRequest(ref, {
      kind: "mention",
      sigil: "@",
      query: "",
    });
    NodeAssert.equal(mention.tag, WS_METHODS.pullRequestsFilterOptions);
    NodeAssert.deepEqual(decode(mention.payload), { kind: "authors", projectId: ref.projectId });
    const query = "a".repeat(100);
    const reference = pullRequestCompletionOptionsRequest(ref, {
      kind: "reference",
      sigil: "!",
      query: query + "a",
    });
    NodeAssert.deepEqual(decode(reference.payload), {
      kind: "references",
      projectId: ref.projectId,
      sigil: "!",
      query,
    });
    NodeAssert.deepEqual(
      readPullRequestCompletionOptions({ labels: [], authors: [], truncated: false }),
      { authors: [], references: [] },
    );
  },
);

NodeTest.test("narrows retained options to the latest sigil and query", async () => {
  const { pullRequestCompletions, readPullRequestCompletionOptions } = await protocol();
  const options = readPullRequestCompletionOptions({
    labels: [],
    authors: [
      { login: "julius", name: "Julius" },
      { login: "ryan", name: "Ryan" },
      { login: "tony", name: "Theo Joseph" },
    ],
    references: [
      { reference: "#123", kind: "issue", number: 123, title: "Crash", state: "open" },
      { reference: "#9", kind: "issue", number: 9, title: "Follow up to 12", state: "closed" },
      { reference: "!12", kind: "change-request", number: 12, title: "Crash", state: "merged" },
    ],
    truncated: false,
  });
  NodeAssert.deepEqual(
    pullRequestCompletions({ kind: "mention", sigil: "@", query: "jo" }, options).map(
      (entry) => entry.token,
    ),
    ["@tony"],
  );
  NodeAssert.deepEqual(
    pullRequestCompletions({ kind: "reference", sigil: "#", query: "12" }, options).map(
      (entry) => entry.token,
    ),
    ["#123", "#9"],
  );
});
