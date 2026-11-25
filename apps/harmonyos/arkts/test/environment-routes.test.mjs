import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";

NodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith("@kit.")) return { url: specifier, shortCircuit: true };
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    let source;
    if (url === "@kit.AbilityKit") source = "export const common = {};";
    if (url === "@kit.ArkTS") {
      source = `import { randomUUID } from "node:crypto";
        export const util = { generateRandomUUID: randomUUID };`;
    }
    if (url === "@kit.ArkData") {
      source = `export const relationalStore = {
        SecurityLevel: { S3: 3 },
        ConflictResolution: { ON_CONFLICT_REPLACE: 1 },
        getRdbStore: async (context) => context.database,
      };`;
    }
    if (url.endsWith(".ets"))
      source = NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(new URL(url), "utf8"));
    if (source !== undefined) return { format: "module", shortCircuit: true, source };
    return nextLoad(url, context);
  },
});

const { EnvironmentStore } = await import("../entry/src/main/ets/client/EnvironmentStore.ets");

const lan = {
  environmentId: "desk",
  label: "Dev machine",
  origin: "http://10.0.0.1:3773",
  token: "lan-token",
};
const vpn = {
  ...lan,
  label: "Desk",
  origin: "https://desk.example.test",
  token: "vpn-token",
};
const other = { ...lan, environmentId: "other" };
const managedA = {
  environmentId: "desk",
  label: "Desk",
  origin: "https://relay-a.example.test",
  accountId: "account-a",
};
const managedB = { ...managedA, accountId: "account-b", origin: "https://relay-b.example.test" };
const lanKey = "direct:desk";
const otherKey = "direct:other";
const managedAKey = 'managed:["account-a","desk"]';
const managedBKey = 'managed:["account-b","desk"]';

function storage(initial) {
  let document = initial === undefined ? undefined : JSON.stringify(initial);
  const database = {
    async executeSql() {},
    async querySql() {
      const snapshot = document;
      return { goToFirstRow: () => snapshot !== undefined, getString: () => snapshot, close() {} };
    },
    async insert(_table, row) {
      document = row.document;
    },
  };
  return () => new EnvironmentStore({ database });
}

NodeTest.test(
  "keeps a legacy route and stores independent credentials for another paired origin",
  async () => {
    const open = storage(lan);
    const first = open();
    NodeAssert.deepEqual(
      (await first.list()).map((route) => route.key),
      [lanKey],
    );
    const added = await first.savePairedDirect(vpn, false);
    const reopened = open();
    const routes = await reopened.list();
    NodeAssert.equal(routes[0].key, lanKey);
    NodeAssert.equal(routes[1].origin, vpn.origin);
    NodeAssert.ok(added.routeId);
    NodeAssert.notEqual(routes[1].key, lanKey);
    NodeAssert.equal((await reopened.active()).token, lan.token);
    NodeAssert.equal((await reopened.get(routes[1].key)).token, vpn.token);
    NodeAssert.equal("token" in routes[1], false);

    const repaired = await reopened.savePairedDirect({ ...vpn, token: "new-vpn-token" }, false);
    NodeAssert.equal(repaired.routeId, added.routeId);
    NodeAssert.deepEqual(
      (await open().list()).map((route) => route.key),
      [lanKey, routes[1].key],
    );
    NodeAssert.equal((await open().get(routes[1].key)).token, "new-vpn-token");
    NodeAssert.equal((await open().get(lanKey)).token, lan.token);
  },
);

NodeTest.test(
  "persists route priority without selecting it or reordering unrelated and hidden routes",
  async () => {
    const open = storage({
      version: 2,
      activeKey: lanKey,
      sessions: [lan, other, managedA, managedB],
    });
    const store = open();
    await store.savePairedDirect(vpn, false);
    const vpnSummary = (await store.list()).find((route) => route.origin === vpn.origin);
    const vpnRoute = await store.get(vpnSummary.key);
    await store.update({ ...vpnRoute, enabled: false });
    await store.moveRoute(vpnSummary.key, -1, "account-a");

    NodeAssert.deepEqual(
      (await open().list("account-a")).map((route) => route.key),
      [lanKey, otherKey, vpnSummary.key, managedAKey],
    );
    NodeAssert.deepEqual(
      (await open().list("account-b")).map((route) => route.key),
      [lanKey, otherKey, vpnSummary.key, managedBKey],
    );
    await NodeAssert.rejects(store.moveRoute(managedBKey, -1, "account-a"), /找不到/);
    NodeAssert.equal((await store.active("account-a")).origin, lan.origin);
    await store.saveAndSelect(await store.get(managedAKey, "account-a"));
    NodeAssert.equal((await open().active("account-a")).accountId, "account-a");
    NodeAssert.equal((await open().active("account-b")).origin, lan.origin);
    NodeAssert.deepEqual(
      (await open().list("account-a")).map((route) => [route.key, route.enabled]),
      [
        [lanKey, true],
        [otherKey, true],
        [vpnSummary.key, false],
        [managedAKey, true],
      ],
    );
  },
);

NodeTest.test(
  "selecting a newly linked managed route preserves the saved direct route's priority",
  async () => {
    const store = storage(lan)();
    await store.saveAndSelect(managedA);
    NodeAssert.equal((await store.active("account-a")).accountId, "account-a");
    NodeAssert.deepEqual(
      (await store.list("account-a")).map((route) => route.key),
      [lanKey, managedAKey],
    );
  },
);

NodeTest.test(
  "route removal protects the last visible route and leaves another account's active route intact",
  async () => {
    const open = storage({ version: 2, activeKey: managedBKey, sessions: [lan, other, managedB] });
    const store = open();
    await NodeAssert.rejects(store.removeRoute(lanKey, "account-a"), /最后一条线路/);
    await NodeAssert.rejects(store.removeRoute(managedBKey, "account-a"), /找不到/);
    await store.savePairedDirect(vpn, false);
    await store.removeRoute(lanKey, "account-a");
    NodeAssert.equal((await open().active("account-b")).accountId, "account-b");
    NodeAssert.deepEqual(
      (await open().list("account-a")).map((route) => route.origin),
      [other.origin, vpn.origin],
    );
    await NodeAssert.rejects(open().get(lanKey, "account-a"), /找不到/);
  },
);
