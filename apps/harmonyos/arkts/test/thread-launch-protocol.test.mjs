import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import { OrchestrationV2RpcSchemas, WS_METHODS } from "@t3tools/contracts";
import * as Schema from "effect/Schema";

const decodeLaunch = Schema.decodeUnknownSync(OrchestrationV2RpcSchemas.launchThread.input);
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
const {
  launchThreadRequest,
  readLaunchedThreadId,
  readThreadLaunchScratchProject,
  readThreadLaunchOptions,
  readThreadModelProviders,
  readThreadModelSettings,
  resolveThreadLaunchLocalWorkspace,
  threadLaunchConfigRequest,
  threadLaunchScratchRequest,
  threadRuntimeModeChoices,
  threadLaunchWorktree,
} = await import(new URL("ThreadLaunchProtocol.ets", client).href);
const {
  changeThreadModelOption,
  readThreadModelCapabilities,
  threadModelOptionDescriptors,
  threadModelSelectionForTarget,
  withThreadModelOptionDefaults,
} = await import(new URL("ThreadModelOptionProtocol.ets", client).href);
loader.deregister();

const replay = {
  instanceId: "devReplay",
  driver: "acpRegistry",
  displayName: "Replay (dev)",
  enabled: true,
  installed: true,
  status: "ready",
  auth: { status: "unknown" },
  models: [
    { slug: "showcase", name: "Showcase", isDefault: true },
    { slug: "multi-turn", name: "Multi turn" },
  ],
};
const showcase = { instanceId: "devReplay", model: "showcase" };

NodeTest.test("preserves model capability descriptors and legacy selections in the catalog", () => {
  const capabilities = {
    optionDescriptors: [
      { id: "fastMode", label: "Fast", type: "boolean", currentValue: true },
      {
        id: "effort",
        label: "Reasoning",
        type: "select",
        options: [{ id: "medium", label: "Medium", isDefault: true }],
      },
    ],
  };
  const options = readThreadLaunchOptions(
    {
      projects: [
        {
          id: "project",
          title: "Fixture",
          workspaceRoot: "/fixtures",
          defaultModelSelection: { ...showcase, options: { effort: "medium", fastMode: false } },
        },
      ],
    },
    {
      providers: [
        {
          ...replay,
          supportedRuntimeModes: ["auto"],
          models: [{ ...replay.models[0], capabilities }],
        },
      ],
    },
  );
  NodeAssert.deepEqual(options.projects[0].defaultModelSelection.options, [
    { id: "effort", value: "medium" },
    { id: "fastMode", value: false },
  ]);
  NodeAssert.equal(options.providers[0].models[0].capabilities.optionDescriptors.length, 2);
  const selection = options.projects[0].defaultModelSelection;
  const request = launchThreadRequest(
    "command",
    "thread",
    "message",
    "project",
    selection,
    "start",
  );
  NodeAssert.deepEqual(decodeLaunch(request.payload).modelSelection.options, selection.options);
});

