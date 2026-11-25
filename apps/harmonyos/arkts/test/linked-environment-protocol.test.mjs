import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import {
  AuthCreatePairingCredentialInput,
  AuthMcpClientAccess,
  AuthPairingCredentialResult,
  mcpClientScopes,
  PeerLinkClientPairingInput,
  PeerLinkClientPairingResult,
  PeerLinkCreateInput,
  PeerLinkRemoveInput,
  PeerLinkRemoveResult,
  PeerLinkSummary,
  PeerLinkThreadHistoryInput,
  PeerLinkThreadInput,
  PeerLinkThreadItemInput,
  WS_METHODS,
} from "@t3tools/contracts";
import * as Schema from "effect/Schema";

const client = new URL("../entry/src/main/ets/client/", import.meta.url);
const decodePeerLinkCreateInput = Schema.decodeUnknownSync(Schema.toCodecJson(PeerLinkCreateInput));
const decodePeerLinkRemoveInput = Schema.decodeUnknownSync(Schema.toCodecJson(PeerLinkRemoveInput));
const decodePeerLinkThreadInput = Schema.decodeUnknownSync(PeerLinkThreadInput);
const decodePeerLinkThreadHistoryInput = Schema.decodeUnknownSync(PeerLinkThreadHistoryInput);
const decodePeerLinkThreadItemInput = Schema.decodeUnknownSync(PeerLinkThreadItemInput);
const decodePeerLinkClientPairingInput = Schema.decodeUnknownSync(PeerLinkClientPairingInput);
const peerLinkClientPairingResultCodec = Schema.toCodecJson(PeerLinkClientPairingResult);
const decodePeerLinkClientPairingResult = Schema.decodeUnknownSync(
  peerLinkClientPairingResultCodec,
);
const encodePeerLinkClientPairingResult = Schema.encodeSync(peerLinkClientPairingResultCodec);
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

const protocol = () => import(new URL("LinkedEnvironmentProtocol.ets", client).href);
const day = 24 * 60 * 60 * 1000;
const now = Date.parse("2026-11-25T12:00:00.000Z");
const link = {
  environmentId: "workstation",
  label: "Workstation",
  urls: ["https://peer.example.test"],
  access: "full-access",
  linkedAt: "2026-11-24T12:00:00.000Z",
  expiresAt: "2026-12-02T12:00:00.000Z",
  lastReachedAt: null,
  lastError: null,
  status: "reachable",
};

NodeTest.test(
  "asks for link health only when the environment offers linked environments",
  async () => {
    const { linkedEnvironmentsRequest, supportsLinkedEnvironments } = await protocol();
    const environment = { capabilities: { peerLinks: true } };
    const settings = { linkedEnvironmentsEnabled: true };
    for (const config of [
      undefined,
      {},
      { environment },
      { settings },
      {
        environment,
        settings: { linkedEnvironmentsEnabled: false },
      },
    ]) {
      NodeAssert.equal(supportsLinkedEnvironments(config), false);
    }
    NodeAssert.equal(supportsLinkedEnvironments({ environment, settings }), true);
    NodeAssert.deepEqual(linkedEnvironmentsRequest(), {
      _tag: "Request",
      id: "1",
      tag: WS_METHODS.peerLinksList,
      payload: {},
      headers: [],
    });
  },
);

NodeTest.test("subscribes to the named peer thread and recognizes revoked access", async () => {
  const {
    linkedThreadHistoryRequest,
    linkedThreadItemRequest,
    linkedThreadReadError,
    linkedThreadRequest,
  } = await protocol();
  const request = linkedThreadRequest("workstation", "child-thread");
  NodeAssert.equal(request.tag, WS_METHODS.peerLinksSubscribeThread);
  const target = {
    environmentId: "workstation",
    threadId: "child-thread",
  };
  NodeAssert.deepEqual(decodePeerLinkThreadInput(request.payload), target);
  const history = linkedThreadHistoryRequest("workstation", "child-thread", "opaque-cursor");
  NodeAssert.equal(history.tag, WS_METHODS.peerLinksThreadHistoryPage);
  NodeAssert.deepEqual(decodePeerLinkThreadHistoryInput(history.payload), {
    ...target,
    cursor: "opaque-cursor",
  });
  const item = linkedThreadItemRequest("workstation", "child-thread", "command");
  NodeAssert.equal(item.tag, WS_METHODS.peerLinksThreadItem);
  NodeAssert.deepEqual(decodePeerLinkThreadItemInput(item.payload), {
    ...target,
    itemId: "command",
  });
  for (const [reason, accessLost] of [
    ["unreachable", false],
    ["expired", true],
    ["rejected", true],
    ["thread_not_found", true],
  ]) {
    const exit = {
      _tag: "Failure",
      cause: [{ _tag: "Fail", error: { _tag: "PeerLinkThreadReadError", reason } }],
    };
    NodeAssert.equal(linkedThreadReadError(exit).accessLost, accessLost);
  }
});

