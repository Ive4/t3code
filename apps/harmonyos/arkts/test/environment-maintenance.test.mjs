import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import {
  AuthEnvironmentMaintainScope,
  AuthOrchestrationReadScope,
  AuthProvidersManageScope,
  ServerProviderUpdateInput,
  ServerProviderUpdatedPayload,
  WsRpcGroup,
  WS_METHODS,
} from "@t3tools/contracts";
import * as Schema from "effect/Schema";

const client = new URL("../entry/src/main/ets/client/", import.meta.url);
const decodeProviderUpdate = Schema.decodeUnknownSync(
  Schema.toCodecJson(ServerProviderUpdateInput),
);
const decodeProviderResult = Schema.decodeUnknownSync(
  Schema.toCodecJson(ServerProviderUpdatedPayload),
);
const refresh = WsRpcGroup.requests.get(WS_METHODS.serverRefreshProviders);
const decodeRefresh = Schema.decodeUnknownSync(Schema.toCodecJson(refresh.payloadSchema));
let releaseResponses;
const loader = NodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === "@kit.NetworkKit") return { shortCircuit: true, url: "native-network:kit" };
    if (specifier.startsWith("./") && context.parentURL?.startsWith(client.href)) {
      return nextResolve(`${specifier}.ets`, context);
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url === "native-network:kit") {
      return {
        format: "module",
        shortCircuit: true,
        source: `export const http = {
          RequestMethod: { GET: "GET" },
          HttpDataType: { STRING: "string" },
          createHttp: () => ({
            request: (...args) => globalThis.requestMaintenanceRelease(...args),
            destroy: () => {},
          }),
        };`,
      };
    }
    if (!url.startsWith(client.href) || !url.endsWith(".ets")) return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(new URL(url), "utf8")),
    };
  },
});
globalThis.requestMaintenanceRelease = (address, settings) => {
  NodeAssert.equal(settings.method, "GET");
  NodeAssert.equal(Object.hasOwn(settings.header, "authorization"), false);
  const response = releaseResponses.get(address);
  NodeAssert.ok(response, `Unexpected release request: ${address}`);
  return Promise.resolve(response);
};
NodeTest.after(() => {
  delete globalThis.requestMaintenanceRelease;
  loader.deregister();
});

const protocol = () => import(new URL("EnvironmentMaintenanceProtocol.ets", client).href);
const allPermissions = [
  AuthEnvironmentMaintainScope,
  AuthOrchestrationReadScope,
  AuthProvidersManageScope,
];
const readyProvider = {
  instanceId: "codex-work",
  driver: "codex",
  displayName: "Codex Work",
  enabled: true,
  installed: true,
  version: "1.0.0",
  status: "ready",
  auth: { status: "authenticated" },
  checkedAt: "2026-11-25T05:00:00.000Z",
  models: [],
  versionAdvisory: {
    status: "behind_latest",
    currentVersion: "1.0.0",
    latestVersion: "1.1.0",
    updateCommand: null,
    canUpdate: true,
    checkedAt: null,
    message: null,
  },
};

NodeTest.test(
  "gates maintenance and provider controls separately and keeps server update policy",
  async () => {
    const { readEnvironmentMaintenance } = await protocol();
    const config = {
      environment: {
        serverVersion: "1.2.3",
        capabilities: { serverSelfUpdate: "desktop-managed", desktopAppUpdate: true },
      },
      providers: [readyProvider],
    };
    const readOnly = readEnvironmentMaintenance(config, [AuthOrchestrationReadScope]);
    NodeAssert.equal(readOnly.version, "1.2.3");
    NodeAssert.equal(readOnly.canCheck, false);
    NodeAssert.equal(readOnly.canRefresh, true);
    NodeAssert.equal(readOnly.providers[0].canUpdate, false);
    const writable = readEnvironmentMaintenance(config, allPermissions);
    NodeAssert.equal(writable.canCheck, true);
    NodeAssert.equal(writable.serverUpdateCapability, "desktop-managed");
    NodeAssert.equal(writable.providers[0].canUpdate, true);
    const operateOnly = ["orchestration:operate"];
    NodeAssert.equal(readEnvironmentMaintenance(config, operateOnly).canCheck, false);
    const legacy = readEnvironmentMaintenance(config, operateOnly, true);
    NodeAssert.equal(legacy.canCheck, true);
    NodeAssert.equal(legacy.providers[0].canUpdate, true);
    const managed = readEnvironmentMaintenance(
      {
        ...config,
        managedPolicy: { organization: "Example", limits: { updates: { mode: "off" } } },
      },
      allPermissions,
    );
    NodeAssert.equal(managed.organization, "Example");
    NodeAssert.match(managed.updateDenial, /Example/);
    NodeAssert.equal(managed.canCheck, false);
  },
);

