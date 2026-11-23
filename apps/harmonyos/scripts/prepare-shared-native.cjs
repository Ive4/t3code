const {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  realpathSync,
  writeFileSync,
} = require("node:fs");
const { basename, dirname, isAbsolute, join, relative, resolve, sep } = require("node:path");
const { parseArgs } = require("node:util");
const { spawnSync } = require("node:child_process");

const harmony = resolve(__dirname, "..");
const repository = realpathSync(resolve(harmony, "../.."));
const snapshot = join(harmony, "shared-native");
const marker = ".t3-shared-native.json";

const vendorModules = [
  [
    "keyboard",
    "keyboard_controller",
    "@react-native-ohos/react-native-keyboard-controller",
    "1.18.0-beta.1",
  ],
  ["screens", "screens", "@react-native-ohos/react-native-screens", "4.10.0-beta.4"],
  ["svg", "svg", "@react-native-ohos/react-native-svg", "15.14.0-beta.4"],
  ["safe_area", "safe_area", "@react-native-ohos/react-native-safe-area-context", "5.6.5"],
  ["reanimated", "reanimated", "@react-native-ohos/react-native-reanimated", "4.1.0-beta.1"],
  ["worklets", "worklets", "@react-native-ohos/react-native-worklets", "1.1.0-beta.1"],
  ["gesture", "gesture_handler", "@react-native-ohos/react-native-gesture-handler", "2.30.2"],
  ["rn", "react_native_openharmony", "@rnoh/react-native-openharmony", "0.88.0"],
];

const workletsCmake = "worklets/src/main/cpp/CMakeLists.txt";
const workletsSourceAssignment = /^set\(WORKLET_SRC_DIR [^\r\n]+\)$/m;
const networkingSource =
  "src/main/ets/RNOHCorePackage/turboModules/Networking/NetworkingTurboModule.ts";
const networkingPatch = join(snapshot, "patches/RNOH-0.88.0-Networking-byte-body.patch");
const expectedPatchFeatures = [
  ["rn/src/main/cpp/RNOH/RNInstanceInternal.cpp", ".bridgelessBindingsExecutor"],
  [
    "gesture/src/main/cpp/componentInstances/RNGestureHandlerDetectorComponentInstance.h",
    "RNGestureHandlerDetectorComponentInstance",
  ],
  [workletsCmake, "WORKLETS_VERSION=0.13.1"],
  ["worklets/src/main/cpp/AsyncQueueImplOHOS.cpp", "AsyncQueueImpl"],
  ["reanimated/src/main/cpp/CMakeLists.txt", "REANIMATED_VERSION=4.7.1"],
  [
    "reanimated/src/main/cpp/Common471/cpp/reanimated/NativeModules/ReanimatedModuleProxy.cpp",
    "ReanimatedModuleProxy",
  ],
];

const existingFiles = [
  "AppScope/app.json5",
  "AppScope/resources",
  "hvigorfile.ts",
  "hvigor/hvigor-config.json5",
  "entry/hvigorfile.ts",
  "entry/src/main/resources/base",
  "entry/src/main/ets/ConnectionStoreModule.ets",
  "entry/src/main/ets/PairingScannerModule.ets",
  "entry/src/main/ets/workers/RNOHWorker.ets",
];

function usage() {
  console.log(
    "Usage: node apps/harmonyos/scripts/prepare-shared-native.cjs --vendor-root <path> --out <path> [--abi arm64-v8a|x86_64]",
  );
}

function canonical(path) {
  if (existsSync(path)) return realpathSync(path);
  return join(canonical(dirname(path)), basename(path));
}

function contains(parent, child) {
  const path = relative(parent, child);
  return !isAbsolute(path) && path !== ".." && !path.startsWith(".." + sep);
}

function writeJson(file, value) {
  writeFileSync(file, JSON.stringify(value, null, 2) + "\n");
}

function readStringProperty(source, property) {
  const field = new RegExp("(^|[,{])\\s*[\"']?" + property + "[\"']?\\s*:\\s*([\"'])([^\"']+)\\2");
  return field.exec(source)?.[3];
}

function requirePatchedVendors(vendor, abi) {
  for (const [directory, module, dependency, version] of vendorModules) {
    const packageFile = join(vendor, directory, "oh-package.json5");
    const moduleFile = join(vendor, directory, "src/main/module.json5");
    const contents = readFileSync(packageFile, "utf8");
    if (
      readStringProperty(contents, "name") !== dependency ||
      readStringProperty(contents, "version") !== version ||
      readStringProperty(readFileSync(moduleFile, "utf8"), "name") !== module
    ) {
      throw new Error(
        packageFile + " must describe " + dependency + " " + version + " in module " + module,
      );
    }
    if (!existsSync(join(vendor, directory, "src/main/cpp/CMakeLists.txt"))) {
      throw new Error("Expected a source module with CMake files in " + directory);
    }
  }
  for (const [file, expected] of expectedPatchFeatures) {
    if (
      !existsSync(join(vendor, file)) ||
      !readFileSync(join(vendor, file), "utf8").includes(expected)
    ) {
      throw new Error("Missing native patch in " + join(vendor, file));
    }
  }
  for (const configuration of ["debug", "release"]) {
    const hermes = join(
      vendor,
      "rn/src/main/cpp/third-party/prebuilt",
      configuration,
      abi,
      "libhermesvm.so",
    );
    if (!existsSync(hermes)) throw new Error("Missing RNOH Hermes library " + hermes);
  }
  const cmake = readFileSync(join(vendor, workletsCmake), "utf8");
  if (!workletsSourceAssignment.test(cmake)) {
    throw new Error("Expected a WORKLET_SRC_DIR assignment in " + join(vendor, workletsCmake));
  }
  return cmake;
}

