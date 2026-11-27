import * as NodeAssert from "node:assert/strict";
import * as NodeAsyncHooks from "node:async_hooks";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";

const fixtureContext = new NodeAsyncHooks.AsyncLocalStorage();

globalThis.threadReconnectFixture = () => fixtureContext.getStore();

NodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith("@kit.")) return { url: specifier, shortCircuit: true };
    if (specifier.startsWith("./") && context.parentURL?.endsWith(".ets")) {
      return nextResolve(specifier + ".ets", context);
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url.startsWith("@kit.")) {
      const source = {
        "@kit.AbilityKit": "export const common = {};",
        "@kit.ArkTS": `export const url = {
          URL: { parseURL: (value) => {
            const address = new URL(value);
            address.params = address.searchParams;
            return address;
          } },
          URLParams: URLSearchParams,
        }, util = { generateRandomUUID: () => crypto.randomUUID() };`,
        "@kit.ArkData": `export const relationalStore = {
          SecurityLevel: { S3: 3 },
          ConflictResolution: { ON_CONFLICT_REPLACE: 0 },
          getRdbStore: async () => globalThis.threadReconnectFixture().store,
        };`,
        "@kit.NetworkKit": `export const http = {
            RequestMethod: { GET: "GET", POST: "POST" },
            HttpDataType: { STRING: "string" },
            createHttp: () => ({ request: (...args) => globalThis.threadReconnectFixture().request(...args), destroy() {} }),
          };
          export const webSocket = { createWebSocket: () => globalThis.threadReconnectFixture().makeSocket() };`,
      }[url];
      return { format: "module", shortCircuit: true, source };
    }
    if (url.endsWith(".ets")) {
      return {
        format: "module",
        shortCircuit: true,
        source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(new URL(url), "utf8")),
      };
    }
    return nextLoad(url, context);
  },
});

const { T3Client } = await import("../entry/src/main/ets/client/T3Client.ets");
const { AccountNetworkError, AccountSessionExpiredError } =
  await import("../entry/src/main/ets/client/AccountProtocol.ets");
const { ThreadForkTargetPendingError, ThreadForkUnconfirmedError } =
  await import("../entry/src/main/ets/client/ThreadForkProtocol.ets");

const threadId = "fixture-thread";
const accountId = "fixture-account";
const environmentId = "fixture-environment";

NodeTest.test(
  "checks the environment identity before exchanging an additional route's code",
  async () => {
    const fixture = makeFixture();
    const requests = [];
    fixture.request = async (target, options) => {
      requests.push([target, options.method]);
      return {
        responseCode: 200,
        result: JSON.stringify({
          environmentId: "wrong-environment",
          label: "Wrong",
          orchestrationProtocolVersion: 2,
          access_token: "should-not-be-fetched",
        }),
      };
    };
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      await NodeAssert.rejects(
        client.pairAddress("https://wrong.example.test", "one-time-code", environmentId),
        /同一个环境/,
      );
      NodeAssert.deepEqual(requests, [
        ["https://wrong.example.test/.well-known/t3/environment", "GET"],
      ]);
      NodeAssert.deepEqual(await client.listEnvironments(accountId), []);
    });
  },
);

NodeTest.test(
  "uses an enabled same-environment Connect route when direct reconnect is offline",
  async () => {
    const managedKey = "managed:" + JSON.stringify([accountId, environmentId]);
    const fixture = makeFixture({
      version: 2,
      activeKey: "direct:" + environmentId,
      sessions: [
        { environmentId, label: "LAN", origin: "https://lan.example", token: "direct-credential" },
        { environmentId, label: "Connect", origin: "https://connect.example", accountId },
        {
          environmentId: "other",
          label: "Other",
          origin: "https://other.example",
          token: "other-token",
        },
      ],
    });
    let directStatus = 0;
    fixture.request = async (target, options) => {
      NodeAssert.equal(options.header.authorization, "Bearer direct-credential");
      if (target.endsWith("/api/auth/websocket-ticket/rpc")) {
        return { responseCode: 200, result: JSON.stringify({ ticket: "LAN-ticket" }) };
      }
      NodeAssert.equal(target, "https://lan.example/api/auth/session");
      if (!directStatus) throw new Error("offline");
      return {
        responseCode: directStatus,
        result: JSON.stringify({ authenticated: directStatus === 200 }),
      };
    };
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      await client.restore();
      let connections = 0;
      const connect = async (id) => {
        NodeAssert.equal(id, environmentId);
        connections++;
        return { ...fixture.makeConnection(), request: async () => ({ authenticated: true }) };
      };
      await client.reconnectEnvironment("direct:" + environmentId, accountId, connect);
      NodeAssert.equal(client.currentEnvironment().key, managedKey);
      directStatus = 403;
      await NodeAssert.rejects(
        client.reconnectEnvironment("direct:" + environmentId, accountId, connect),
        /权限/,
      );
      NodeAssert.equal(client.currentEnvironment().key, managedKey);
      NodeAssert.equal(connections, 1);
      directStatus = 200;
      await client.reconnectEnvironment(managedKey, accountId, async () => {
        throw new AccountNetworkError();
      });
      NodeAssert.equal(client.currentEnvironment().key, "direct:" + environmentId);
      fixture.canOpen = (address) => !address.startsWith("wss://lan.example");
      await client.reconnectEnvironment("direct:" + environmentId, accountId, connect);
      NodeAssert.equal(client.currentEnvironment().key, managedKey);
      await client.setEnvironmentEnabled(managedKey, false, accountId);
      directStatus = 0;
      await NodeAssert.rejects(
        client.reconnectEnvironment("direct:" + environmentId, accountId, connect),
        /无法访问/,
      );
      NodeAssert.equal(connections, 2);
    });
  },
);

NodeTest.test(
  "preserves distinct direct credentials and the preferred fallback order across a restart",
  async () => {
    const fixture = makeFixture();
    const attempts = [];
    fixture.request = async (target, options) => {
      const { hostname, pathname } = new URL(target);
      const token = hostname.split(".")[0] + "-credential";
      if (pathname === "/.well-known/t3/environment") {
        return {
          responseCode: 200,
          result: JSON.stringify({
            environmentId,
            label: "Fixture",
            orchestrationProtocolVersion: 2,
          }),
        };
      }
      if (pathname === "/oauth/token") {
        return { responseCode: 200, result: JSON.stringify({ access_token: token }) };
      }
      NodeAssert.equal(options.header.authorization, "Bearer " + token);
      if (pathname === "/api/auth/session") {
        attempts.push(hostname);
        if (hostname !== "preferred.example") throw new Error("offline");
        return { responseCode: 200, result: JSON.stringify({ authenticated: true }) };
      }
      NodeAssert.equal(pathname, "/api/auth/websocket-ticket/rpc");
      return { responseCode: 200, result: JSON.stringify({ ticket: "preferred-ticket" }) };
    };
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      NodeAssert.equal(await client.pairAddress("https://primary.example", "initial-code"), true);
      NodeAssert.equal(
        await client.pairAddress("https://alternate.example", "second-code", environmentId),
        false,
      );
      NodeAssert.equal(
        await client.pairAddress("https://preferred.example", "third-code", environmentId),
        false,
      );
      NodeAssert.equal(
        await client.pairAddress("https://primary.example", "renew-code", environmentId),
        true,
      );
      const [primary, alternate, preferred] = await client.listEnvironments();
      NodeAssert.equal(client.currentEnvironment().key, primary.key);
      NodeAssert.equal(new Set([primary.key, alternate.key, preferred.key]).size, 3);
      await client.moveEnvironmentRoute(preferred.key, -1);
      const restarted = new T3Client({});
      await restarted.restore();
      NodeAssert.deepEqual(
        (await restarted.listEnvironments()).map((row) => row.key),
        [primary.key, preferred.key, alternate.key],
      );
      await restarted.reconnectEnvironment(primary.key);
      NodeAssert.deepEqual(attempts, ["primary.example", "preferred.example"]);
      NodeAssert.equal(restarted.currentEnvironment().key, preferred.key);
    });
  },
);

