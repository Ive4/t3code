import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import {
  GitActionProgressEvent,
  GitRunStackedActionInput,
  ORCHESTRATION_V2_WS_METHODS,
  OrchestrationV2Command,
  VcsCreateRefInput,
  VcsListRefsInput,
  VcsListRefsResult,
  VcsPullInput,
  VcsPullResult,
  VcsRefreshStatusResult,
  VcsStatusInput,
  VcsSwitchRefInput,
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
const protocol = import(new URL("ThreadGitProtocol.ets", client).href);
void protocol.catch(() => {});
NodeTest.after(() => loader.deregister());

const decodeRequest = Schema.decodeUnknownSync(
  Schema.Struct({ ...VcsStatusInput.fields, localOnly: Schema.optional(Schema.Boolean) }),
);
const decodeStatus = Schema.decodeUnknownSync(Schema.toCodecJson(VcsRefreshStatusResult));

function status(fields) {
  const wire = {
    isRepo: true,
    refName: null,
    hasPrimaryRemote: false,
    isDefaultRef: false,
    hasWorkingTreeChanges: false,
    workingTree: { files: [], insertions: 0, deletions: 0 },
    hasUpstream: false,
    aheadCount: 0,
    behindCount: 0,
    pr: null,
    ...fields,
  };
  decodeStatus(wire);
  return wire;
}

NodeTest.test(
  "refreshes local status or requests a full remote refresh for the exact task directory",
  async () => {
    const { threadGitStatusRequest } = await protocol;
    for (const cwd of ["/worktrees/Android 对齐", "C:\\repos\\task folder"]) {
      const request = threadGitStatusRequest(cwd);
      NodeAssert.equal(request.tag, WS_METHODS.vcsRefreshStatus);
      NodeAssert.deepEqual(decodeRequest(request.payload), { cwd, localOnly: true });
      const remote = threadGitStatusRequest(cwd, false);
      NodeAssert.equal(remote.tag, WS_METHODS.vcsRefreshStatus);
      NodeAssert.deepEqual(decodeRequest(remote.payload), { cwd });
    }
    for (const cwd of ["", " /worktree", "/worktree ", "/bad\0dir"]) {
      NodeAssert.throws(() => threadGitStatusRequest(cwd));
    }
  },
);

NodeTest.test("keeps the actual branch and all modified files including binary files", async () => {
  const { readThreadGitStatus } = await protocol;
  const files = [
    { path: "src/规则.ets", insertions: 8, deletions: 2 },
    { path: "assets/Logo 2.png", insertions: 0, deletions: 0 },
  ];
  const wire = status({
    refName: "feature/harmony-android",
    hasPrimaryRemote: true,
    hasUpstream: true,
    aheadCount: 2,
    behindCount: 1,
    hasWorkingTreeChanges: true,
    workingTree: { files, insertions: 8, deletions: 2, rootPath: "/home/task" },
  });
  NodeAssert.deepEqual(readThreadGitStatus(wire), {
    isRepo: true,
    refName: "feature/harmony-android",
    hasPrimaryRemote: true,
    isDefaultRef: false,
    hasUpstream: true,
    aheadCount: 2,
    behindCount: 1,
    hasWorkingTreeChanges: true,
    files,
    insertions: 8,
    deletions: 2,
  });
});

NodeTest.test("distinguishes a detached HEAD from a directory outside Git", async () => {
  const { readThreadGitStatus } = await protocol;
  const detached = readThreadGitStatus(status());
  NodeAssert.equal(detached.isRepo, true);
  NodeAssert.equal(detached.refName, null);
  const outsideGit = readThreadGitStatus(status({ isRepo: false }));
  NodeAssert.equal(outsideGit.isRepo, false);
  NodeAssert.equal(outsideGit.refName, null);
  NodeAssert.deepEqual(outsideGit.files, []);
});

NodeTest.test(
  "rejects incomplete or malformed status rather than treating it as clean",
  async () => {
    const { readThreadGitStatus } = await protocol;
    for (const wire of [
      {},
      { ...status(), refName: "" },
      { ...status(), hasUpstream: null },
      { ...status(), isDefaultRef: null },
      { ...status(), hasPrimaryRemote: "true" },
      { ...status(), aheadCount: -1 },
      { ...status(), behindCount: "1" },
      { ...status(), workingTree: { files: [], insertions: -1, deletions: 0 } },
      {
        ...status(),
        workingTree: {
          files: [{ path: "src/foo", insertions: 0, deletions: "0" }],
          insertions: 0,
          deletions: 0,
        },
      },
    ]) {
      NodeAssert.throws(() => readThreadGitStatus(wire));
    }
  },
);

const worktree = "/repo/task 树";
const decodeRefsRequest = Schema.decodeUnknownSync(Schema.toCodecJson(VcsListRefsInput));
const decodeRefs = Schema.decodeUnknownSync(Schema.toCodecJson(VcsListRefsResult));
const decodeCreate = Schema.decodeUnknownSync(Schema.toCodecJson(VcsCreateRefInput));
const decodeSwitch = Schema.decodeUnknownSync(Schema.toCodecJson(VcsSwitchRefInput));
const decodeCommitRequest = Schema.decodeUnknownSync(Schema.toCodecJson(GitRunStackedActionInput));
const decodeProgress = Schema.decodeUnknownSync(Schema.toCodecJson(GitActionProgressEvent));
const decodePullRequest = Schema.decodeUnknownSync(Schema.toCodecJson(VcsPullInput));
const decodePull = Schema.decodeUnknownSync(Schema.toCodecJson(VcsPullResult));

NodeTest.test(
  "publishes only a clean named branch with local commits and a usable remote",
  async () => {
    const { canPushThreadGit, readThreadGitStatus } = await protocol;
    const localAhead = { refName: "feature/new", aheadCount: 3 };
    for (const [fields, expected] of [
      [{ hasPrimaryRemote: true }, true],
      [{ hasUpstream: true }, true],
      [{ hasPrimaryRemote: true, refName: null }, false],
      [{ hasPrimaryRemote: true, isRepo: false }, false],
      [{ hasPrimaryRemote: true, aheadCount: 0 }, false],
      [{ hasPrimaryRemote: true, behindCount: 1 }, false],
      [{ hasPrimaryRemote: true, hasWorkingTreeChanges: true }, false],
      [{}, false],
    ]) {
      NodeAssert.equal(
        canPushThreadGit(readThreadGitStatus(status({ ...localAhead, ...fields }))),
        expected,
      );
    }
    NodeAssert.equal(canPushThreadGit(undefined), false);
  },
);

NodeTest.test("offers a pull for a named branch behind its configured upstream", async () => {
  const { canPullThreadGit, readThreadGitStatus } = await protocol;
  const localBehind = { refName: "feature/existing", hasUpstream: true, behindCount: 2 };
  for (const [fields, expected] of [
    [{}, true],
    [{ hasWorkingTreeChanges: true }, true],
    [{ behindCount: 0 }, false],
    [{ hasUpstream: false, hasPrimaryRemote: true }, false],
    [{ refName: null }, false],
    [{ isRepo: false }, false],
  ]) {
    NodeAssert.equal(
      canPullThreadGit(readThreadGitStatus(status({ ...localBehind, ...fields }))),
      expected,
    );
  }
  NodeAssert.equal(canPullThreadGit(undefined), false);
});

NodeTest.test(
  "pulls the current worktree's configured upstream and keeps the receipt",
  async () => {
    const { threadGitPullRequest, readThreadGitPullResult } = await protocol;
    const request = threadGitPullRequest(worktree);
    NodeAssert.equal(request.tag, WS_METHODS.vcsPull);
    NodeAssert.deepEqual(decodePullRequest(request.payload), { cwd: worktree });
    for (const status of ["pulled", "skipped_up_to_date"]) {
      const result = { status, refName: "Team/工作任务", upstreamRef: "custom/Team/工作任务" };
      decodePull(result);
      NodeAssert.deepEqual(readThreadGitPullResult(result), result);
    }
    NodeAssert.throws(() => threadGitPullRequest(""));
    NodeAssert.throws(() => readThreadGitPullResult({ status: "pulled", refName: "main" }));
    NodeAssert.throws(() =>
      readThreadGitPullResult({ status: "force", refName: "main", upstreamRef: null }),
    );
  },
);

NodeTest.test(
  "pushes without committing or creating a ref and reports whether upstream was set",
  async () => {
    const { threadGitPushRequest, readThreadGitPushProgress } = await protocol;
    const context = { actionId: "publish-branch", cwd: worktree, action: "push" };
    const request = threadGitPushRequest(worktree, context.actionId, "task", "project");
    NodeAssert.equal(request.tag, WS_METHODS.gitRunStackedAction);
    NodeAssert.deepEqual(decodeCommitRequest(request.payload), {
      ...context,
      threadId: "task",
      projectId: "project",
    });
    NodeAssert.throws(() => threadGitPushRequest(worktree, ""));
    const started = { ...context, kind: "action_started", phases: ["push"] };
    decodeProgress(started);
    NodeAssert.equal(readThreadGitPushProgress(started, worktree, context.actionId), undefined);
    const push = {
      status: "pushed",
      branch: "feature/new",
      upstreamBranch: "custom/feature/new",
      setUpstream: true,
    };
    const finished = {
      ...context,
      kind: "action_finished",
      result: {
        action: "push",
        branch: { status: "skipped_not_requested" },
        commit: { status: "skipped_not_requested" },
        push,
        pr: { status: "skipped_not_requested" },
        toast: { title: "Pushed branch", cta: { kind: "none" } },
      },
    };
    decodeProgress(finished);
    NodeAssert.deepEqual(readThreadGitPushProgress(finished, worktree, context.actionId), push);
    const upToDate = {
      ...finished,
      result: {
        ...finished.result,
        push: { ...push, status: "skipped_up_to_date", setUpstream: false },
      },
    };
    decodeProgress(upToDate);
    NodeAssert.deepEqual(
      readThreadGitPushProgress(upToDate, worktree, context.actionId),
      upToDate.result.push,
    );
    for (const frame of [
      { ...finished, cwd: "/another" },
      { ...finished, actionId: "another" },
      { ...finished, action: "commit" },
      { ...finished, result: { ...finished.result, push: { status: "skipped_not_requested" } } },
      { ...finished, result: { ...finished.result, push: { ...push, setUpstream: "true" } } },
    ]) {
      NodeAssert.throws(() => readThreadGitPushProgress(frame, worktree, context.actionId));
    }
    const failed = {
      ...context,
      kind: "action_failed",
      phase: "push",
      message: "Remote requires authentication",
    };
    decodeProgress(failed);
    NodeAssert.throws(
      () => readThreadGitPushProgress(failed, worktree, context.actionId),
      /Remote requires authentication/,
    );
  },
);

NodeTest.test("searches and paginates local refs in the task worktree", async () => {
  const { threadGitRefsRequest, readThreadGitRefs } = await protocol;
  const opened = threadGitRefsRequest(worktree, "", null);
  NodeAssert.equal(opened.tag, WS_METHODS.vcsListRefs);
  NodeAssert.deepEqual(decodeRefsRequest(opened.payload), {
    cwd: worktree,
    refKind: "local",
    limit: 50,
    refresh: true,
  });
  const paged = threadGitRefsRequest(worktree, "  feat  ", 50);
  NodeAssert.deepEqual(decodeRefsRequest(paged.payload), {
    cwd: worktree,
    query: "feat",
    cursor: 50,
    refKind: "local",
    limit: 50,
  });

  const refs = [
    { name: "feature/current", current: true, isDefault: false, worktreePath: worktree },
    { name: "feature/other", current: false, isDefault: false, worktreePath: "/repo/other" },
    { name: "feature/available", current: false, isDefault: false, worktreePath: null },
  ];
  const wire = { refs, isRepo: true, nextCursor: 53, totalCount: 100, hasPrimaryRemote: true };
  decodeRefs(wire);
  NodeAssert.deepEqual(readThreadGitRefs(wire), {
    refs,
    isRepo: true,
    nextCursor: 53,
    totalCount: 100,
  });
  NodeAssert.throws(() => readThreadGitRefs({ ...wire, nextCursor: -1 }));
  NodeAssert.throws(() => readThreadGitRefs({ ...wire, refs: [{ ...refs[0], isRemote: true }] }));

  const refreshed = threadGitRefsRequest(worktree, "feature", null, "all", true);
  NodeAssert.deepEqual(decodeRefsRequest(refreshed.payload), {
    cwd: worktree,
    query: "feature",
    refKind: "all",
    limit: 50,
    refresh: true,
  });
  const remote = {
    name: "origin/main",
    isRemote: true,
    isDefault: true,
    current: false,
    worktreePath: null,
  };
  const allRefs = { ...wire, refs: [remote], isAtRepositoryRoot: false };
  NodeAssert.deepEqual(readThreadGitRefs(allRefs, "all"), {
    refs: [remote],
    isRepo: true,
    nextCursor: 53,
    totalCount: 100,
    isAtRepositoryRoot: false,
  });
});

NodeTest.test("protects branches checked out in other worktrees", async () => {
  const { threadGitRefOccupied } = await protocol;
  const branch = {
    name: "feature/other",
    current: false,
    isDefault: false,
    worktreePath: "/repo/other",
  };
  NodeAssert.equal(threadGitRefOccupied(branch, worktree), true);
  NodeAssert.equal(threadGitRefOccupied({ ...branch, worktreePath: null }, worktree), false);
  NodeAssert.equal(threadGitRefOccupied({ ...branch, worktreePath: worktree }, worktree), false);
  NodeAssert.equal(threadGitRefOccupied({ ...branch, current: true }, "/repo/other/subdir"), false);
});

NodeTest.test(
  "creates and checks out a normalized branch and keeps existing ref names intact",
  async () => {
    const {
      normalizeThreadGitNewRef,
      threadGitCreateRefRequest,
      threadGitSwitchRefRequest,
      readThreadGitRefName,
    } = await protocol;
    const created = threadGitCreateRefRequest(
      worktree,
      normalizeThreadGitNewRef("  Fix café tabs  "),
    );
    NodeAssert.equal(created.tag, WS_METHODS.vcsCreateRef);
    NodeAssert.deepEqual(decodeCreate(created.payload), {
      cwd: worktree,
      refName: "feature/fix-cafe-tabs",
      switchRef: true,
    });
    const switched = threadGitSwitchRefRequest(worktree, "Maintenance/国际化");
    NodeAssert.equal(switched.tag, WS_METHODS.vcsSwitchRef);
    NodeAssert.deepEqual(decodeSwitch(switched.payload), {
      cwd: worktree,
      refName: "Maintenance/国际化",
    });
    NodeAssert.equal(readThreadGitRefName({ refName: "Maintenance/国际化" }), "Maintenance/国际化");
    NodeAssert.equal(readThreadGitRefName({ refName: null }), null);
    NodeAssert.throws(() => readThreadGitRefName({}));
    NodeAssert.throws(() => threadGitSwitchRefRequest(worktree, " feature/bad"));
  },
);

NodeTest.test("updates only the branch and guards against a concurrent worktree move", async () => {
  const { threadGitBranchMetadataRequest } = await protocol;
  const decodeCommand = Schema.decodeUnknownSync(Schema.toCodecJson(OrchestrationV2Command));
  for (const expectedWorktreePath of [worktree, null]) {
    const request = threadGitBranchMetadataRequest(
      "set-branch",
      "task",
      "feature/current",
      expectedWorktreePath,
    );
    NodeAssert.equal(request.tag, ORCHESTRATION_V2_WS_METHODS.dispatchCommand);
    NodeAssert.deepEqual(decodeCommand(request.payload), {
      type: "thread.metadata.update",
      commandId: "set-branch",
      threadId: "task",
      branch: "feature/current",
      expectedWorktreePath,
    });
  }
});

NodeTest.test(
  "commits all or exactly the selected changes and never converts an empty selection to all",
  async () => {
    const { threadGitCommitRequest, threadGitCommitFilePaths } = await protocol;
    const files = [
      { path: "src/file [draft].ets", insertions: 2, deletions: 1 },
      { path: "resources/ icon.png ", insertions: 0, deletions: 0 },
      { path: "renamed/规则.ets", insertions: 0, deletions: 0 },
    ];
    const all = threadGitCommitFilePaths(files, new Set());
    const allRequest = threadGitCommitRequest(
      worktree,
      "all",
      "  chore: update files\n\nKeep file names.\n",
      all,
      "task",
    );
    NodeAssert.equal(allRequest.tag, WS_METHODS.gitRunStackedAction);
    NodeAssert.deepEqual(decodeCommitRequest(allRequest.payload), {
      cwd: worktree,
      actionId: "all",
      action: "commit",
      commitMessage: "chore: update files\n\nKeep file names.",
      threadId: "task",
    });
    const selection = threadGitCommitFilePaths(files, new Set(["src/file [draft].ets"]));
    const partial = threadGitCommitRequest(
      worktree,
      "partial",
      "fix: preserve selected files",
      selection,
    );
    NodeAssert.deepEqual(decodeCommitRequest(partial.payload).filePaths, [
      "resources/ icon.png ",
      "renamed/规则.ets",
    ]);
    NodeAssert.throws(() =>
      threadGitCommitFilePaths(files, new Set(files.map((file) => file.path))),
    );
    NodeAssert.throws(() => threadGitCommitRequest(worktree, "empty", "Valid message", []));
    NodeAssert.throws(() => threadGitCommitRequest(worktree, "blank", " \n ", undefined));
  },
);

NodeTest.test(
  "reads the local commit receipt from the matching action's terminal progress event",
  async () => {
    const { readThreadGitCommitProgress } = await protocol;
    const context = { actionId: "local-commit", cwd: worktree, action: "commit" };
    const started = { ...context, kind: "action_started", phases: ["commit"] };
    decodeProgress(started);
    NodeAssert.equal(readThreadGitCommitProgress(started, worktree, context.actionId), undefined);
    const commit = {
      status: "created",
      commitSha: "a".repeat(40),
      subject: "fix: preserve selection",
    };
    const finished = {
      ...context,
      kind: "action_finished",
      result: {
        action: "commit",
        branch: { status: "skipped_not_requested" },
        commit,
        push: { status: "skipped_not_requested" },
        pr: { status: "skipped_not_requested" },
        toast: { title: "Committed changes", cta: { kind: "none" } },
      },
    };
    decodeProgress(finished);
    NodeAssert.deepEqual(readThreadGitCommitProgress(finished, worktree, context.actionId), commit);
    const noChanges = {
      ...finished,
      result: { ...finished.result, commit: { status: "skipped_no_changes" } },
    };
    decodeProgress(noChanges);
    NodeAssert.deepEqual(readThreadGitCommitProgress(noChanges, worktree, context.actionId), {
      status: "skipped_no_changes",
    });
    NodeAssert.throws(() => readThreadGitCommitProgress(finished, "/wrong/path", context.actionId));
    NodeAssert.throws(() => readThreadGitCommitProgress(finished, worktree, "another-action"));
    NodeAssert.throws(() =>
      readThreadGitCommitProgress({ ...finished, result: {} }, worktree, context.actionId),
    );
    const failed = {
      ...context,
      kind: "action_failed",
      phase: "commit",
      message: "Commit hook failed",
    };
    decodeProgress(failed);
    NodeAssert.throws(
      () => readThreadGitCommitProgress(failed, worktree, context.actionId),
      /Commit hook failed/,
    );
  },
);