function findWorkletsCommon() {
  const packageFile = require.resolve("react-native-worklets/package.json", {
    paths: [join(harmony, "../mobile")],
  });
  const { version } = JSON.parse(readFileSync(packageFile, "utf8"));
  const common = join(dirname(packageFile), "Common");
  if (version !== "0.13.1" || !existsSync(join(common, "cpp/worklets"))) {
    throw new Error("Install the mobile workspace's react-native-worklets 0.13.1 sources");
  }
  return common;
}

function copyVendors(vendor, output, workletsCommon, cmake) {
  const ignored = new Set([".git", ".cxx", ".hvigor", ".idea", "oh_modules", "node_modules"]);
  for (const [directory] of vendorModules) {
    const from = join(vendor, directory);
    cpSync(from, join(output, directory), {
      recursive: true,
      dereference: true,
      filter: (file) => {
        const local = relative(from, file);
        return (
          !local.split(sep).some((part) => ignored.has(part)) &&
          local !== "build" &&
          local !== "oh-package-lock.json5"
        );
      },
    });
  }
  cpSync(workletsCommon, join(output, "worklets/src/main/cpp/WorkletCore"), { recursive: true });
  const candidateCmake = cmake.replace(
    workletsSourceAssignment,
    'set(WORKLET_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/WorkletCore")',
  );
  writeFileSync(join(output, workletsCmake), candidateCmake);
}

function patchNetworking(rnoh) {
  const isPatched = () =>
    readFileSync(join(rnoh, networkingSource), "utf8").includes(
      "return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);",
    );
  if (isPatched()) return;

  const patch = spawnSync("git", ["apply", "--ignore-space-change", networkingPatch], {
    cwd: rnoh,
    encoding: "utf8",
  });
  if (patch.status !== 0 || !isPatched()) {
    throw new Error(
      "Could not apply the RNOH 0.88.0 networking patch in " +
        rnoh +
        ": " +
        (patch.error?.message ?? patch.stderr?.trim() ?? "unexpected RNOH source"),
    );
  }
}

function writeProjectFiles(output, abi) {
  const dependencies = (prefix) =>
    Object.fromEntries(
      vendorModules.map(([directory, , dependency]) => [dependency, "file:" + prefix + directory]),
    );
  writeJson(join(output, "oh-package.json5"), {
    modelVersion: "26.0.0",
    name: "t3-code",
    version: "1.0.0",
    dependencies: dependencies("./"),
  });
  writeJson(join(output, "entry/oh-package.json5"), {
    name: "entry",
    version: "1.0.0",
    dependencies: dependencies("../"),
  });

  // DevEco adds signing configuration to this file. Leave an existing local profile in place.
  const projectProfile = join(output, "build-profile.json5");
  if (!existsSync(projectProfile)) {
    writeJson(projectProfile, {
      app: {
        products: [
          {
            name: "default",
            compatibleSdkVersion: "26.0.0",
            targetSdkVersion: "26.0.0",
            runtimeOS: "HarmonyOS",
          },
        ],
      },
      modules: [
        ...vendorModules.map(([directory, name]) => ({ name, srcPath: "./" + directory })),
        {
          name: "entry",
          srcPath: "./entry",
          targets: [{ name: "default", applyToProducts: ["default"] }],
        },
      ],
    });
  }
  writeJson(join(output, "entry/build-profile.json5"), {
    apiType: "stageMode",
    buildOption: {
      externalNativeOptions: { path: "./src/main/cpp/CMakeLists.txt", abiFilters: [abi] },
    },
    targets: [{ name: "default" }],
  });
}

function main() {
  const { values } = parseArgs({
    options: {
      "vendor-root": { type: "string" },
      out: { type: "string" },
      abi: { type: "string", default: "arm64-v8a" },
      help: { type: "boolean" },
    },
  });
  if (values.help) {
    usage();
    return;
  }
  const { out, abi } = values;
  if (!out || !values["vendor-root"] || !["arm64-v8a", "x86_64"].includes(abi)) {
    usage();
    throw new Error("Supply the vendor root, candidate path, and a supported ABI");
  }
  const vendor = realpathSync(resolve(values["vendor-root"]));
  const output = canonical(resolve(out));
  if ([repository, vendor].some((path) => contains(path, output) || contains(output, path))) {
    throw new Error("The candidate path must be separate from the repository and vendor root");
  }

  const markerPath = join(output, marker);
  const state = existsSync(markerPath) ? JSON.parse(readFileSync(markerPath, "utf8")) : null;
  if (state === null && existsSync(output) && readdirSync(output).length > 0) {
    throw new Error("Use an empty directory or an existing T3 shared native candidate");
  }
  if (state !== null && (state.version !== 1 || state.vendor !== vendor || state.abi !== abi)) {
    throw new Error(
      "Use a fresh candidate when changing the vendor root, preparation format, or ABI",
    );
  }
  if (!state?.ready) {
    const cmake = requirePatchedVendors(vendor, abi);
    const workletsCommon = findWorkletsCommon();
    mkdirSync(output, { recursive: true });
    writeJson(markerPath, { version: 1, vendor, abi, ready: false });
    copyVendors(vendor, output, workletsCommon, cmake);
  }
  patchNetworking(join(output, "rn"));

  for (const file of existingFiles) {
    cpSync(join(harmony, file), join(output, file), { recursive: true });
  }
  cpSync(join(snapshot, "entry"), join(output, "entry"), { recursive: true });
  writeProjectFiles(output, abi);
  writeJson(markerPath, { version: 1, vendor, abi, ready: true });
  console.log(output);
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
