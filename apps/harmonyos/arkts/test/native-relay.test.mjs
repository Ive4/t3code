import * as NodeAssert from "node:assert/strict";
import * as NodeAsyncHooks from "node:async_hooks";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";

const requests = new NodeAsyncHooks.AsyncLocalStorage();
const relay = "https://relay.example.test";
const tunnel = "https://tunnel.example.test";
const endpoint = {
  httpBaseUrl: tunnel,
  wsBaseUrl: "wss://socket.example.test/ws",
  providerKind: "t3_relay",
};
const environment = {
  environmentId: "desk-1",
  label: "Desk",
  endpoint,
  linkedAt: "2026-11-24T00:00:00Z",
};
const clerk = (sub) => `a.${Buffer.from(JSON.stringify({ sub })).toString("base64url")}.b`;
const issuer = "urn:ietf:params:oauth:token-type:access_token";
const scoped = (scope, token = "relay-access") => ({
  token_type: "DPoP",
  issued_token_type: issuer,
  expires_in: 300,
  access_token: token,
  scope,
});
const signer = {
  thumbprint: async () => "key-thumbprint",
  proof: async (method, target, token) => `${method} ${target} ${token ?? ""}`,
};
function reply(value, responseCode = 200) {
  return { responseCode, result: JSON.stringify(value) };
}

