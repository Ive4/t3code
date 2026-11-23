import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import * as Option from "effect/Option";
import { ConnectionTransientError } from "../connection/model.ts";
import * as CredentialStore from "../connection/credentialStore.ts";
import * as ProfileStore from "../connection/profileStore.ts";
import {
  PullRequestRoutingPermissions,
  makePullRequestRoutingPermissions,
} from "../connection/pullRequestRoutingPermissions.ts";
import {
  make as makeRemoteTokenStore,
  RemoteDpopAccessTokenStore,
} from "../authorization/tokenStore.ts";
import {
  ConnectionPersistenceError,
  ConnectionRegistrationStore,
  ConnectionTargetStore,
} from "./persistence.ts";
import {
  type ConnectionCatalogDocument,
  putRemoteDpopTokenInCatalog,
  registerConnectionInCatalog,
  removeConnectionFromCatalog,
  setConnectionEnabledInCatalog,
  setRoutesInCatalog,
  removeCatalogValue,
  replaceCatalogValue,
} from "./storageDocument.ts";

interface ConnectionCatalogStore {
  readonly read: Effect.Effect<ConnectionCatalogDocument, ConnectionTransientError>;
  readonly update: (
    transform: (document: ConnectionCatalogDocument) => ConnectionCatalogDocument,
  ) => Effect.Effect<void, ConnectionTransientError>;
}

function targetPersistenceError(
  operation:
    | "list-targets"
    | "list-disabled-targets"
    | "register-connection"
    | "set-connection-routes"
    | "remove-connection"
    | "set-connection-enabled",
  error: ConnectionTransientError,
) {
  return new ConnectionPersistenceError({
    operation,
    message: error.message,
  });
}

export const makeConnectionCatalogServices = Effect.fn(
  "clientRuntime.makeConnectionCatalogServices",
)(function* (catalog: ConnectionCatalogStore) {
  const githubRoutingPermissions = yield* makePullRequestRoutingPermissions({
    read: catalog.read.pipe(Effect.map((document) => document.githubRoutingPermissions ?? [])),
    write: (githubRoutingPermissions) =>
      catalog.update((document) => ({ ...document, githubRoutingPermissions })),
  });

  const targetStore = ConnectionTargetStore.of({
    list: catalog.read.pipe(
      Effect.map((document) => document.targets),
      Effect.mapError((error) => targetPersistenceError("list-targets", error)),
    ),
    listDisabled: catalog.read.pipe(
      Effect.map((document) => document.disabledEnvironmentIds),
      Effect.mapError((error) => targetPersistenceError("list-disabled-targets", error)),
    ),
  });
  const registrationStore = ConnectionRegistrationStore.of({
    register: Effect.fn("ConnectionRegistrationStore.register")((registration, routes) =>
      catalog
        .update((document) => registerConnectionInCatalog(document, registration, routes))
        .pipe(Effect.mapError((error) => targetPersistenceError("register-connection", error))),
    ),
    setRoutes: Effect.fn("ConnectionRegistrationStore.setRoutes")((environmentId, routes) =>
      catalog
        .update((document) => setRoutesInCatalog(document, environmentId, routes))
        .pipe(Effect.mapError((error) => targetPersistenceError("set-connection-routes", error))),
    ),
    remove: Effect.fn("ConnectionRegistrationStore.remove")((environmentId) =>
      catalog
        .update((document) => removeConnectionFromCatalog(document, environmentId))
        .pipe(Effect.mapError((error) => targetPersistenceError("remove-connection", error))),
    ),
    setEnabled: Effect.fn("ConnectionRegistrationStore.setEnabled")((environmentId, enabled) =>
      catalog
        .update((document) => setConnectionEnabledInCatalog(document, environmentId, enabled))
        .pipe(Effect.mapError((error) => targetPersistenceError("set-connection-enabled", error))),
    ),
  });
  const profileStore = ProfileStore.make({
    get: (connectionId) =>
      catalog.read.pipe(
        Effect.map((document) =>
          Option.fromUndefinedOr(
            document.profiles.find((candidate) => candidate.connectionId === connectionId),
          ),
        ),
      ),
    put: (profile) =>
      catalog.update((document) => ({
        ...document,
        profiles: replaceCatalogValue(document.profiles, (value) => value.connectionId, profile),
      })),
    remove: (connectionId) =>
      catalog.update((document) => ({
        ...document,
        profiles: removeCatalogValue(
          document.profiles,
          (value) => value.connectionId,
          connectionId,
        ),
      })),
  });
  const credentialStore = CredentialStore.make({
    get: (connectionId) =>
      catalog.read.pipe(
        Effect.map((document) =>
          Option.fromUndefinedOr(
            document.credentials.find((entry) => entry.connectionId === connectionId)?.credential,
          ),
        ),
      ),
    put: (connectionId, credential) =>
      catalog.update((document) => ({
        ...document,
        credentials: replaceCatalogValue(document.credentials, (value) => value.connectionId, {
          connectionId,
          credential,
        }),
      })),
    remove: (connectionId) =>
      catalog.update((document) => ({
        ...document,
        credentials: removeCatalogValue(
          document.credentials,
          (value) => value.connectionId,
          connectionId,
        ),
      })),
  });
  const remoteTokenStore = makeRemoteTokenStore({
    get: (environmentId) =>
      catalog.read.pipe(
        Effect.map((document) =>
          Option.fromUndefinedOr(
            document.remoteDpopTokens.find((token) => token.environmentId === environmentId),
          ),
        ),
      ),
    put: (token) => catalog.update((document) => putRemoteDpopTokenInCatalog(document, token)),
    remove: (environmentId) =>
      catalog.update((document) => ({
        ...document,
        remoteDpopTokens: removeCatalogValue(
          document.remoteDpopTokens,
          (value) => value.environmentId,
          environmentId,
        ),
      })),
  });
  return Context.make(ConnectionTargetStore, targetStore).pipe(
    Context.add(PullRequestRoutingPermissions, githubRoutingPermissions),
    Context.add(ConnectionRegistrationStore, registrationStore),
    Context.add(ProfileStore.ConnectionProfileStore, profileStore),
    Context.add(CredentialStore.ConnectionCredentialStore, credentialStore),
    Context.add(RemoteDpopAccessTokenStore, remoteTokenStore),
  );
});
