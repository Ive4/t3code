const { loadRepoEnv } = require("../../../scripts/lib/public-config.ts");

function sharedCloudConfig(env = loadRepoEnv()) {
  return {
    clerk: {
      publishableKey: env.EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY ?? null,
      jwtTemplate: env.EXPO_PUBLIC_CLERK_JWT_TEMPLATE ?? null,
    },
    relay: { url: env.T3CODE_RELAY_URL ?? null },
    harmonyPush: { url: env.T3CODE_HARMONY_PUSH_URL ?? null },
  };
}

module.exports = { sharedCloudConfig };
