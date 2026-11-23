# Shared React Native native host

Use this host to build a local HarmonyOS HAP from the shared mobile bundle. It uses the HarmonyOS SDK 26 and source builds of its native dependencies. It reuses the Harmony app identity, icon, pairing scanner, connection store, and worker.

## Prepare a candidate

Install the mobile workspace dependencies so `react-native-worklets` 0.13.1 provides its `Common` sources. Use Git, ohpm, and DevEco Studio with the HarmonyOS SDK 26. Keep the candidate directory short on Windows for Ninja's path limits.

Supply a local vendor root containing the prepared source modules below as sibling directories. Preparation checks the module names, native package versions, and selected patch markers. The prepared RNOH source was based on commit `07ae308f0e29be1306f7239cc452b3ec5d7cdad4`.

| Directory  | Package                                             | Version        | Notes                                                                                                                                                                        |
| ---------- | --------------------------------------------------- | -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| rn         | @rnoh/react-native-openharmony                      | 0.88.0         | Source tree with the Fabric scheduler bootstrap patch, required SDK compatibility fixes, native third-party sources, and debug/release Hermes libraries for the selected ABI |
| gesture    | @react-native-ohos/react-native-gesture-handler     | 2.30.2         | Harmony host with the Gesture Handler 3.5 module and detector changes                                                                                                        |
| worklets   | @react-native-ohos/react-native-worklets            | 1.1.0-beta.1   | Harmony host with Worklets 0.13.1 integration and OHOS async queue                                                                                                           |
| reanimated | @react-native-ohos/react-native-reanimated          | 4.1.0-beta.1   | Harmony host with the native Reanimated 4.7.1 Common471 overlay                                                                                                              |
| screens    | @react-native-ohos/react-native-screens             | 4.10.0-beta.4  | Prepared source module                                                                                                                                                       |
| safe_area  | @react-native-ohos/react-native-safe-area-context   | 5.6.5          | Prepared source module                                                                                                                                                       |
| svg        | @react-native-ohos/react-native-svg                 | 15.14.0-beta.4 | Prepared source module                                                                                                                                                       |
| keyboard   | @react-native-ohos/react-native-keyboard-controller | 1.18.0-beta.1  | Prepared source module                                                                                                                                                       |

```sh
node apps/harmonyos/scripts/prepare-shared-native.cjs --vendor-root <vendor-root> --out <candidate-directory> --abi arm64-v8a
```

Choose `x86_64` for an x86_64 emulator. Preparation copies the vendor sources into the candidate and applies the checked-in RNOH networking patch there if needed. It also copies the installed Worklets `Common` sources and points the host CMake configuration at that copy.

From the candidate directory, run `ohpm install --all`. Generate the shared mobile bundle into its `entry/src/main/resources/rawfile` directory. Open the candidate in DevEco Studio, configure local signing, and build the entry module.

Rerun the same preparation command to refresh the T3 entry sources. It keeps the root build profile for local signing and leaves the previously generated bundle in place. Use a fresh candidate when changing the ABI or replacing the vendor sources.

The default HarmonyOS build is documented in the [HarmonyOS README](../README.md).