NodeTest.test("reads the peer list wire format and discards malformed rows", async () => {
  const { readLinkedEnvironments } = await protocol();
  const codec = Schema.toCodecJson(Schema.Struct({ links: Schema.Array(PeerLinkSummary) }));
  const encoded = Schema.encodeSync(codec)(Schema.decodeUnknownSync(codec)({ links: [link] }));
  const [valid] = encoded.links;
  NodeAssert.deepEqual(
    readLinkedEnvironments({
      links: [null, { ...valid, status: "unknown" }, { ...valid, expiresAt: "invalid" }, valid],
    }),
    [
      {
        environmentId: "workstation",
        label: "Workstation",
        status: "reachable",
        expiresAtMs: now + 7 * day,
        lastError: null,
      },
    ],
  );
  NodeAssert.deepEqual(readLinkedEnvironments({ links: [] }), []);
  NodeAssert.throws(() => readLinkedEnvironments({ links: {} }), /关联环境列表/);
});

NodeTest.test("uses a link-issued pairing only for the intended target before expiry", async () => {
  const { linkedClientPairingRequest, readLinkedClientPairing } = await protocol();
  const request = linkedClientPairingRequest("workstation");
  NodeAssert.equal(request.tag, WS_METHODS.peerLinksPairClient);
  NodeAssert.deepEqual(decodePeerLinkClientPairingInput(request.payload), {
    environmentId: "workstation",
  });
  const urls = ["https://peer.example.test", "http://192.168.1.99"];
  const result = decodePeerLinkClientPairingResult({
    type: "credential",
    environmentId: "workstation",
    label: "Workstation",
    urls,
    credential: "synthetic-credential",
    expiresAt: new Date(now + 1).toISOString(),
  });
  const wire = encodePeerLinkClientPairingResult(result);
  NodeAssert.deepEqual(readLinkedClientPairing(wire, "workstation", now), {
    urls,
    credential: "synthetic-credential",
  });
  NodeAssert.equal(readLinkedClientPairing(wire, "workstation", now + 1).credential, undefined);
  NodeAssert.throws(
    () => readLinkedClientPairing(wire, "different-workstation", now),
    /所选关联环境/,
  );
});

NodeTest.test("prioritizes expiry, saved failures, and the five-day warning", async () => {
  const { linkedEnvironmentHealth, readLinkedEnvironments } = await protocol();
  const [base] = readLinkedEnvironments({ links: [link] });
  for (const [changes, expected] of [
    [{}, { kind: "reachable" }],
    [{ expiresAtMs: now + 5 * day + 1 }, { kind: "reachable" }],
    [{ expiresAtMs: now + 5 * day }, { kind: "reachable", expiresInDays: 5 }],
    [{ expiresAtMs: now + 1 }, { kind: "reachable", expiresInDays: 1 }],
    [{ status: "unreachable" }, { kind: "unreachable" }],
    [
      { status: "unreachable", lastError: "Connection refused" },
      {
        kind: "unreachable",
        detail: "Connection refused",
      },
    ],
    [
      { lastError: "Access revoked", expiresAtMs: now + day },
      {
        kind: "failing",
        detail: "Access revoked",
      },
    ],
    [
      { expiresAtMs: now, status: "unreachable", lastError: "Connection refused" },
      { kind: "expired" },
    ],
    [{ status: "expired" }, { kind: "expired" }],
  ]) {
    NodeAssert.deepEqual(linkedEnvironmentHealth({ ...base, ...changes }, now), expected);
  }
});

