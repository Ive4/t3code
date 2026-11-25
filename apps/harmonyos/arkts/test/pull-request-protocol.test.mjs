import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import {
  PullRequestDiffInput,
  PullRequestFilterOptionsInput,
  PullRequestListInput,
  PullRequestRef,
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

const protocol = () => import(new URL("PullRequestProtocol.ets", client).href);
const decodeList = Schema.decodeUnknownSync(Schema.toCodecJson(PullRequestListInput));
const decodeRef = Schema.decodeUnknownSync(Schema.toCodecJson(PullRequestRef));
const decodeDiff = Schema.decodeUnknownSync(Schema.toCodecJson(PullRequestDiffInput));
const ref = { projectId: "project", host: "git.example.test", repository: "team/code", number: 17 };
const row = {
  ...ref,
  projectTitle: "Test project",
  title: "Fix profile state",
  url: "https://git.example.test/team/code/pull/17",
  state: "open",
  headBranch: "fix/profile",
  baseBranch: "main",
  updatedAt: "2026-11-25T09:00:00Z",
  author: { login: "reviewer", name: null },
  labels: [{ name: "bug" }],
};

NodeTest.test("encodes the read contracts and keeps host and project scope", async () => {
  const {
    pullRequestListRequest,
    pullRequestDetailRequest,
    pullRequestActivityRequest,
    pullRequestDiffBody,
  } = await protocol();
  const cursors = { "git.example.test team/code": "another-page" };
  const list = pullRequestListRequest({
    state: "open",
    involvement: "reviewing",
    query: "  fix  ",
    sort: "created",
    cursors,
  });
  NodeAssert.equal(list.tag, WS_METHODS.pullRequestsList);
  NodeAssert.equal("sort" in list.payload, false);
  NodeAssert.deepEqual(decodeList(list.payload), {
    state: "open",
    involvement: "reviewing",
    query: "fix",
    limit: 30,
    cursors,
  });
  const detail = pullRequestDetailRequest(ref);
  NodeAssert.equal(detail.tag, WS_METHODS.pullRequestsDetail);
  NodeAssert.deepEqual(decodeRef(detail.payload), ref);
  NodeAssert.deepEqual(decodeRef(pullRequestDetailRequest(ref, false).payload), {
    ...ref,
    allowStale: false,
  });
  const discussion = pullRequestActivityRequest(ref);
  NodeAssert.equal(discussion.tag, WS_METHODS.pullRequestsActivity);
  NodeAssert.deepEqual(decodeRef(discussion.payload), ref);
  NodeAssert.deepEqual(decodeDiff(JSON.parse(pullRequestDiffBody(ref, "next"))), {
    ...ref,
    cursor: "next",
  });
  NodeAssert.deepEqual(
    decodeDiff(JSON.parse(pullRequestDiffBody(ref, "next", "src/big file.ts"))),
    {
      ...ref,
      path: "src/big file.ts",
    },
  );
  for (const path of ["", " file", "/file", "dir/../file", "dir\0file"]) {
    NodeAssert.throws(() => pullRequestDiffBody(ref, undefined, path), /路径无效/);
  }
});

NodeTest.test(
  "rejects a detail from another project and preserves the actual host on accepted detail",
  async () => {
    const { readPullRequestDetail } = await protocol();
    const detail = {
      ...row,
      body: "Description",
      changedFiles: 2,
      createdAt: "2026-11-24T09:00:00Z",
    };
    NodeAssert.equal(readPullRequestDetail(detail, ref).host, ref.host);
    NodeAssert.equal(readPullRequestDetail(detail, ref).body, "Description");
    NodeAssert.equal(readPullRequestDetail(detail, ref).createdAt, detail.createdAt);
    NodeAssert.throws(
      () => readPullRequestDetail({ ...detail, projectId: "another" }, ref),
      /不匹配/,
    );
  },
);

NodeTest.test(
  "uses provider and viewer capabilities to gate editing and open-PR reviews",
  async () => {
    const { readPullRequestDetail, canEditPullRequestComment } = await protocol();
    const wire = {
      ...row,
      body: "Description",
      provider: "forgejo",
      headSha: "current-head",
      viewer: "Reviewer",
      capabilities: {
        comment: true,
        labels: true,
        reviewers: { request: true, listCandidates: true, searchCandidates: true },
        edit: { changeRequest: true, comment: true },
        review: { inlineComment: true, verdicts: ["comment", "approve", "request-changes"] },
      },
      viewerPermissions: {
        comment: true,
        actions: [],
        verdicts: ["comment", "request-changes"],
        requestReviewers: true,
      },
    };
    const detail = readPullRequestDetail(wire, ref);
    NodeAssert.equal(detail.headSha, "current-head");
    NodeAssert.equal(detail.actions.editChangeRequest, true);
    NodeAssert.equal(detail.actions.comment, true);
    NodeAssert.equal(detail.actions.inlineComment, true);
    NodeAssert.equal(detail.actions.requiresChangeSummary, true);
    NodeAssert.equal(detail.actions.editLabels, true);
    NodeAssert.equal(detail.actions.requestReviewers, true);
    NodeAssert.equal(detail.actions.searchReviewers, true);
    NodeAssert.deepEqual(detail.actions.verdicts, ["comment", "request-changes"]);
    const denied = readPullRequestDetail(
      {
        ...wire,
        viewerPermissions: { ...wire.viewerPermissions, editChangeRequest: false, labels: false },
      },
      ref,
    );
    NodeAssert.equal(denied.actions.editChangeRequest, false);
    NodeAssert.equal(denied.actions.editLabels, false);
    NodeAssert.equal(
      readPullRequestDetail({ ...wire, state: "closed" }, ref).actions.requestReviewers,
      false,
    );
    NodeAssert.deepEqual(
      readPullRequestDetail({ ...wire, state: "closed" }, ref).actions.verdicts,
      [],
    );
    NodeAssert.equal(
      canEditPullRequestComment(detail, { kind: "issue-comment", authorLogin: "reviewer" }),
      true,
    );
    NodeAssert.equal(
      canEditPullRequestComment(detail, {
        kind: "review-comment",
        authorLogin: "reviewer",
        canEdit: false,
      }),
      false,
    );
    NodeAssert.equal(
      canEditPullRequestComment(detail, { kind: "review", authorLogin: "reviewer", canEdit: true }),
      false,
    );
    NodeAssert.equal(readPullRequestDetail({ ...row, body: "Legacy" }, ref).actions.comment, false);
  },
);

NodeTest.test(
  "anchors removed, added and context lines without counting diff headers or metadata",
  async () => {
    const { pullRequestDiffLines } = await protocol();
    const patch =
      "diff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -11,2 +30,3 @@\n-old\n+first\n+second\n context\n\\ No newline at end of file\n";
    NodeAssert.deepEqual(pullRequestDiffLines(patch), [
      { side: "LEFT", line: 11, code: "-old" },
      { side: "RIGHT", line: 30, code: "+first" },
      { side: "RIGHT", line: 31, code: "+second" },
      { side: "RIGHT", line: 32, code: " context" },
    ]);
    NodeAssert.deepEqual(pullRequestDiffLines("GIT binary patch\n+not a diff line"), []);
  },
);

NodeTest.test(
  "continues cursor and legacy pages with stable sorting and scoped deduplication",
  async () => {
    const { readPullRequestPage, nextPullRequestQuery, mergePullRequestRows } = await protocol();
    const initial = { state: "open", involvement: "all" };
    const cursors = { "git.example.test team/code": "another-page" };
    const first = readPullRequestPage({
      entries: [row],
      providers: [],
      errors: [],
      nextCursors: cursors,
      truncated: false,
    });
    NodeAssert.deepEqual(nextPullRequestQuery(initial, first), { ...initial, cursors, limit: 30 });
    NodeAssert.equal(nextPullRequestQuery({ ...initial, sort: "oldest" }, first)?.sort, "oldest");
    const newer = { ...row, title: "Updated title", updatedAt: "2026-11-25T10:00:00Z" };
    const otherHost = { ...row, host: "mirror.example.test", number: 17 };
    const next = readPullRequestPage({
      entries: [newer, otherHost],
      providers: [],
      errors: [],
      nextCursors: {},
      truncated: true,
    });
    NodeAssert.deepEqual(
      mergePullRequestRows(first.rows, next.rows).map((entry) => entry.title),
      [newer.title, row.title],
    );
    NodeAssert.equal(mergePullRequestRows(next.rows, first.rows)[0]?.title, newer.title);
    NodeAssert.deepEqual(nextPullRequestQuery(initial, next), { ...initial, limit: 60 });
    NodeAssert.equal(nextPullRequestQuery({ ...initial, limit: 500 }, next), undefined);
    NodeAssert.equal(nextPullRequestQuery({ ...initial, cursors }, first), undefined);
  },
);

NodeTest.test(
  "sorts merged pages by update or creation time while keeping ties stable",
  async () => {
    const { readPullRequestPage, mergePullRequestRows, sortPullRequestRows } = await protocol();
    const page = (entries) => readPullRequestPage({ entries, providers: [], errors: [] });
    const earlier = {
      ...row,
      number: 1,
      updatedAt: "2026-11-25T11:00:00Z",
      createdAt: "2026-11-25T06:00:00Z",
    };
    const later = {
      ...row,
      number: 2,
      updatedAt: "2026-11-25T08:00:00Z",
      createdAt: "2026-11-25T09:30:00+02:00",
    };
    const legacy = { ...row, number: 3, updatedAt: "2026-11-25T07:00:00Z" };
    const tied = { ...later, number: 4, createdAt: "2026-11-25T07:30:00Z" };
    const rows = mergePullRequestRows(page([earlier, later]).rows, page([legacy, tied]).rows);
    NodeAssert.deepEqual(
      sortPullRequestRows(rows, "updated").map((entry) => entry.number),
      [1, 2, 4, 3],
    );
    NodeAssert.deepEqual(
      sortPullRequestRows(rows, "created").map((entry) => entry.number),
      [2, 4, 3, 1],
    );
    NodeAssert.deepEqual(
      sortPullRequestRows(rows, "oldest").map((entry) => entry.number),
      [3, 2, 4, 1],
    );
    NodeAssert.deepEqual(
      rows.map((entry) => entry.number),
      [1, 2, 4, 3],
    );
  },
);

NodeTest.test(
  "carries supported status filters through requests and pages without leaking invalid fields",
  async () => {
    const {
      pullRequestListRequest,
      nextPullRequestQuery,
      readPullRequestPage,
      filterPullRequestRows,
    } = await protocol();
    const filters = { draft: "only", review: "approved", checks: "passing" };
    const input = { state: "open", involvement: "all", projectId: ref.projectId, filters };
    const cursors = { "git.example.test team/code": "second-page" };
    const first = readPullRequestPage({
      entries: [{ ...row, isDraft: false, reviewDecision: "approved", checksState: "passing" }],
      providers: [],
      errors: [],
      nextCursors: cursors,
    });
    NodeAssert.deepEqual(filterPullRequestRows(first.rows, filters), []);
    const continuation = nextPullRequestQuery(input, first);
    NodeAssert.deepEqual(decodeList(pullRequestListRequest(continuation).payload), {
      ...input,
      limit: 30,
      cursors,
    });
    NodeAssert.deepEqual(
      decodeList(
        pullRequestListRequest({
          ...input,
          filters: { draft: "either", review: "none", checks: "pending" },
        }).payload,
      ).filters,
      { review: "none" },
    );
  },
);

NodeTest.test(
  "filters known PR status locally while retaining unavailable review and check states",
  async () => {
    const { readPullRequestPage, filterPullRequestRows } = await protocol();
    const page = readPullRequestPage({
      entries: [
        { ...row, number: 1, isDraft: true, reviewDecision: "approved", checksState: "passing" },
        {
          ...row,
          number: 2,
          isDraft: true,
          reviewDecision: "review-required",
          checksState: "pending",
        },
        {
          ...row,
          number: 3,
          isDraft: true,
          reviewDecision: "changes-requested",
          checksState: "failing",
        },
        { ...row, number: 4, isDraft: true },
        { ...row, number: 5, isDraft: false },
      ],
      providers: [],
      errors: [],
    });
    const numbers = (filters) =>
      filterPullRequestRows(page.rows, filters).map((entry) => entry.number);
    NodeAssert.deepEqual(numbers({ draft: "only", review: "approved", checks: "passing" }), [1, 4]);
    NodeAssert.deepEqual(numbers({ checks: "failing" }), [3, 4, 5]);
    NodeAssert.deepEqual(numbers({ review: "none" }), [4, 5]);
    NodeAssert.deepEqual(numbers({ review: "changes-requested" }), [3, 4, 5]);
    NodeAssert.deepEqual(numbers({ review: "review-required" }), [2, 4, 5]);
    NodeAssert.deepEqual(numbers({ draft: "hide" }), [5]);
    NodeAssert.deepEqual(numbers(undefined), [1, 2, 3, 4, 5]);
  },
);

NodeTest.test(
  "reads comments and raw diff pages while preserving pending and truncation states",
  async () => {
    const { readPullRequestDiscussion, readPullRequestDiff } = await protocol();
    const comments = [{ id: "a", body: "Overview", createdAt: row.updatedAt, author: row.author }];
    const reviewThreads = [
      {
        id: "r",
        path: "src/app.ts",
        line: 18,
        comments: [{ ...comments[0], body: "Check this case" }],
      },
    ];
    const discussion = readPullRequestDiscussion({
      comments,
      reviewThreads,
      commentsTruncated: true,
    });
    NodeAssert.deepEqual(
      discussion.comments.map((entry) => entry.location),
      ["", "src/app.ts:18"],
    );
    NodeAssert.ok(discussion.truncated);
    const patch =
      "diff --git a/src/app.ts b/src/app.ts\n--- a/src/app.ts\n+++ b/src/app.ts\n@@ -1,1 +1,1 @@\n-before\n+after\n";
    const diff = readPullRequestDiff({ patch, truncated: true, nextCursor: "next" });
    NodeAssert.equal(diff.files[0]?.path, "src/app.ts");
    NodeAssert.match(diff.files[0]?.patch ?? "", /\+after/);
    NodeAssert.equal(diff.nextCursor, "next");
    NodeAssert.ok(diff.truncated);
    const deleted =
      "diff --git a/gone b/gone\n--- a/gone\n+++ /dev/null\n@@ -1 +0,0 @@\n-deleted\n";
    const renamed =
      "diff --git a/old file b/new file\nsimilarity index 100%\nrename from old file\nrename to new file\n";
    NodeAssert.deepEqual(
      readPullRequestDiff({
        patch: `${deleted}${renamed}`,
        truncated: false,
        nextCursor: null,
      }).files.map((entry) => entry.path),
      ["gone", "new file"],
    );
  },
);

NodeTest.test("round-trips sort preferences and keeps older or invalid values usable", async () => {
  const { pullRequestViewMatches, readPullRequestPreferences, savePullRequestView } =
    await protocol();
  const legacy = { id: "legacy", name: "Legacy", state: "open", involvement: "all", query: "" };
  const scope = { state: "open", involvement: "all", query: "", sort: "created" };
  const invalid = { ...legacy, id: "invalid", sort: "unsupported" };
  const views = savePullRequestView([legacy, invalid], "one", "Newest", scope);
  const key = "preference-key";
  const restored = readPullRequestPreferences(
    JSON.stringify({
      key,
      state: scope.state,
      involvement: scope.involvement,
      sort: "oldest",
      views,
    }),
    key,
  );
  NodeAssert.equal(restored.sort, "oldest");
  NodeAssert.equal(restored.views.length, 3);
  NodeAssert.equal(restored.views[1]?.sort, undefined);
  NodeAssert.equal(restored.views[2]?.sort, "created");
  NodeAssert.ok(pullRequestViewMatches(restored.views[0], { ...scope, sort: "updated" }));
  NodeAssert.ok(pullRequestViewMatches(restored.views[1], { ...scope, sort: "updated" }));
  NodeAssert.equal(pullRequestViewMatches(restored.views[0], scope), false);
  NodeAssert.ok(pullRequestViewMatches(restored.views[2], scope));
  const unsupported = readPullRequestPreferences(
    JSON.stringify({ ...restored, sort: "unsupported" }),
    key,
  );
  NodeAssert.equal(unsupported.sort, undefined);
});

NodeTest.test(
  "restores active status filters in saved views and normalizes legacy storage",
  async () => {
    const { pullRequestViewMatches, savePullRequestView, readPullRequestPreferences } =
      await protocol();
    const key = "preference-key";
    const base = { state: "open", involvement: "all", query: "" };
    const scope = { ...base, filters: { draft: "only", review: "none", checks: "failing" } };
    const views = savePullRequestView(
      [{ ...base, id: "legacy", name: "Legacy" }],
      "one",
      "Filtered",
      scope,
    );
    const restored = readPullRequestPreferences(
      JSON.stringify({
        key,
        ...scope,
        views: [
          ...views,
          {
            ...base,
            id: "invalid",
            name: "Invalid",
            sort: "ignored",
            filters: { draft: "ignored", review: "approved", checks: "ignored" },
          },
        ],
      }),
      key,
    );
    NodeAssert.deepEqual(restored.filters, scope.filters);
    NodeAssert.deepEqual(restored.views[1]?.filters, scope.filters);
    NodeAssert.deepEqual(restored.views[2]?.filters, { review: "approved" });
    NodeAssert.ok(pullRequestViewMatches(restored.views[0], { ...base, filters: {} }));
    NodeAssert.ok(pullRequestViewMatches(restored.views[1], scope));
    NodeAssert.equal(pullRequestViewMatches(restored.views[1], base), false);
  },
);

NodeTest.test(
  "keeps project, author and label groups in list continuations and saved views",
  async () => {
    const {
      nextPullRequestQuery,
      pullRequestListRequest,
      pullRequestViewMatches,
      readPullRequestPreferences,
      savePullRequestView,
    } = await protocol();
    const scope = {
      state: "open",
      involvement: "all",
      sort: "oldest",
      projectId: "project",
      query: "",
      filters: {
        draft: "hide",
        author: "  @me ",
        labels: [["Bug", "fix"], [" Docs "]],
        excludedLabels: ["WIP", " "],
      },
    };
    const filters = {
      draft: "hide",
      author: "@me",
      labels: [["Bug", "fix"], ["Docs"]],
      excludedLabels: ["WIP"],
    };
    const cursors = { "git.example.test team/code": "next" };
    const next = nextPullRequestQuery(scope, {
      rows: [],
      messages: [],
      nextCursors: cursors,
      truncated: false,
    });
    NodeAssert.deepEqual(decodeList(pullRequestListRequest(next).payload), {
      state: "open",
      involvement: "all",
      projectId: "project",
      limit: 30,
      filters,
      cursors,
    });
    const views = savePullRequestView([], "one", "Project", scope);
    const restored = readPullRequestPreferences(
      JSON.stringify({ key: "account", ...scope, views }),
      "account",
    );
    NodeAssert.equal(restored.projectId, "project");
    NodeAssert.deepEqual(restored.filters, filters);
    NodeAssert.equal(restored.views[0].projectId, "project");
    NodeAssert.ok(
      pullRequestViewMatches(restored.views[0], {
        ...scope,
        filters: { ...filters, labels: [["Docs"], ["fix", "Bug"]] },
      }),
    );
    NodeAssert.ok(
      pullRequestViewMatches(
        { state: "open", involvement: "all", query: "" },
        {
          state: "open",
          involvement: "all",
          query: "",
          projectId: "",
          filters: { labels: [], excludedLabels: [] },
        },
      ),
    );
    NodeAssert.equal(
      pullRequestViewMatches(restored.views[0], { ...scope, projectId: "another" }),
      false,
    );
  },
);

NodeTest.test(
  "matches project, signed-in host login and inclusive/exclusive labels locally",
  async () => {
    const { readPullRequestPage, filterPullRequestRows } = await protocol();
    const labels = [{ name: "BUG" }, { name: "docs" }];
    const entries = [
      { ...row, labels, author: { login: "Alice", name: "A Person" } },
      {
        ...row,
        number: 18,
        labels: [...labels, { name: "wip" }],
        author: { login: "Alice", name: "A Person" },
      },
      {
        ...row,
        number: 19,
        labels: [{ name: "BUG" }],
        author: { login: "Alice", name: "A Person" },
      },
      {
        ...row,
        number: 20,
        labels,
        projectId: "other",
        author: { login: "Alice", name: "A Person" },
      },
      {
        ...row,
        number: 21,
        labels,
        host: "other.example.test",
        author: { login: "Alice", name: "A Person" },
      },
      {
        ...row,
        number: 22,
        labels,
        host: "other.example.test",
        author: { login: "bob", name: "Other Name" },
      },
    ];
    const { rows } = readPullRequestPage({
      entries,
      errors: [],
      providers: [],
      truncated: false,
      viewers: { [row.host]: "alice", "other.example.test": "Bob" },
    });
    const filters = { author: "me", labels: [["bug", "patch"], ["Docs"]], excludedLabels: ["WIP"] };
    NodeAssert.deepEqual(
      filterPullRequestRows(rows, filters, row.projectId).map((entry) => entry.number),
      [17, 22],
    );
    NodeAssert.deepEqual(
      filterPullRequestRows(rows, { author: "aLiCe" }, "other").map((entry) => entry.number),
      [20],
    );
  },
);

NodeTest.test(
  "scopes candidate reads and keeps provider identities and label colours",
  async () => {
    const { pullRequestFilterOptionsRequest, readPullRequestFilterOptions } = await import(
      new URL("PullRequestFilterOptionsProtocol.ets", client).href
    );
    const decodeOptions = Schema.decodeUnknownSync(
      Schema.toCodecJson(PullRequestFilterOptionsInput),
    );
    const request = pullRequestFilterOptionsRequest("excluded-labels", "project", "  fi ");
    NodeAssert.equal(request.tag, WS_METHODS.pullRequestsFilterOptions);
    NodeAssert.deepEqual(decodeOptions(request.payload), {
      kind: "labels",
      projectId: "project",
      query: "fi",
    });
    const longQuery = "q".repeat(101);
    NodeAssert.deepEqual(
      decodeOptions(pullRequestFilterOptionsRequest("authors", " ", longQuery).payload),
      {
        kind: "authors",
        query: longQuery.slice(0, 100),
      },
    );
    NodeAssert.throws(() => pullRequestFilterOptionsRequest("projects"), /项目/);
    const data = {
      labels: [
        { name: "fix", color: "ab11cf" },
        { name: "plain", color: null },
      ],
      authors: [{ login: "alice", name: "A Person", avatarUrl: null }],
      truncated: true,
    };
    NodeAssert.deepEqual(readPullRequestFilterOptions(data, "labels"), {
      candidates: [
        { key: "fix", title: "fix", color: "#ab11cf" },
        { key: "plain", title: "plain" },
      ],
      truncated: true,
    });
    NodeAssert.deepEqual(readPullRequestFilterOptions(data, "authors").candidates, [
      { key: "alice", title: "A Person" },
    ]);
  },
);

NodeTest.test(
  "prepares readable file stats and grouping for the dedicated diff route",
  async () => {
    const { groupPullRequestFiles, readPullRequestDiff } = await protocol();
    const renamed = [
      'diff --git a/src/old name.ets "b/src/ \\346\\226\\260 \\345\\220\\215.ets"',
      "rename from src/old name.ets",
      'rename to "src/ \\346\\226\\260 \\345\\220\\215.ets"',
      "--- a/src/old name.ets\t",
      '+++ "b/src/ \\346\\226\\260 \\345\\220\\215.ets"',
      "@@ -1 +1,2 @@",
      "-before",
      "+after",
      "+++ b/literal-content",
      "",
    ].join("\n");
    const binary =
      "diff --git a/logo.png b/logo.png\nBinary files a/logo.png and b/logo.png differ\n";
    const diff = readPullRequestDiff({
      patch: renamed + binary,
      truncated: true,
      nextCursor: "second-page",
      omittedFileStats: [{ path: "src/generated.ets", additions: 500, deletions: 0 }],
      withheldFilesReadable: true,
    });
    NodeAssert.deepEqual(
      diff.files.map(({ path, previousPath, additions, deletions, withheld }) => ({
        path,
        previousPath,
        additions,
        deletions,
        withheld,
      })),
      [
        {
          path: "src/ 新 名.ets",
          previousPath: "src/old name.ets",
          additions: 2,
          deletions: 1,
          withheld: false,
        },
        { path: "logo.png", previousPath: null, additions: 0, deletions: 0, withheld: false },
        {
          path: "src/generated.ets",
          previousPath: null,
          additions: 500,
          deletions: 0,
          withheld: true,
        },
      ],
    );
    NodeAssert.deepEqual(
      groupPullRequestFiles(diff.files).map(({ directory, files }) => [directory, files.length]),
      [
        ["src", 1],
        ["", 1],
        ["src", 1],
      ],
    );
    NodeAssert.equal(diff.nextCursor, "second-page");
    NodeAssert.equal(diff.withheldFilesReadable, true);
    NodeAssert.equal(
      readPullRequestDiff({ patch: "", truncated: false, nextCursor: null }).withheldFilesReadable,
      undefined,
    );
    NodeAssert.match(diff.files[0].patch, /\+after/);
    NodeAssert.doesNotMatch(diff.files[0].patch, /logo\.png/);
  },
);

NodeTest.test("accepts only a complete, path-matched patch for one withheld file", async () => {
  const { readPullRequestFileDiff } = await protocol();
  const path = "src/new file.ts";
  const patch =
    "diff --git a/src/old.ts b/src/new file.ts\nrename from src/old.ts\nrename to src/new file.ts\n" +
    "--- a/src/old.ts\n+++ b/src/new file.ts\n@@ -1 +1,2 @@\n-before\n+after\n+new\n";
  const result = { patch, truncated: false, nextCursor: null };
  NodeAssert.deepEqual(readPullRequestFileDiff(result, path), {
    path,
    previousPath: "src/old.ts",
    additions: 2,
    deletions: 1,
    patch,
    withheld: false,
  });
  NodeAssert.throws(() => readPullRequestFileDiff(result, "src/old.ts"), /不匹配/);
  NodeAssert.throws(
    () => readPullRequestFileDiff({ ...result, patch: patch + patch }, path),
    /不匹配/,
  );
  NodeAssert.throws(
    () => readPullRequestFileDiff({ ...result, patch: "unscoped patch" }, path),
    /不匹配/,
  );
  NodeAssert.throws(
    () => readPullRequestFileDiff({ ...result, nextCursor: "next" }, path),
    /不完整/,
  );
  NodeAssert.throws(() => readPullRequestFileDiff({ ...result, truncated: true }, path), /不完整/);
  NodeAssert.equal(readPullRequestFileDiff({ ...result, patch: "" }, path), undefined);
  const binary =
    "diff --git a/logo.png b/logo.png\nBinary files a/logo.png and b/logo.png differ\n";
  NodeAssert.equal(readPullRequestFileDiff({ ...result, patch: binary }, "logo.png"), undefined);
  NodeAssert.throws(() => readPullRequestFileDiff({ ...result, patch: binary }, path), /不匹配/);
});

NodeTest.test(
  "keeps saved views and list controls within the account and environment",
  async () => {
    const { pullRequestPreferencesKey, readPullRequestPreferences, savePullRequestView } =
      await protocol();
    const key = pullRequestPreferencesKey("alice", "code");
    NodeAssert.notEqual(key, pullRequestPreferencesKey("bob", "code"));
    NodeAssert.notEqual(key, pullRequestPreferencesKey("alice", "another"));
    const scope = { state: "closed", involvement: "reviewing", query: "  fix the bug   " };
    const views = savePullRequestView([], "one", "  Reviews  ", scope);
    const raw = JSON.stringify({ key, state: scope.state, involvement: scope.involvement, views });
    NodeAssert.deepEqual(readPullRequestPreferences(raw, key), {
      key,
      state: "closed",
      involvement: "reviewing",
      views: [{ id: "one", name: "Reviews", ...scope, query: scope.query.trim() }],
    });
    NodeAssert.deepEqual(
      readPullRequestPreferences(raw, pullRequestPreferencesKey("bob", "code")),
      {
        key: pullRequestPreferencesKey("bob", "code"),
        state: "open",
        involvement: "all",
        views: [],
      },
    );
    NodeAssert.equal(readPullRequestPreferences("not JSON", key).state, "open");
  },
);

NodeTest.test(
  "matches trimmed queries and edits one named view without changing others",
  async () => {
    const { pullRequestViewMatches, savePullRequestView } = await protocol();
    const scope = { state: "open", involvement: "all", query: " prototype " };
    const views = savePullRequestView([], "one", "Prototype", scope);
    NodeAssert.ok(pullRequestViewMatches(views[0], { ...scope, query: "prototype" }));
    NodeAssert.equal(
      pullRequestViewMatches(views[0], { ...scope, involvement: "reviewing" }),
      false,
    );
    NodeAssert.throws(() => savePullRequestView(views, "two", "prototype", scope), /已存在/);
    NodeAssert.throws(() => savePullRequestView(views, "two", " ", scope), /名称/);
    const added = savePullRequestView(views, "two", "Closed", { ...scope, state: "closed" });
    const updated = savePullRequestView(added, "one", "Open", { ...scope, query: "next" });
    NodeAssert.deepEqual(updated, [{ ...views[0], name: "Open", query: "next" }, added[1]]);
  },
);
