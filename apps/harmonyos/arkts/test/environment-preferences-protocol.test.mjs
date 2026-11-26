import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import { ClientServerSettingsPatch, WS_METHODS } from "@t3tools/contracts";
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

const { buildEnvironmentSettingsPatchRequest, readEnvironmentPreferences } = await import(
  new URL("EnvironmentPreferencesProtocol.ets", client).href
);
loader.deregister();

const decodePatch = Schema.decodeUnknownSync(ClientServerSettingsPatch);

NodeTest.test("reads ServerSettings defaults when config is empty or missing", () => {
  const expectedDefaults = {
    threadPreferences: {
      defaultThreadEnvMode: null,
      defaultRuntimeMode: "full-access",
      responseStreamingMode: "paragraph",
      enableAgentBrowserAccess: true,
      autoResumeLimitedThreads: false,
      snoozeLimitedThreads: false,
      sidebarAutoSettleOnMerge: true,
      sidebarAutoSettleAfterDays: 7,
    },
    sourceControl: {
      removeAgentCreditsOnMerge: false,
      defaultAutoPull: false,
      ghqCloneLayout: false,
    },
    worktrees: {
      newWorktreesStartFromOrigin: true,
      worktreeSubmodules: null,
    },
    maintenance: {
      enableProviderUpdateChecks: true,
      continueThreadsAfterServerUpdate: true,
      keepAwakeWhileAgentsWork: true,
    },
    labs: {
      fastWorktreeCheckout: false,
      guestSharingEnabled: false,
      linkedEnvironmentsEnabled: false,
      workflowsEnabled: false,
      promptSuggestionsEnabled: false,
      simlockDeviceHostsEnabled: false,
    },
  };

  NodeAssert.deepEqual(readEnvironmentPreferences(undefined), expectedDefaults);
  NodeAssert.deepEqual(readEnvironmentPreferences({ settings: {} }), expectedDefaults);
});

NodeTest.test("reads populated ServerConfig and normalizes invalid fields safely", () => {
  const snapshot = readEnvironmentPreferences({
    settings: {
      defaultThreadEnvMode: "worktree",
      defaultRuntimeMode: "auto-accept-edits",
      responseStreamingMode: "turn",
      enableAgentBrowserAccess: false,
      autoResumeLimitedThreads: true,
      snoozeLimitedThreads: true,
      sidebarAutoSettleOnMerge: false,
      sidebarAutoSettleAfterDays: null,
      removeAgentCreditsOnMerge: true,
      defaultAutoPull: true,
      ghqCloneLayout: true,
      newWorktreesStartFromOrigin: false,
      worktreeSubmodules: "top-level",
      enableProviderUpdateChecks: false,
      continueThreadsAfterServerUpdate: false,
      keepAwakeWhileAgentsWork: false,
      fastWorktreeCheckout: true,
      guestSharingEnabled: true,
      linkedEnvironmentsEnabled: true,
      workflowsEnabled: true,
      promptSuggestionsEnabled: true,
      simlockDeviceHostsEnabled: true,
    },
  });

  NodeAssert.deepEqual(snapshot, {
    threadPreferences: {
      defaultThreadEnvMode: "worktree",
      defaultRuntimeMode: "auto-accept-edits",
      responseStreamingMode: "turn",
      enableAgentBrowserAccess: false,
      autoResumeLimitedThreads: true,
      snoozeLimitedThreads: true,
      sidebarAutoSettleOnMerge: false,
      sidebarAutoSettleAfterDays: null,
    },
    sourceControl: {
      removeAgentCreditsOnMerge: true,
      defaultAutoPull: true,
      ghqCloneLayout: true,
    },
    worktrees: {
      newWorktreesStartFromOrigin: false,
      worktreeSubmodules: "top-level",
    },
    maintenance: {
      enableProviderUpdateChecks: false,
      continueThreadsAfterServerUpdate: false,
      keepAwakeWhileAgentsWork: false,
    },
    labs: {
      fastWorktreeCheckout: true,
      guestSharingEnabled: true,
      linkedEnvironmentsEnabled: true,
      workflowsEnabled: true,
      promptSuggestionsEnabled: true,
      simlockDeviceHostsEnabled: true,
    },
  });

  const normalized = readEnvironmentPreferences({
    settings: {
      defaultThreadEnvMode: "unknown-mode",
      defaultRuntimeMode: "unknown-runtime",
      responseStreamingMode: "stream",
      sidebarAutoSettleAfterDays: 999,
      worktreeSubmodules: "unknown-submodules",
    },
  });
  NodeAssert.equal(normalized.threadPreferences.defaultThreadEnvMode, null);
  NodeAssert.equal(normalized.threadPreferences.defaultRuntimeMode, "full-access");
  NodeAssert.equal(normalized.threadPreferences.responseStreamingMode, "paragraph");
  NodeAssert.equal(normalized.threadPreferences.sidebarAutoSettleAfterDays, 7);
  NodeAssert.equal(normalized.worktrees.worktreeSubmodules, null);
});

