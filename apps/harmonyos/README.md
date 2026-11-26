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

To enable T3 Account in the shared build, supply the mobile client's
`T3CODE_CLERK_PUBLISHABLE_KEY`, `T3CODE_CLERK_JWT_TEMPLATE`, and
`T3CODE_RELAY_URL` when bundling. The repository's `.env.example` lists the
production values. For your own Clerk instance, enable the Native API and
register `clerk://com.t3tools.t3code.dev.hosted-callback` under its native redirect
URLs. Build and sign the HAP for the matching app identity.

For verified HTTPS conversation links, associate `app.t3.codes` with the release
app in AppGallery Connect and publish its AppGallery App ID in
`https://app.t3.codes/.well-known/applinking.json`.

For background Agent notifications, enable Account Kit and Push Kit in AppGallery
Connect for the signed HarmonyOS app identity. Register the signing certificate
fingerprint and use a signing profile issued after Push Kit activation.

- Set `T3CODE_HUAWEI_ACCOUNT_CLIENT_ID` when running `prepare-shared-native.cjs`.
  Use the app's OAuth 2.0 Client ID from **App information** in AppGallery Connect.
- Set `T3CODE_HARMONY_PUSH_URL` when running `bundle-shared.cjs`. Use the HTTPS
  origin of the independent push service. This value is included in the HAP, so
  changing it requires rebundling. Keep the Huawei client secret on the push service.

Pair with an environment that has a sender configured for the push service. On
the phone, open **Settings → Huawei Account** and authorize with the phone's
Huawei Account. Allow system notifications and turn on **Background notifications**
in **Settings → Notifications**. When the push session expires, sign in again
under **Huawei Account**. The **T3 Account** entry controls T3 Connect independently.
