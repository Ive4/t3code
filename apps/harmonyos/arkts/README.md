# T3 Code for HarmonyOS · ArkTS preview

This DevEco project uses ArkUI and HarmonyOS SDK 26. The workspace opens
conversations and settings. It uses the T3 environment HTTP and WebSocket
contracts for pairing, environment switching, and conversations.

Open `apps/harmonyos/arkts` in DevEco Studio and configure debug signing for
the test device. The default bundle ID `com.t3tools.t3code.dev` is shared with
the existing HarmonyOS development app. Use an isolated emulator for signed
preview builds, or configure a separate bundle ID and a matching profile.

Start an isolated T3 environment with Replay. Create a one-time pairing link
with `t3 auth pairing create` and select **Settings → Environments → Add
environment**. Emulator hosts may need to forward the backend port.

## T3 account and Connect

Set the public Clerk key, token template, and relay URL using the same
configuration as the shared mobile client. From the repository root, populate
the resources in a prepared copy of the DevEco project before signing.

```sh
node apps/harmonyos/scripts/configure-arkts-cloud.cjs /path/to/prepared-arkts-project
```

The hosted auth callback uses
`clerk://com.t3tools.t3code.dev.hosted-callback`. A developer bundle ID change
needs the corresponding native registration, manifest URI, and account
redirect.

## Terminal renderer

The terminal loads the bundled Ghostty VT document offline. After editing the
shared renderer, regenerate the ArkUI resource from the repository root.

```sh
node -e 'require("./apps/harmonyos/scripts/terminal-document.cjs").buildTerminalDocument().then(html => process.stdout.write(html))' > apps/harmonyos/arkts/entry/src/main/resources/rawfile/thread-terminal.html
```
