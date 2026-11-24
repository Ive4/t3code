# T3 Code for HarmonyOS

The HarmonyOS app runs React Native for OpenHarmony 0.86.1 on HarmonyOS SDK 26.
Pair with a direct environment link or use the system QR scanner. Saved connections are encrypted and restored when the app opens. Open **Environments** from the thread list or **Settings** to add or switch connections. Open an environment's details to remove it.

Open a project to read threads, select a model for a new thread, and send text messages. You can respond to approvals and questions and stop an active run from the thread.

From the repository root, install the HarmonyOS workspace dependencies and bundle the app.

```sh
pnpm --filter @t3tools/harmonyos... install --frozen-lockfile
pnpm --filter @t3tools/harmonyos bundle
```

From this directory, run `ohpm install --all`. Open this directory in DevEco Studio,
configure a local debug signature for the connected device, and run the `entry` module.
Rebundle after changing TypeScript code. The HAP embeds the JavaScript bundle.

On Windows, use a short project path. The SDK's Ninja can reject paths over 260
characters in the expanded RNOH headers.

For an x86_64 emulator, use the source `react_native_openharmony.har` from the
same npm package in a separate local build. Set `abiFilters` to `["x86_64"]` and
use `add_subdirectory` on the HAR's `src/main/cpp` in the entry CMake file.
The checked-in device build uses the precompiled ARM64 HAR.

## Shared mobile build

The shared build bundles the same `apps/mobile/index.ts` entry used by Android.
Prepare the [RNOH 0.88 native host](shared-native/README.md) and use the matching
RNOH JavaScript package. When starting from source, run `pnpm init-ws` in a
fresh RNOH checkout to integrate the upstream React Native files. Pass its
`packages/react-native-harmony` directory as `--framework`.

```sh
node apps/harmonyos/scripts/bundle-shared.cjs --framework <rnoh-js-package> --native-workspace <candidate-directory>
```

If the RNOH checkout does not have its JavaScript dependencies installed, pass the
directory containing its pinned runtime packages with `--runtime-node-modules`.
The command compiles the shared bundle to `bundle.harmony.hbc` with the Hermes compiler
matched to RNOH 0.88.0 and writes it with its assets into the candidate's entry module.