NodeTest.test("resolves current model options and only changes selectable values", () => {
  const model = {
    slug: "showcase",
    name: "Showcase",
    capabilities: readThreadModelCapabilities({
      optionDescriptors: [
        {
          id: "effort",
          label: "Reasoning",
          type: "select",
          options: [
            { id: "medium", label: "Medium", isDefault: true },
            { id: "high", label: "High" },
            { id: "ultrathink", label: "Ultrathink" },
          ],
          promptInjectedValues: ["ultrathink"],
        },
        { id: "fastMode", label: "Fast", type: "boolean", currentValue: true },
        { id: "edit", label: "Edits", type: "boolean", currentValue: true },
      ],
    }),
  };
  const selected = { ...showcase, options: [{ id: "edit", value: false }] };
  const ui = threadModelOptionDescriptors(model, selected, "Ultrathink: test");
  NodeAssert.deepEqual(
    ui.map((row) => row.currentValue),
    ["medium", false, false],
  );
  NodeAssert.deepEqual(
    ui[0].options.map((choice) => choice.id),
    ["medium", "high"],
  );
  NodeAssert.equal(ui[0].promptControlled, true);
  NodeAssert.equal(ui[0].promptLocked, false);
  NodeAssert.equal(
    changeThreadModelOption(model, selected, "effort", "ultrathink", "test"),
    undefined,
  );
  NodeAssert.equal(changeThreadModelOption(model, selected, "effort", "low", "test"), undefined);
  NodeAssert.equal(
    changeThreadModelOption(model, selected, "effort", "high", "test ultrathink"),
    undefined,
  );
  NodeAssert.deepEqual(
    changeThreadModelOption(model, selected, "effort", "high", "Ultrathink: test"),
    {
      selection: {
        ...showcase,
        options: [
          { id: "effort", value: "high" },
          { id: "fastMode", value: false },
          { id: "edit", value: false },
        ],
      },
      prompt: "test",
    },
  );
  NodeAssert.deepEqual(withThreadModelOptionDefaults(model, selected).options, [
    { id: "edit", value: false },
    { id: "fastMode", value: false },
  ]);
});

NodeTest.test("keeps compatible choices without leaking choices to a different provider", () => {
  const model = {
    slug: "other",
    name: "Other",
    capabilities: readThreadModelCapabilities({
      optionDescriptors: [
        { id: "fastMode", label: "Fast", type: "boolean" },
        {
          id: "effort",
          label: "Effort",
          type: "select",
          options: [
            { id: "medium", label: "Medium" },
            { id: "xhigh", label: "Extra high" },
          ],
        },
        { id: "ultracode", label: "Ultracode", type: "boolean" },
      ],
    }),
  };
  const previous = {
    ...showcase,
    options: [
      { id: "fastMode", value: false },
      { id: "effort", value: "high" },
      { id: "other", value: true },
    ],
  };
  NodeAssert.deepEqual(threadModelSelectionForTarget("devReplay", model, previous).options, [
    { id: "fastMode", value: false },
  ]);
  NodeAssert.equal(threadModelSelectionForTarget("other", model, previous).options, undefined);
  NodeAssert.deepEqual(
    threadModelSelectionForTarget("devReplay", model, previous, [
      { id: "effort", value: "ultracode" },
    ]).options,
    [
      { id: "effort", value: "xhigh" },
      { id: "ultracode", value: true },
    ],
  );
});

NodeTest.test("reads pickable projects and server-discovered providers for an environment", () => {
  const options = readThreadLaunchOptions(
    {
      projects: [
        { id: "normal", title: "Normal", workspaceRoot: "/repos/normal" },
        {
          id: "pinned",
          title: "Pinned",
          workspaceRoot: "/repos/pinned",
          pinnedAt: "2026-11-24T12:00:00Z",
          defaultModelSelection: { provider: "devReplay", model: "showcase" },
        },
        {
          id: "archive",
          title: "Archive",
          workspaceRoot: "/repos/archive",
          archivedAt: "2026-11-24T12:00:00Z",
        },
        { id: "scratch", title: "Scratch", workspaceRoot: "C:\\T3\\Scratch" },
      ],
      threads: [{ id: "thread", projectId: "archive" }],
    },
    {
      scratchWorkspaceRoot: "c:/t3/scratch/",
      providers: [
        replay,
        { ...replay, instanceId: "disabled", enabled: false },
        { ...replay, instanceId: "missing", installed: false },
        { ...replay, instanceId: "signedOut", auth: { status: "unauthenticated" } },
        { ...replay, instanceId: "unavailable", availability: "unavailable" },
        { ...replay, instanceId: "noModels", models: [] },
        { ...replay, instanceId: "codex", driver: "codex" },
      ],
      managedPolicy: { limits: { providers: { allowedDrivers: ["acpRegistry"] } } },
    },
  );

  NodeAssert.deepEqual(
    options.projects.map(({ id }) => id),
    ["pinned", "normal"],
  );
  NodeAssert.deepEqual(options.projects[0].defaultModelSelection, showcase);
  NodeAssert.deepEqual(
    options.providers.map(({ instanceId }) => instanceId),
    ["devReplay"],
  );
  NodeAssert.equal(options.providers[0].displayName, "Replay (dev)");
  NodeAssert.deepEqual(options.providers[0].projectIds, ["pinned", "normal"]);
  NodeAssert.deepEqual(
    options.providers[0].models.map(({ slug }) => slug),
    ["showcase", "multi-turn"],
  );
});