NodeTest.test(
  "uses the target's own session to mint the peer code and the source's socket to link and unlink",
  async () => {
    const fixture = makeFixture({
      version: 2,
      activeKey: "direct:source",
      sessions: [
        {
          environmentId: "source",
          label: "Source",
          origin: "https://source.example",
          token: "source-token",
        },
        {
          environmentId: "peer",
          label: "Peer",
          origin: "https://peer.example",
          token: "peer-token",
        },
        {
          environmentId: "peer",
          label: "Peer",
          origin: "https://fallback.example",
          token: "fallback-token",
          routeId: "alt",
        },
      ],
    });
    const sourcePermissions = ["access:read", "orchestration:read"];
    const targetPermissions = ["access:write", "orchestration:read"];
    const writes = [];
    const linked = [];
    let peerOffline = false;
    fixture.request = async (target, options) => {
      const { hostname, pathname } = new URL(target);
      const isSource = hostname === "source.example";
      NodeAssert.ok(["source.example", "peer.example", "fallback.example"].includes(hostname));
      NodeAssert.equal(options.header.authorization, "Bearer " + hostname.split(".")[0] + "-token");
      if (peerOffline && hostname === "peer.example") throw new Error("offline");
      if (pathname === "/api/auth/session") {
        return {
          responseCode: 200,
          result: JSON.stringify({
            authenticated: true,
            permissions: isSource ? sourcePermissions : targetPermissions,
          }),
        };
      }
      if (pathname === "/api/auth/websocket-ticket/rpc") {
        return { responseCode: 200, result: JSON.stringify({ ticket: hostname }) };
      }
      NodeAssert.equal(pathname, "/api/auth/pairing-token");
      NodeAssert.equal(isSource, false);
      NodeAssert.equal(options.method, "POST");
      const body = JSON.parse(options.extraData);
      writes.push(body);
      return {
        responseCode: 200,
        result: JSON.stringify({ ...body, credential: "peer-one-time" }),
      };
    };
    fixture.onFrame = (frame, receive, address) => {
      const host = new URL(address).hostname;
      let value;
      if (frame.tag === "server.getConfig") {
        value =
          host === "source.example"
            ? {
                environment: { capabilities: { peerLinks: true } },
                settings: { linkedEnvironmentsEnabled: true },
              }
            : { environment: { capabilities: { peerLinkPairingCodes: true } } };
      } else {
        NodeAssert.equal(host, "source.example");
        if (frame.tag === "peerLinks.list") value = { links: [] };
        else {
          linked.push([frame.tag, frame.payload]);
          value = frame.tag === "peerLinks.unlink" ? { removed: true, endedThere: false } : {};
        }
      }
      receive(
        null,
        JSON.stringify({ _tag: "Exit", requestId: frame.id, exit: { _tag: "Success", value } }),
      );
    };
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      await client.restore();
      NodeAssert.deepEqual(await client.readLinkedEnvironmentHealth(), {
        links: [],
        canManage: false,
      });
      await NodeAssert.rejects(client.linkSavedEnvironment("direct:peer", "read-only"), /管理权限/);
      await NodeAssert.rejects(client.unlinkEnvironment("peer"), /管理权限/);
      sourcePermissions.push("access:write");
      await NodeAssert.rejects(client.linkSavedEnvironment("direct:peer", "full-access"), /签发/);
      NodeAssert.deepEqual(writes, []);
      await client.linkSavedEnvironment("direct:peer", "read-only");
      NodeAssert.deepEqual(writes, [
        { label: "T3 Code link", purpose: "peer-link", access: "read-only" },
      ]);
      NodeAssert.deepEqual(await client.unlinkEnvironment("peer"), {
        removed: true,
        endedThere: false,
      });
      NodeAssert.deepEqual(linked, [
        [
          "peerLinks.link",
          {
            url: "https://peer.example",
            alternateUrls: ["https://fallback.example"],
            expectedEnvironmentId: "peer",
            expectedLabel: "Peer",
            pairingCode: "peer-one-time",
            access: "read-only",
          },
        ],
        ["peerLinks.unlink", { environmentId: "peer" }],
      ]);
      peerOffline = true;
      await client.linkSavedEnvironment("direct:peer", "read-only");
      NodeAssert.equal(linked.at(-1)[1].url, "https://fallback.example");
      NodeAssert.deepEqual(linked.at(-1)[1].alternateUrls, ["https://peer.example"]);
      NodeAssert.equal(client.currentEnvironment().key, "direct:source");
    });
  },
);

