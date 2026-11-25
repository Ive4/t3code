import * as NodeAssert from "node:assert/strict";
import * as NodeAsyncHooks from "node:async_hooks";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";

const socketContext = new NodeAsyncHooks.AsyncLocalStorage();
globalThis.connectDeviceApprovalTestSocket = () => socketContext.getStore().makeSocket();

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
        "@kit.ArkTS": "export const util = {}, url = {};",
        "@kit.NetworkKit":
          "export const webSocket = { createWebSocket: globalThis.connectDeviceApprovalTestSocket };",
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

const { ConnectDeviceApprovals } =
  await import("../entry/src/main/ets/client/ConnectDeviceApprovals.ets");

function waiting(id, minute = "00") {
  return {
    id,
    subject: "device",
    scopes: [],
    createdAt: `2026-11-24T00:${minute}:00Z`,
    expiresAt: "2099-01-01T00:00:00Z",
    connectDeviceRequest: {
      verificationCode: "23WX-YZNX",
      client: { browser: "Firefox", os: "HarmonyOS", deviceType: "mobile" },
    },
  };
}

function snapshot(links, revision = 1) {
  return {
    type: "snapshot",
    version: 1,
    revision,
    payload: { pairingLinks: links, clientSessions: [], connectDevices: [] },
  };
}

function configSnapshot(required) {
  return {
    version: 1,
    type: "snapshot",
    config: { settings: { requireConnectDeviceApproval: required } },
  };
}

function configUpdate(required) {
  return {
    version: 1,
    type: "settingsUpdated",
    payload: { settings: { requireConnectDeviceApproval: required } },
  };
}

function fixture(initialApprovalRequired) {
  const addresses = [];
  const prompts = [];
  const actions = [];
  const subscriptions = new Map();
  const coordinator = new ConnectDeviceApprovals((prompt) => prompts.push(prompt));
  return {
    addresses,
    prompts,
    actions,
    coordinator,
    current: () => prompts.at(-1),
    target(key) {
      let ticket = 0;
      return {
        key,
        label: `Host ${key}`,
        async socketAddress() {
          return `wss://${key}.example.test/ws?wsTicket=${++ticket}`;
        },
        async approve(id) {
          actions.push([key, "approve", id]);
          return "done";
        },
        async deny(id) {
          actions.push([key, "deny", id]);
          return "done";
        },
      };
    },
    nextSubscription(key) {
      return this.nextRequest(key, "subscribeAuthAccess");
    },
    nextRequest(key, tag = "") {
      const signal = Promise.withResolvers();
      subscriptions.set(`${key}:${tag}`, signal);
      return signal.promise;
    },
    makeSocket() {
      const handlers = new Map();
      const messages = [];
      let address;
      const socket = {
        messages,
        on(event, handler) {
          handlers.set(event, handler);
        },
        off(event) {
          handlers.delete(event);
        },
        async connect(nextAddress) {
          address = new URL(nextAddress);
          addresses.push(nextAddress);
          handlers.get("open")?.();
          return true;
        },
        async send(raw) {
          const frame = JSON.parse(raw);
          messages.push(frame);
          if (frame._tag === "Request") {
            const host = address.hostname.split(".")[0];
            for (const key of [`${host}:`, `${host}:${frame.tag}`]) {
              const signal = subscriptions.get(key);
              subscriptions.delete(key);
              signal?.resolve(socket);
            }
            if (frame.tag === "subscribeServerConfig") {
              socket.chunkFor(frame.id, configSnapshot(initialApprovalRequired));
            }
          }
          return true;
        },
        async close() {},
        chunk(...values) {
          this.chunkFor(
            messages.findLast((frame) => frame.tag === "subscribeAuthAccess").id,
            ...values,
          );
        },
        config(...values) {
          this.chunkFor(
            messages.find((frame) => frame.tag === "subscribeServerConfig").id,
            ...values,
          );
        },
        chunkFor(requestId, ...values) {
          handlers.get("message")?.(null, JSON.stringify({ _tag: "Chunk", requestId, values }));
        },
        disconnect() {
          handlers.get("close")?.();
        },
      };
      return socket;
    },
  };
}