NodeTest.test("honors project provider overrides without changing other projects", () => {
  const { providers } = readThreadLaunchOptions(
    {
      projects: [
        { id: "a", title: "A", workspaceRoot: "/a" },
        { id: "b", title: "B", workspaceRoot: "/b" },
      ],
    },
    {
      providers: [
        replay,
        { ...replay, instanceId: "projectOnly", enabled: false, status: "disabled" },
      ],
      settings: {
        projectSettingsOverrides: {
          a: {
            providerInstances: { devReplay: { enabled: false }, projectOnly: { enabled: true } },
          },
        },
      },
    },
  );
  NodeAssert.deepEqual(
    providers.map(({ instanceId, projectIds }) => [instanceId, projectIds]),
    [
      ["devReplay", ["b"]],
      ["projectOnly", ["a"]],
    ],
  );
});

NodeTest.test("prefers the existing thread's own worktree model catalog", () => {
  const cwd = "/projects/scratch-worktree";
  const providers = readThreadModelProviders(
    {
      scratchWorkspaceRoot: "/projects/scratch",
      providers: [
        {
          ...replay,
          workspaceSnapshots: [
            { cwd: "/projects/other", models: [{ slug: "other", name: "Other" }] },
            { cwd, models: [{ slug: "local-model", name: "Local model" }] },
          ],
        },
        { ...replay, instanceId: "disabledHere" },
      ],
      settings: {
        projectSettingsOverrides: {
          scratch: { providerInstances: { disabledHere: { enabled: false } } },
        },
      },
    },
    "scratch",
    cwd,
  );
  NodeAssert.deepEqual(providers, [
    {
      instanceId: "devReplay",
      displayName: "Replay (dev)",
      models: [{ slug: "local-model", name: "Local model" }],
      projectIds: ["scratch"],
    },
  ]);
});

NodeTest.test("shows supported runtime modes and marks those blocked by the managed policy", () => {
  const settings = readThreadModelSettings(
    {
      providers: [
        {
          ...replay,
          supportedRuntimeModes: ["approval-required", "auto", "full-access"],
          models: [{ slug: "showcase", name: "Showcase" }],
        },
      ],
      managedPolicy: { limits: { maxRuntimeMode: "auto" } },
    },
    "project",
  );
  NodeAssert.deepEqual(
    threadRuntimeModeChoices(settings.providers[0].models[0], settings.maxRuntimeMode),
    [
      { mode: "approval-required", allowed: true },
      { mode: "auto", allowed: true },
      { mode: "full-access", allowed: false },
    ],
  );
});