NodeTest.test(
  "batch linking keeps successful or existing links and retries only targets that can be linked",
  async () => {
    const hosts = ["source", "first", "offline", "last", "existing", "changesource", "remaining"];
    const fixture = makeFixture({
      version: 2,
      activeKey: "direct:source",
      sessions: [
        ...hosts.map((host) => ({
          environmentId: host,
          label: host,
          origin: `https://${host}.example`,
          token: `${host}-session`,
        })),
        {
          environmentId: "managed",
          label: "Managed",
          origin: "https://managed.example",
          accountId,
        },
      ],
    });
    let offline = true;
    let beforeMintResult;
    const minted = [];
    const linked = new Set(["existing"]);
    fixture.request = async (target, options) => {
      const { hostname, pathname } = new URL(target);
      const host = hostname.split(".")[0];
      NodeAssert.equal(options.header.authorization, `Bearer ${host}-session`);
      if (host === "offline" && offline) throw new Error("offline");
      const payload =
        pathname === "/api/auth/session"
          ? {
              authenticated: true,
              permissions: ["access:read", "access:write", "orchestration:read"],
            }
          : pathname === "/api/auth/websocket-ticket/rpc"
            ? { ticket: host }
            : {};
      if (pathname === "/api/auth/pairing-token") {
        NodeAssert.notEqual(host, "source");
        const { purpose, access } = JSON.parse(options.extraData);
        minted.push(host);
        await beforeMintResult?.(host);
        return {
          responseCode: 200,
          result: JSON.stringify({ purpose, access, credential: `${host}-code` }),
        };
      }
      return { responseCode: 200, result: JSON.stringify(payload) };
    };
    fixture.onFrame = (frame, receive, address) => {
      const host = new URL(address).hostname.split(".")[0];
      let value = {};
      if (frame.tag === "server.getConfig") {
        value = {
          environment: { capabilities: { peerLinks: true, peerLinkPairingCodes: true } },
          settings: { linkedEnvironmentsEnabled: true },
        };
      } else if (frame.tag === "peerLinks.list") {
        NodeAssert.equal(host, "source");
        value = {
          links: Array.from(linked, (id) => ({
            environmentId: id,
            label: id,
            status: "reachable",
            expiresAt: new Date(8e15).toISOString(),
            lastError: null,
          })),
        };
      } else {
        NodeAssert.equal(host, "source");
        NodeAssert.equal(frame.tag, "peerLinks.link");
        const id = frame.payload.expectedEnvironmentId;
        NodeAssert.equal(frame.payload.pairingCode, `${id}-code`);
        NodeAssert.equal(linked.has(id), false);
        linked.add(id);
      }
      receive(
        null,
        JSON.stringify({ _tag: "Exit", requestId: frame.id, exit: { _tag: "Success", value } }),
      );
    };
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      await client.restore();
      const progress = [];
      const targets = [
        "direct:first",
        "direct:offline",
        "direct:last",
        "direct:existing",
        "direct:first",
      ];
      const first = await client.linkSavedEnvironmentBatch(
        targets,
        "read-only",
        undefined,
        undefined,
        (result) => progress.push([result.key, result.status]),
      );
      NodeAssert.deepEqual(
        first.map((row) => row.status),
        ["linked", "failed", "linked", "linked"],
      );
      NodeAssert.deepEqual(minted, ["first", "last"]);
      NodeAssert.ok(progress.some(([key, status]) => key === "direct:last" && status === "linked"));
      NodeAssert.doesNotMatch(JSON.stringify(first), /-code/);

      offline = false;
      const retried = await client.linkSavedEnvironmentBatch(targets, "read-only");
      NodeAssert.deepEqual(
        retried.map((row) => row.status),
        ["linked", "linked", "linked", "linked"],
      );
      NodeAssert.deepEqual(minted, ["first", "last", "offline"]);
      NodeAssert.equal(client.currentEnvironment().key, "direct:source");

      const managedKey = "managed:" + JSON.stringify([accountId, "managed"]);
      const expired = await client.linkSavedEnvironmentBatch(
        [managedKey],
        "read-only",
        accountId,
        async () => {
          throw new AccountSessionExpiredError();
        },
      );
      NodeAssert.equal(expired[0].status, "failed");
      NodeAssert.match(expired[0].message, /重新登录/);

      beforeMintResult = () => client.select("direct:last");
      const interrupted = await client.linkSavedEnvironmentBatch(
        ["direct:changesource", "direct:remaining"],
        "read-only",
      );
      NodeAssert.deepEqual(
        interrupted.map((row) => row.status),
        ["failed", "failed"],
      );
      NodeAssert.equal(linked.has("changesource"), false);
      NodeAssert.deepEqual(minted, ["first", "last", "offline", "changesource"]);
    });
  },
);

NodeTest.test(
  "maintenance rechecks the live permission and provider instance before dispatching an update",
  async () => {
    const fixture = makeFixture();
    const provider = {
      instanceId: "codex-work",
      driver: "codex",
      displayName: "Codex Work",
      enabled: true,
      installed: true,
      version: "1.0.0",
      versionAdvisory: { canUpdate: true, status: "behind_latest", latestVersion: "1.1.0" },
    };
    let permissions = ["orchestration:read", "environment:maintain", "providers:manage"];
    const dispatched = [];
    fixture.onFrame = (frame, receive) => {
      let value;
      if (frame.tag === "server.getConfig") {
        value = {
          environment: {
            serverVersion: "1.2.3",
            capabilities: { serverSelfUpdate: "boot-service" },
          },
          providers: [provider],
        };
      } else {
        dispatched.push([frame.tag, frame.payload]);
        value = {
          providers: [
            frame.tag === "server.updateProvider"
              ? { ...provider, updateState: { status: "failed", message: "Fixture failure" } }
              : provider,
          ],
        };
      }
      receive(
        null,
        JSON.stringify({ _tag: "Exit", requestId: frame.id, exit: { _tag: "Success", value } }),
      );
    };
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      const connect = async () => ({
        ...fixture.makeConnection(),
        request: async () => ({ authenticated: true, permissions }),
      });
      await client.connectManaged(environmentId, accountId, connect);
      const initial = await client.readEnvironmentMaintenance();
      NodeAssert.equal(initial.version, "1.2.3");
      NodeAssert.equal(initial.canCheck, true);
      NodeAssert.equal(initial.providers[0].canUpdate, true);
      permissions = ["orchestration:read", "orchestration:operate"];
      await NodeAssert.rejects(
        client.updateEnvironmentMaintenanceProvider(initial.providers[0]),
        /更新/,
      );
      NodeAssert.deepEqual(dispatched, []);
      await client.refreshEnvironmentMaintenanceProviders();
      permissions.push("providers:manage");
      await NodeAssert.rejects(
        client.updateEnvironmentMaintenanceProvider({ ...initial.providers[0], driver: "other" }),
        /更新/,
      );
      const result = await client.updateEnvironmentMaintenanceProvider(initial.providers[0]);
      NodeAssert.equal(result.providers[0].status, "failed");
      NodeAssert.deepEqual(dispatched, [
        ["server.refreshProviders", { reloadSecrets: true, workspaceSnapshotsOnDemand: true }],
        ["server.updateProvider", { instanceId: "codex-work", provider: "codex" }],
      ]);
    });
  },
);

NodeTest.test(
  "model preferences require a live settings grant from the original environment",
  async () => {
    const fixture = makeFixture();
    const dispatched = [];
    const permissionRead = Promise.withResolvers();
    const release = Promise.withResolvers();
    let permissions = ["orchestration:operate"];
    let hold = false;
    fixture.onFrame = (frame, receive) => {
      NodeAssert.equal(frame.tag, "server.updateSettings");
      dispatched.push(frame.payload.patch);
      receive(
        null,
        JSON.stringify({
          _tag: "Exit",
          requestId: frame.id,
          exit: {
            _tag: "Success",
            value: { favorites: [{ provider: "qaProvider", model: "qaModel" }] },
          },
        }),
      );
    };
    const connect = async (id) => ({
      ...fixture.makeConnection(),
      environmentId: id,
      request: async () => {
        if (hold && id === environmentId) {
          permissionRead.resolve();
          await release.promise;
        }
        return { authenticated: true, permissions };
      },
    });
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      await client.connectManaged(environmentId, accountId, connect);
      await NodeAssert.rejects(
        client.updateModelCatalogPreferences("qaProvider", "qaModel", "favorite", true),
        /授权/,
      );
      NodeAssert.deepEqual(dispatched, []);
      permissions = ["settings:write"];
      const saved = await client.updateModelCatalogPreferences(
        "qaProvider",
        "qaModel",
        "favorite",
        true,
      );
      NodeAssert.deepEqual(saved.favorites, [{ provider: "qaProvider", model: "qaModel" }]);
      hold = true;
      const rejected = NodeAssert.rejects(
        client.updateModelCatalogPreferences("qaProvider", "qaModel", "hidden", true),
        /环境连接已更换/,
      );
      await permissionRead.promise;
      await client.connectManaged("other-fixture", accountId, connect);
      release.resolve();
      await rejected;
      NodeAssert.deepEqual(dispatched, [
        { setModelFavorites: [{ provider: "qaProvider", model: "qaModel", favorite: true }] },
      ]);
    });
  },
);

