const { execFileSync } = require("node:child_process");
const { createHash } = require("node:crypto");
const {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
  writeFileSync,
} = require("node:fs");
const { dirname, isAbsolute, join, relative, resolve, sep } = require("node:path");
const { parseArgs } = require("node:util");

const harmony = resolve(__dirname, "..");
const repository = realpathSync(resolve(harmony, "../.."));
const rnohRevision = "07ae308f0e29be1306f7239cc452b3ec5d7cdad4";
const packages = [
  [
    "gesture",
    "gesture_handler",
    "gesture-handler",
    "2.30.2",
    "282e63e029577e77b1c2c430d9a20a375b7ef748f735739af7b048b76bbfd05a",
  ],
  [
    "keyboard",
    "keyboard_controller",
    "keyboard-controller",
    "1.18.0-beta.1",
    "558ce2810f3d512f2f460beba81780fb266e1c4751f75d34120ca50682a405f4",
  ],
  [
    "reanimated",
    "reanimated",
    "reanimated",
    "4.1.0-beta.1",
    "c5ccbc5d75d17a05011673b4163b32ca71509d7b7199dee2e0f49cf12db090eb",
  ],
  [
    "safe_area",
    "safe_area",
    "safe-area-context",
    "5.6.5",
    "cf866beea55e692004db7c4b3577114e57cd803e0f73e45db114085ed08f17b5",
  ],
  [
    "screens",
    "screens",
    "screens",
    "4.10.0-beta.4",
    "6cb63f62017607a8725db3ac3dec63fd60625e3eb7840acf9d361c75f83a4a48",
  ],
  [
    "svg",
    "svg",
    "svg",
    "15.14.0-beta.4",
    "1943d7204ab2a50f12ea751ffe957b5010afba2a87f794d26b8907f778d1205e",
  ],
  [
    "worklets",
    "worklets",
    "worklets",
    "1.1.0-beta.1",
    "ff73483eb65d68c6e30b01f9d9c1de0e1168762ea7d8d6a9be6d49514a71845e",
  ],
];

function canonical(path) {
  if (existsSync(path)) return realpathSync(path);
  return join(canonical(dirname(path)), path.slice(path.lastIndexOf(sep) + 1));
}

function contains(parent, child) {
  const path = relative(parent, child);
  return !isAbsolute(path) && path !== ".." && !path.startsWith(".." + sep);
}

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function writeJson(path, value) {
  writeFileSync(path, JSON.stringify(value, null, 2) + "\n");
}

async function extractPackage(staging, [directory, module, suffix, version, sha256]) {
  const packageName = "react-native-" + suffix;
  const url = `https://registry.npmjs.org/@react-native-ohos/${packageName}/-/${packageName}-${version}.tgz`;
  const response = await fetch(url, { signal: AbortSignal.timeout(60000) });
  if (!response.ok) throw new Error(`Download failed (${response.status}): ${url}`);
  const archive = Buffer.from(await response.arrayBuffer());
  if (createHash("sha256").update(archive).digest("hex") !== sha256) {
    throw new Error("Unexpected checksum for " + url);
  }
  const tgz = join(staging, directory + ".tgz");
  const har = join(staging, directory + ".har");
  const destination = join(staging, directory);
  writeFileSync(tgz, archive);
  writeFileSync(har, execFileSync("tar", ["-xOf", tgz, "package/harmony/" + module + ".har"]));
  mkdirSync(destination);
  execFileSync("tar", ["-xf", har, "--strip-components", "1", "-C", destination]);
  rmSync(tgz);
  rmSync(har);

  const manifest = join(destination, "oh-package.json5");
  const { metadata: _, ...sourcePackage } = readJson(manifest);
  const dependencies = {
    ...sourcePackage.dependencies,
    "@rnoh/react-native-openharmony": "file:../rn",
  };
  writeJson(manifest, { ...sourcePackage, dependencies });
  const compiledModule = join(destination, "src/main/module.json");
  const { module: compiled } = readJson(compiledModule);
  const profile = { name: compiled.name, type: compiled.type, deviceTypes: compiled.deviceTypes };
  if (compiled.description) profile.description = compiled.description;
  if (compiled.requestPermissions) profile.requestPermissions = compiled.requestPermissions;
  writeJson(join(destination, "src/main/module.json5"), { module: profile });
  rmSync(compiledModule);
}