NodeTest.test("builds server.updateSettings patches validated by ClientServerSettingsPatch", () => {
  const patches = [
    { defaultThreadEnvMode: null },
    { defaultThreadEnvMode: "local" },
    { defaultThreadEnvMode: "worktree" },
    { defaultRuntimeMode: "approval-required" },
    { defaultRuntimeMode: "auto-accept-edits" },
    { defaultRuntimeMode: "auto" },
    { defaultRuntimeMode: "full-access" },
    { responseStreamingMode: "turn" },
    { responseStreamingMode: "paragraph" },
    { enableAgentBrowserAccess: false },
    { autoResumeLimitedThreads: true },
    { snoozeLimitedThreads: true },
    { sidebarAutoSettleOnMerge: false },
    { sidebarAutoSettleAfterDays: null },
    { sidebarAutoSettleAfterDays: 14 },
    { removeAgentCreditsOnMerge: true },
    { defaultAutoPull: true },
    { ghqCloneLayout: true },
    { newWorktreesStartFromOrigin: false },
    { worktreeSubmodules: null },
    { worktreeSubmodules: "recursive" },
    { worktreeSubmodules: "top-level" },
    { worktreeSubmodules: "none" },
    { enableProviderUpdateChecks: false },
    { continueThreadsAfterServerUpdate: false },
    { keepAwakeWhileAgentsWork: false },
    { fastWorktreeCheckout: true },
    { guestSharingEnabled: true },
    { linkedEnvironmentsEnabled: true },
    { workflowsEnabled: true },
    { promptSuggestionsEnabled: true },
    { simlockDeviceHostsEnabled: true },
  ];

  for (const patch of patches) {
    const request = buildEnvironmentSettingsPatchRequest(patch);
    NodeAssert.equal(request.method, WS_METHODS.serverUpdateSettings);
    NodeAssert.deepEqual(decodePatch(request.params.patch), patch);
  }
});

NodeTest.test("rejects empty, invalid, or unsupported environment settings patches", () => {
  NodeAssert.throws(() => buildEnvironmentSettingsPatchRequest({}));
  NodeAssert.throws(() => buildEnvironmentSettingsPatchRequest({ defaultRuntimeMode: null }));
  NodeAssert.throws(() => buildEnvironmentSettingsPatchRequest({ defaultThreadEnvMode: "remote" }));
  NodeAssert.throws(() => buildEnvironmentSettingsPatchRequest({ sidebarAutoSettleAfterDays: 0 }));
  NodeAssert.throws(() =>
    buildEnvironmentSettingsPatchRequest({ enableAgentBrowserAccess: "yes" }),
  );
  NodeAssert.throws(() => buildEnvironmentSettingsPatchRequest({ unknownKey: true }));
});
