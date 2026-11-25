const { writeFileSync } = require("node:fs");
const { resolve } = require("node:path");
const { sharedCloudConfig } = require("./shared-cloud-config.cjs");

const project = process.argv[2];
if (!project) throw new Error("Pass the prepared ArkTS project directory.");

const config = sharedCloudConfig();
const resource = {
  string: [
    { name: "clerk_publishable_key", value: config.clerk.publishableKey ?? "" },
    { name: "clerk_jwt_template", value: config.clerk.jwtTemplate ?? "" },
    { name: "relay_url", value: config.relay.url ?? "" },
  ],
};
writeFileSync(
  resolve(project, "entry/src/main/resources/base/element/cloud_config.json"),
  JSON.stringify(resource, null, 2) + "\n",
);
