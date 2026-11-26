import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";

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
  defaultClientPreferences,
  formatStorageBytes,
  parseClientPreferences,
  serializeClientPreferences,
  updateClientPreference,
} = await import(new URL("ClientPreferencesProtocol.ets", client).href);
loader.deregister();

const expectedDefaults = {
  projectGrouping: "repository",
  sidebarChatsFirst: false,
  useLastProject: true,
  runningAgentBehavior: "queue",
  composerReturnBehavior: "send",
};

NodeTest.test("returns default client preferences for empty or invalid JSON", () => {
  NodeAssert.deepEqual(defaultClientPreferences(), expectedDefaults);
  for (const raw of ["", "   ", "{bad json", "null", "[]", "123", '"string"', "true"]) {
    NodeAssert.deepEqual(parseClientPreferences(raw), expectedDefaults);
  }
});

NodeTest.test("preserves valid partial fields and falls back on invalid fields", () => {
  NodeAssert.deepEqual(
    parseClientPreferences(
      JSON.stringify({
        projectGrouping: "repository-path",
        sidebarChatsFirst: true,
        useLastProject: "yes",
        runningAgentBehavior: "invalid",
        composerReturnBehavior: "newline",
      }),
    ),
    {
      projectGrouping: "repository-path",
      sidebarChatsFirst: true,
      useLastProject: true,
      runningAgentBehavior: "queue",
      composerReturnBehavior: "newline",
    },
  );

  NodeAssert.deepEqual(
    parseClientPreferences(
      JSON.stringify({
        projectGrouping: "separate",
        useLastProject: false,
        runningAgentBehavior: "steer",
      }),
    ),
    {
      projectGrouping: "separate",
      sidebarChatsFirst: false,
      useLastProject: false,
      runningAgentBehavior: "steer",
      composerReturnBehavior: "send",
    },
  );
});

NodeTest.test("serializes and round-trips client preferences", () => {
  const custom = {
    projectGrouping: "separate",
    sidebarChatsFirst: true,
    useLastProject: false,
    runningAgentBehavior: "steer",
    composerReturnBehavior: "newline",
  };
  const serialized = serializeClientPreferences(custom);
  NodeAssert.deepEqual(parseClientPreferences(serialized), custom);
});

NodeTest.test("updates client preferences immutably", () => {
  const initial = defaultClientPreferences();

  const step1 = updateClientPreference(initial, "projectGrouping", "repository-path");
  NodeAssert.notEqual(step1, initial);
  NodeAssert.deepEqual(initial, expectedDefaults);
  NodeAssert.equal(step1.projectGrouping, "repository-path");

  const step2 = updateClientPreference(step1, "sidebarChatsFirst", true);
  NodeAssert.equal(step1.sidebarChatsFirst, false);
  NodeAssert.equal(step2.sidebarChatsFirst, true);
  NodeAssert.equal(step2.projectGrouping, "repository-path");

  const step3 = updateClientPreference(step2, "useLastProject", false);
  NodeAssert.equal(step3.useLastProject, false);

  const step4 = updateClientPreference(step3, "runningAgentBehavior", "steer");
  NodeAssert.equal(step4.runningAgentBehavior, "steer");

  const step5 = updateClientPreference(step4, "composerReturnBehavior", "newline");
  NodeAssert.deepEqual(step5, {
    projectGrouping: "repository-path",
    sidebarChatsFirst: true,
    useLastProject: false,
    runningAgentBehavior: "steer",
    composerReturnBehavior: "newline",
  });
});

NodeTest.test("formats storage bytes across units and edge cases", () => {
  NodeAssert.equal(formatStorageBytes(0), "0 B");
  NodeAssert.equal(formatStorageBytes(-128), "0 B");
  NodeAssert.equal(formatStorageBytes(Number.NaN), "0 B");
  NodeAssert.equal(formatStorageBytes(Number.POSITIVE_INFINITY), "0 B");
  NodeAssert.equal(formatStorageBytes(512), "512 B");
  NodeAssert.equal(formatStorageBytes(1024), "1 KB");
  NodeAssert.equal(formatStorageBytes(1536), "1.5 KB");
  NodeAssert.equal(formatStorageBytes(12 * 1024), "12 KB");
  NodeAssert.equal(formatStorageBytes(2.5 * 1024 * 1024), "2.5 MB");
  NodeAssert.equal(formatStorageBytes(3 * 1024 * 1024 * 1024), "3 GB");
});