async function verify(run, initialApprovalRequired = true) {
  const app = fixture(initialApprovalRequired);
  try {
    await socketContext.run(app, () => run(app));
  } finally {
    app.coordinator.setTargets([]);
  }
}

NodeTest.test(
  "serializes prompts and binds identical request IDs to their original hosts",
  async () => {
    await verify(async (app) => {
      const alpha = app.nextSubscription("alpha");
      const bravo = app.nextSubscription("bravo");
      app.coordinator.setTargets([app.target("alpha"), app.target("bravo")]);
      const first = await alpha;
      first.chunk(snapshot([waiting("newer", "01"), waiting("same-id")]));
      (await bravo).chunk(snapshot([waiting("same-id")]));
      const access = first.messages.find((frame) => frame.tag === "subscribeAuthAccess");
      NodeAssert.ok(
        first.messages.some((frame) => frame._tag === "Ack" && frame.requestId === access.id),
      );
      const initial = app.current();
      NodeAssert.deepEqual(initial, {
        environmentKey: "alpha",
        environmentLabel: "Host alpha",
        pairingLinkId: "same-id",
        verificationCode: "23WX-YZNX",
        deviceLabel: "Firefox · HarmonyOS",
      });
      NodeAssert.equal(app.prompts.length, 1);
      NodeAssert.equal(await app.coordinator.respond(initial, true), "done");
      NodeAssert.equal(app.current().pairingLinkId, "newer");
      await app.coordinator.respond(app.current(), false);
      NodeAssert.equal(app.current().environmentKey, "bravo");
      await app.coordinator.respond(app.current(), true);
      NodeAssert.equal(app.current(), undefined);
      NodeAssert.deepEqual(app.actions, [
        ["alpha", "approve", "same-id"],
        ["alpha", "deny", "newer"],
        ["bravo", "approve", "same-id"],
      ]);
    });
  },
);

NodeTest.test(
  "follows live approval settings and replaces requests when approval is re-enabled",
  async (test) => {
    test.mock.timers.enable({ apis: ["setTimeout", "setInterval"] });
    await verify(async (app) => {
      const authorization = Promise.withResolvers();
      const target = app.target("alpha");
      const approve = target.approve;
      target.approve = async (id, isCurrent) => {
        await authorization.promise;
        return isCurrent() ? approve(id) : "gone";
      };
      const first = app.nextRequest("alpha");
      app.coordinator.setTargets([target]);
      const socket = await first;
      NodeAssert.deepEqual(
        socket.messages.flatMap((frame) => (frame.tag ? [frame.tag] : [])),
        ["subscribeServerConfig"],
      );
      const config = socket.messages[0];
      NodeAssert.ok(
        socket.messages.some((frame) => frame._tag === "Ack" && frame.requestId === config.id),
      );
      NodeAssert.equal(app.current(), undefined);
      test.mock.timers.tick(16000);
      NodeAssert.equal(app.addresses.length, 1);

      socket.config(configUpdate(true));
      socket.chunk(snapshot([waiting("one")]));
      const retired = app.current();
      NodeAssert.equal(retired.pairingLinkId, "one");
      const oldAccess = socket.messages.find((frame) => frame.tag === "subscribeAuthAccess");
      const answering = app.coordinator.respond(retired, true);

      socket.config(configUpdate(false));
      NodeAssert.equal(app.current(), undefined);
      NodeAssert.ok(
        socket.messages.some(
          (frame) => frame._tag === "Interrupt" && frame.requestId === oldAccess.id,
        ),
      );
      authorization.resolve();
      NodeAssert.equal(await answering, "stale");
      NodeAssert.deepEqual(app.actions, []);

      socket.config(configUpdate(true), configSnapshot(true));
      const subscriptions = socket.messages.filter((frame) => frame.tag === "subscribeAuthAccess");
      NodeAssert.equal(subscriptions.length, 2);
      NodeAssert.notEqual(subscriptions[1].id, oldAccess.id);
      socket.chunkFor(oldAccess.id, snapshot([waiting("old")], 2));
      NodeAssert.equal(app.current(), undefined);
      socket.chunk(snapshot([waiting("one")]));
      NodeAssert.equal(app.current().pairingLinkId, "one");
      NodeAssert.notEqual(app.current(), retired);
      NodeAssert.equal(await app.coordinator.respond(app.current(), false), "done");
      NodeAssert.deepEqual(app.actions, [["alpha", "deny", "one"]]);
      NodeAssert.equal(app.addresses.length, 1);
    }, false);
  },
);

