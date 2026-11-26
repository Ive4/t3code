const { execFileSync } = require("node:child_process");
const { createHash } = require("node:crypto");
const { existsSync, readFileSync, realpathSync, statSync } = require("node:fs");
const { copyFile, mkdir, mkdtemp, rm, writeFile } = require("node:fs/promises");
const { createRequire, registerHooks } = require("node:module");
const { platform, tmpdir } = require("node:os");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { parseArgs } = require("node:util");
const { loadConfig, runBuild } = require("metro");
const { buildTerminalDocument } = require("./terminal-document.cjs");
const { sharedCloudConfig } = require("./shared-cloud-config.cjs");

const harmonyRoot = path.resolve(__dirname, "..");
const mobileRoot = path.resolve(harmonyRoot, "../mobile");
const sharedRoot = path.join(harmonyRoot, "src/shared");
const mobileRequire = createRequire(path.join(mobileRoot, "package.json"));
const frameworkPackage = "@react-native-oh/react-native-harmony";
const frameworkVersion = "0.88.0";
const hermesCompilerBins = {
  darwin: "osx-bin/hermesc",
  linux: "linux64-bin/hermesc",
  win32: "win64-bin/hermesc.exe",
};
const runtimePackages = [
  "@react-native/assets-registry",
  "@react-native/js-polyfills",
  "@react-native/normalize-colors",
  "@react-native/virtualized-lists",
];
const ports = new Map(
  [
    ["expo-application", "expo-application"],
    ["expo-audio", "expo-audio"],
    ["expo-clipboard", "expo-clipboard"],
    ["expo-crypto", "expo-crypto"],
    ["expo-device", "expo-device"],
    ["expo-document-picker", "expo-document-picker"],
    ["expo/fetch", "expo-fetch"],
    ["expo-file-system", "expo-file-system"],
    ["expo-haptics", "expo-haptics"],
    ["expo-image", "expo-image"],
    ["expo-image-manipulator", "expo-image-manipulator"],
    ["expo-image-picker", "expo-image-picker"],
    ["expo-keep-awake", "expo-keep-awake"],
    ["expo-network", "expo-network"],
    ["expo-secure-store", "expo-secure-store"],
    ["expo-sensors", "expo-sensors"],
    ["expo-sharing", "expo-sharing"],
    ["expo-sqlite", "expo-sqlite"],
    ["expo-updates", "expo-updates"],
    ["react-native-webview", "react-native-webview"],
  ].map(([request, moduleName]) => [
    request,
    path.join(sharedRoot, "ports", moduleName + ".harmony.js"),
  ]),
);

const nativeFallbacks = new Set(["T3ComposerEditor", "T3KeyboardCommands"]);
// The pinned RNOH Hermes build disables Intl, so these polyfills always install.
const requiredIntlPolyfills = new Set([
  "@formatjs/intl-datetimeformat/polyfill",
  "@formatjs/intl-displaynames/polyfill",
  "@formatjs/intl-numberformat/polyfill",
  "@formatjs/intl-pluralrules/polyfill",
]);

const usage =
  "Usage: node apps/harmonyos/scripts/bundle-shared.cjs " +
  "--framework <RNOH JS package root> --native-workspace <native host root> " +
  "[--runtime-node-modules <pinned JS dependencies>] [--out-dir <rawfile output>]";

function manifest(packageRoot) {
  return JSON.parse(readFileSync(path.join(packageRoot, "package.json"), "utf8"));
}

function getPaths() {
  const { values } = parseArgs({
    options: {
      framework: { type: "string" },
      "native-workspace": { type: "string" },
      "runtime-node-modules": { type: "string" },
      "out-dir": { type: "string" },
      help: { type: "boolean" },
    },
  });
  if (values.help) {
    console.log(usage);
    return;
  }
  if (!values.framework || !values["native-workspace"]) throw new Error(usage);

  const frameworkRoot = realpathSync(values.framework);
  const nativeRoot = realpathSync(values["native-workspace"]);
  const entryRoot = path.join(nativeRoot, "entry/src/main");
  if (!statSync(path.join(entryRoot, "module.json5")).isFile()) {
    throw new Error("Expected a Harmony native workspace with an entry module.");
  }
  const runtimePath = values["runtime-node-modules"] ?? path.join(frameworkRoot, "node_modules");
  const outDir = path.resolve(values["out-dir"] ?? path.join(entryRoot, "resources/rawfile"));
  return { frameworkRoot, runtimePath, outDir };
}

