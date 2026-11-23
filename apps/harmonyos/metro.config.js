const path = require("node:path");
const { createHash } = require("node:crypto");
const { readFileSync } = require("node:fs");
const { getDefaultConfig, mergeConfig } = require("@react-native/metro-config");
const { createHarmonyMetroConfig } = require("@react-native-oh/react-native-harmony/metro.config");

const harmony = createHarmonyMetroConfig({
  reactNativeHarmonyPackageName: "@react-native-oh/react-native-harmony",
});
const reactEntries = new Map(
  ["react", "react/jsx-runtime", "react/jsx-dev-runtime"].map((name) => [
    name,
    require.resolve(name),
  ]),
);

module.exports = mergeConfig(getDefaultConfig(__dirname), harmony, {
  cacheVersion: createHash("sha256")
    .update(readFileSync(path.join(__dirname, "babel.config.js")))
    .digest("hex"),
  watchFolders: [path.resolve(__dirname, "../..")],
  resolver: {
    nodeModulesPaths: [path.resolve(__dirname, "node_modules")],
    extraNodeModules: {
      "@babel/runtime": path.dirname(require.resolve("@babel/runtime/package.json")),
    },
    // Shared mobile views must use the same React instance as the Harmony renderer.
    resolveRequest(context, moduleName, platform) {
      const filePath = reactEntries.get(moduleName);
      if (filePath) return { type: "sourceFile", filePath };
      return harmony.resolver.resolveRequest(context, moduleName, platform);
    },
  },
});