NodeTest.test("composer reads use the active host checkout and its current grants", async () => {
  const fixture = makeFixture();
  const provider = {
    instanceId: "codex-work",
    driver: "codex",
    enabled: true,
    installed: true,
    status: "ready",
    models: [{ slug: "test", name: "Fixture" }],
  };
  let permissions = ["orchestration:read"];
  let modernScopesOnly = false;
  const dispatched = [];
  fixture.onFrame = (frame, receive) => {
    dispatched.push([frame.tag, frame.payload]);
    let value;
    if (frame.tag === "server.getConfig") {
      value = {
        providers: [provider],
        settings: {
          projectSettingsOverrides: {
            denied: { providerInstances: { "codex-work": { enabled: false } } },
          },
        },
      };
    } else if (frame.tag === "server.refreshProviders") {
      value = {
        providers: [
          {
            ...provider,
            workspaceSnapshots: [
              {
                cwd: "/project/worktree",
                slashCommands: [{ name: "workspace" }],
                skills: [],
              },
            ],
          },
        ],
      };
    } else {
      value = { entries: [{ path: "README.md", kind: "file" }], truncated: false };
    }
    receive(
      null,
      JSON.stringify({ _tag: "Exit", requestId: frame.id, exit: { _tag: "Success", value } }),
    );
  };
  await fixtureContext.run(fixture, async () => {
    const client = new T3Client({});
    await client.connectManaged(environmentId, accountId, async () => ({
      ...fixture.makeConnection(),
      request: async () =>
        modernScopesOnly
          ? { authenticated: true, scopes: permissions, auth: { serverUpdateScope: "disabled" } }
          : { authenticated: true, permissions },
    }));
    const scope = {
      environmentKey: client.currentEnvironment().key,
      projectId: "allowed",
      cwd: "/project/worktree",
    };
    await NodeAssert.rejects(
      client.searchComposerPaths({ ...scope, environmentKey: "old" }, ""),
      /环境连接/,
    );
    await NodeAssert.rejects(client.searchComposerPaths(scope, ""), /文件读取权限/);
    modernScopesOnly = true;
    await NodeAssert.rejects(client.searchComposerPaths(scope, ""), /文件读取权限/);
    NodeAssert.deepEqual(dispatched, []);
    permissions = ["orchestration:read", "filesystem:read"];
    NodeAssert.equal((await client.searchComposerPaths(scope, ""))[0].path, "README.md");
    await NodeAssert.rejects(
      client.readComposerProviderCatalog({ ...scope, projectId: "denied" }, "codex-work"),
      /未启用/,
    );
    const catalog = await client.readComposerProviderCatalog(scope, "codex-work");
    NodeAssert.equal(catalog.slashCommands[0].name, "workspace");
    const repeated = await client.readComposerProviderCatalog(scope, "codex-work");
    NodeAssert.equal(repeated, catalog);
    const settings = await client.composerModelSettings(scope);
    NodeAssert.equal(settings.providers[0].instanceId, "codex-work");
    NodeAssert.equal(await client.composerModelSettings(scope), settings);
    NodeAssert.deepEqual(dispatched, [
      ["projects.searchEntries", { cwd: scope.cwd, query: "", limit: 20 }],
      ["server.getConfig", {}],
      ["server.getConfig", {}],
      [
        "server.refreshProviders",
        {
          instanceId: "codex-work",
          cwd: scope.cwd,
          workspaceSnapshotsOnDemand: true,
          providerCatalogsOnDemand: true,
        },
      ],
    ]);
  });
});

NodeTest.test("reuses composer link discovery only in the selected session", async () => {
  const fixture = makeFixture();
  const dispatched = [];
  fixture.onFrame = (frame, receive) => {
    dispatched.push(frame.tag);
    const value =
      frame.tag === "server.getConfig"
        ? {
            environment: { capabilities: { peerLinks: true } },
            settings: { linkedEnvironmentsEnabled: true },
          }
        : {
            links: [
              {
                environmentId: "peer",
                label: "Fixture peer",
                status: "reachable",
                expiresAt: "2035-01-01T00:00:00.000Z",
                lastError: null,
              },
            ],
          };
    receive(
      null,
      JSON.stringify({ _tag: "Exit", requestId: frame.id, exit: { _tag: "Success", value } }),
    );
  };
  await fixtureContext.run(fixture, async () => {
    const client = new T3Client({});
    const connect = async (id) => ({
      ...fixture.makeConnection(),
      environmentId: id,
      request: async () => ({
        authenticated: true,
        permissions: ["orchestration:read", "access:read"],
      }),
    });
    await client.connectManaged(environmentId, accountId, connect);
    const scope = { environmentKey: client.currentEnvironment().key };
    const [first, repeated] = await Promise.all([
      client.readComposerLinkedEnvironments(scope),
      client.readComposerLinkedEnvironments(scope),
    ]);
    NodeAssert.equal(first.links[0].environmentId, "peer");
    NodeAssert.equal(repeated, first);
    await client.connectManaged("new-environment", accountId, connect);
    await NodeAssert.rejects(client.readComposerLinkedEnvironments(scope), /环境连接已更换/);
    const newResult = await client.readComposerLinkedEnvironments({
      environmentKey: client.currentEnvironment().key,
    });
    NodeAssert.notEqual(newResult, first);
    NodeAssert.deepEqual(dispatched, [
      "server.getConfig",
      "peerLinks.list",
      "server.getConfig",
      "peerLinks.list",
    ]);
  });
});

NodeTest.test(
  "checkpoint diff reads require orchestration read on the original environment",
  async () => {
    const fixture = makeFixture();
    const dispatched = [];
    let permissions = ["filesystem:read"];
    let hold = false;
    const permissionRead = Promise.withResolvers();
    const release = Promise.withResolvers();
    fixture.onFrame = (frame, receive) => {
      dispatched.push([frame.tag, frame.payload]);
      const { threadId, fromTurnCount, toTurnCount } = frame.payload;
      const value = { threadId, fromTurnCount, toTurnCount, diff: "" };
      receive(
        null,
        JSON.stringify({ _tag: "Exit", requestId: frame.id, exit: { _tag: "Success", value } }),
      );
    };
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      const connect = async (id) => ({
        ...fixture.makeConnection(),
        environmentId: id,
        request: async () => {
          if (hold) {
            permissionRead.resolve();
            await release.promise;
          }
          return { authenticated: true, permissions };
        },
      });
      await client.connectManaged(environmentId, accountId, connect);
      const key = client.currentEnvironment().key;
      await NodeAssert.rejects(
        client.readThreadCheckpointDiff("other-key", "checkpoint-thread", 1),
        /环境连接/,
      );
      await NodeAssert.rejects(
        client.readThreadCheckpointDiff(key, "checkpoint-thread", 1),
        /读取权限/,
      );
      NodeAssert.deepEqual(dispatched, []);
      permissions = ["orchestration:read"];
      const diff = await client.readThreadCheckpointDiff(key, "checkpoint-thread", 1);
      NodeAssert.deepEqual(diff.groups, []);
      hold = true;
      const rejected = NodeAssert.rejects(
        client.readThreadCheckpointDiff(key, "checkpoint-thread", 2),
        /环境连接/,
      );
      await permissionRead.promise;
      await client.connectManaged("other-environment", accountId, connect);
      release.resolve();
      await rejected;
      NodeAssert.deepEqual(dispatched, [
        [
          "orchestration.getTurnDiff",
          {
            threadId: "checkpoint-thread",
            fromTurnCount: 0,
            toTurnCount: 1,
            ignoreWhitespace: false,
          },
        ],
      ]);
    });
  },
);

