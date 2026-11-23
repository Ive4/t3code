import { ConnectionTransientError } from "@t3tools/client-runtime/connection";
import {
  ConnectionCatalogDocument,
  EMPTY_CONNECTION_CATALOG_DOCUMENT,
  makeConnectionCatalogServices,
} from "@t3tools/client-runtime/platform";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Ref from "effect/Ref";
import * as Schema from "effect/Schema";
import * as Semaphore from "effect/Semaphore";
import { TurboModuleRegistry, type TurboModule } from "react-native";

interface ConnectionStoreModule extends TurboModule {
  readCatalog(): Promise<string | null>;
  writeCatalog(document: string): Promise<void>;
}

const catalogJson = Schema.fromJsonString(ConnectionCatalogDocument);
const decodeCatalog = Schema.decodeEffect(catalogJson);
const encodeCatalog = Schema.encodeEffect(catalogJson);
const readFailure = () =>
  new ConnectionTransientError({
    reason: "remote-unavailable",
    detail: "Could not read saved HarmonyOS connections.",
  });
const writeFailure = () =>
  new ConnectionTransientError({
    reason: "remote-unavailable",
    detail: "Could not save HarmonyOS connections.",
  });

export const connectionStorage = Layer.effectContext(
  Effect.gen(function* () {
    const native = TurboModuleRegistry.getEnforcing<ConnectionStoreModule>("T3ConnectionStore");
    const raw = yield* Effect.tryPromise({ try: () => native.readCatalog(), catch: readFailure });
    const initial =
      raw === null
        ? EMPTY_CONNECTION_CATALOG_DOCUMENT
        : yield* decodeCatalog(raw).pipe(Effect.mapError(readFailure));
    const document = yield* Ref.make(initial);
    const lock = yield* Semaphore.make(1);

    return yield* makeConnectionCatalogServices({
      read: Ref.get(document),
      update: Effect.fn("HarmonyConnectionStorage.update")((transform) =>
        lock.withPermits(1)(
          Effect.gen(function* () {
            const updated = transform(yield* Ref.get(document));
            const encoded = yield* encodeCatalog(updated).pipe(Effect.mapError(writeFailure));
            yield* Effect.tryPromise({
              try: () => native.writeCatalog(encoded),
              catch: writeFailure,
            });
            yield* Ref.set(document, updated);
          }).pipe(Effect.uninterruptible),
        ),
      ),
    });
  }),
);
