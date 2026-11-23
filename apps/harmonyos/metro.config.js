const path = require("node:path");
const { createHash } = require("node:crypto");
const { readFileSync } = require("node:fs");
const { getDefaultConfig, mergeConfig } = require("@react-native/metro-config");
const { createHarmonyMetroConfig } = require("@react-native-oh/react-native-harmony/metro.config");

module.exports = mergeConfig(
  getDefaultConfig(__dirname),
  createHarmonyMetroConfig({
    reactNativeHarmonyPackageName: "@react-native-oh/react-native-harmony",
  }),
  {
    cacheVersion: createHash("sha256")
      .update(readFileSync(path.join(__dirname, "babel.config.js")))
      .digest("hex"),
    watchFolders: [path.resolve(__dirname, "../..")],
    resolver: {
      extraNodeModules: {
        "@babel/runtime": path.dirname(require.resolve("@babel/runtime/package.json")),
      },
    },
  },
);