NodeTest.test(
  "refreshes using the Android payload and limits provider updates to ready instances",
  async () => {
    const {
      refreshEnvironmentProvidersRequest,
      updateEnvironmentProviderRequest,
      readMaintenanceProviders,
    } = await protocol();
    const refreshRequest = refreshEnvironmentProvidersRequest();
    NodeAssert.equal(refreshRequest.tag, WS_METHODS.serverRefreshProviders);
    NodeAssert.deepEqual(decodeRefresh(refreshRequest.payload), {
      reloadSecrets: true,
      workspaceSnapshotsOnDemand: true,
    });
    const providers = readMaintenanceProviders(
      decodeProviderResult({
        providers: [
          readyProvider,
          { ...readyProvider, instanceId: "disabled", enabled: false },
          {
            ...readyProvider,
            instanceId: "queued",
            updateState: {
              status: "queued",
              message: "Waiting",
              startedAt: null,
              finishedAt: null,
              output: null,
            },
          },
          {
            ...readyProvider,
            instanceId: "broken",
            compatibilityAdvisory: {
              status: "supported",
              latestVersionStatus: "broken",
              message: null,
              recommendedVersion: null,
              recommendedRange: null,
            },
          },
          { ...readyProvider, instanceId: "missing", installed: false },
        ],
      }),
      allPermissions,
    );
    NodeAssert.deepEqual(
      providers.map((provider) => [provider.instanceId, provider.canUpdate]),
      [
        ["codex-work", true],
        ["queued", false],
        ["broken", false],
        ["missing", false],
      ],
    );
    const update = updateEnvironmentProviderRequest(providers[0]);
    NodeAssert.equal(update.tag, WS_METHODS.serverUpdateProvider);
    NodeAssert.deepEqual(decodeProviderUpdate(update.payload), {
      instanceId: "codex-work",
      provider: "codex",
    });
    NodeAssert.throws(() => updateEnvironmentProviderRequest(providers[1]), /更新/);
  },
);

NodeTest.test("reads stable and prerelease feeds without crossing release channels", async () => {
  const { checkEnvironmentRelease } = await protocol();
  const stable = "https://github.com/pingdotgg/t3code/releases/latest";
  const atom = "https://github.com/pingdotgg/t3code/releases.atom";
  const api = "https://api.github.com/repos/pingdotgg/t3code/releases?per_page=100&page=1";
  const atomTags = ["desktop", "v1.0.0", "v1.0.0-nightly.20261124.10"];
  releaseResponses = new Map([
    [stable, { responseCode: 200, result: JSON.stringify({ tag_name: "v1.2.11" }) }],
    [
      atom,
      {
        responseCode: 200,
        result: atomTags
          .map((tag) => `<entry><id>tag:github.com,2008:Repository/1/${tag}</id></entry>`)
          .join(""),
      },
    ],
    [
      api,
      {
        responseCode: 200,
        result: JSON.stringify([
          { tag_name: "v1.2.11" },
          { tag_name: "v1.0.0-preview.20261124.9", draft: true },
          { tag_name: "v1.0.0-preview.20261124.2" },
        ]),
      },
    ],
  ]);
  NodeAssert.equal(await checkEnvironmentRelease("1.2.9"), "1.2.11");
  NodeAssert.equal(await checkEnvironmentRelease("1.2.11"), null);
  NodeAssert.equal(
    await checkEnvironmentRelease("1.0.0-nightly.20261124.9"),
    "1.0.0-nightly.20261124.10",
  );
  NodeAssert.equal(
    await checkEnvironmentRelease("1.0.0-preview.20261124.1"),
    "1.0.0-preview.20261124.2",
  );
  releaseResponses.set(stable, { responseCode: 429, result: "" });
  await NodeAssert.rejects(checkEnvironmentRelease("1.2.9"), /429/);
});