globalThis.nativeRelayTestRequest = (target, options) => {
  NodeAssert.equal(options.maxRedirects, 0);
  NodeAssert.equal(options.remoteValidation, "system");
  return requests.getStore()(target, options);
};
NodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith("@kit.")) return { url: specifier, shortCircuit: true };
    if (specifier.startsWith("./") && context.parentURL?.endsWith(".ets")) {
      return nextResolve(`${specifier}.ets`, context);
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url === "@kit.ArkTS") {
      return {
        format: "module",
        shortCircuit: true,
        source: `export const url = { URL: { parseURL: (value) => new URL(value) } };
          export const util = {
            Base64Helper: class { decodeSync(value) { return Buffer.from(value, "base64url"); } },
            TextDecoder: { create: () => ({ decodeToString: (bytes) => new TextDecoder().decode(bytes) }) },
            Type: { BASIC_URL_SAFE: 1 },
          };`,
      };
    }
    if (url === "@kit.NetworkKit") {
      return {
        format: "module",
        shortCircuit: true,
        source: `export const http = {
          createHttp: () => ({ request: globalThis.nativeRelayTestRequest, destroy() {} }),
          HttpDataType: { STRING: 'string' },
          RequestMethod: { GET: 'GET', POST: 'POST' },
        };`,
      };
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

const { NativeRelay, RelayApprovalPendingError, RelayApprovalUnavailableError } =
  await import("../entry/src/main/ets/client/NativeRelay.ets");
const { DeviceApprovalClient } =
  await import("../entry/src/main/ets/client/DeviceApprovalClient.ets");
const { connectDeviceVerificationCode } =
  await import("../entry/src/main/ets/client/RelayProtocol.ets");

function makeClient(origin = relay + "/") {
  return new NativeRelay(origin, signer);
}

NodeTest.test(
  "accepts an empty authenticated discovery response without exchanging tokens",
  async () => {
    const token = clerk("account-a");
    await requests.run(
      (target, options) => {
        NodeAssert.equal(target, `${relay}/v1/environments`);
        NodeAssert.equal(options.method, "GET");
        NodeAssert.equal(options.header.authorization, `Bearer ${token}`);
        return reply({ environments: [] });
      },
      async () => NodeAssert.deepEqual(await makeClient().listEnvironments(token), []),
    );
  },
);

NodeTest.test(
  "rejects insecure or decorated relay origins and a rejected discovery bearer",
  async () => {
    for (const origin of [
      "http://relay.example.test",
      "https://user@relay.example.test",
      "https://relay.example.test/subpath",
      "https://relay.example.test?query=1",
      "https://relay.example.test/#fragment",
    ]) {
      NodeAssert.throws(() => makeClient(origin));
    }
    await requests.run(
      (target) => {
        NodeAssert.equal(target, `${relay}/v1/environments`);
        return reply(
          { _tag: "RelayAuthInvalidError", code: "auth_invalid", reason: "invalid_bearer" },
          401,
        );
      },
      async () => NodeAssert.rejects(makeClient().listEnvironments(clerk("account-a"))),
    );
  },
);

NodeTest.test("deregisters an encoded environment using the account bearer", async () => {
  const token = clerk("account-a");
  for (const ok of [true, false]) {
    await requests.run(
      (target, options) => {
        NodeAssert.equal(target, `${relay}/v1/client/environment-links/desk%2F2`);
        NodeAssert.equal(options.method, "DELETE");
        NodeAssert.deepEqual(options.header, { authorization: `Bearer ${token}` });
        NodeAssert.equal(options.extraData, undefined);
        return reply({ ok });
      },
      async () => makeClient().deregisterEnvironment(token, "desk/2"),
    );
  }
});

NodeTest.test(
  "retains the account and ignores unlink-looking data in an HTTP failure",
  async () => {
    const token = clerk("account-a");
    const client = makeClient();
    const pendingList = Promise.withResolvers();
    let attempts = 0;
    await requests.run(
      (target, options) => {
        NodeAssert.equal(options.header.authorization, `Bearer ${token}`);
        if (target === `${relay}/v1/environments`) return pendingList.promise;
        NodeAssert.equal(target, `${relay}/v1/client/environment-links/desk-1`);
        attempts += 1;
        return attempts === 1 ? reply({ ok: false }, 403) : reply({ ok: "false" });
      },
      async () => {
        const listing = client.listEnvironments(token);
        await NodeAssert.rejects(client.deregisterEnvironment(token, "desk-1"), /403/);
        await NodeAssert.rejects(client.deregisterEnvironment(token, "desk-1"), /注销结果无效/);
        pendingList.resolve(reply({ environments: [] }));
        NodeAssert.deepEqual(await listing, []);
      },
    );
    NodeAssert.equal(attempts, 2);
  },
);

NodeTest.test(
  "publishes available environments while a slow host is still being checked",
  async () => {
    const snapshots = [];
    const slowStarted = Promise.withResolvers();
    const slowReply = Promise.withResolvers();
    const fastPublished = Promise.withResolvers();
    const client = makeClient();
    const second = { ...environment, environmentId: "desk-2" };
    const status = (row, value) =>
      reply({
        environmentId: row.environmentId,
        endpoint,
        status: value,
        checkedAt: row.linkedAt,
      });
    await requests.run(
      (target) => {
        switch (target) {
          case `${relay}/v1/environments`:
            return reply({ environments: [environment, second] });
          case `${relay}/v1/client/dpop-token`:
            return reply(scoped("environment:connect environment:status"));
          case `${relay}/v1/environments/desk-1/status`:
            return status(environment, "online");
          case `${relay}/v1/environments/desk-2/status`:
            slowStarted.resolve();
            return slowReply.promise;
          default:
            NodeAssert.fail(`unexpected target: ${target}`);
        }
      },
      async () => {
        const result = client.listEnvironments(clerk("account-a"), (rows) => {
          snapshots.push(rows);
          if (rows[0].availability === "online") fastPublished.resolve(rows);
        });
        try {
          await slowStarted.promise;
          NodeAssert.deepEqual(
            snapshots[0]?.map((row) => row.availability),
            ["checking", "checking"],
          );
          const partial = await fastPublished.promise;
          NodeAssert.deepEqual(
            partial.map((row) => row.availability),
            ["online", "checking"],
          );
        } finally {
          slowReply.resolve(status(second, "offline"));
          await result;
        }
        NodeAssert.deepEqual(
          (await result).map((row) => row.availability),
          ["online", "offline"],
        );
        NodeAssert.deepEqual(
          snapshots.map((rows) => rows.map((row) => row.availability)),
          [
            ["checking", "checking"],
            ["online", "checking"],
            ["online", "offline"],
          ],
        );
      },
    );
  },
);

NodeTest.test(
  "shares exact status scopes and returns online, offline, and mismatched environments by ID",
  async () => {
    let exchanges = 0;
    const token = clerk("account-a");
    await requests.run(
      (target, options) => {
        const path = new URL(target).pathname;
        if (path === "/v1/environments") {
          return reply({
            environments: [
              environment,
              { ...environment, environmentId: "desk/2" },
              { ...environment, environmentId: "desk-3" },
            ],
          });
        }
        if (path === "/v1/client/dpop-token") {
          NodeAssert.equal(new URL(target).origin, relay);
          const form = new URLSearchParams(options.extraData);
          NodeAssert.equal(form.get("subject_token"), token);
          NodeAssert.equal(form.get("client_id"), "t3-mobile");
          NodeAssert.equal(form.get("resource"), relay);
          NodeAssert.equal(form.get("scope"), "environment:status environment:connect");
          exchanges += 1;
          return reply(scoped("environment:connect environment:status"));
        }
        NodeAssert.equal(new URL(target).origin, relay);
        NodeAssert.equal(options.header.dpop, `POST ${target} relay-access`);
        const environmentId = decodeURIComponent(path.split("/")[3]);
        return reply({
          environmentId: environmentId === "desk-3" ? "other" : environmentId,
          endpoint,
          status: environmentId === "desk/2" ? "offline" : "online",
          checkedAt: "2026-11-24T00:00:00Z",
        });
      },
      async () => {
        const rows = await makeClient().listEnvironments(token);
        NodeAssert.deepEqual(
          rows.map(({ environmentId, availability }) => [environmentId, availability]),
          [
            ["desk-1", "online"],
            ["desk/2", "offline"],
            ["desk-3", "error"],
          ],
        );
      },
    );
    NodeAssert.equal(exchanges, 1);
  },
);

NodeTest.test("suppresses a pending status after a same-account discovery refresh", async () => {
  const client = makeClient();
  const started = Promise.withResolvers();
  const pending = Promise.withResolvers();
  const oldRows = [];
  const newRows = [];
  let lists = 0;
  await requests.run(
    (target) => {
      switch (target) {
        case `${relay}/v1/environments`:
          lists += 1;
          return reply({ environments: lists === 1 ? [environment] : [] });
        case `${relay}/v1/client/dpop-token`:
          return reply(scoped("environment:connect environment:status"));
        case `${relay}/v1/environments/desk-1/status`:
          started.resolve();
          return pending.promise;
        default:
          NodeAssert.fail(`unexpected target: ${target}`);
      }
    },
    async () => {
      const old = client.listEnvironments(clerk("account-a"), (rows) => oldRows.push(rows));
      await started.promise;
      await client.listEnvironments(clerk("account-a"), (rows) => newRows.push(rows));
      pending.resolve(
        reply({
          environmentId: "desk-1",
          endpoint,
          status: "online",
          checkedAt: environment.linkedAt,
        }),
      );
      await NodeAssert.rejects(old, /已刷新/);
      NodeAssert.deepEqual(
        oldRows.map((rows) => rows[0]?.availability),
        ["checking"],
      );
      NodeAssert.deepEqual(newRows, [[]]);
    },
  );
});

NodeTest.test("suppresses pre-existing discovery results after deregistration", async () => {
  const client = makeClient();
  const token = clerk("account-a");
  const started = Promise.withResolvers();
  const pending = Promise.withResolvers();
  const snapshots = [];
  await requests.run(
    (target) => {
      if (target === `${relay}/v1/client/environment-links/desk-1`) return reply({ ok: false });
      NodeAssert.equal(target, `${relay}/v1/environments`);
      started.resolve();
      return pending.promise;
    },
    async () => {
      const old = client.listEnvironments(token, (rows) => snapshots.push(rows));
      await started.promise;
      try {
        await client.deregisterEnvironment(token, "desk-1");
      } finally {
        pending.resolve(reply({ environments: [] }));
        await NodeAssert.rejects(old, /已刷新/);
      }
      NodeAssert.deepEqual(snapshots, []);
    },
  );
});

NodeTest.test("rejects a delayed successful deregistration after the account changes", async () => {
  const client = makeClient();
  const first = clerk("account-a");
  const second = clerk("account-b");
  const started = Promise.withResolvers();
  const pending = Promise.withResolvers();
  await requests.run(
    (target, options) => {
      if (target === `${relay}/v1/client/environment-links/desk-1`) {
        NodeAssert.equal(options.header.authorization, `Bearer ${first}`);
        started.resolve();
        return pending.promise;
      }
      NodeAssert.equal(target, `${relay}/v1/environments`);
      NodeAssert.equal(options.header.authorization, `Bearer ${second}`);
      return reply({ environments: [] });
    },
    async () => {
      const old = client.deregisterEnvironment(first, "desk-1");
      await started.promise;
      NodeAssert.deepEqual(await client.listEnvironments(second), []);
      pending.resolve(reply({ ok: true }));
      await NodeAssert.rejects(old, /账号/);
    },
  );
});

NodeTest.test(
  "discards shared tunnel grants started before a server was deregistered",
  async () => {
    const client = makeClient();
    const token = clerk("account-a");
    const started = Promise.withResolvers();
    const oldGrant = Promise.withResolvers();
    let bootstraps = 0;
    await requests.run(
      (target, options) => {
        switch (target) {
          case `${relay}/v1/client/dpop-token`:
            return reply(scoped("environment:connect"));
          case `${relay}/v1/environments/desk-1/connect`:
            return reply({
              environmentId: "desk-1",
              endpoint,
              credential: `bootstrap-${++bootstraps}`,
              expiresAt: environment.linkedAt,
            });
          case `${relay}/v1/client/environment-links/desk-1`:
            return reply({ ok: true });
          case `${tunnel}/.well-known/t3/environment`:
            return reply({ environmentId: "desk-1", label: "Desk" });
          case `${tunnel}/oauth/token`:
            if (new URLSearchParams(options.extraData).get("subject_token") === "bootstrap-1") {
              started.resolve();
              return oldGrant.promise;
            }
            return reply(scoped("orchestration:read", "relinked-grant"));
          case `${tunnel}/api/orchestration/shell`:
            NodeAssert.equal(options.header.authorization, "DPoP relinked-grant");
            return reply({ projects: [] });
          default:
            NodeAssert.fail(`unexpected target: ${target}`);
        }
      },
      async () => {
        const first = client.connectEnvironment(token, "desk-1");
        const second = client.connectEnvironment(token, "desk-1");
        await started.promise;
        await client.deregisterEnvironment(token, "desk-1");
        const relinked = await client.connectEnvironment(token, "desk-1");
        oldGrant.resolve(reply(scoped("orchestration:read", "revoked-grant")));
        await Promise.all([
          NodeAssert.rejects(first, /登记已注销/),
          NodeAssert.rejects(second, /登记已注销/),
        ]);
        NodeAssert.deepEqual(await relinked.request("/api/orchestration/shell"), { projects: [] });
      },
    );
    NodeAssert.equal(bootstraps, 2);
  },
);

NodeTest.test(
  "ignores a delayed discovery result after changing account or signing out",
  async () => {
    const first = clerk("account-a");
    const second = clerk("account-b");
    for (const change of ["account", "sign-out"]) {
      const client = makeClient();
      const started = Promise.withResolvers();
      const delayed = Promise.withResolvers();
      await requests.run(
        (_target, options) => {
          if (options.header.authorization === `Bearer ${first}`) {
            started.resolve();
            return delayed.promise;
          }
          NodeAssert.equal(options.header.authorization, `Bearer ${second}`);
          return reply({ environments: [] });
        },
        async () => {
          const oldRows = [];
          const old = client.listEnvironments(first, (rows) => oldRows.push(rows));
          await started.promise;
          if (change === "account") NodeAssert.deepEqual(await client.listEnvironments(second), []);
          else client.clear();
          delayed.resolve(reply({ environments: [environment] }));
          await NodeAssert.rejects(old, /账号/);
          NodeAssert.deepEqual(oldRows, []);
        },
      );
    }
  },
);

NodeTest.test("rejects expanded relay scopes before sending the bootstrap request", async () => {
  await requests.run(
    (target) => {
      NodeAssert.equal(target, `${relay}/v1/client/dpop-token`);
      return reply(scoped("environment:connect mobile:registration"));
    },
    async () =>
      NodeAssert.rejects(makeClient().connectEnvironment(clerk("account-a"), "desk-1"), /权限范围/),
  );
});

NodeTest.test(
  "refreshes a rejected relay token once and invalidates the replacement if it is rejected",
  async () => {
    let exchanged = 0;
    let attempted = 0;
    const client = makeClient();
    await requests.run(
      (target, options) => {
        if (target === `${relay}/v1/client/dpop-token`) {
          exchanged += 1;
          return reply(scoped("environment:connect", `relay-access-${exchanged}`));
        }
        NodeAssert.equal(target, `${relay}/v1/environments/desk-1/connect`);
        attempted += 1;
        NodeAssert.equal(options.header.authorization, `DPoP relay-access-${attempted}`);
        return reply(
          { _tag: "RelayAuthInvalidError", code: "auth_invalid", reason: "invalid_bearer" },
          401,
        );
      },
      async () => {
        await NodeAssert.rejects(client.connectEnvironment(clerk("account-a"), "desk-1"));
        NodeAssert.equal(exchanged, 2);
        await NodeAssert.rejects(client.connectEnvironment(clerk("account-a"), "desk-1"));
      },
    );
    NodeAssert.equal(attempted, 4);
    NodeAssert.equal(exchanged, 4);
  },
);

NodeTest.test(
  "keeps relay and tunnel credentials separate through bootstrap, shell reads and a ticket-bound upgrade",
  async () => {
    const client = makeClient();
    const authToken = clerk("account-a");
    const denyStarted = Promise.withResolvers();
    const denyReply = Promise.withResolvers();
    let bootstrap = 0;
    await requests.run(
      (target, options) => {
        const authorization = options.header.authorization;
        const proof = options.header.dpop;
        switch (target) {
          case `${relay}/v1/client/dpop-token`:
            NodeAssert.equal(authorization, undefined);
            NodeAssert.equal(proof, `POST ${target} `);
            NodeAssert.equal(
              new URLSearchParams(options.extraData).get("subject_token"),
              authToken,
            );
            return reply(scoped("environment:connect"));
          case `${relay}/v1/environments/desk-1/connect`:
            NodeAssert.equal(authorization, "DPoP relay-access");
            NodeAssert.deepEqual(JSON.parse(options.extraData), {
              deviceId: "installation-id",
              clientKeyThumbprint: "key-thumbprint",
            });
            bootstrap += 1;
            return reply({
              environmentId: "desk-1",
              endpoint,
              credential: `bootstrap-${bootstrap}`,
              expiresAt: "2026-11-24T00:05:00Z",
            });
          case `${tunnel}/.well-known/t3/environment`:
            NodeAssert.equal(authorization, undefined);
            return reply({
              environmentId: "desk-1",
              label: "Desk",
              orchestrationProtocolVersion: 2,
            });
          case `${tunnel}/oauth/token`: {
            NodeAssert.equal(authorization, undefined);
            NodeAssert.equal(proof, `POST ${target} `);
            const form = new URLSearchParams(options.extraData);
            NodeAssert.equal(form.get("subject_token"), `bootstrap-${bootstrap}`);
            NodeAssert.equal(
              form.get("subject_token_type"),
              "urn:t3:params:oauth:token-type:environment-bootstrap",
            );
            if (bootstrap === 1) {
              return reply(
                {
                  _tag: "EnvironmentConnectApprovalPendingError",
                  code: "connect_approval_pending",
                  traceId: "approval-trace",
                },
                403,
              );
            }
            if (bootstrap === 2) {
              return reply(
                {
                  _tag: "EnvironmentAuthInvalidError",
                  code: "auth_invalid",
                  reason: "invalid_credential",
                  traceId: "refused-trace",
                },
                401,
              );
            }
            return reply(scoped("orchestration:read orchestration:operate", "tunnel-access"));
          }
          case `${tunnel}/api/orchestration/shell`:
            NodeAssert.equal(authorization, "DPoP tunnel-access");
            NodeAssert.equal(proof, `GET ${target} tunnel-access`);
            NodeAssert.equal(options.readTimeout, 15_000);
            NodeAssert.equal(Object.hasOwn(options, "maxLimit"), false);
            return reply({ projects: [] });
          case `${tunnel}/api/pull-requests/diff`:
            NodeAssert.equal(proof, `POST ${target} tunnel-access`);
            NodeAssert.equal(options.readTimeout, 60_000);
            NodeAssert.equal(options.maxLimit, 64 * 1024 * 1024);
            return reply({ patch: "", truncated: false, nextCursor: null });
          case `${tunnel}/api/auth/websocket-ticket/rpc`:
            NodeAssert.equal(authorization, "DPoP tunnel-access");
            NodeAssert.equal(proof, `POST ${target} tunnel-access`);
            return reply({ ticket: "only-for-this-socket", expiresAt: "2026-11-24T00:05:00Z" });
          case `${tunnel}/api/auth/connect-devices/approve`:
            NodeAssert.equal(proof, `POST ${target} tunnel-access`);
            NodeAssert.equal(authorization, "DPoP tunnel-access");
            NodeAssert.equal(options.header["content-type"], "application/json");
            NodeAssert.deepEqual(JSON.parse(options.extraData), { pairingLinkId: "old" });
            return reply(
              {
                _tag: "EnvironmentScopeRequiredError",
                code: "insufficient_scope",
                requiredScope: "access:write",
                traceId: "restricted",
              },
              403,
            );
          case `${tunnel}/api/auth/pairing-links/revoke`:
            NodeAssert.equal(proof, `POST ${target} tunnel-access`);
            NodeAssert.deepEqual(JSON.parse(options.extraData), { id: "new" });
            denyStarted.resolve();
            return denyReply.promise;
          default:
            NodeAssert.fail(`unexpected target: ${target}`);
        }
      },
      async () => {
        await NodeAssert.rejects(
          client.connectEnvironment(authToken, "desk-1", "installation-id"),
          (error) =>
            error instanceof RelayApprovalPendingError &&
            error.environmentId === "desk-1" &&
            error.environmentLabel === "Desk" &&
            error.verificationCode === "6YLY-F3G8" &&
            error.traceId === "approval-trace",
        );
        await NodeAssert.rejects(
          client.connectEnvironment(authToken, "desk-1", "installation-id"),
          (error) =>
            error instanceof RelayApprovalUnavailableError &&
            error.environmentId === "desk-1" &&
            error.verificationCode === "6YLY-F3G8" &&
            error.traceId === "refused-trace",
        );
        const connection = await client.connectEnvironment(authToken, "desk-1", "installation-id");
        NodeAssert.equal(connection.origin, tunnel);
        NodeAssert.equal(connection.orchestrationProtocolVersion, 2);
        NodeAssert.deepEqual(await connection.request("/api/orchestration/shell"), {
          projects: [],
        });
        NodeAssert.deepEqual(
          await connection.request("/api/pull-requests/diff", "POST", '{"path":"large.ts"}', {
            readTimeout: 60_000,
            maxLimit: 64 * 1024 * 1024,
          }),
          { patch: "", truncated: false, nextCursor: null },
        );
        const address = new URL(await connection.socketAddress("2"));
        NodeAssert.equal(address.origin + address.pathname, "wss://socket.example.test/ws");
        NodeAssert.equal(address.searchParams.get("orchestrationProtocol"), "2");
        NodeAssert.equal(address.searchParams.get("wsTicket"), "only-for-this-socket");
        NodeAssert.equal(
          address.searchParams.get("dpop"),
          "GET https://socket.example.test/ws only-for-this-socket",
        );
        await NodeAssert.rejects(connection.request("//external.example.test"));
        const approvals = new DeviceApprovalClient(
          async () => approvalSnapshot,
          connection.request,
        );
        await NodeAssert.rejects(approvals.approve("old"), /权限/);
        const oldDecision = approvals.deny("new");
        await denyStarted.promise;
        client.clear();
        denyReply.resolve(reply({ revoked: true }));
        await NodeAssert.rejects(oldDecision, /账号/);
        await NodeAssert.rejects(connection.request("/api/orchestration/shell"), /账号/);
        await NodeAssert.rejects(approvals.deny("new"), /账号/);
      },
    );
  },
);

NodeTest.test(
  "recovers stale tunnel endpoints for websocket tickets without retrying writes",
  async () => {
    const movedEndpoint = {
      httpBaseUrl: "https://moved-tunnel.example.test",
      wsBaseUrl: "wss://moved-socket.example.test",
      providerKind: "t3_relay",
    };
    for (const failure of ["network", 404, 410, 503, 403]) {
      const client = makeClient();
      const token = clerk("account-a");
      let bootstraps = 0;
      let writes = 0;
      const formerTicketPaths = [];
      const response = () => {
        if (failure === "network") throw new Error("old tunnel closed");
        return reply({ error: "old tunnel response" }, failure);
      };
      await requests.run(
        (target, options) => {
          switch (target) {
            case `${relay}/v1/client/dpop-token`:
              return reply(scoped("environment:connect"));
            case `${relay}/v1/environments/desk-1/connect`:
              return reply({
                environmentId: "desk-1",
                endpoint: ++bootstraps === 1 ? endpoint : movedEndpoint,
                credential: `bootstrap-${bootstraps}`,
                expiresAt: environment.linkedAt,
              });
            case `${tunnel}/.well-known/t3/environment`:
            case `${movedEndpoint.httpBaseUrl}/.well-known/t3/environment`:
              return reply({
                environmentId: "desk-1",
                label: "Desk",
                orchestrationProtocolVersion: 2,
              });
            case `${tunnel}/oauth/token`:
            case `${movedEndpoint.httpBaseUrl}/oauth/token`:
              return reply(scoped("orchestration:read", `grant-${bootstraps}`));
            case `${tunnel}/api/auth/connect-devices/approve`:
              writes += 1;
              return response();
            case `${tunnel}/api/auth/websocket-ticket/rpc`:
            case `${tunnel}/api/auth/websocket-ticket`:
              formerTicketPaths.push(new URL(target).pathname);
              NodeAssert.equal(options.header.dpop, `POST ${target} grant-1`);
              return response();
            case `${movedEndpoint.httpBaseUrl}/api/auth/websocket-ticket/rpc`:
              NodeAssert.equal(options.header.dpop, `POST ${target} grant-2`);
              return reply({ ticket: "moved-ticket", expiresAt: environment.linkedAt });
            default:
              NodeAssert.fail(`unexpected target: ${target}`);
          }
        },
        async () => {
          const connection = await client.connectEnvironment(token, "desk-1");
          await NodeAssert.rejects(
            connection.request(
              "/api/auth/connect-devices/approve",
              "POST",
              '{"pairingLinkId":"p1"}',
            ),
          );
          NodeAssert.equal(writes, 1);
          NodeAssert.equal(bootstraps, 1);
          if (failure === 403) {
            await NodeAssert.rejects(connection.socketAddress("2"), /403/);
            NodeAssert.equal(bootstraps, 1);
          } else {
            const address = new URL(await connection.socketAddress("2"));
            NodeAssert.equal(
              address.origin + address.pathname,
              "wss://moved-socket.example.test/ws",
            );
            NodeAssert.equal(address.searchParams.get("wsTicket"), "moved-ticket");
            NodeAssert.equal(
              address.searchParams.get("dpop"),
              "GET https://moved-socket.example.test/ws moved-ticket",
            );
            NodeAssert.equal(bootstraps, 2);
          }
          NodeAssert.deepEqual(
            formerTicketPaths,
            failure === 404
              ? ["/api/auth/websocket-ticket/rpc", "/api/auth/websocket-ticket"]
              : ["/api/auth/websocket-ticket/rpc"],
          );
        },
      );
    }
  },
);

NodeTest.test(
  "renews a rejected managed session even when the session route responds 200",
  async () => {
    for (const replacementValid of [true, false]) {
      const client = makeClient();
      let bootstraps = 0;
      const probes = [];
      await requests.run(
        (target, options) => {
          switch (target) {
            case `${relay}/v1/client/dpop-token`:
              return reply(scoped("environment:connect"));
            case `${relay}/v1/environments/desk-1/connect`:
              return reply({
                environmentId: "desk-1",
                endpoint,
                credential: `bootstrap-${++bootstraps}`,
                expiresAt: environment.linkedAt,
              });
            case `${tunnel}/.well-known/t3/environment`:
              return reply({
                environmentId: "desk-1",
                label: "Desk",
                orchestrationProtocolVersion: 2,
              });
            case `${tunnel}/oauth/token`:
              return reply(scoped("orchestration:operate", `grant-${bootstraps}`));
            case `${tunnel}/api/auth/session`:
              probes.push(options.header.dpop);
              return reply(
                replacementValid && bootstraps === 2
                  ? { authenticated: true, permissions: ["orchestration:operate"] }
                  : { authenticated: false },
              );
            default:
              NodeAssert.fail(`unexpected target: ${target}`);
          }
        },
        async () => {
          const connection = await client.connectEnvironment(clerk("account-a"), "desk-1");
          NodeAssert.deepEqual(
            await connection.request("/api/auth/session"),
            replacementValid
              ? { authenticated: true, permissions: ["orchestration:operate"] }
              : { authenticated: false },
          );
          NodeAssert.equal(bootstraps, 2);
          NodeAssert.deepEqual(probes, [
            `GET ${tunnel}/api/auth/session grant-1`,
            `GET ${tunnel}/api/auth/session grant-2`,
          ]);
        },
      );
    }
  },
);

NodeTest.test(
  "refreshes a stale tunnel once for workspace and session reads without a socket",
  async () => {
    for (const path of ["/api/orchestration/shell", "/api/auth/session"]) {
      for (const replacementAvailable of [true, false]) {
        const client = makeClient();
        const movedEndpoint = {
          httpBaseUrl: "https://moved-tunnel.example.test",
          wsBaseUrl: "wss://moved-socket.example.test/ws",
          providerKind: "t3_relay",
        };
        const requestsToRead = [];
        let bootstraps = 0;
        await requests.run(
          (target, options) => {
            switch (target) {
              case `${relay}/v1/client/dpop-token`:
                return reply(scoped("environment:connect"));
              case `${relay}/v1/environments/desk-1/connect`:
                return reply({
                  environmentId: "desk-1",
                  endpoint: ++bootstraps === 1 ? endpoint : movedEndpoint,
                  credential: `bootstrap-${bootstraps}`,
                  expiresAt: environment.linkedAt,
                });
              case `${tunnel}/.well-known/t3/environment`:
              case `${movedEndpoint.httpBaseUrl}/.well-known/t3/environment`:
                return reply({
                  environmentId: "desk-1",
                  label: "Desk",
                  orchestrationProtocolVersion: 2,
                });
              case `${tunnel}/oauth/token`:
              case `${movedEndpoint.httpBaseUrl}/oauth/token`:
                return reply(scoped("orchestration:read", `grant-${bootstraps}`));
              case tunnel + path:
              case movedEndpoint.httpBaseUrl + path:
                requestsToRead.push(options.header.dpop);
                return target === movedEndpoint.httpBaseUrl + path && replacementAvailable
                  ? reply({ authenticated: true, threads: [] })
                  : reply({ error: "tunnel unavailable" }, 503);
              default:
                NodeAssert.fail(`unexpected target: ${target}`);
            }
          },
          async () => {
            const connection = await client.connectEnvironment(clerk("account-a"), "desk-1");
            if (replacementAvailable) {
              NodeAssert.deepEqual(await connection.request(path), {
                authenticated: true,
                threads: [],
              });
              NodeAssert.equal(connection.currentOrigin(), movedEndpoint.httpBaseUrl);
            } else {
              await NodeAssert.rejects(connection.request(path), /503/);
            }
            NodeAssert.equal(bootstraps, 2);
            NodeAssert.deepEqual(requestsToRead, [
              `GET ${tunnel}${path} grant-1`,
              `GET ${movedEndpoint.httpBaseUrl}${path} grant-2`,
            ]);
          },
        );
      }
    }
  },
);

const approvalSnapshot = {
  version: 1,
  type: "snapshot",
  revision: 1,
  payload: {
    pairingLinks: [
      {
        id: "new",
        createdAt: "2026-11-24T00:02:00Z",
        connectDeviceRequest: { verificationCode: "23WX-YZNX" },
      },
      { id: "ordinary-pairing-link", createdAt: "2026-11-24T00:00:00Z" },
      {
        id: "old",
        createdAt: "2026-11-24T00:01:00Z",
        connectDeviceRequest: {
          verificationCode: "CCRH-TWES",
          client: { label: "HarmonyOS test phone", deviceType: "mobile" },
        },
      },
    ],
  },
};

NodeTest.test("matches the server verification alphabet across base64url character ranges", () => {
  NodeAssert.equal(
    connectDeviceVerificationCode("Kq3vZ8sYbTn0eW1pLr5uXc7dHf9gJm2aQs4tVw6yBzE"),
    "CCRH-TWES",
  );
  NodeAssert.equal(connectDeviceVerificationCode("ABcd-_09thumbnail"), "23WX-YZNX");
});

NodeTest.test("lists waiting devices oldest first and looks up the normalized code", async () => {
  const approvals = new DeviceApprovalClient(
    async () => approvalSnapshot,
    () => NodeAssert.fail("reading approvals should use the access stream"),
  );
  const listed = await approvals.list();
  NodeAssert.deepEqual(
    listed.map((row) => row.pairingLinkId),
    ["old", "new"],
  );
  NodeAssert.equal(listed[0].deviceLabel, "HarmonyOS test phone");
  NodeAssert.equal(listed[1].verificationCode, "23WX-YZNX");
  NodeAssert.deepEqual(await approvals.lookup("  ccrh twes "), [listed[0]]);
  NodeAssert.deepEqual(await approvals.lookup("ZZZZ-ZZZZ"), []);
  const unreadable = new DeviceApprovalClient(
    async () => {
      throw new Error("access:read");
    },
    () => NodeAssert.fail("reading approvals should use the access stream"),
  );
  await NodeAssert.rejects(unreadable.list(), /access:read/);
});

NodeTest.test(
  "posts the typed decisions and distinguishes requests that were already answered",
  async () => {
    const approvals = new DeviceApprovalClient(
      () => NodeAssert.fail("a decision should target the selected request ID"),
      async (path, method, body) => {
        NodeAssert.equal(method, "POST");
        const parsed = JSON.parse(body);
        if (path === "/api/auth/connect-devices/approve") {
          NodeAssert.deepEqual(parsed, { pairingLinkId: "old" });
          return { approved: true };
        }
        NodeAssert.equal(path, "/api/auth/pairing-links/revoke");
        NodeAssert.deepEqual(parsed, { id: "new" });
        return { revoked: false };
      },
    );
    NodeAssert.equal(await approvals.approve("old"), "done");
    NodeAssert.equal(await approvals.deny("new"), "gone");
    await NodeAssert.rejects(approvals.approve(" "), /申请/);
  },
);

NodeTest.test("rejects malformed approval snapshots and mutation results", async () => {
  const approvals = new DeviceApprovalClient(
    async () => ({
      ...approvalSnapshot,
      payload: { pairingLinks: [{ connectDeviceRequest: {} }] },
    }),
    async () => ({ approved: "true" }),
  );
  await NodeAssert.rejects(approvals.list(), /申请/);
  await NodeAssert.rejects(approvals.approve("old"), /审批/);
});