NodeTest.test(
  "applies live approval changes and makes an externally removed prompt stale",
  async () => {
    await verify(async (app) => {
      const opened = app.nextSubscription("alpha");
      app.coordinator.setTargets([app.target("alpha")]);
      const socket = await opened;
      socket.chunk(snapshot([]));
      socket.chunk({
        version: 1,
        revision: 2,
        type: "pairingLinkUpserted",
        payload: waiting("live"),
      });
      const retired = app.current();
      NodeAssert.equal(retired.pairingLinkId, "live");
      socket.chunk(
        { version: 1, revision: 3, type: "pairingLinkRemoved", payload: { id: "live" } },
        { version: 1, revision: 4, type: "pairingLinkUpserted", payload: waiting("next") },
      );
      NodeAssert.equal(app.current().pairingLinkId, "next");
      NodeAssert.equal(await app.coordinator.respond(retired, true), "stale");
      NodeAssert.deepEqual(app.actions, []);
    });
  },
);

NodeTest.test(
  "keeps an open confirmation valid when the same device supplies its name",
  async () => {
    await verify(async (app) => {
      const opened = app.nextSubscription("alpha");
      app.coordinator.setTargets([app.target("alpha")]);
      const socket = await opened;
      const request = waiting("one");
      socket.chunk(snapshot([request]));
      const prompt = app.current();
      request.connectDeviceRequest.client.label = "My phone";
      socket.chunk({ version: 1, revision: 2, type: "pairingLinkUpserted", payload: request });
      NodeAssert.equal(app.current(), prompt);
      NodeAssert.equal(await app.coordinator.respond(prompt, true), "done");
      NodeAssert.deepEqual(app.actions, [["alpha", "approve", "one"]]);
    });
  },
);

NodeTest.test("renews a disconnected stream without offering duplicate approvals", async (test) => {
  test.mock.timers.enable({ apis: ["setTimeout", "setInterval"] });
  await verify(async (app) => {
    const first = app.nextSubscription("alpha");
    app.coordinator.setTargets([app.target("alpha")]);
    const original = await first;
    original.chunk(snapshot([waiting("one")]));
    const prompt = app.current();
    original.disconnect();
    await NodeAssert.rejects(app.coordinator.respond(prompt, true));
    NodeAssert.deepEqual(app.actions, []);

    const second = app.nextSubscription("alpha");
    test.mock.timers.tick(1000);
    const recovered = await second;
    recovered.chunk(snapshot([waiting("one")]));
    NodeAssert.deepEqual(app.addresses, [
      "wss://alpha.example.test/ws?wsTicket=1",
      "wss://alpha.example.test/ws?wsTicket=2",
    ]);
    NodeAssert.equal(app.current(), prompt);
    NodeAssert.equal(await app.coordinator.respond(prompt, true), "done");
    recovered.chunk(snapshot([waiting("one")], 2));
    NodeAssert.deepEqual(app.prompts, [prompt, undefined]);
  });
});