NodeTest.test(
  "fork retries retain the same target and navigate only to its confirmed host projection",
  async () => {
    const fixture = makeFixture();
    const source = { sourceThreadId: "source-thread", runId: "source-run" };
    const attempt = { commandId: "fork-command", targetThreadId: "fork-target" };
    const targetPath = "/api/orchestration/threads/fork-target/bounded?deferWork=1";
    const commands = [];
    const targetReads = [];
    let dispatchState = "accepted";
    let targetState = "missing";
    let permissions = ["orchestration:read"];
    fixture.onFrame = (frame, receive) => {
      NodeAssert.equal(frame.tag, "orchestration.dispatchCommand");
      commands.push(frame.payload);
      if (dispatchState === "unknown") {
        receive(null, JSON.stringify({ _tag: "Defect" }));
        return;
      }
      const exit =
        dispatchState === "accepted"
          ? { _tag: "Success", value: { sequence: 7 } }
          : { _tag: "Failure" };
      receive(null, JSON.stringify({ _tag: "Exit", requestId: frame.id, exit }));
    };
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      await client.connectManaged(environmentId, accountId, async () => ({
        ...fixture.makeConnection(),
        request: async (path) => {
          if (path === "/api/auth/session") return { authenticated: true, permissions };
          if (path === "/api/projects")
            return {
              projects: [
                { id: "host-project", title: "Host project", workspaceRoot: "/isolated/workspace" },
              ],
            };
          NodeAssert.equal(path, targetPath);
          targetReads.push(path);
          if (targetState === "missing") throw new Error("Fixture target not available");
          return {
            projection: {
              thread: {
                id: attempt.targetThreadId,
                title: "Host fork title",
                projectId: "host-project",
                lineage: { relationshipToParent: "fork", parentThreadId: source.sourceThreadId },
                forkedFrom: {
                  type: "run",
                  threadId: source.sourceThreadId,
                  runId: targetState === "correct" ? source.runId : "wrong-run",
                },
              },
            },
          };
        },
      }));
      const key = client.currentEnvironment().key;
      await NodeAssert.rejects(
        client.forkThreadFromReply("wrong-key", source, attempt),
        /环境连接/,
      );
      await NodeAssert.rejects(
        client.forkThreadFromReply(key, source, attempt),
        /缺少分叉会话的权限/,
      );
      NodeAssert.deepEqual(commands, []);
      NodeAssert.deepEqual(targetReads, []);
      permissions = ["orchestration:read", "orchestration:operate"];
      await NodeAssert.rejects(
        client.forkThreadFromReply(key, source, attempt),
        ThreadForkTargetPendingError,
      );
      targetState = "wrong-source";
      await NodeAssert.rejects(
        client.forkThreadFromReply(key, source, attempt),
        ThreadForkTargetPendingError,
      );
      dispatchState = "unknown";
      await NodeAssert.rejects(
        client.forkThreadFromReply(key, source, attempt),
        ThreadForkUnconfirmedError,
      );
      targetState = "correct";
      dispatchState = "rejected";
      const target = await client.forkThreadFromReply(key, source, attempt);
      NodeAssert.equal(target.title, "Host fork title");
      NodeAssert.equal(target.workspaceRoot, "/isolated/workspace");
      NodeAssert.equal(target.environmentKey, key);
      NodeAssert.deepEqual(targetReads, Array(4).fill(targetPath));
      NodeAssert.deepEqual(
        commands,
        Array(4).fill({
          type: "thread.fork",
          commandId: attempt.commandId,
          createdBy: "user",
          creationSource: "mobile",
          sourceThreadId: source.sourceThreadId,
          targetThreadId: attempt.targetThreadId,
          sourcePoint: { type: "run", runId: source.runId },
        }),
      );
    });
  },
);

NodeTest.test(
  "resumes background work from the shell cursor and scopes live updates to the open thread",
  async () => {
    const key = "direct:" + environmentId;
    const fixture = makeFixture({
      version: 2,
      activeKey: key,
      sessions: [
        {
          environmentId,
          label: "Source",
          origin: "https://source.example",
          token: "fixture-token",
        },
      ],
    });
    const row = (id, taskId) => ({
      id,
      title: "Thread",
      latestRunId: "run-1",
      pendingBackgroundTasks: taskId ? [{ taskId, kind: "command" }] : [],
    });
    fixture.request = async (target) => {
      const path = new URL(target).pathname;
      const value =
        path === "/api/orchestration/shell"
          ? { snapshotSequence: 10, threads: [row(threadId, "build")], archivedThreads: [] }
          : path === "/api/auth/session"
            ? { authenticated: true }
            : { ticket: "source" };
      return { responseCode: 200, result: JSON.stringify(value) };
    };
    const subscribed = Promise.withResolvers();
    fixture.onFrame = (frame, receive) => {
      if (frame.tag === "orchestration.subscribeShell") subscribed.resolve({ frame, receive });
    };
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      await client.restore();
      await client.listThreads();
      const updates = [];
      const errors = [];
      const stop = client.watchBackgroundWork(
        key,
        threadId,
        (thread) => updates.push(thread?.pendingBackgroundTasks.map((task) => task.taskId)),
        (error) => errors.push(error),
      );
      try {
        const { frame, receive } = await subscribed.promise;
        NodeAssert.deepEqual(frame.payload, { afterSequence: 10, requestCompletionMarker: true });
        const send = (...values) =>
          receive(null, JSON.stringify({ _tag: "Chunk", requestId: frame.id, values }));
        send(
          {
            kind: "snapshot",
            resolvedRepositoryIdentityRoots: ["/workspace"],
            snapshot: { snapshotSequence: 13, threads: [], archivedThreads: [] },
          },
          {
            kind: "thread.updated",
            sequence: 11,
            location: "active",
            thread: row("other-thread", "unrelated"),
          },
          { kind: "synchronized" },
        );
        NodeAssert.deepEqual(updates, [["build"]]);
        send(
          {
            kind: "thread.updated",
            sequence: 12,
            location: "active",
            thread: row(threadId, "next"),
          },
          {
            kind: "thread.updated",
            sequence: 11,
            location: "active",
            thread: row(threadId, "stale"),
          },
          {
            kind: "thread.updated",
            sequence: 13,
            location: "active",
            thread: row(threadId),
          },
        );
        NodeAssert.deepEqual(updates, [["build"], ["next"], []]);
        stop();
        send({
          kind: "thread.updated",
          sequence: 14,
          location: "active",
          thread: row(threadId, "closed"),
        });
        NodeAssert.deepEqual(updates, [["build"], ["next"], []]);
        NodeAssert.deepEqual(errors, []);
      } finally {
        stop();
      }
    });
  },
);