function loadFrameworkConfig(frameworkRoot) {
  const configPath = path.join(frameworkRoot, "metro.config.js");
  const frameworkRequire = createRequire(configPath);
  // A source checkout can use the same Metro config dependency as the installed Harmony package.
  const installedFrameworkRequire = createRequire(
    require.resolve(frameworkPackage + "/metro.config"),
  );
  const hooks = registerHooks({
    resolve(specifier, context, nextResolve) {
      if (specifier !== "colors/safe" || context.parentURL !== pathToFileURL(configPath).href) {
        return nextResolve(specifier, context);
      }
      try {
        return nextResolve(specifier, context);
      } catch (error) {
        if (error.code !== "MODULE_NOT_FOUND") throw error;
        const url = pathToFileURL(installedFrameworkRequire.resolve(specifier)).href;
        return { url, shortCircuit: true };
      }
    },
  });
  try {
    return frameworkRequire(configPath).createHarmonyMetroConfig({
      reactNativeHarmonyPackageName: frameworkPackage,
      __reactNativeHarmonyPattern: path.sep + "react-native-harmony" + path.sep,
    });
  } finally {
    hooks.deregister();
  }
}

function configureResolver(config, frameworkConfig, frameworkRoot, runtimeRoot, cloudConfigPath) {
  // Clerk loads React DOM transitively. Both entry points must use the Harmony renderer's React version.
  const reactPackageRoots = ["react", "react-dom"].map((name) => [
    name,
    path.dirname(require.resolve(name + "/package.json")),
  ]);
  const gtRequire = createRequire(mobileRequire.resolve("gt-react-native"));
  const intlRequire = createRequire(gtRequire.resolve("gt-i18n"));
  const intlPackages = ["@formatjs/intl-numberformat", "@formatjs/intl-datetimeformat"];
  const intlRoots = new Map(
    intlPackages.map((name) => [name, path.dirname(intlRequire.resolve(name + "/package.json"))]),
  );

  const installedFrameworkScope = path.dirname(
    path.dirname(path.dirname(require.resolve(frameworkPackage + "/metro.config"))),
  );
  config.resolver.nodeModulesPaths = [
    ...config.resolver.nodeModulesPaths,
    path.join(mobileRoot, "node_modules"),
    installedFrameworkScope,
  ];
  config.resolver.resolveRequest = (context, request, platform) => {
    const resolve = context.resolveRequest;
    const origin = context.originModulePath.replaceAll("\\", "/");
    if (platform === "harmony") {
      if (requiredIntlPolyfills.has(request)) request += "-force";
      if (origin.includes("/mobile/src/") && request.endsWith("/nativeTerminalModule")) {
        return { type: "sourceFile", filePath: path.join(sharedRoot, "terminal", "surface.js") };
      }
      if (origin.endsWith("/shared/terminal/surface.js") && request === "./document") {
        return {
          type: "sourceFile",
          filePath: path.join(path.dirname(cloudConfigPath), "terminalDocument.js"),
        };
      }
      const port = ports.get(request);
      if (port) return { type: "sourceFile", filePath: port };
      if (
        origin.endsWith("/mobile/src/features/cloud/publicConfig.ts") &&
        request === "./cloudConfigExtra"
      ) {
        return { type: "sourceFile", filePath: cloudConfigPath };
      }
      if (
        origin.includes("/@clerk/expo/") &&
        (request === "expo-auth-session" || request === "expo-web-browser")
      ) {
        return {
          type: "sourceFile",
          filePath: path.join(sharedRoot, "ports", request + ".harmony.js"),
        };
      }
      if (
        origin.includes("/@react-navigation/native-stack/") &&
        request.endsWith("/NativeStackView")
      ) {
        return resolve({ ...context, preferNativePlatform: false }, request, null);
      }
      const nativeModule = request.split("/").at(-1);
      if (origin.includes("/mobile/src/") && nativeFallbacks.has(nativeModule)) {
        return {
          type: "sourceFile",
          filePath: path.join(mobileRoot, "src/native", nativeModule + ".harmony.tsx"),
        };
      }
      if (
        origin.includes("/react-native-gesture-handler/") &&
        request.endsWith("/GestureHandlerRootView")
      ) {
        return resolve(context, request, "android");
      }
      if (origin.includes("/expo-paste-input/") && request === "./TextInputWrapperView") {
        return resolve(context, request, "web");
      }
      for (const [name, packageRoot] of intlRoots) {
        if (request.startsWith(name + "/")) {
          return resolve(context, path.join(packageRoot, request.slice(name.length + 1)), platform);
        }
      }
    }
    for (const [name, packageRoot] of reactPackageRoots) {
      if (request === name || request.startsWith(name + "/")) {
        return resolve(context, path.join(packageRoot, request.slice(name.length)), platform);
      }
    }

    function resolveFramework(ctx, name, targetPlatform) {
      const original = { ...ctx, resolveRequest: resolve };
      if (runtimePackages.some((pkg) => name === pkg || name.startsWith(pkg + "/"))) {
        return resolve(original, path.join(runtimeRoot, name), targetPlatform);
      }
      if (name === frameworkPackage || name.startsWith(frameworkPackage + "/")) {
        const subpath = name.slice(frameworkPackage.length + 1);
        const target =
          subpath === "unstable-internals-do-not-use"
            ? "src/unstable-internals-do-not-use"
            : subpath;
        return resolve(original, path.join(frameworkRoot, target), targetPlatform);
      }
      return resolve(original, name, targetPlatform);
    }

    try {
      return frameworkConfig.resolver.resolveRequest(
        { ...context, resolveRequest: resolveFramework },
        request,
        platform,
      );
    } catch (error) {
      if (
        platform !== "harmony" ||
        !request.startsWith(".") ||
        (!origin.includes("/react-native-screens/") &&
          !origin.includes("/react-native-image-viewing/"))
      ) {
        throw error;
      }
      return resolve(context, request, "android");
    }
  };
}

