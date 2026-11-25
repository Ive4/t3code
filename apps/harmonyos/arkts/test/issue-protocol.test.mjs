import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import {
  IssueCandidates,
  IssueDetail,
  IssueListInput,
  IssueListResult,
  IssueRef,
  IssueScopeRef,
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

const protocol = () => import(new URL("IssueProtocol.ets", client).href);
const decodeListInput = Schema.decodeUnknownSync(Schema.toCodecJson(IssueListInput));
const decodeListResult = Schema.decodeUnknownSync(Schema.toCodecJson(IssueListResult));
const decodeIssueRef = Schema.decodeUnknownSync(Schema.toCodecJson(IssueRef));
const decodeIssueScope = Schema.decodeUnknownSync(Schema.toCodecJson(IssueScopeRef));
const decodeIssueCandidates = Schema.decodeUnknownSync(Schema.toCodecJson(IssueCandidates));
const decodeDetail = Schema.decodeUnknownSync(Schema.toCodecJson(IssueDetail));

const ref = {
  projectId: "workspace-1",
  tracker: "gitlab",
  host: "git.intranet.example",
  scope: "team/repo",
  key: "27",
};
const actor = { login: "someone", name: "Example", avatarUrl: null };
const now = "2026-11-25T12:00:00.000Z";
const row = {
  ...ref,
  projectTitle: "Workspace",
  displayKey: "#27",
  title: "Keyboard focus",
  url: "https://git.intranet.example/team/repo/-/issues/27",
  author: actor,
  state: { category: "open", name: "In Review" },
  createdAt: now,
  updatedAt: now,
  closedAt: null,
  assignees: [],
  labels: [{ name: "Accessibility", color: "0099ff" }],
  commentCount: 1,
};

NodeTest.test(
  "issue reads carry filters, continuations and the complete tracker address",
  async () => {
    const { issueListRequest, issueDetailRequest, supportsIssues } = await protocol();
    const request = issueListRequest(
      {
        state: "closed",
        query: "  focus  ",
        involvement: "assigned",
        sort: "created",
        labels: ["Accessibility", "UI"],
        assignee: "someone",
      },
      { scope1: "opaque/cursor=1" },
      true,
    );
    NodeAssert.equal(request.tag, "issues.list");
    NodeAssert.deepEqual(decodeListInput(request.payload), {
      state: "closed",
      query: "focus",
      involvement: "assigned",
      sort: "created",
      labels: ["Accessibility", "UI"],
      assignee: "someone",
      limit: 50,
      cursors: { scope1: "opaque/cursor=1" },
      refresh: true,
    });
    NodeAssert.deepEqual(decodeIssueRef(issueDetailRequest(row).payload), ref);
    NodeAssert.deepEqual(issueDetailRequest(row).payload, ref);
    NodeAssert.equal(issueDetailRequest(row).tag, "issues.detail");
    NodeAssert.equal(supportsIssues({ environment: { capabilities: { issues: true } } }), true);
    NodeAssert.equal(supportsIssues({ environment: { capabilities: { issues: false } } }), false);
  },
);

NodeTest.test(
  "issue list rejects unusable addresses and keeps tracker warnings and cursors",
  async () => {
    const { readIssuePage, issueRefKey, mergeIssueEntries, issueSearchEntries } = await protocol();
    const next = { ...row, key: "28", displayKey: "#28", updatedAt: "2026-11-26T12:00:00.000Z" };
    const first = {
      entries: [row],
      viewers: {},
      trackers: [
        {
          tracker: "gitlab",
          host: row.host,
          projectCount: 1,
          capabilities: null,
          configured: true,
          detail: null,
        },
      ],
      errors: [{ projectId: "workspace-2", projectTitle: "Other", message: "Offline" }],
      nextCursors: { scope1: "next" },
    };
    NodeAssert.deepEqual(readIssuePage(first), decodeListResult(first));
    NodeAssert.throws(() => readIssuePage({ ...first, entries: [{ ...row, scope: "" }] }), /工单/);
    NodeAssert.throws(() => readIssuePage({ ...first, nextCursors: { scope1: 1 } }), /工单/);
    NodeAssert.notEqual(issueRefKey(ref), issueRefKey({ ...ref, host: "git.other.example" }));
    NodeAssert.notEqual(issueRefKey(ref), issueRefKey({ ...ref, projectId: "workspace-2" }));
    NodeAssert.deepEqual(mergeIssueEntries([row], [row, next], "updated"), [next, row]);
    NodeAssert.deepEqual(issueSearchEntries(readIssuePage(first), " FOCUS "), [row]);
    NodeAssert.deepEqual(issueSearchEntries(readIssuePage(first), "#27"), [row]);
    NodeAssert.deepEqual(issueSearchEntries(readIssuePage(first), "nothing matched"), []);
    NodeAssert.deepEqual(
      issueSearchEntries(
        { ...first, trackers: [{ ...first.trackers[0], capabilities: { search: true } }] },
        "body match",
      ),
      [row],
    );
  },
);

NodeTest.test(
  "issue detail rejects crossover and gates write-form affordances per capability and permission",
  async () => {
    const { readIssueDetail, issueCanShowEditor } = await protocol();
    const detail = {
      ...row,
      writable: true,
      viewer: actor.login,
      viewerPermissions: {
        edit: true,
        labels: false,
        assignees: true,
        comment: false,
        setState: true,
      },
      capabilities: {
        create: true,
        edit: true,
        labels: true,
        assignees: false,
        comment: true,
        reactions: false,
        templates: false,
        linkedPullRequests: false,
        events: false,
        search: true,
      },
      states: [row.state],
      body: "Reproduce by focusing the item.",
      comments: [{ id: "one", author: actor, body: "Confirmed", createdAt: now, url: null }],
      commentsCursor: null,
      events: [],
      linkedPullRequests: [],
    };
    NodeAssert.deepEqual(readIssueDetail(detail, ref), decodeDetail(detail));
    NodeAssert.throws(() => readIssueDetail({ ...detail, projectId: "workspace-2" }, ref), /工单/);
    NodeAssert.throws(() => readIssueDetail({ ...detail, host: "git.other.example" }, ref), /工单/);
    NodeAssert.equal(issueCanShowEditor(detail, true, "edit"), true);
    NodeAssert.equal(issueCanShowEditor(detail, true, "labels"), false);
    NodeAssert.equal(issueCanShowEditor(detail, true, "assignees"), false);
    NodeAssert.equal(issueCanShowEditor(detail, false, "edit"), false);
    NodeAssert.equal(issueCanShowEditor({ ...detail, writable: false }, true, "edit"), false);
  },
);

NodeTest.test(
  "saved issue views restore valid filters and ignore malformed or duplicate stored entries",
  async () => {
    const { readIssueSavedViews, issueSavedViewMatches } = await import(
      new URL("IssueSavedViews.ets", client).href
    );
    const view = {
      id: "issues-assigned",
      name: "Assigned",
      query: " keyboard ",
      state: "open",
      involvement: "assigned",
      sort: "updated",
    };
    const received = JSON.stringify([
      null,
      view,
      { ...view, name: "Duplicate ID" },
      { ...view, id: "duplicate", name: "assigned" },
      { ...view, id: "bad-state", state: "merged" },
      { ...view, id: "bad-query", query: 7 },
    ]);
    const restored = readIssueSavedViews(received);
    NodeAssert.deepEqual(restored, [{ ...view, query: "keyboard", labels: [], assignee: null }]);
    NodeAssert.equal(issueSavedViewMatches(restored[0], { ...view, name: "Renamed" }), true);
    NodeAssert.equal(issueSavedViewMatches(view, { ...view, state: "closed" }), false);
    NodeAssert.deepEqual(readIssueSavedViews("{ incomplete"), []);
  },
);

NodeTest.test(
  "candidate reads use an exact advertised scope, with older list entries as a fallback",
  async () => {
    const { issueCandidateScopes, issueCandidatesRequest, readIssueCandidates } = await protocol();
    const { key: _ignored, ...scope } = ref;
    const other = { ...scope, projectId: "other-account" };
    const wrongHost = { ...scope, host: "another.invalid" };
    const trackers = [
      {
        tracker: ref.tracker,
        host: ref.host,
        configured: true,
        capabilities: { labels: true, assignees: false },
      },
    ];
    const page = { scopes: [scope, other, scope, wrongHost], entries: [], trackers };
    NodeAssert.deepEqual(issueCandidateScopes(page, "labels"), [scope, other]);
    NodeAssert.deepEqual(issueCandidateScopes(page, "assignee"), []);
    NodeAssert.deepEqual(issueCandidateScopes({ entries: [row, row], trackers }, "labels"), [
      scope,
    ]);
    NodeAssert.deepEqual(
      issueCandidateScopes({ entries: [row], scopes: [], trackers }, "labels"),
      [],
    );
    const request = issueCandidatesRequest(row);
    NodeAssert.equal(request.tag, "issues.candidates");
    NodeAssert.deepEqual(request.payload, decodeIssueScope(scope));
    const candidates = {
      labels: [{ name: "Accessibility", color: null, description: null }],
      assignees: [{ ...actor, id: "identity-99" }],
      truncated: true,
    };
    NodeAssert.deepEqual(readIssueCandidates(candidates), decodeIssueCandidates(candidates));
    NodeAssert.throws(() => readIssueCandidates({ ...candidates, assignees: [actor] }), /候选/);
  },
);

NodeTest.test(
  "issue list distinguishes no source, an empty search, and a page that can continue",
  async () => {
    const { issueListEmptyMessage, readIssuePage } = await protocol();
    const page = readIssuePage({
      entries: [],
      errors: [],
      trackers: [],
      nextCursors: {},
      viewers: {},
    });
    NodeAssert.equal(issueListEmptyMessage(page, ""), "当前环境没有工单来源。");
    NodeAssert.equal(
      issueListEmptyMessage({ ...page, unavailable: true }, ""),
      "当前环境版本未启用工单。",
    );
    const tracker = {
      tracker: row.tracker,
      host: row.host,
      projectCount: 1,
      configured: true,
      detail: null,
      capabilities: null,
    };
    const tracked = { ...page, trackers: [tracker] };
    NodeAssert.equal(issueListEmptyMessage(tracked, "filter"), "没有相关搜索结果。");
    NodeAssert.equal(issueListEmptyMessage(tracked, " "), "没有符合当前筛选条件的工单。");
    NodeAssert.equal(
      issueListEmptyMessage({ ...tracked, scopes: [] }, ""),
      "当前环境没有工单来源。",
    );
    NodeAssert.equal(
      issueListEmptyMessage({ ...tracked, trackers: [{ ...tracker, configured: false }] }, ""),
      "请先配置工单跟踪器。",
    );
    NodeAssert.equal(
      issueListEmptyMessage({ ...tracked, nextCursors: { scope1: "more" } }, "filter"),
      "",
    );
    NodeAssert.equal(issueListEmptyMessage({ ...tracked, entries: [row] }, ""), "");
  },
);

NodeTest.test(
  "saving issue views updates the same ID without collisions or changing unrelated views",
  async () => {
    const { writeIssueSavedView } = await import(new URL("IssueSavedViews.ets", client).href);
    const initial = {
      id: "validated",
      name: "Triage",
      query: "",
      state: "open",
      involvement: "all",
      sort: "updated",
    };
    const additional = {
      ...initial,
      id: "mine",
      name: "Mine",
      involvement: "assigned",
      labels: [],
      assignee: null,
    };
    const views = writeIssueSavedView([initial], additional);
    const updated = {
      ...initial,
      name: " Updated triage ",
      query: " repro ",
      state: "closed",
      labels: ["UI", "Bug"],
      assignee: { login: "someone", name: "Example" },
    };
    NodeAssert.deepEqual(writeIssueSavedView(views, updated), [
      { ...updated, name: "Updated triage", query: "repro" },
      additional,
    ]);
    const { readIssueSavedViews, issueSavedViewMatches } = await import(
      new URL("IssueSavedViews.ets", client).href
    );
    const persisted = readIssueSavedViews(JSON.stringify(writeIssueSavedView(views, updated)));
    NodeAssert.deepEqual(persisted, [
      { ...updated, name: "Updated triage", query: "repro" },
      additional,
    ]);
    NodeAssert.equal(
      issueSavedViewMatches(persisted[0], {
        ...updated,
        labels: ["Bug", "UI"],
        assignee: { ...updated.assignee, name: "Renamed" },
      }),
      true,
    );
    NodeAssert.equal(issueSavedViewMatches(persisted[0], { ...updated, assignee: null }), false);
    NodeAssert.throws(() => writeIssueSavedView(views, { ...initial, name: " MINE " }), /已经存在/);
    NodeAssert.throws(() => writeIssueSavedView(views, { ...initial, name: " " }), /请输入/);
    NodeAssert.throws(() => writeIssueSavedView(views, { ...initial, name: "a".repeat(81) }), /80/);
  },
);