NodeTest.test(
  "background stop rechecks the source and operate grant before sending the host's command",
  async () => {
    const key = "direct:" + environmentId;
    const fixture = makeFixture({
      version: 2,
      activeKey: key,
      sessions: [
        {
          environmentId,
          label: "Source",
          origin: "https://source.example",
          token: "fixture-token",
        },
      ],
    });
    let operate = false;
    let supported = true;
    let inScope = true;
    const commands = [];
    fixture.request = async (target) => {
      const value =
        new URL(target).pathname === "/api/auth/session"
          ? {
              authenticated: true,
              permissions: operate
                ? ["orchestration:read", "orchestration:operate"]
                : ["orchestration:read"],
            }
          : { ticket: "source" };
      return { responseCode: 200, result: JSON.stringify(value) };
    };
    fixture.onFrame = (frame, receive) => {
      if (frame._tag !== "Request") return;
      if (frame.tag === "orchestration.dispatchCommand") commands.push(frame.payload);
      const value =
        frame.tag === "server.getConfig"
          ? { environment: { capabilities: { threadStop: supported } } }
          : {};
      receive(
        null,
        JSON.stringify({ _tag: "Exit", requestId: frame.id, exit: { _tag: "Success", value } }),
      );
    };
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      await client.restore();
      const watches = [{ host: "git.example.test", repository: "example/project", number: 4 }];
      const stop = (sourceKey, run) =>
        client.stopBackgroundWork(sourceKey, threadId, run, watches, () => inScope);
      await NodeAssert.rejects(async () => stop("different-environment", "run-1"), /环境已更换/);
      await NodeAssert.rejects(async () => stop(key, "run-1"), /缺少停止.*权限/);
      NodeAssert.deepEqual(commands, []);
      operate = true;
      inScope = false;
      await NodeAssert.rejects(async () => stop(key, "run-1"), /后台工作已更换/);
      NodeAssert.deepEqual(commands, []);
      inScope = true;
      await stop(key, "run-1");
      supported = false;
      await stop(key, "run-1");
      await stop(key, "");
      NodeAssert.deepEqual(
        commands.map(({ commandId: _commandId, ...command }) => command),
        [
          { type: "thread.stop", threadId },
          { type: "run.interrupt", threadId, runId: "run-1", holdQueue: true },
          {
            type: "thread.pull-request.watch",
            threadId,
            host: "git.example.test",
            repository: "example/project",
            number: 4,
            watching: false,
          },
        ],
      );
    });
  },
);

function makeFixture(saved) {
  let persisted = saved === undefined ? undefined : JSON.stringify(saved);
  const addresses = [];
  const subscriptions = [];
  const nextSubscription = () => {
    const signal = Promise.withResolvers();
    subscriptions.push(signal);
    return signal.promise;
  };
  return {
    addresses,
    nextSubscription,
    store: {
      executeSql: async () => {},
      querySql: async () => ({
        goToFirstRow: () => persisted !== undefined,
        getString: () => persisted,
        close() {},
      }),
      insert: async (_table, values) => {
        persisted = values.document;
      },
    },
    makeSocket() {
      const handlers = new Map();
      let currentAddress;
      const socket = {
        on(event, handler) {
          handlers.set(event, handler);
        },
        off(event) {
          handlers.delete(event);
        },
        async connect(address) {
          currentAddress = address;
          addresses.push(address);
          if (fixtureContext.getStore().canOpen?.(address) === false) return false;
          handlers.get("open")?.();
          return true;
        },
        async send(raw) {
          const frame = JSON.parse(raw);
          fixtureContext.getStore().onFrame?.(frame, handlers.get("message"), currentAddress);
          if (frame.tag === "orchestration.subscribeThread") {
            NodeAssert.equal(frame.payload.threadId, threadId);
            subscriptions.shift().resolve(socket);
          }
          return true;
        },
        async close() {},
        message(text, sequence, snapshotThreadId = threadId) {
          handlers.get("message")?.(
            null,
            JSON.stringify({
              _tag: "Chunk",
              requestId: "1",
              values: [
                {
                  kind: "snapshot",
                  snapshotSequence: sequence,
                  projection: {
                    thread: { id: snapshotThreadId, title: "QA" },
                    messages: [{ id: "message-1", role: "assistant", text }],
                  },
                },
              ],
            }),
          );
        },
        streamItem(item) {
          handlers.get("message")?.(
            null,
            JSON.stringify({ _tag: "Chunk", requestId: "1", values: [item] }),
          );
        },
        disconnect() {
          handlers.get("close")?.();
        },
      };
      return socket;
    },
    makeConnection() {
      let ticket = 0;
      return {
        environmentId,
        label: "QA",
        origin: "https://fixture.example.test",
        orchestrationProtocolVersion: 2,
        async socketAddress() {
          ticket++;
          return `wss://fixture.example.test/ws?wsTicket=single-use-${ticket}`;
        },
      };
    },
  };
}

NodeTest.test(
  "restores the same environment by direct route if the saved Connect route is offline",
  async () => {
    const managedKey = "managed:" + JSON.stringify([accountId, environmentId]);
    const directKey = "direct:" + environmentId;
    const fixture = makeFixture({
      version: 2,
      activeKey: managedKey,
      sessions: [
        {
          environmentId: "other",
          label: "Other",
          origin: "https://other.example",
          token: "other-token",
        },
        { environmentId, label: "Connect", origin: "https://connect.example", accountId },
        { environmentId, label: "Direct", origin: "https://direct.example", token: "direct-token" },
      ],
    });
    fixture.request = async (target, options) => {
      const address = new URL(target);
      NodeAssert.equal(address.hostname, "direct.example");
      NodeAssert.equal(options.header.authorization, "Bearer direct-token");
      const value =
        address.pathname === "/api/auth/session" ? { authenticated: true } : { ticket: "direct" };
      return { responseCode: 200, result: JSON.stringify(value) };
    };
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      await NodeAssert.rejects(
        client.restore(accountId, async () => {
          throw new Error("approval-required");
        }),
        /approval-required/,
      );
      NodeAssert.equal(client.currentEnvironment(), undefined);
      await client.restore(accountId, async () => {
        throw new AccountNetworkError();
      });
      NodeAssert.equal(client.currentEnvironment().key, directKey);

      const connect = async () => ({
        ...fixture.makeConnection(),
        request: async () => ({ authenticated: true }),
      });
      await client.removeEnvironmentRoute(directKey, accountId, connect);
      NodeAssert.equal(client.currentEnvironment().key, managedKey);
      NodeAssert.deepEqual(
        (await client.listEnvironments(accountId)).map((row) => row.key),
        ["direct:other", managedKey],
      );
      const restarted = new T3Client({});
      await restarted.restore(accountId, connect);
      NodeAssert.equal(restarted.currentEnvironment().key, managedKey);
    });
  },
);

