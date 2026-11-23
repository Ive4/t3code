import { makeConnectionCatalogServices } from "@t3tools/client-runtime/platform";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";

import * as CatalogStore from "./catalog-store";

export const layer = Layer.effectContext(
  CatalogStore.make().pipe(Effect.flatMap(makeConnectionCatalogServices)),
);