NodeTest.test("creates a schema-valid mobile launch with stable operation and message IDs", () => {
  const text = "  第一条消息\n\n请继续。  ";
  const request = launchThreadRequest(
    "command-1",
    "thread-1",
    "message-1",
    "pinned",
    showcase,
    text,
  );
  NodeAssert.deepEqual(
    request,
    launchThreadRequest("command-1", "thread-1", "message-1", "pinned", showcase, text),
  );
  NodeAssert.equal(request._tag, "Request");
  NodeAssert.equal(request.tag, "orchestration.launchThread");
  const payload = decodeLaunch(request.payload);
  NodeAssert.equal(payload.commandId, "command-1");
  NodeAssert.equal(payload.threadId, "thread-1");
  NodeAssert.equal(payload.projectId, "pinned");
  NodeAssert.equal(payload.creationSource, "mobile");
  NodeAssert.equal(payload.runtimeMode, "approval-required");
  NodeAssert.equal(payload.title, "第一条消息 请继续。");
  NodeAssert.equal(payload.generateTitle, true);
  NodeAssert.deepEqual(payload.modelSelection, showcase);
  NodeAssert.deepEqual(payload.workspaceStrategy, { type: "root" });
  NodeAssert.deepEqual(payload.initialMessage, {
    messageId: "message-1",
    text: "第一条消息\n\n请继续。",
    attachments: [],
  });
  const named = launchThreadRequest(
    "command-1",
    "thread-1",
    "message-1",
    "pinned",
    showcase,
    text,
    "明确的名称",
  );
  NodeAssert.equal(named.payload.title, "明确的名称");
  NodeAssert.equal(named.payload.generateTitle, false);
});

NodeTest.test("refuses launch without a first message or operation ID", () => {
  NodeAssert.throws(() =>
    launchThreadRequest("command-1", "thread-1", "message-1", "pinned", showcase, "\n "),
  );
  NodeAssert.throws(() =>
    launchThreadRequest("", "thread-1", "message-1", "pinned", showcase, "hello"),
  );
});

NodeTest.test("launches with only an uploaded attachment and the selected runtime mode", () => {
  const attachment = {
    type: "file",
    id: "upload-1",
    name: "notes.txt",
    mimeType: "text/plain",
    sizeBytes: 20,
  };
  const request = launchThreadRequest(
    "command-1",
    "thread-1",
    "message-1",
    "pinned",
    showcase,
    "",
    undefined,
    "auto-accept-edits",
    [attachment],
  );
  const payload = decodeLaunch(request.payload);
  NodeAssert.equal(payload.title, "notes.txt");
  NodeAssert.equal(payload.runtimeMode, "auto-accept-edits");
  NodeAssert.deepEqual(payload.initialMessage, {
    messageId: "message-1",
    text: "",
    attachments: [attachment],
  });
});

NodeTest.test("keeps a thread mention in the first message of a launch", () => {
  const record = {
    version: 1,
    kind: "thread",
    contextId: "thread_source",
    label: "Source conversation",
    title: "Source conversation",
    environmentId: "env-local",
    threadId: "source",
  };
  const text = "Check [Source conversation](t3-context://v1/thread/thread_source)";
  const context = { version: 1, records: [record] };
  const request = launchThreadRequest(
    "command-1",
    "thread-1",
    "message-1",
    "pinned",
    showcase,
    text,
    undefined,
    "approval-required",
    [],
    { type: "root" },
    context,
  );
  const message = decodeLaunch(request.payload).initialMessage;
  NodeAssert.deepEqual(message, { messageId: "message-1", text, attachments: [], context });
});

NodeTest.test("launches a new worktree from the chosen base or reuses an existing checkout", () => {
  const workspaces = [
    { type: "worktree", baseRef: "origin/main", startFromOrigin: true },
    { type: "existing_worktree", branch: "feature", worktreePath: "/repos/feature" },
    { type: "root", branch: "feature" },
  ];
  for (const workspace of workspaces) {
    const request = launchThreadRequest(
      "command-1",
      "thread-1",
      "message-1",
      "pinned",
      showcase,
      "hello",
      undefined,
      "approval-required",
      [],
      workspace,
    );
    NodeAssert.deepEqual(decodeLaunch(request.payload).workspaceStrategy, workspace);
  }
});

