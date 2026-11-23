# T3 Code for HarmonyOS

The HarmonyOS app runs React Native for OpenHarmony 0.86.1 on HarmonyOS SDK 26.
Pair with a direct environment link or use the system QR scanner. Saved connections are encrypted and restored when the app opens. Use **Environments** to add or switch connections and **Disconnect** to remove the current one.

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