NodeTest.test(
  "binds device approval to its enabled, permitted environment without selecting it",
  async () => {
    const fixture = makeFixture({
      version: 2,
      activeKey: "direct:current",
      sessions: [
        {
          environmentId: "current",
          label: "Current",
          origin: "https://current.example",
          token: "current-token",
        },
        { environmentId, label: "Managed", origin: "https://connect.example", accountId },
      ],
    });
    let permissions = ["access:read"];
    const mutations = [];
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      await client.restore();
      const [managed] = (await client.listEnvironments(accountId)).filter((entry) => entry.managed);
      const connect = async () => ({
        ...fixture.makeConnection(),
        request: async (path, method, body) => {
          if (path === "/api/auth/session") return { authenticated: true, permissions };
          mutations.push({ path, method, body });
          return { approved: true };
        },
      });
      NodeAssert.equal(
        await client.bindDeviceApprovalTarget(managed, accountId, connect),
        undefined,
      );
      permissions = ["access:read", "access:write"];
      NodeAssert.equal(
        await client.bindDeviceApprovalTarget(managed, accountId, connect),
        undefined,
      );
      permissions.push("orchestration:read");
      const target = await client.bindDeviceApprovalTarget(managed, accountId, connect);
      NodeAssert.equal(await target.approve("pair-1", () => false), "gone");
      NodeAssert.equal(await target.approve("pair-1", () => true), "done");
      NodeAssert.equal(client.currentEnvironment().key, "direct:current");
      NodeAssert.deepEqual(mutations, [
        {
          path: "/api/auth/connect-devices/approve",
          method: "POST",
          body: JSON.stringify({ pairingLinkId: "pair-1" }),
        },
      ]);
      await client.setEnvironmentEnabled(managed.key, false, accountId);
      NodeAssert.equal(await target.approve("pair-1", () => true), "gone");
    });
  },
);

NodeTest.test(
  "a dropped managed stream renews the ticket and catches up before publishing",
  async (test) => {
    test.mock.timers.enable({ apis: ["setTimeout", "setInterval"] });
    const fixture = makeFixture();
    const cursors = [];
    fixture.onFrame = (frame) => {
      if (frame.tag === "orchestration.subscribeThread") cursors.push(frame.payload.afterSequence);
    };
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      const connection = fixture.makeConnection();
      await client.connectManaged(environmentId, accountId, async () => connection);
      const updates = [];
      const failures = [];
      const firstSubscription = fixture.nextSubscription();
      const stop = client.watchThread(
        threadId,
        (messages) => updates.push(messages.map((message) => message.text)),
        (_error, reconnecting) => failures.push(reconnecting),
      );
      try {
        const first = await firstSubscription;
        first.message("Before drop", 5);
        first.disconnect();
        NodeAssert.deepEqual(failures, [true]);
        const secondSubscription = fixture.nextSubscription();
        test.mock.timers.tick(1000);
        const second = await secondSubscription;
        second.streamItem({
          kind: "event",
          sequence: 8,
          event: {
            threadId,
            type: "message.updated",
            payload: { id: "message-2", threadId, role: "assistant", text: "Caught up" },
          },
        });
        NodeAssert.deepEqual(updates, [["Before drop"]]);
        second.streamItem({ kind: "synchronized" });
        first.message("Retired socket", 9);
        NodeAssert.deepEqual(updates, [["Before drop"], ["Before drop", "Caught up"]]);
        second.disconnect();
        const thirdSubscription = fixture.nextSubscription();
        test.mock.timers.tick(1000);
        (await thirdSubscription).message("Replacement snapshot", 10);
        NodeAssert.deepEqual(updates.at(-1), ["Replacement snapshot"]);
        NodeAssert.deepEqual(cursors, [undefined, 5, 8]);
        NodeAssert.deepEqual(fixture.addresses, [
          "wss://fixture.example.test/ws?wsTicket=single-use-1",
          "wss://fixture.example.test/ws?wsTicket=single-use-2",
          "wss://fixture.example.test/ws?wsTicket=single-use-3",
        ]);
      } finally {
        stop();
      }
    });
  },
);

NodeTest.test("a reconnect publishes even when no events were missed", async (test) => {
  test.mock.timers.enable({ apis: ["setTimeout", "setInterval"] });
  const fixture = makeFixture();
  await fixtureContext.run(fixture, async () => {
    const client = new T3Client({});
    await client.connectManaged(environmentId, accountId, async () => fixture.makeConnection());
    const updates = [];
    const opened = fixture.nextSubscription();
    const stop = client.watchThread(
      threadId,
      (messages) => updates.push(messages[0].text),
      () => {},
    );
    try {
      const first = await opened;
      first.message("Already visible", 5);
      first.disconnect();
      const reopened = fixture.nextSubscription();
      test.mock.timers.tick(1000);
      (await reopened).streamItem({ kind: "synchronized" });
      NodeAssert.deepEqual(updates, ["Already visible", "Already visible"]);
    } finally {
      stop();
    }
  });
});

NodeTest.test(
  "keeps retrying a temporarily unavailable route after the initial backoff",
  async (test) => {
    test.mock.timers.enable({ apis: ["setTimeout", "setInterval"] });
    const fixture = makeFixture();
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      const connection = fixture.makeConnection();
      let online = true;
      await client.connectManaged(environmentId, accountId, async () => ({
        ...connection,
        socketAddress: async () => {
          if (!online) throw new AccountNetworkError();
          return connection.socketAddress();
        },
      }));
      let failure = Promise.withResolvers();
      const updates = [];
      const opened = fixture.nextSubscription();
      const stop = client.watchThread(
        threadId,
        (messages) => updates.push(messages[0].text),
        (_error, reconnecting) => failure.resolve(reconnecting),
      );
      try {
        const first = await opened;
        first.message("Before the outage", 5);
        online = false;
        first.disconnect();
        NodeAssert.equal(await failure.promise, true);
        for (const delay of [1000, 2000, 4000]) {
          failure = Promise.withResolvers();
          test.mock.timers.tick(delay);
          NodeAssert.equal(await failure.promise, true);
        }
        online = true;
        const reopened = fixture.nextSubscription();
        test.mock.timers.tick(8000);
        (await reopened).streamItem({ kind: "synchronized" });
        NodeAssert.deepEqual(updates, ["Before the outage", "Before the outage"]);
      } finally {
        stop();
      }
    });
  },
);

NodeTest.test(
  "discards a subscription snapshot for a different thread before showing messages",
  async (test) => {
    test.mock.timers.enable({ apis: ["setTimeout", "setInterval"] });
    const fixture = makeFixture();
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      await client.connectManaged(environmentId, accountId, async () => fixture.makeConnection());
      const updates = [];
      const errors = [];
      const opened = fixture.nextSubscription();
      const stop = client.watchThread(
        threadId,
        (messages) => updates.push(messages),
        (error) => errors.push(error.message),
      );
      try {
        const socket = await opened;
        socket.message("Should not appear", 1, "different-thread");
        NodeAssert.deepEqual(updates, []);
        NodeAssert.equal(errors.length, 1);
      } finally {
        stop();
      }
    });
  },
);

NodeTest.test(
  "leaving a conversation cancels the managed stream's scheduled reconnect",
  async (test) => {
    test.mock.timers.enable({ apis: ["setTimeout", "setInterval"] });
    const fixture = makeFixture();
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      const connection = fixture.makeConnection();
      await client.connectManaged(environmentId, accountId, async () => connection);
      const opened = fixture.nextSubscription();
      const stop = client.watchThread(
        threadId,
        () => {},
        () => {},
      );
      (await opened).disconnect();
      stop();
      test.mock.timers.tick(1000);
      NodeAssert.equal(fixture.addresses.length, 1);
    });
  },
);

NodeTest.test(
  "reports expired environment authentication instead of a read-only grant",
  async () => {
    await fixtureContext.run(makeFixture(), async () => {
      const client = new T3Client({});
      await client.connectManaged(environmentId, accountId, async () => ({
        ...fixtureContext.getStore().makeConnection(),
        request: async () => ({ authenticated: false }),
      }));
      await NodeAssert.rejects(client.threadPermissions(), /授权已失效/);
    });
  },
);

