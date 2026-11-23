// @effect-diagnostics globalFetch:off - The HarmonyOS HTTP layer adapts React Native's fetch.
import {
  Connection,
  ConnectionBlockedError,
  ConnectionOnboarding,
  Connectivity,
  Wakeups,
} from "@t3tools/client-runtime/connection";
import {
  ClientCapabilities,
  Persistence,
  PlatformConnectionSource,
} from "@t3tools/client-runtime/platform";
import { ManagedRelay } from "@t3tools/client-runtime/relay";
import { layerRemoteHttpClient } from "@t3tools/client-runtime/rpc";
import {
  createEnvironmentShellAtoms,
  ShellSnapshotLoader,
} from "@t3tools/client-runtime/state/shell";
import {
  BoundedThreadSnapshotLoader,
  createEnvironmentThreadStateAtoms,
} from "@t3tools/client-runtime/state/threads";
import { createEnvironmentCatalogAtoms } from "@t3tools/client-runtime/state/connections";
import { createServerEnvironmentAtoms } from "@t3tools/client-runtime/state/server";
import { createEnvironmentSessionAtoms } from "@t3tools/client-runtime/state/session";
import {
  createPullRequestEnvironmentAtoms,
  PullRequestDiffLoader,
} from "@t3tools/client-runtime/state/pull-requests";
import { createIssueEnvironmentAtoms } from "@t3tools/client-runtime/state/issues";
import { createOrchestrationEnvironmentAtoms } from "@t3tools/client-runtime/state/orchestration";
import {
  createEnvironmentRpcCommand,
  createEnvironmentRpcQueryAtomFamily,
  createRuntimeCommand,
} from "@t3tools/client-runtime/state/runtime";
import { ORCHESTRATION_V2_WS_METHODS, WS_METHODS } from "@t3tools/contracts";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Queue from "effect/Queue";
import * as Stream from "effect/Stream";
import { Atom } from "effect/reactivity";
import * as Socket from "effect/socket/Socket";
import { AppState } from "react-native";

import { connectionStorage } from "./connectionStorage";

const unavailable = new ConnectionBlockedError({
  reason: "configuration",
  detail: "This connection method is unavailable on HarmonyOS.",
});

const ignoreWrite = Effect.fn("HarmonySession.ignoreWrite")(() => Effect.void);
const noCache = Effect.fn("HarmonySession.noCache")(() => Effect.succeedNone);
const unavailableSsh = Effect.fn("HarmonySession.unavailableSsh")(() => Effect.fail(unavailable));

const nativeFetch = fetch;
const http = layerRemoteHttpClient((url, options) => {
  const body = options?.body;
  if (body instanceof Uint8Array) {
    const contentType = new Headers(options?.headers).get("content-type")?.split(";")[0];
    // RNOH sends binary request bodies as Base64 text. Preserve UTF-8 form and JSON payloads.
    if (contentType === "application/x-www-form-urlencoded" || contentType === "application/json") {
      return nativeFetch(url, {
        ...options,
        body: new TextDecoder("utf-8", { fatal: true }).decode(body),
      });
    }
  }
  return nativeFetch(url, options);
});
const signer = Layer.succeed(ManagedRelay.ManagedRelayDpopSigner, {
  thumbprint: Effect.fail(
    new ManagedRelay.ManagedRelayDpopKeyLoadError({
      keyStore: "indexed-db",
      cause: unavailable,
    }),
  ),
  createProof: Effect.fn("HarmonyDpopSigner.createProof")(({ method, url }) =>
    Effect.fail(
      new ManagedRelay.ManagedRelayDpopProofCreationError({ method, url, cause: unavailable }),
    ),
  ),
});

