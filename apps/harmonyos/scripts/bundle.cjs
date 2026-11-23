const { mkdir } = require("node:fs/promises");
const path = require("node:path");
const { loadConfig, runBuild } = require("metro");

async function bundle() {
  const root = path.resolve(__dirname, "..");
  const output = path.join(root, "entry/src/main/resources/rawfile");
  await mkdir(output, { recursive: true });
  await runBuild(await loadConfig({ cwd: root }), {
    entry: path.join(root, "index.js"),
    out: path.join(output, "bundle.harmony.js"),
    platform: "harmony",
    dev: false,
    minify: true,
  });
}

bundle().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