async function writeAssets(assets, assetsRoot) {
  let copied = 0;
  for (const asset of assets) {
    const scales = asset.scales.filter((scale) => [1, 2, 3, 4].includes(scale));
    if (scales.length === 0 && asset.scales.length > 0) {
      scales.push(asset.scales.find((scale) => scale > 4) ?? asset.scales.at(-1));
    }
    for (const scale of scales) {
      const index = asset.scales.indexOf(scale);
      const suffix = scale === 1 ? "" : "@" + scale + "x";
      const relative = (
        asset.httpServerLocation.replace(/^\//, "") +
        "/" +
        asset.name +
        suffix +
        "." +
        asset.type
      )
        .replace(/^assets\//, "")
        .replaceAll("../", "_");
      const target = path.resolve(assetsRoot, relative);
      if (!target.startsWith(assetsRoot + path.sep))
        throw new Error("Asset path outside root: " + relative);
      await mkdir(path.dirname(target), { recursive: true });
      await copyFile(asset.files[index], target);
      copied += 1;
    }
  }
  return copied;
}

async function bundle() {
  const paths = getPaths();
  if (!paths) return;
  const { frameworkRoot, runtimePath, outDir } = paths;
  const framework = manifest(frameworkRoot);
  if (framework.name !== frameworkPackage || framework.version !== frameworkVersion) {
    throw new Error("Shared Harmony bundles require " + frameworkPackage + "@" + frameworkVersion);
  }
  const hostPlatform = platform();
  const compilerBin = hermesCompilerBins[hostPlatform];
  if (!compilerBin) throw new Error("No Hermes compiler for " + hostPlatform);
  const compilerRoot = path.dirname(require.resolve("hermes-compiler/package.json"));
  const compiler = path.join(compilerRoot, "hermesc", compilerBin);
  if (!existsSync(path.join(frameworkRoot, "Libraries/Core/InitializeCore.js"))) {
    throw new Error(
      "RNOH source is missing upstream React Native files in " +
        frameworkRoot +
        ". Run `pnpm init-ws` in a fresh RNOH checkout before using its JavaScript package.",
    );
  }
  const runtimeRoot = realpathSync(runtimePath);
  for (const name of runtimePackages) {
    const runtime = manifest(path.join(runtimeRoot, name));
    if (runtime.name !== name || runtime.version !== framework.dependencies[name]) {
      throw new Error(
        "Expected " + name + "@" + framework.dependencies[name] + " in " + runtimeRoot,
      );
    }
  }

  process.chdir(harmonyRoot);
  process.env.NODE_ENV ??= "production";
  const { withUniwindConfig } = mobileRequire("uniwind/metro");
  const config = await loadConfig({ cwd: harmonyRoot });
  const mobileConfig = await mobileRequire("./metro.config.js");
  const frameworkConfig = loadFrameworkConfig(frameworkRoot);
  const babelTransformerPath = path.join(__dirname, "shared-harmony-transformer.cjs");
  config.cacheVersion = createHash("sha256")
    .update(config.cacheVersion)
    .update(readFileSync(__filename))
    .update(readFileSync(babelTransformerPath))
    .update(frameworkRoot)
    .update(runtimeRoot)
    .digest("hex");
  config.watchFolders = [...new Set([...config.watchFolders, frameworkRoot, runtimeRoot])];
  config.serializer = {
    ...config.serializer,
    ...frameworkConfig.serializer,
    getPolyfills: require(path.join(runtimeRoot, "@react-native/js-polyfills")),
  };
  config.transformer = {
    ...config.transformer,
    ...frameworkConfig.transformer,
    babelTransformerPath,
  };
  config.resolver.extraNodeModules = {
    ...config.resolver.extraNodeModules,
    ...mobileConfig.resolver.extraNodeModules,
  };
  const temporary = await mkdtemp(path.join(tmpdir(), "t3-harmony-uniwind-"));
  try {
    const cloudConfigPath = path.join(temporary, "cloudConfigExtra.js");
    await writeFile(
      cloudConfigPath,
      `exports.getCloudConfigExtra = () => (${JSON.stringify(sharedCloudConfig())});\n`,
    );
    await writeFile(
      path.join(temporary, "terminalDocument.js"),
      `module.exports = ${JSON.stringify(await buildTerminalDocument())};\n`,
    );
    config.watchFolders.push(temporary);
    configureResolver(config, frameworkConfig, frameworkRoot, runtimeRoot, cloudConfigPath);
    const styledConfig = withUniwindConfig(config, {
      cssEntryFile: "../mobile/global.css",
      extraThemes: mobileRequire("./generated-uniwind-theme-names.json"),
      polyfills: { rem: 14 },
      dtsFile: path.join(temporary, "uniwind.d.ts"),
    });
    const bundlePath = path.join(temporary, "bundle.harmony.js");
    const bytecodePath = path.join(temporary, "bundle.harmony.hbc");
    const result = await runBuild(styledConfig, {
      entry: path.join(sharedRoot, "index.js"),
      out: bundlePath,
      platform: "harmony",
      dev: false,
      minify: false,
      assets: true,
    });
    execFileSync(compiler, ["-emit-binary", "-O", "-out", bytecodePath, bundlePath], {
      stdio: "inherit",
    });
    await mkdir(outDir, { recursive: true });
    const count = await writeAssets(result.assets ?? [], path.join(outDir, "assets"));
    await copyFile(bytecodePath, path.join(outDir, "bundle.harmony.hbc"));
    await rm(path.join(outDir, "bundle.harmony.js"), { force: true });
    console.log("Copied " + count + " mobile assets to " + outDir);
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

bundle().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
