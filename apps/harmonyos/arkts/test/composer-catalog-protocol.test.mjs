import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import {
  ProjectSearchEntriesInput,
  WS_METHODS,
  WsServerRefreshProvidersRpc,
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
const protocol = () => import(new URL("ComposerCatalogProtocol.ets", client).href);
const decode = (schema) => Schema.decodeUnknownSync(Schema.toCodecJson(schema));

NodeTest.test(
  "uses the selected provider instance and checkout and allows an empty file picker query",
  async () => {
    const { composerProviderCatalogRequest, composerPathSearchRequest } = await protocol();
    const cwd = "/home/user/project worktree";
    const provider = composerProviderCatalogRequest("codex_secondary", cwd);
    NodeAssert.equal(provider.tag, WS_METHODS.serverRefreshProviders);
    NodeAssert.deepEqual(decode(WsServerRefreshProvidersRpc.payloadSchema)(provider.payload), {
      instanceId: "codex_secondary",
      cwd,
      workspaceSnapshotsOnDemand: true,
      providerCatalogsOnDemand: true,
    });
    NodeAssert.throws(() => composerProviderCatalogRequest("codex/secondary", cwd));
    const files = composerPathSearchRequest(cwd, "  ");
    NodeAssert.equal(files.tag, WS_METHODS.projectsSearchEntries);
    NodeAssert.deepEqual(decode(ProjectSearchEntriesInput)(files.payload), {
      cwd,
      query: "",
      limit: 20,
    });
    NodeAssert.equal(
      composerPathSearchRequest(cwd, "x".repeat(255) + "📁").payload.query,
      "x".repeat(255),
    );
    NodeAssert.throws(() => composerPathSearchRequest("/home/user\0other", ""));
  },
);

NodeTest.test(
  "uses only the matching checkout catalog and user-invocable, deduplicated skills",
  async () => {
    const { readComposerProviderCatalog } = await protocol();
    const skill = {
      name: "review",
      path: "/workspace/review/SKILL.md",
      enabled: true,
      userInvocationOnly: true,
    };
    const instance = {
      instanceId: "codex_secondary",
      driver: "codex",
      installed: true,
      slashCommands: [{ name: "machine" }],
      skills: [],
      workspaceSnapshots: [
        { cwd: "/other", slashCommands: [{ name: "other" }], skills: [] },
        {
          cwd: "/workspace",
          slashCommands: [
            { name: "help", description: "Get help", input: { hint: "subject" } },
            { name: "review" },
            { name: "invalid command" },
          ],
          skills: [
            skill,
            { ...skill, name: "REVIEW" },
            { ...skill, name: "agent-only", userInvocable: false },
            { ...skill, name: "disabled", enabled: false },
          ],
        },
      ],
    };
    const value = { providers: [{ ...instance, instanceId: "codex_primary" }, instance] };
    NodeAssert.deepEqual(readComposerProviderCatalog(value, "codex_secondary", "/workspace"), {
      instanceId: "codex_secondary",
      driver: "codex",
      pending: false,
      slashCommands: [{ name: "help", description: "Get help", input: { hint: "subject" } }],
      skills: [{ name: skill.name, path: skill.path, userInvocationOnly: true }],
    });
    NodeAssert.deepEqual(
      readComposerProviderCatalog(value, "codex_secondary", "/missing").slashCommands,
      [{ name: "machine" }],
    );
    NodeAssert.throws(() => readComposerProviderCatalog(value, "unrelated", "/workspace"));
    const partial = {
      ...instance,
      workspaceSnapshots: [
        {
          cwd: "/workspace",
          slashCommands: [{ name: "partial" }],
          slashCommandsPending: true,
        },
      ],
    };
    NodeAssert.equal(
      readComposerProviderCatalog({ providers: [partial] }, "codex_secondary", "/workspace")
        .pending,
      true,
    );
  },
);

NodeTest.test(
  "limits thread mentions to the current and explicitly linked machines and eligible lineage",
  async () => {
    const { matchComposerThreadTitles } = await protocol();
    const thread = {
      id: "same",
      title: "T3 Composer",
      environmentKey: "current",
      createdAt: "2026-11-20",
    };
    const linked = { ...thread, environmentKey: "linked" };
    const side = {
      ...thread,
      id: "side",
      title: "Composer side chat",
      latestUserMessageAt: "2026-11-21",
      lineage: { sideChat: true, parentThreadId: "same" },
    };
    const rows = [
      thread,
      linked,
      side,
      { ...side, id: "untouched", latestUserMessageAt: null },
      { ...side, id: "other-parent", lineage: { sideChat: true, parentThreadId: "other-parent" } },
      { ...thread, id: "subagent", lineage: { relationshipToParent: "subagent" } },
      { ...thread, id: "workflow", lineage: { workflowStep: true } },
      { ...thread, id: "archive", archivedAt: "2026-11-21" },
      { ...thread, id: "deleted", deletedAt: "2026-11-21" },
      { ...thread, id: "wrong", environmentKey: "paired-only" },
      { ...thread, id: "unknown", environmentKey: undefined },
    ];
    NodeAssert.deepEqual(
      matchComposerThreadTitles(rows, "composer", "current", "same", ["linked"]),
      [side, linked],
    );
    NodeAssert.deepEqual(matchComposerThreadTitles(rows, "", "current", "same", ["linked"]), []);
  },
);

NodeTest.test(
  "uses host project repository identity and never suggests a same-number PR from another scope",
  async () => {
    const { matchComposerPullRequests, readComposerProjectRepository } = await protocol();
    const projects = {
      projects: [
        {
          id: "other",
          repositoryIdentity: { canonicalKey: "git.invalid/team/demo", displayName: "team/demo" },
        },
        {
          id: "project",
          repositoryIdentity: { canonicalKey: "git.example/team/demo", displayName: "Team/Demo" },
        },
      ],
    };
    const scope = readComposerProjectRepository(projects, "project");
    NodeAssert.deepEqual(scope, {
      projectId: "project",
      host: "git.example",
      repository: "Team/Demo",
    });
    NodeAssert.equal(readComposerProjectRepository(projects, "missing"), undefined);
    const row = {
      ...scope,
      number: 123,
      title: "Fix Composer",
      headBranch: "composer-token",
      baseBranch: "main",
    };
    const exact = { ...row, number: 12 };
    const unrelated = { ...exact, repository: "team/more" };
    const rows = [
      unrelated,
      row,
      exact,
      { ...exact, host: "git.invalid" },
      { ...exact, projectId: "other" },
    ];
    NodeAssert.deepEqual(matchComposerPullRequests(rows, scope, "12"), [exact, row]);
    NodeAssert.deepEqual(matchComposerPullRequests(rows, scope, "composer token"), [row, exact]);
  },
);
