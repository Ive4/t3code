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
NodeTest.after(() => loader.deregister());

const { buildProviderEnabledPatchRequest, readProvidersSummary } = await import(
  new URL("ProvidersProtocol.ets", client).href
);

const decodePatch = Schema.decodeUnknownSync(ClientServerSettingsPatch);

NodeTest.test("reads provider summaries from server config and ignores malformed entries", () => {
  NodeAssert.deepEqual(readProvidersSummary(null), []);
  NodeAssert.deepEqual(readProvidersSummary({}), []);

  const summaries = readProvidersSummary({
    providers: [
      {
        instanceId: "codex",
        driver: "codex",
        displayName: "Codex",
        installed: true,
        enabled: true,
        status: "ready",
        availability: "available",
        auth: { status: "authenticated" },
        version: "0.42.0",
      },
      {
        instanceId: "claude_work",
        driver: "claudeAgent",
        installed: true,
        enabled: true,
        status: "disabled",
        availability: "unavailable",
        auth: { status: "unauthenticated" },
        message: "Sign in required",
      },
      {
        instanceId: "bad:id",
        driver: "codex",
        installed: true,
        enabled: true,
        auth: { status: "authenticated" },
      },
    ],
  });

  NodeAssert.deepEqual(summaries, [
    {
      instanceId: "codex",
      driver: "codex",
      displayName: "Codex",
      installed: true,
      enabled: true,
      authStatus: "authenticated",
      availability: "available",
      status: "ready",
      version: "0.42.0",
    },
    {
      instanceId: "claude_work",
      driver: "claudeAgent",
      displayName: "claude_work",
      installed: true,
      enabled: false,
      authStatus: "unauthenticated",
      availability: "unavailable",
      status: "disabled",
      message: "Sign in required",
    },
  ]);
});

NodeTest.test("builds server.updateSettings providerInstances enabled patch request", () => {
  const defaultDriverReq = buildProviderEnabledPatchRequest("codex", false);
  NodeAssert.equal(defaultDriverReq.method, WS_METHODS.serverUpdateSettings);
  NodeAssert.deepEqual(decodePatch(defaultDriverReq.params.patch), {
    providerInstances: {
      codex: {
        driver: "codex",
        enabled: false,
      },
    },
  });

  const explicitDriverReq = buildProviderEnabledPatchRequest("claude_work", true, "claudeAgent");
  NodeAssert.equal(explicitDriverReq.method, WS_METHODS.serverUpdateSettings);
  NodeAssert.deepEqual(decodePatch(explicitDriverReq.params.patch), {
    providerInstances: {
      claude_work: {
        driver: "claudeAgent",
        enabled: true,
      },
    },
  });

  NodeAssert.throws(() => buildProviderEnabledPatchRequest("", true));
  NodeAssert.throws(() => buildProviderEnabledPatchRequest("bad:id", true));
});
