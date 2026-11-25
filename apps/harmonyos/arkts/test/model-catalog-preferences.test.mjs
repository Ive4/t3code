import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import { ClientServerSettingsPatch, WS_METHODS } from "@t3tools/contracts";
import * as Schema from "effect/Schema";

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
const {
  modelCatalogIsFavorite,
  modelCatalogIsHidden,
  modelCatalogSettingsWriteAllowed,
  modelCatalogUpdateRequest,
  readModelCatalogPreferences,
  readUpdatedModelCatalogPreferences,
} = await import(new URL("ModelCatalogPreferences.ets", client).href);
const { readThreadLaunchOptions, readThreadModelSettings } = await import(
  new URL("ThreadLaunchProtocol.ets", client).href
);
loader.deregister();

const decodePatch = Schema.decodeUnknownSync(ClientServerSettingsPatch);
const fixture = {
  favorites: [
    { provider: "remoteProvider", model: "shared-model" },
    { provider: "remoteProvider", model: " shared-model " },
    { provider: "bad:provider", model: "shared-model" },
  ],
  providerModelPreferences: {
    remoteProvider: { hiddenModels: ["shared-model", "shared-model"], modelOrder: ["other-model"] },
  },
};

NodeTest.test(
  "reads catalog preferences without conflating provider instances or custom models",
  () => {
    const snapshot = readModelCatalogPreferences(fixture);
    NodeAssert.deepEqual(snapshot.favorites, [
      { provider: "remoteProvider", model: "shared-model" },
    ]);
    NodeAssert.deepEqual(snapshot.providerModelPreferences.remoteProvider, {
      hiddenModels: ["shared-model"],
      modelOrder: ["other-model"],
    });
    NodeAssert.equal(modelCatalogIsFavorite(snapshot, "remoteProvider", "shared-model"), true);
    NodeAssert.equal(modelCatalogIsFavorite(snapshot, "otherProvider", "shared-model"), false);
    NodeAssert.equal(modelCatalogIsHidden(snapshot, "remoteProvider", "shared-model"), true);
    NodeAssert.equal(modelCatalogIsHidden(snapshot, "otherProvider", "shared-model"), false);
    NodeAssert.equal(modelCatalogIsHidden(snapshot, "remoteProvider", "shared-model", true), false);
    NodeAssert.deepEqual(
      readModelCatalogPreferences({ favorites: null, providerModelPreferences: null }),
      {
        favorites: [],
        providerModelPreferences: {},
      },
    );
    const config = readThreadModelSettings(
      {
        providers: [
          {
            instanceId: "remoteProvider",
            driver: "codex",
            installed: true,
            enabled: true,
            supportedRuntimeModes: ["full-access"],
            models: [{ slug: "shared-model", name: "Model", isCustom: true }],
          },
        ],
        settings: fixture,
      },
      "project",
    );
    NodeAssert.equal(config.providers[0].models[0].isCustom, true);
    NodeAssert.deepEqual(config.modelCatalog, snapshot);
    NodeAssert.deepEqual(
      readThreadLaunchOptions({ projects: [] }, { providers: [], settings: fixture }).modelCatalog,
      snapshot,
    );
  },
);

NodeTest.test(
  "sends narrow favorite and visibility operations and requires authoritative readback",
  () => {
    for (const enabled of [true, false]) {
      const body = { provider: "remoteProvider", model: "shared-model" };
      const favorite = modelCatalogUpdateRequest(body.provider, body.model, "favorite", enabled);
      NodeAssert.equal(favorite.tag, WS_METHODS.serverUpdateSettings);
      NodeAssert.deepEqual(decodePatch(favorite.payload.patch), {
        setModelFavorites: [{ ...body, favorite: enabled }],
      });
      const hidden = modelCatalogUpdateRequest(body.provider, body.model, "hidden", enabled);
      NodeAssert.deepEqual(decodePatch(hidden.payload.patch), {
        setModelsHidden: [{ ...body, hidden: enabled }],
      });
      const response = enabled ? fixture : { favorites: [], providerModelPreferences: {} };
      NodeAssert.deepEqual(
        readUpdatedModelCatalogPreferences(
          response,
          body.provider,
          body.model,
          "favorite",
          enabled,
        ),
        readModelCatalogPreferences(response),
      );
      NodeAssert.deepEqual(
        readUpdatedModelCatalogPreferences(response, body.provider, body.model, "hidden", enabled),
        readModelCatalogPreferences(response),
      );
    }
    NodeAssert.throws(() => modelCatalogUpdateRequest("", "shared-model", "favorite", true));
    NodeAssert.throws(() => modelCatalogUpdateRequest("remoteProvider", " ", "hidden", true));
    NodeAssert.throws(() => {
      readUpdatedModelCatalogPreferences({}, "remoteProvider", "shared-model", "favorite", false);
    });
    NodeAssert.throws(() => {
      readUpdatedModelCatalogPreferences(
        fixture,
        "remoteProvider",
        "shared-model",
        "hidden",
        false,
      );
    });
  },
);

NodeTest.test(
  "requires settings write and respects explicit permission sets over the legacy scope",
  () => {
    NodeAssert.equal(
      modelCatalogSettingsWriteAllowed({ authenticated: true, permissions: ["settings:write"] }),
      true,
    );
    NodeAssert.equal(
      modelCatalogSettingsWriteAllowed({
        authenticated: true,
        permissions: ["orchestration:operate"],
      }),
      false,
    );
    NodeAssert.equal(
      modelCatalogSettingsWriteAllowed({
        authenticated: true,
        permissions: [],
        scopes: ["settings:write"],
      }),
      false,
    );
    NodeAssert.equal(
      modelCatalogSettingsWriteAllowed({ authenticated: true, scopes: ["orchestration:operate"] }),
      true,
    );
    NodeAssert.equal(
      modelCatalogSettingsWriteAllowed({
        authenticated: true,
        scopes: ["orchestration:operate"],
        serverUpdateScope: "environment:maintain",
      }),
      false,
    );
    NodeAssert.equal(
      modelCatalogSettingsWriteAllowed({ authenticated: false, scopes: ["settings:write"] }),
      false,
    );
  },
);