NodeTest.test(
  "mints a peer-only code with the selected access and the scopes it can delegate",
  async () => {
    const {
      canMintLinkedEnvironmentPairing,
      linkedEnvironmentPairingBody,
      readLinkedEnvironmentPairingCode,
      supportsLinkedEnvironmentPairing,
    } = await protocol();
    NodeAssert.equal(
      supportsLinkedEnvironmentPairing({ environment: { capabilities: {} } }),
      false,
    );
    NodeAssert.equal(
      supportsLinkedEnvironmentPairing({
        environment: { capabilities: { peerLinkPairingCodes: true } },
      }),
      true,
    );
    NodeAssert.equal(
      canMintLinkedEnvironmentPairing("access:write orchestration:read", "read-only"),
      false,
    );
    const decodeInput = Schema.decodeUnknownSync(
      Schema.toCodecJson(AuthCreatePairingCredentialInput),
    );
    const decodeResult = Schema.decodeUnknownSync(Schema.toCodecJson(AuthPairingCredentialResult));
    for (const access of AuthMcpClientAccess.literals) {
      const delegatedScopes = mcpClientScopes(access);
      NodeAssert.equal(canMintLinkedEnvironmentPairing(delegatedScopes, access), false);
      NodeAssert.equal(
        canMintLinkedEnvironmentPairing(["access:write", ...delegatedScopes], access),
        true,
      );
      for (const missing of delegatedScopes) {
        NodeAssert.equal(
          canMintLinkedEnvironmentPairing(
            ["access:write", ...delegatedScopes.filter((scope) => scope !== missing)],
            access,
          ),
          false,
        );
      }
      NodeAssert.deepEqual(decodeInput(JSON.parse(linkedEnvironmentPairingBody(access))), {
        label: "T3 Code link",
        purpose: "peer-link",
        access,
      });
      const code = {
        id: "credential-1",
        credential: "ABC",
        expiresAt: "2026-11-25T12:02:00.000Z",
        purpose: "peer-link",
        access,
      };
      decodeResult(code);
      NodeAssert.equal(readLinkedEnvironmentPairingCode(code, access), "ABC");
      NodeAssert.throws(() =>
        readLinkedEnvironmentPairingCode({ ...code, purpose: undefined }, access),
      );
      NodeAssert.throws(() =>
        readLinkedEnvironmentPairingCode({ ...code, access: undefined }, access),
      );
      NodeAssert.throws(() =>
        readLinkedEnvironmentPairingCode({ ...code, credential: " " }, access),
      );
    }
  },
);

NodeTest.test(
  "linking pins the selected peer identity and sends its one-use credential to the source",
  async () => {
    const { linkEnvironmentRequest } = await protocol();
    const request = linkEnvironmentRequest(
      {
        key: "direct:workstation",
        environmentId: "workstation",
        label: "Workstation",
        origin: "https://peer.example.test",
      },
      "ABC",
      "approval-required",
    );
    NodeAssert.deepEqual(request, {
      _tag: "Request",
      id: "1",
      tag: WS_METHODS.peerLinksLink,
      payload: {
        url: "https://peer.example.test",
        expectedEnvironmentId: "workstation",
        expectedLabel: "Workstation",
        pairingCode: "ABC",
        access: "approval-required",
      },
      headers: [],
    });
    decodePeerLinkCreateInput(request.payload);
  },
);

NodeTest.test(
  "unlinking reads whether the peer session ended, including the older server response",
  async () => {
    const { readUnlinkEnvironmentResult, unlinkEnvironmentRequest } = await protocol();
    const request = unlinkEnvironmentRequest("workstation");
    NodeAssert.deepEqual(request, {
      _tag: "Request",
      id: "1",
      tag: WS_METHODS.peerLinksUnlink,
      payload: { environmentId: "workstation" },
      headers: [],
    });
    decodePeerLinkRemoveInput(request.payload);
    const codec = Schema.toCodecJson(PeerLinkRemoveResult);
    for (const payload of [
      { removed: true, endedThere: true },
      { removed: true },
      { removed: false, endedThere: false },
    ]) {
      NodeAssert.deepEqual(
        readUnlinkEnvironmentResult(payload),
        Schema.decodeUnknownSync(codec)(payload),
      );
    }
    NodeAssert.throws(() => readUnlinkEnvironmentResult({ removed: "true" }));
    NodeAssert.throws(() => readUnlinkEnvironmentResult({ removed: true, endedThere: "true" }));
  },
);