const platform = Layer.mergeAll(
  http,
  Socket.layerWebSocketConstructorGlobal,
  connectionStorage,
  Connectivity.layer({ status: Effect.succeed("unknown"), changes: Stream.empty }),
  Wakeups.layer({
    changes: Stream.callback<Wakeups.ConnectionWakeup>((queue) =>
      Effect.acquireRelease(
        Effect.sync(() =>
          AppState.addEventListener("change", (state) => {
            if (state === "active") Queue.offerUnsafe(queue, "application-active");
          }),
        ),
        (subscription) => Effect.sync(() => subscription.remove()),
      ).pipe(Effect.asVoid),
    ),
  }),
  Layer.succeed(PlatformConnectionSource.PlatformConnectionSource, { registrations: Stream.empty }),
  Layer.succeed(Persistence.EnvironmentCacheStore, {
    loadShell: noCache,
    saveShell: ignoreWrite,
    loadThread: noCache,
    saveThread: ignoreWrite,
    removeThread: ignoreWrite,
    loadServerConfig: noCache,
    saveServerConfig: ignoreWrite,
    loadVcsRefs: noCache,
    saveVcsRefs: ignoreWrite,
    removeVcsRefs: ignoreWrite,
    clearVcsRefs: ignoreWrite,
    clear: ignoreWrite,
  }),
  Layer.succeed(ClientCapabilities.ClientPresentation, {
    metadata: {
      label: "T3 Code HarmonyOS",
      deviceType: "mobile",
      os: "HarmonyOS",
      surface: "mobile",
    },
  }),
  Layer.succeed(ClientCapabilities.PrimaryEnvironmentAuth, { bearerToken: Effect.succeedNone }),
  Layer.succeed(ClientCapabilities.CloudSession, {
    identity: Effect.succeedNone,
    clerkToken: Effect.fail(unavailable),
  }),
  Layer.succeed(ClientCapabilities.RelayDeviceIdentity, { deviceId: Effect.succeedNone }),
  Layer.succeed(ClientCapabilities.SshEnvironmentGateway, {
    provision: unavailableSsh,
    prepare: unavailableSsh,
    disconnect: ignoreWrite,
  }),
  signer,
  ManagedRelay.layer({ relayUrl: "https://relay.invalid", clientId: "t3-mobile" }).pipe(
    Layer.provide(Layer.merge(http, signer)),
  ),
);

const runtime = Atom.runtime(
  Layer.mergeAll(
    ShellSnapshotLoader.layer,
    BoundedThreadSnapshotLoader.layer,
    PullRequestDiffLoader.layer,
  ).pipe(Layer.provideMerge(Connection.layer), Layer.provideMerge(platform)),
);

export const catalog = createEnvironmentCatalogAtoms(runtime);
export const session = createEnvironmentSessionAtoms(runtime);
export const server = createServerEnvironmentAtoms(runtime, {
  initialConfigValueAtom: session.initialConfigValueAtom,
});
export const shell = createEnvironmentShellAtoms(runtime);
export const threads = createEnvironmentThreadStateAtoms(runtime);

export const pair = createRuntimeCommand(runtime, {
  label: "harmonyos:pair",
  execute: (pairingUrl: string) =>
    ConnectionOnboarding.ConnectionOnboarding.pipe(
      Effect.flatMap((onboarding) => onboarding.registerPairing({ pairingUrl })),
    ),
});

export const dispatch = createEnvironmentRpcCommand(runtime, {
  label: "harmonyos:dispatch",
  tag: ORCHESTRATION_V2_WS_METHODS.dispatchCommand,
});

export const pullRequests = createPullRequestEnvironmentAtoms(runtime);
export const issues = createIssueEnvironmentAtoms(runtime);
export const orchestration = createOrchestrationEnvironmentAtoms(runtime, {
  shellState: shell.stateValueAtom,
});
export const files = {
  list: createEnvironmentRpcQueryAtomFamily(runtime, {
    label: "harmonyos:files:list",
    tag: WS_METHODS.projectsListEntries,
    staleTimeMs: 30_000,
  }),
  read: createEnvironmentRpcQueryAtomFamily(runtime, {
    label: "harmonyos:files:read",
    tag: WS_METHODS.projectsReadFile,
    staleTimeMs: 30_000,
  }),
};
