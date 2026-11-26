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
NodeTest.after(() => loader.deregister());

const protocolSource = NodeFS.readFileSync(new URL("PushNotificationProtocol.ets", client), "utf8");
const { buildPushRegistrationBody, formatOngoingAgentSummary, parseNotificationLaunchLink } =
  await import(new URL("PushNotificationProtocol.ets", client).href);

NodeTest.test("stays pure ArkTS without @kit.* imports", () => {
  NodeAssert.equal(/@kit\./.test(protocolSource), false);
});

NodeTest.test("extracts notification launch links from Want parameters and deep-link URIs", () => {
  NodeAssert.deepEqual(
    parseNotificationLaunchLink({
      environmentId: " env-1 ",
      threadId: " thread-42 ",
    }),
    { environmentId: "env-1", threadId: "thread-42" },
  );

  NodeAssert.deepEqual(
    parseNotificationLaunchLink({
      uri: "t3code://threads/remote%2Fteam/thread-99",
    }),
    { environmentId: "remote/team", threadId: "thread-99" },
  );

  NodeAssert.deepEqual(
    parseNotificationLaunchLink({
      threadLink: "t3code-preview://threads/env-a/thread-b?source=push",
    }),
    { environmentId: "env-a", threadId: "thread-b" },
  );

  NodeAssert.deepEqual(
    parseNotificationLaunchLink({
      link: "t3code-dev://threads/env-dev/thread-dev",
    }),
    { environmentId: "env-dev", threadId: "thread-dev" },
  );

  NodeAssert.deepEqual(
    parseNotificationLaunchLink({
      url: "t3code://threads/env-url/thread-url",
    }),
    { environmentId: "env-url", threadId: "thread-url" },
  );
});

NodeTest.test("returns null for missing or malformed notification launch parameters", () => {
  for (const params of [
    null,
    undefined,
    [],
    {},
    { environmentId: "env-1" },
    { threadId: "thread-1" },
    { environmentId: "   ", threadId: "thread-1" },
    { environmentId: "env-1", threadId: "" },
    { environmentId: 123, threadId: "thread-1" },
    { environmentId: "env-1\n", threadId: "thread-1" },
    { environmentId: "env-1", threadId: "thread\u0000" },
    { uri: "https://app.t3.codes/threads/env-1/thread-1" },
    { uri: "t3code://settings/env-1/thread-1" },
  ]) {
    NodeAssert.equal(parseNotificationLaunchLink(params), null);
  }
});

NodeTest.test("serializes and normalizes push registration payloads", () => {
  const json = buildPushRegistrationBody({
    pushToken: "  push-token-123  ",
    huaweiAccountOpenId: "  open-id-456  ",
    deviceName: "  Mate 70 Pro  ",
    environmentIds: [" env-1 ", "env-2", "env-1"],
    liveActivityEnabled: true,
  });

  NodeAssert.deepEqual(JSON.parse(json), {
    pushToken: "push-token-123",
    huaweiAccountOpenId: "open-id-456",
    deviceName: "Mate 70 Pro",
    environmentIds: ["env-1", "env-2"],
    liveActivityEnabled: true,
  });

  const withoutOpenId = buildPushRegistrationBody({
    pushToken: "token-abc",
    huaweiAccountOpenId: "   ",
    deviceName: "Pura 70",
    environmentIds: [],
    liveActivityEnabled: false,
  });

  NodeAssert.deepEqual(JSON.parse(withoutOpenId), {
    pushToken: "token-abc",
    deviceName: "Pura 70",
    environmentIds: [],
    liveActivityEnabled: false,
  });
});

NodeTest.test("rejects invalid push registration inputs", () => {
  const base = {
    pushToken: "token-1",
    huaweiAccountOpenId: "open-1",
    deviceName: "MatePad",
    environmentIds: ["env-1"],
    liveActivityEnabled: true,
  };

  NodeAssert.throws(() => buildPushRegistrationBody(null));
  NodeAssert.throws(() => buildPushRegistrationBody({ ...base, pushToken: "   " }));
  NodeAssert.throws(() => buildPushRegistrationBody({ ...base, pushToken: "bad\ntoken" }));
  NodeAssert.throws(() => buildPushRegistrationBody({ ...base, deviceName: "" }));
  NodeAssert.throws(() => buildPushRegistrationBody({ ...base, environmentIds: "env-1" }));
  NodeAssert.throws(() => buildPushRegistrationBody({ ...base, environmentIds: ["env-1", " "] }));
  NodeAssert.throws(() =>
    buildPushRegistrationBody({ ...base, environmentIds: ["env-1", "env\u0007"] }),
  );
  NodeAssert.throws(() => buildPushRegistrationBody({ ...base, liveActivityEnabled: "yes" }));
  NodeAssert.throws(() => buildPushRegistrationBody({ ...base, huaweiAccountOpenId: 42 }));
  NodeAssert.throws(() =>
    buildPushRegistrationBody({ ...base, huaweiAccountOpenId: "bad\u0000id" }),
  );
});

NodeTest.test("formats ongoing agent summaries for single, multiple, and fallback states", () => {
  NodeAssert.equal(
    formatOngoingAgentSummary(1, "Fix auth race", "Running tests"),
    "Fix auth race · Running tests",
  );
  NodeAssert.equal(
    formatOngoingAgentSummary(3, "Fix auth race", "Editing files"),
    "3 active · Fix auth race · Editing files",
  );
  NodeAssert.equal(
    formatOngoingAgentSummary(2, "  Refactor router  ", "   "),
    "2 active · Refactor router",
  );
  NodeAssert.equal(
    formatOngoingAgentSummary(0, "", "Waiting for approval"),
    "Agent · Waiting for approval",
  );
  NodeAssert.equal(formatOngoingAgentSummary(-2, "   ", "   "), "Agent");
  NodeAssert.equal(
    formatOngoingAgentSummary(2.9, "Build release", "Compiling"),
    "2 active · Build release · Compiling",
  );
});
