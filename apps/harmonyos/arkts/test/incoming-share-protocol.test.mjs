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
const { mergeShareIntoDraft, parseIncomingShareWant } = await import(
  new URL("IncomingShareProtocol.ets", client).href
);
NodeTest.after(() => loader.deregister());

NodeTest.test("parses text share wants and defaults mimeType to text/plain", () => {
  const payload = parseIncomingShareWant("ohos.want.action.sendData", {
    "ability.params.text": "  Review this snippet  ",
  });

  NodeAssert.deepEqual(payload, {
    text: "Review this snippet",
    uris: [],
    mimeType: "text/plain",
  });
});

NodeTest.test("parses single and multiple stream URIs without duplicates", () => {
  const payload = parseIncomingShareWant(
    "ohos.want.action.sendMultipleData",
    {
      text: "Attached logs",
      "ability.params.stream": [
        "file://docs/a.log",
        "  ",
        "file://docs/b.log",
        "file://docs/a.log",
      ],
      "ability.params.mimeType": "text/x-log",
    },
    "file://docs/a.log",
  );

  NodeAssert.deepEqual(payload, {
    text: "Attached logs",
    uris: ["file://docs/a.log", "file://docs/b.log"],
    mimeType: "text/x-log",
  });
});

NodeTest.test("returns null for non-share actions or empty share wants", () => {
  NodeAssert.equal(
    parseIncomingShareWant("ohos.want.action.viewData", {
      "ability.params.text": "ignored",
    }),
    null,
  );
  NodeAssert.equal(
    parseIncomingShareWant("ohos.want.action.sendData", {
      "ability.params.text": "   ",
      "ability.params.stream": ["  "],
    }),
    null,
  );
  NodeAssert.equal(parseIncomingShareWant("ohos.want.action.sendData", {}), null);
});

NodeTest.test("merges shared text into existing composer draft", () => {
  NodeAssert.equal(mergeShareIntoDraft("", "  Shared text  "), "Shared text");
  NodeAssert.equal(mergeShareIntoDraft("   \n ", "Shared text"), "Shared text");
  NodeAssert.equal(mergeShareIntoDraft("Existing draft", "   "), "Existing draft");
  NodeAssert.equal(
    mergeShareIntoDraft("Existing draft\n", "  Shared text  "),
    "Existing draft\n\nShared text",
  );
  NodeAssert.equal(
    mergeShareIntoDraft("Existing draft", "Shared text"),
    "Existing draft\n\nShared text",
  );
});