NodeTest.test(
  "invalidates an in-flight approval before dispatch after its target is replaced",
  async () => {
    await verify(async (app) => {
      const pendingAuthorization = Promise.withResolvers();
      const target = app.target("alpha");
      const approve = target.approve;
      target.approve = async (id, isCurrent) => {
        await pendingAuthorization.promise;
        if (!isCurrent()) throw new Error("Approval target changed during authorization");
        return approve(id);
      };
      const first = app.nextSubscription("alpha");
      app.coordinator.setTargets([target]);
      (await first).chunk(snapshot([waiting("one")]));
      const retired = app.current();
      const answering = app.coordinator.respond(retired, true);

      const second = app.nextSubscription("alpha");
      app.coordinator.setTargets([app.target("alpha")]);
      (await second).chunk(snapshot([waiting("one")]));
      pendingAuthorization.resolve();
      NodeAssert.equal(await answering, "stale");
      NodeAssert.deepEqual(app.actions, []);
      NodeAssert.notEqual(app.current(), retired);
      NodeAssert.equal(await app.coordinator.respond(app.current(), false), "done");
      NodeAssert.deepEqual(app.actions, [["alpha", "deny", "one"]]);
    });
  },
);

NodeTest.test(
  "can recover after consecutive failures and stops when the target is removed",
  async (test) => {
    test.mock.timers.enable({ apis: ["setTimeout", "setInterval"] });
    await verify(async (app) => {
      const first = app.nextSubscription("alpha");
      app.coordinator.setTargets([app.target("alpha")]);
      let socket = await first;
      socket.chunk(snapshot([waiting("one")]));
      for (const delay of [1000, 2000, 4000]) {
        const next = app.nextSubscription("alpha");
        socket.disconnect();
        test.mock.timers.tick(delay);
        socket = await next;
      }
      const restored = app.nextSubscription("alpha");
      socket.disconnect();
      test.mock.timers.tick(30000);
      await Promise.resolve();
      NodeAssert.equal(app.addresses.length, 5);
      (await restored).chunk(snapshot([waiting("late")]));
      NodeAssert.equal(app.current()?.pairingLinkId, "late");
      app.coordinator.setTargets([]);
      test.mock.timers.tick(60000);
      NodeAssert.equal(app.addresses.length, 5);
      NodeAssert.equal(app.current(), undefined);
    });
  },
);

NodeTest.test(
  "defers a dismissed prompt without answering and gives it a fresh identity on reconnect",
  async (test) => {
    test.mock.timers.enable({ apis: ["setTimeout", "setInterval"] });
    await verify(async (app) => {
      const first = app.nextSubscription("alpha");
      app.coordinator.setTargets([app.target("alpha")]);
      const original = await first;
      original.chunk(snapshot([waiting("dismissed"), waiting("next", "01")]));
      const retired = app.current();
      app.coordinator.defer(retired);
      NodeAssert.equal(app.current().pairingLinkId, "next");
      await app.coordinator.respond(app.current(), false);

      original.chunk(snapshot([waiting("dismissed"), waiting("next", "01")], 2));
      NodeAssert.equal(app.current(), undefined);
      NodeAssert.deepEqual(app.actions, [["alpha", "deny", "next"]]);

      const second = app.nextSubscription("alpha");
      original.disconnect();
      test.mock.timers.tick(1000);
      (await second).chunk(snapshot([waiting("dismissed")]));
      NodeAssert.equal(app.current().pairingLinkId, "dismissed");
      NodeAssert.notEqual(app.current(), retired);
      NodeAssert.equal(await app.coordinator.respond(retired, true), "stale");
    });
  },
);

NodeTest.test(
  "can retry an unsuccessful response without dispatching duplicate decisions",
  async () => {
    await verify(async (app) => {
      const firstResponse = Promise.withResolvers();
      const target = app.target("alpha");
      const approve = target.approve;
      target.approve = () => firstResponse.promise;
      const opened = app.nextSubscription("alpha");
      app.coordinator.setTargets([target]);
      (await opened).chunk(snapshot([waiting("one")]));
      const prompt = app.current();

      const first = app.coordinator.respond(prompt, true);
      NodeAssert.equal(await app.coordinator.respond(prompt, false), "stale");
      firstResponse.reject(new Error("transport not available"));
      await NodeAssert.rejects(first, /transport not available/);
      NodeAssert.equal(app.current(), prompt);

      target.approve = approve;
      NodeAssert.equal(await app.coordinator.respond(prompt, true), "done");
      NodeAssert.deepEqual(app.actions, [["alpha", "approve", "one"]]);
    });
  },
);
