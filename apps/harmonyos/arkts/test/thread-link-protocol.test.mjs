import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";

const source = new URL("../entry/src/main/ets/", import.meta.url);
const kits = {
  "@kit.AbilityKit":
    "export class UIAbility { context = { config: {} }; } export const Want = {}; export const ConfigurationConstant = { ColorMode: { COLOR_MODE_DARK: 0 } };",
  "@kit.ArkUI": "export const window = {};",
  "@kit.PerformanceAnalysisKit": "export const hilog = {};",
};
const loader = NodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier in kits) return { url: specifier, shortCircuit: true };
    if (specifier.startsWith(".") && context.parentURL?.startsWith(source.href)) {
      return nextResolve(`${specifier}.ets`, context);
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url in kits) return { format: "module", shortCircuit: true, source: kits[url] };
    if (!url.startsWith(source.href)) return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(new URL(url), "utf8")),
    };
  },
});
const { default: EntryAbility } = await import(
  new URL("entryability/EntryAbility.ets", source).href
);
const { parseThreadLink } = await import(new URL("client/ThreadLinkProtocol.ets", source).href);
NodeTest.after(() => loader.deregister());

function createAbility(t) {
  const storage = new Map();
  globalThis.AppStorage = { setOrCreate: (key, value) => storage.set(key, value) };
  t.after(() => delete globalThis.AppStorage);
  return { ability: new EntryAbility(), storage };
}

NodeTest.test("forwards system language and appearance to the app", (t) => {
  const { ability, storage } = createAbility(t);
  ability.context.config = { language: "zh-CN", colorMode: 0 };
  ability.onCreate({});
  NodeAssert.equal(storage.get("t3.arkts.systemLanguage"), "zh-CN");
  NodeAssert.equal(storage.get("t3.arkts.darkAppearance"), true);
  ability.onConfigurationUpdate({ language: "en-US", colorMode: 1 });
  NodeAssert.equal(storage.get("t3.arkts.systemLanguage"), "en-US");
  NodeAssert.equal(storage.get("t3.arkts.darkAppearance"), false);
});

NodeTest.test("hands scoped thread URLs to the page at cold start and while running", (t) => {
  const { ability, storage } = createAbility(t);
  const production = "t3code://threads/local/shared-thread";
  const development = "t3code-dev://threads/remote/shared-thread";
  const preview = "t3code-preview://threads/preview/shared-thread";
  ability.onCreate({ uri: production });
  NodeAssert.equal(storage.get("t3.arkts.threadLink"), production);
  ability.onNewWant({ uri: development });
  NodeAssert.equal(storage.get("t3.arkts.threadLink"), development);
  ability.onNewWant({ uri: preview });
  NodeAssert.equal(storage.get("t3.arkts.threadLink"), preview);
});

NodeTest.test("dispatches pairing and account links to their existing destinations", (t) => {
  const { ability, storage } = createAbility(t);
  const accountLink = "clerk://com.t3tools.t3code.dev.hosted-callback?state=example";
  const pairingLink = "t3code-preview://pair?url=http%3A%2F%2Fhost.invalid";
  ability.onCreate({ uri: accountLink });
  ability.onNewWant({ uri: pairingLink });
  NodeAssert.deepEqual(
    [...storage],
    [
      ["t3.arkts.accountCallback", accountLink],
      ["t3.arkts.pairingLink", pairingLink],
    ],
  );
});

NodeTest.test(
  "decodes the linked environment and thread IDs independently and exactly once",
  () => {
    NodeAssert.deepEqual(
      parseThreadLink(
        "t3code-preview://threads/remote%2Fteam/%E4%BB%BB%E5%8A%A1%252F?environmentId=other#message",
      ),
      { environmentId: "remote/team", threadId: "任务%2F" },
    );
  },
);

NodeTest.test("ignores malformed paths and refuses to replace a pending thread link", (t) => {
  const { ability, storage } = createAbility(t);
  const validLink = "t3code://threads/local/thread";
  ability.onCreate({ uri: validLink });
  NodeAssert.equal(storage.get("t3.arkts.threadLink"), validLink);
  for (const uri of [
    undefined,
    "https://app.t3.codes/threads/local/thread",
    "t3code-other://threads/local/thread",
    "t3code://settings/local/thread",
    "t3code://threads.example/local/thread",
    "t3code://user@threads/local/thread",
    "t3code://threads:443/local/thread",
    "t3code:///threads/local/thread",
    "t3code://threads/local/thread/unknown",
    "t3code://threads/local",
    "t3code://threads//thread",
    "t3code://threads/local/",
    "t3code://threads/local/%E0%A4%A",
    "t3code://threads/%GG/thread",
    "t3code://threads/local/%20",
    "t3code://threads/%E3%80%80/thread",
    "t3code://threads/local/thread%00",
    "t3code://threads/local\\other/thread",
    "t3code://threads/local/thread\n",
  ]) {
    ability.onNewWant({ uri });
    NodeAssert.equal(storage.get("t3.arkts.threadLink"), validLink, uri);
  }
  NodeAssert.deepEqual([...storage], [["t3.arkts.threadLink", validLink]]);
});