NodeTest.test(
  "a disabled managed environment stays disabled across restarts until enabled",
  async () => {
    const fixture = makeFixture();
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      const connection = fixture.makeConnection();
      let opens = 0;
      const connect = async () => {
        opens++;
        return connection;
      };
      await client.connectManaged(environmentId, accountId, connect);
      const key = client.currentEnvironment().key;
      await client.updateEnvironment(key, "Renamed QA", undefined, accountId);
      await client.setEnvironmentEnabled(key, false, accountId);
      NodeAssert.equal(client.currentEnvironment(), undefined);

      const restored = new T3Client({});
      NodeAssert.equal(await restored.restore(accountId, connect), false);
      const [saved] = await restored.listEnvironments(accountId);
      NodeAssert.equal(saved.label, "Renamed QA");
      NodeAssert.equal(saved.enabled, false);
      await NodeAssert.rejects(
        restored.connectManaged(environmentId, accountId, connect),
        /已停用/,
      );
      NodeAssert.equal(opens, 1);

      await restored.setEnvironmentEnabled(key, true, accountId);
      await restored.select(key, accountId, connect);
      NodeAssert.equal(restored.currentEnvironment().label, "Renamed QA");
      NodeAssert.equal(opens, 2);
    });
  },
);

NodeTest.test(
  "changing a direct address checks the environment before sending credentials",
  async () => {
    const fixture = makeFixture({
      environmentId,
      label: "Saved",
      origin: "https://old.example.test",
      token: "saved-credential",
    });
    const requests = [];
    fixture.request = async (target, options) => {
      requests.push([target, options.header.authorization]);
      return {
        responseCode: 200,
        result: JSON.stringify({
          environmentId: target.includes("different") ? "other-environment" : environmentId,
          orchestrationProtocolVersion: 2,
        }),
      };
    };
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      NodeAssert.equal(await client.restore(), true);
      const key = client.currentEnvironment().key;
      await NodeAssert.rejects(
        client.updateEnvironment(key, "New label", "https://different.example.test"),
        /同一个兼容的 T3 环境/,
      );
      NodeAssert.equal(client.currentEnvironment().origin, "https://old.example.test");
      await client.updateEnvironment(key, "New label", "wss://new.example.test");
      NodeAssert.equal(client.currentEnvironment().origin, "https://new.example.test");
      NodeAssert.equal(client.currentEnvironment().label, "New label");
      NodeAssert.deepEqual(requests, [
        ["https://different.example.test/.well-known/t3/environment", undefined],
        ["https://new.example.test/.well-known/t3/environment", undefined],
      ]);
    });
  },
);

NodeTest.test(
  "looks up a deep-linked thread with a bounded snapshot and verifies its identity",
  async () => {
    const fixture = makeFixture();
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      const paths = [];
      const linkedId = "task:ß";
      await client.connectManaged(environmentId, accountId, async () => ({
        ...fixture.makeConnection(),
        request: async (path) => {
          paths.push(path);
          return path === "/api/projects"
            ? { projects: [{ id: "project-1", title: "Project", workspaceRoot: "/repo" }] }
            : {
                projection: {
                  thread: { id: linkedId, title: "Linked task", projectId: "project-1" },
                },
              };
        },
      }));
      const target = await client.readThreadLinkTarget(linkedId);
      NodeAssert.equal(target.title, "Linked task");
      NodeAssert.equal(target.workspaceRoot, "/repo");
      await NodeAssert.rejects(client.readThreadLinkTarget("unknown"), /会话不存在/);
      NodeAssert.deepEqual(paths, [
        "/api/orchestration/threads/task%3A%C3%9F/bounded?deferWork=1",
        "/api/projects",
        "/api/orchestration/threads/unknown/bounded?deferWork=1",
      ]);
    });
  },
);

NodeTest.test(
  "reads another environment without replacing the current connection or its credential",
  async () => {
    const fixture = makeFixture({
      version: 2,
      activeKey: "direct:current",
      sessions: [
        {
          environmentId: "current",
          label: "Current",
          origin: "https://current.example",
          token: "first",
        },
        {
          environmentId: "other",
          label: "Other",
          origin: "https://other.example",
          token: "second",
        },
      ],
    });
    const requests = [];
    fixture.request = async (target, options) => {
      requests.push([target, options.header.authorization]);
      return {
        responseCode: 200,
        result: JSON.stringify({
          threads: [
            { id: "same-id", title: target.includes("other") ? "Other task" : "Current task" },
          ],
          projects: [],
        }),
      };
    };
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      await client.restore();
      const [other, current] = await Promise.all([
        client.listEnvironmentThreads("direct:other"),
        client.listThreads(),
      ]);
      NodeAssert.equal(client.currentEnvironment().environmentId, "current");
      NodeAssert.equal(other[0].title, "Other task");
      NodeAssert.equal(current[0].title, "Current task");
      NodeAssert.deepEqual(requests.sort(), [
        ["https://current.example/api/orchestration/shell", "Bearer first"],
        ["https://other.example/api/orchestration/shell", "Bearer second"],
      ]);
    });
  },
);

NodeTest.test(
  "refreshing an already active managed account keeps its thread subscription",
  async () => {
    const fixture = makeFixture();
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      const connection = fixture.makeConnection();
      await client.connectManaged(environmentId, accountId, async () => connection);
      const updates = [];
      const opened = fixture.nextSubscription();
      const stop = client.watchThread(
        threadId,
        (messages) => updates.push(messages[0].text),
        () => {},
      );
      try {
        const socket = await opened;
        socket.message("Before account refresh", 5);
        await client.restore(accountId, async () =>
          NodeAssert.fail("The active transport is already bound"),
        );
        socket.message("Still subscribed", 6);
        NodeAssert.deepEqual(updates, ["Before account refresh", "Still subscribed"]);
      } finally {
        stop();
      }
    });
  },
);

NodeTest.test(
  "honors separate terminal and Git grants, including an explicitly empty permission list",
  async () => {
    const fixture = makeFixture();
    await fixtureContext.run(fixture, async () => {
      const client = new T3Client({});
      let access = {
        authenticated: true,
        permissions: ["terminal:read", "source-control:write"],
        scopes: ["orchestration:operate", "terminal:operate"],
      };
      await client.connectManaged(environmentId, accountId, async () => ({
        ...fixture.makeConnection(),
        request: async () => access,
      }));
      let permissions = await client.threadPermissions();
      NodeAssert.deepEqual(
        [permissions.terminalRead, permissions.terminalOperate, permissions.gitWrite],
        [true, false, true],
      );
      access = { ...access, permissions: [] };
      permissions = await client.threadPermissions();
      NodeAssert.deepEqual(
        [permissions.terminalRead, permissions.terminalOperate, permissions.gitWrite],
        [false, false, false],
      );
      access = { authenticated: true, scopes: ["orchestration:operate", "terminal:operate"] };
      permissions = await client.threadPermissions();
      NodeAssert.deepEqual(
        [permissions.terminalRead, permissions.terminalOperate, permissions.gitWrite],
        [true, true, true],
      );
    });
  },
);