async function main() {
  const { values } = parseArgs({
    options: {
      "rnoh-root": { type: "string" },
      out: { type: "string" },
      help: { type: "boolean" },
    },
  });
  if (values.help) {
    console.log(
      "Usage: node apps/harmonyos/scripts/bootstrap-shared-vendor.cjs --rnoh-root <RNOH checkout> --out <new vendor directory>",
    );
    return;
  }
  if (!values["rnoh-root"] || !values.out) throw new Error("Supply --rnoh-root and --out");
  const rnoh = realpathSync(values["rnoh-root"]);
  const output = canonical(resolve(values.out));
  if (
    existsSync(output) ||
    [repository, rnoh].some((path) => contains(path, output) || contains(output, path))
  ) {
    throw new Error("Use a new vendor directory outside the T3 Code and RNOH checkouts.");
  }
  if (
    execFileSync("git", ["rev-parse", "HEAD"], { cwd: rnoh, encoding: "utf8" }).trim() !==
    rnohRevision
  ) {
    throw new Error("Expected the RNOH v0.88.0 checkout at " + rnohRevision);
  }
  const native = join(rnoh, "packages/tester/harmony/react_native_openharmony");
  const thirdParty = join(native, "src/main/cpp/third-party");
  if (!existsSync(join(thirdParty, "rn/ReactCommon/react/renderer/scheduler/SchedulerToolbox.h"))) {
    throw new Error(
      "Run pnpm init-ws in the RNOH checkout to prepare its submodules and ReactCommon.",
    );
  }
  for (const configuration of ["debug", "release"]) {
    const hermes = join(thirdParty, "prebuilt", configuration, "arm64-v8a/libhermesvm.so");
    if (
      !existsSync(hermes) ||
      !readFileSync(hermes)
        .subarray(0, 4)
        .equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46]))
    ) {
      throw new Error("Fetch the RNOH Hermes libraries with Git LFS. Missing ELF file: " + hermes);
    }
  }

  mkdirSync(dirname(output), { recursive: true });
  const staging = mkdtempSync(join(dirname(output), ".t3-harmony-vendor-"));
  try {
    const extracted = await Promise.allSettled(packages.map((pkg) => extractPackage(staging, pkg)));
    for (const result of extracted) {
      if (result.status === "rejected") throw result.reason;
    }
    cpSync(native, join(staging, "rn"), {
      recursive: true,
      filter: (file) =>
        ![".git", ".cxx", ".hvigor", "build", "oh_modules", "oh-package-lock.json5"].includes(
          file.split(sep).at(-1),
        ) &&
        // glog's Autotools test runner is an absolute symlink. The SDK builds glog with CMake.
        file !== join(thirdParty, "glog/test-driver"),
    });
    const reanimated = require.resolve("react-native-reanimated/package.json", {
      paths: [join(harmony, "../mobile")],
    });
    if (readJson(reanimated).version !== "4.7.1") {
      throw new Error("Install the mobile workspace's react-native-reanimated 4.7.1 sources.");
    }
    cpSync(
      join(dirname(reanimated), "Common"),
      join(staging, "reanimated/src/main/cpp/Common471"),
      { recursive: true },
    );
    const patchDirectory = join(harmony, "shared-native/patches");
    for (const patch of [
      "Gesture-Handler-3.5.0-HarmonyOS.patch",
      "RNOH-0.88.0-scheduler-bindings.patch",
      "Worklets-0.13.1-HarmonyOS.patch",
      "Reanimated-4.7.1-HarmonyOS.patch",
    ]) {
      execFileSync("git", ["apply", "--ignore-space-change", join(patchDirectory, patch)], {
        cwd: staging,
        stdio: "inherit",
      });
    }
    renameSync(staging, output);
  } finally {
    rmSync(staging, { recursive: true, force: true });
  }
  console.log(output);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