NodeTest.test("uses the remote default as the worktree base if no branch was picked", () => {
  const local = { name: "feature", current: true, isDefault: false, worktreePath: null };
  const remote = {
    name: "origin/main",
    isRemote: true,
    current: false,
    isDefault: true,
    worktreePath: null,
  };
  NodeAssert.deepEqual(threadLaunchWorktree([local, remote], undefined, true), {
    type: "worktree",
    baseRef: "origin/main",
    startFromOrigin: true,
  });
  NodeAssert.equal(
    threadLaunchWorktree([local, remote], "older-feature", false).baseRef,
    "older-feature",
  );
  NodeAssert.equal(threadLaunchWorktree([], undefined, false), undefined);
});

NodeTest.test("reuses only the matching upstream checkout at a repository root", async () => {
  const project = "/repos/project";
  const remote = { name: "team/origin/feature", isRemote: true, remoteName: "team/origin" };
  const ref = {
    name: "feature",
    upstreamRef: "refs/remotes/team/origin/feature",
    worktreePath: "/repos/feature",
  };
  const results = { refs: [ref], isAtRepositoryRoot: true, nextCursor: null };
  const switchRef = () => Promise.reject(new Error("existing checkout should be reused"));
  const listRefs = async (cwd, query, cursor, refKind, refresh) => {
    NodeAssert.deepEqual(
      [cwd, query, cursor, refKind, refresh],
      [project, "feature", null, "local", true],
    );
    return results;
  };
  NodeAssert.deepEqual(
    await resolveThreadLaunchLocalWorkspace(project, remote, listRefs, switchRef),
    {
      type: "existing_worktree",
      branch: "feature",
      worktreePath: "/repos/feature",
    },
  );
  await NodeAssert.rejects(
    () =>
      resolveThreadLaunchLocalWorkspace(
        project,
        remote,
        async () => ({
          ...results,
          isAtRepositoryRoot: false,
        }),
        switchRef,
      ),
    /仓库根目录/,
  );
  await NodeAssert.rejects(
    () =>
      resolveThreadLaunchLocalWorkspace(
        project,
        remote,
        async () => ({
          ...results,
          isAtRepositoryRoot: undefined,
        }),
        switchRef,
      ),
    /仓库根目录/,
  );
});

NodeTest.test("switches Git before recording a changed root branch", async () => {
  const project = "/repos/project";
  const branch = { name: "feature", current: true, worktreePath: null };
  const workspace = await resolveThreadLaunchLocalWorkspace(
    project,
    branch,
    async () => ({
      refs: [{ ...branch, current: false }],
      nextCursor: null,
    }),
    async (cwd, name) => {
      NodeAssert.deepEqual([cwd, name], [project, "feature"]);
      return name;
    },
  );
  NodeAssert.deepEqual(workspace, { type: "root", branch: "feature" });
});

NodeTest.test("resolves the scratch project using the advertised environment root", () => {
  const options = readThreadLaunchOptions(
    { projects: [] },
    { providers: [replay], scratchWorkspaceRoot: "/t3/scratch" },
  );
  NodeAssert.equal(options.scratchWorkspaceRoot, "/t3/scratch");
  NodeAssert.equal(threadLaunchScratchRequest().tag, WS_METHODS.projectsEnsureScratch);
  const scratch = readThreadLaunchScratchProject(
    { projectId: "scratch" },
    options.scratchWorkspaceRoot,
  );
  NodeAssert.equal(scratch.id, "scratch");
  NodeAssert.equal(scratch.workspaceRoot, "/t3/scratch");
  NodeAssert.throws(() => readThreadLaunchScratchProject({ projectId: "" }, "/t3/scratch"));
});

NodeTest.test("reads the returned thread ID for immediate navigation", () => {
  NodeAssert.equal(readLaunchedThreadId({ threadId: "new-thread", resumed: false }), "new-thread");
  NodeAssert.throws(() => readLaunchedThreadId({ resumed: false }));
});

NodeTest.test("requests provider discovery with the config RPC", () => {
  NodeAssert.deepEqual(threadLaunchConfigRequest(), {
    _tag: "Request",
    id: "1",
    tag: WS_METHODS.serverGetConfig,
    payload: {},
    headers: [],
  });
});
